import Foundation

class CharacterWalletAPI {
    static let shared = CharacterWalletAPI()

    // 缓存结构
    private struct CacheEntry: Codable {
        let value: String  // 改用字符串存储以保持精度
        let timestamp: Date
    }

    // 添加并发队列用于同步访问
    private let cacheQueue = DispatchQueue(
        label: "com.eve-nexus.wallet-cache", attributes: .concurrent
    )

    // 内存缓存
    private var memoryCache: [Int: CacheEntry] = [:]
    private let cacheTimeout: TimeInterval = 20 * 60  // 20分钟缓存，钱包余额使用

    // UserDefaults键前缀
    private let walletCachePrefix = "wallet_cache_"

    // 钱包交易记录缓存前缀
    private let lastJournalQueryKey = "LastWalletJournalQuery_"
    private let lastTransactionQueryKey = "LastWalletTransactionQuery_"
    private let queryInterval: TimeInterval = 3600  // 1小时的查询间隔

    // 获取最后查询时间
    private func getLastQueryTime(characterId: Int, isJournal: Bool) -> Date? {
        let key =
            isJournal
            ? lastJournalQueryKey + String(characterId)
            : lastTransactionQueryKey + String(characterId)
        return UserDefaults.standard.object(forKey: key) as? Date
    }

    // 更新最后查询时间
    private func updateLastQueryTime(characterId: Int, isJournal: Bool) {
        let key =
            isJournal
            ? lastJournalQueryKey + String(characterId)
            : lastTransactionQueryKey + String(characterId)
        UserDefaults.standard.set(Date(), forKey: key)
    }

    // 检查是否需要刷新数据
    private func shouldRefreshData(characterId: Int, isJournal: Bool) -> Bool {
        guard let lastQuery = getLastQueryTime(characterId: characterId, isJournal: isJournal)
        else {
            Logger.debug("没有找到上次查询时间记录，需要刷新数据")
            return true  // 如果没有查询记录，需要刷新
        }

        let timeInterval = Date().timeIntervalSince(lastQuery)
        let remainingTime = queryInterval - timeInterval
        let remainingMinutes = Int(remainingTime / 60)
        let remainingSeconds = Int(remainingTime.truncatingRemainder(dividingBy: 60))

        let dataType = isJournal ? "钱包流水" : "钱包交易记录"
        Logger.debug("\(dataType)下次刷新剩余时间: \(remainingMinutes)分\(remainingSeconds)秒")

        return timeInterval > queryInterval
    }

    private init() {
        // 从 UserDefaults 恢复缓存
        let defaults = UserDefaults.standard
        Logger.debug("正在从 UserDefaults 读取所有钱包缓存键")
        for key in defaults.dictionaryRepresentation().keys {
            if key.hasPrefix(walletCachePrefix),
                let data = defaults.data(forKey: key),
                let entry = try? JSONDecoder().decode(CacheEntry.self, from: data),
                let characterId = Int(key.replacingOccurrences(of: walletCachePrefix, with: ""))
            {
                memoryCache[characterId] = entry
            }
        }
    }

    // 安全地获取钱包缓存
    private func getWalletMemoryCache(characterId: Int) -> CacheEntry? {
        var result: CacheEntry?
        cacheQueue.sync {
            result = memoryCache[characterId]
        }
        return result
    }

    // 安全地设置钱包缓存
    private func setWalletMemoryCache(characterId: Int, cache: CacheEntry) {
        cacheQueue.async(flags: .barrier) {
            self.memoryCache[characterId] = cache
        }
    }

    // 检查缓存是否有效
    private func isCacheValid(_ cache: CacheEntry?) -> Bool {
        guard let cache = cache else {
            Logger.info("钱包缓存为空")
            return false
        }
        let timeInterval = Date().timeIntervalSince(cache.timestamp)
        let isValid = timeInterval < cacheTimeout
        Logger.info(
            "钱包缓存时间检查 - 缓存时间: \(cache.timestamp), 当前时间: \(Date()), 时间间隔: \(timeInterval)秒, 超时时间: \(cacheTimeout)秒, 是否有效: \(isValid)"
        )
        return isValid
    }

    // 从UserDefaults获取缓存
    private func getDiskCache(characterId: Int) -> CacheEntry? {
        let key = walletCachePrefix + String(characterId)
        guard let data = UserDefaults.standard.data(forKey: key) else {
            Logger.info("钱包磁盘缓存不存在 - Key: \(key)")
            return nil
        }

        guard let cache = try? JSONDecoder().decode(CacheEntry.self, from: data) else {
            Logger.error("钱包磁盘缓存解码失败 - Key: \(key)")
            return nil
        }

        Logger.info("成功读取钱包磁盘缓存 - Key: \(key), 缓存时间: \(cache.timestamp), 值: \(cache.value)")
        return cache
    }

    // 保存缓存到UserDefaults
    private func saveToDiskCache(characterId: Int, cache: CacheEntry) {
        let key = walletCachePrefix + String(characterId)
        if let encoded = try? JSONEncoder().encode(cache) {
            Logger.info(
                "保存钱包缓存到磁盘 - Key: \(key), 缓存时间: \(cache.timestamp), 值: \(cache.value), 数据大小: \(encoded.count) bytes"
            )
            UserDefaults.standard.set(encoded, forKey: key)
        } else {
            Logger.error("保存钱包缓存到磁盘失败 - Key: \(key)")
        }
    }

    // 获取缓存的钱包余额（异步方法）
    func getCachedWalletBalance(characterId: Int) async -> String {
        // 1. 先检查内存缓存
        if let memoryCached = getWalletMemoryCache(characterId: characterId) {
            return memoryCached.value
        }

        // 2. 如果内存缓存不可用，检查磁盘缓存
        if let diskCached = getDiskCache(characterId: characterId) {
            // 更新内存缓存
            setWalletMemoryCache(characterId: characterId, cache: diskCached)
            return diskCached.value
        }

        return "-"
    }

    // 获取钱包余额（异步方法，用于后台刷新）
    func getWalletBalance(characterId: Int, forceRefresh: Bool = false) async throws -> Double {
        // 如果不是强制刷新，检查缓存是否有效
        if !forceRefresh {
            // 检查缓存
            let cachedResult: Double? = {
                if let memoryCached = getWalletMemoryCache(characterId: characterId),
                    isCacheValid(memoryCached)
                {
                    Logger.info("使用内存缓存的钱包余额数据 - 角色ID: \(characterId)")
                    return Double(memoryCached.value)
                }

                if let diskCached = getDiskCache(characterId: characterId),
                    isCacheValid(diskCached)
                {
                    Logger.info("使用磁盘缓存的钱包余额数据 - 角色ID: \(characterId)")
                    setWalletMemoryCache(characterId: characterId, cache: diskCached)
                    return Double(diskCached.value)
                }

                return nil
            }()

            if let cachedValue = cachedResult {
                return cachedValue
            }

            Logger.info("缓存未命中或已过期,需要从服务器获取钱包数据 - 角色ID: \(characterId)")
        }

        let urlString = "https://esi.evetech.net/latest/characters/\(characterId)/wallet/"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId
        )

        guard
            let stringValue = String(data: data, encoding: .utf8)?.trimmingCharacters(
                in: .whitespacesAndNewlines)
        else {
            Logger.error("无法解析钱包余额数据: \(String(data: data, encoding: .utf8) ?? "无数据")")
            throw NetworkError.invalidResponse
        }

        Logger.info("ESI响应: 钱包余额 = \(stringValue) ISK")

        // 创建新的缓存条目，直接存储字符串值
        let cacheEntry = CacheEntry(value: stringValue, timestamp: Date())

        // 更新内存缓存
        setWalletMemoryCache(characterId: characterId, cache: cacheEntry)

        // 更新磁盘缓存
        saveToDiskCache(characterId: characterId, cache: cacheEntry)

        return Double(stringValue) ?? 0.0
    }

    // 从数据库获取钱包流水
    private func getWalletJournalFromDB(characterId: Int) -> [[String: Any]]? {
        let query = """
                SELECT id, amount, balance, context_id, context_id_type,
                       date, description, first_party_id, reason, ref_type,
                       second_party_id, last_updated
                FROM wallet_journal 
                WHERE character_id = ? 
                ORDER BY date DESC 
                LIMIT 1000
            """

        if case let .success(results) = CharacterDatabaseManager.shared.executeQuery(
            query, parameters: [characterId]
        ) {
            return results
        }
        return nil
    }

    // 保存钱包流水到数据库
    private func saveWalletJournalToDB(characterId: Int, entries: [[String: Any]]) -> Bool {
        // 如果没有条目需要保存，直接返回成功
        if entries.isEmpty {
            Logger.info("没有钱包流水需要保存")
            return true
        }

        // 首先获取已存在的日志ID
        let checkQuery = "SELECT id FROM wallet_journal WHERE character_id = ?"
        guard
            case let .success(existingResults) = CharacterDatabaseManager.shared.executeQuery(
                checkQuery, parameters: [characterId]
            )
        else {
            Logger.error("查询现有钱包流水失败")
            return false
        }

        let existingIds = Set(existingResults.compactMap { ($0["id"] as? Int64) })

        // 过滤出需要插入的新记录
        let newEntries = entries.filter { entry in
            let journalId = entry["id"] as? Int64 ?? 0
            return !existingIds.contains(journalId)
        }

        // 如果没有新记录，直接返回成功
        if newEntries.isEmpty {
            Logger.info("无需新增钱包流水")
            return true
        }

        Logger.info("准备插入\(newEntries.count)条新钱包流水记录")

        // 开始事务
        _ = CharacterDatabaseManager.shared.executeQuery("BEGIN TRANSACTION")

        // 计算每批次的大小（每条记录12个参数）
        let batchSize = 100  // 每批次处理100条记录
        var success = true

        // 分批处理数据
        for batchStart in stride(from: 0, to: newEntries.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, newEntries.count)
            let currentBatch = Array(newEntries[batchStart..<batchEnd])

            // 构建批量插入语句
            let placeholders = Array(
                repeating: "(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", count: currentBatch.count
            ).joined(separator: ",")
            let insertSQL = """
                    INSERT OR REPLACE INTO wallet_journal (
                        id, character_id, amount, balance, context_id, context_id_type,
                        date, description, first_party_id, reason, ref_type,
                        second_party_id
                    ) VALUES \(placeholders)
                """

            // 准备参数数组
            var parameters: [Any] = []
            for entry in currentBatch {
                let journalId = entry["id"] as? Int64 ?? 0
                let params: [Any] = [
                    journalId,
                    characterId,
                    entry["amount"] as? Double ?? 0.0,
                    entry["balance"] as? Double ?? 0.0,
                    entry["context_id"] as? Int ?? 0,
                    entry["context_id_type"] as? String ?? "",
                    entry["date"] as? String ?? "",
                    entry["description"] as? String ?? "",
                    entry["first_party_id"] as? Int ?? 0,
                    entry["reason"] as? String ?? "",
                    entry["ref_type"] as? String ?? "",
                    entry["second_party_id"] as? Int ?? 0,
                ]
                parameters.append(contentsOf: params)
            }

            Logger.debug("执行批量插入钱包流水，批次大小: \(currentBatch.count), 参数数量: \(parameters.count)")

            // 执行批量插入
            if case let .error(message) = CharacterDatabaseManager.shared.executeQuery(
                insertSQL, parameters: parameters
            ) {
                Logger.error("批量插入钱包流水失败: \(message)")
                success = false
                break
            }
        }

        // 根据执行结果提交或回滚事务
        if success {
            _ = CharacterDatabaseManager.shared.executeQuery("COMMIT")
            Logger.info("成功插入\(newEntries.count)条钱包流水到数据库")
            return true
        } else {
            _ = CharacterDatabaseManager.shared.executeQuery("ROLLBACK")
            Logger.error("保存钱包流水失败，执行回滚")
            return false
        }
    }

    // 获取钱包流水
    func getWalletJournal(characterId: Int, forceRefresh: Bool = false) async throws
        -> String?
    {
        // 检查数据库中是否有数据，以及是否需要刷新
        let checkQuery = "SELECT COUNT(*) as count FROM wallet_journal WHERE character_id = ?"
        let result = CharacterDatabaseManager.shared.executeQuery(
            checkQuery, parameters: [characterId]
        )
        let isEmpty =
            if case let .success(rows) = result,
                let row = rows.first,
                let count = row["count"] as? Int64
            {
                count == 0
            } else {
                true
            }

        // 如果数据为空、强制刷新或达到查询间隔，则从网络获取
        if isEmpty || forceRefresh || shouldRefreshData(characterId: characterId, isJournal: true) {
            Logger.debug("钱包流水为空或需要刷新，从网络获取数据")
            let journalData = try await fetchJournalFromServer(characterId: characterId)
            if !saveWalletJournalToDB(characterId: characterId, entries: journalData) {
                Logger.error("保存钱包流水到数据库失败")
            }
            // 更新最后查询时间
            updateLastQueryTime(characterId: characterId, isJournal: true)
        } else {
            Logger.debug("使用数据库中的钱包流水数据")
        }

        // 从数据库获取数据并返回
        if let results = getWalletJournalFromDB(characterId: characterId) {
            let jsonData = try JSONSerialization.data(
                withJSONObject: results, options: [.prettyPrinted, .sortedKeys]
            )
            return String(data: jsonData, encoding: .utf8)
        }
        return nil
    }

    // 从服务器获取钱包流水
    private func fetchJournalFromServer(characterId: Int) async throws -> [[String: Any]] {
        let baseUrlString =
            "https://esi.evetech.net/latest/characters/\(characterId)/wallet/journal/?datasource=tranquility"
        guard let baseUrl = URL(string: baseUrlString) else {
            throw NetworkError.invalidURL
        }

        let journalEntries = try await NetworkManager.shared.fetchPaginatedData(
            from: baseUrl,
            characterId: characterId,
            maxConcurrentPages: 3,
            decoder: { data in
                guard
                    let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
                else {
                    throw NetworkError.invalidResponse
                }
                return entries
            },
            progressCallback: { currentPage, totalPages in
                Logger.debug("正在获取第 \(currentPage)/\(totalPages) 页钱包流水数据")
            }
        )

        Logger.info("钱包流水获取完成，共\(journalEntries.count)条记录")
        return journalEntries
    }

    // 从数据库获取钱包交易记录
    private func getWalletTransactionsFromDB(characterId: Int) -> [[String: Any]]? {
        let query = """
                SELECT transaction_id, client_id, date, is_buy, is_personal,
                       journal_ref_id, location_id, quantity, type_id,
                       unit_price, last_updated
                FROM wallet_transactions 
                WHERE character_id = ? 
                ORDER BY date DESC 
                LIMIT 1000
            """

        if case let .success(results) = CharacterDatabaseManager.shared.executeQuery(
            query, parameters: [characterId]
        ) {
            // 将整数转换回布尔值
            return results.map { row in
                var mutableRow = row
                if let isBuy = row["is_buy"] as? Int64 {
                    mutableRow["is_buy"] = isBuy != 0
                }
                if let isPersonal = row["is_personal"] as? Int64 {
                    mutableRow["is_personal"] = isPersonal != 0
                }
                return mutableRow
            }
        }
        return nil
    }

    // 保存钱包交易记录到数据库
    private func saveWalletTransactionsToDB(characterId: Int, entries: [[String: Any]]) -> Bool {
        // 如果没有条目需要保存，直接返回成功
        if entries.isEmpty {
            Logger.info("没有钱包交易记录需要保存")
            return true
        }

        // 首先获取已存在的交易ID
        let checkQuery = "SELECT transaction_id FROM wallet_transactions WHERE character_id = ?"
        guard
            case let .success(existingResults) = CharacterDatabaseManager.shared.executeQuery(
                checkQuery, parameters: [characterId]
            )
        else {
            Logger.error("查询现有交易记录失败")
            return false
        }

        let existingIds = Set(existingResults.compactMap { ($0["transaction_id"] as? Int64) })

        // 过滤出需要插入的新记录
        let newEntries = entries.filter { entry in
            let transactionId = entry["transaction_id"] as? Int64 ?? 0
            return !existingIds.contains(transactionId)
        }

        // 如果没有新记录，直接返回成功
        if newEntries.isEmpty {
            Logger.info("无需新增交易记录")
            return true
        }

        Logger.info("准备插入\(newEntries.count)条新钱包交易记录")

        // 开始事务
        _ = CharacterDatabaseManager.shared.executeQuery("BEGIN TRANSACTION")

        // 计算每批次的大小（每条记录11个参数）
        let batchSize = 100  // 每批次处理100条记录
        var success = true

        // 分批处理数据
        for batchStart in stride(from: 0, to: newEntries.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, newEntries.count)
            let currentBatch = Array(newEntries[batchStart..<batchEnd])

            // 构建批量插入语句
            let placeholders = Array(
                repeating: "(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", count: currentBatch.count
            ).joined(separator: ",")
            let insertSQL = """
                    INSERT OR REPLACE INTO wallet_transactions (
                        transaction_id, character_id, client_id, date, is_buy,
                        is_personal, journal_ref_id, location_id, quantity,
                        type_id, unit_price
                    ) VALUES \(placeholders)
                """

            // 准备参数数组
            var parameters: [Any] = []
            for entry in currentBatch {
                let transactionId = entry["transaction_id"] as? Int64 ?? 0

                // 将布尔值转换为整数
                let isBuy = (entry["is_buy"] as? Bool ?? false) ? 1 : 0
                let isPersonal = (entry["is_personal"] as? Bool ?? false) ? 1 : 0

                let params: [Any] = [
                    transactionId,
                    characterId,
                    entry["client_id"] as? Int ?? 0,
                    entry["date"] as? String ?? "",
                    isBuy,
                    isPersonal,
                    entry["journal_ref_id"] as? Int64 ?? 0,
                    entry["location_id"] as? Int64 ?? 0,
                    entry["quantity"] as? Int ?? 0,
                    entry["type_id"] as? Int ?? 0,
                    entry["unit_price"] as? Double ?? 0.0,
                ]
                parameters.append(contentsOf: params)
            }

            Logger.debug("执行批量插入钱包交易记录，批次大小: \(currentBatch.count), 参数数量: \(parameters.count)")

            // 执行批量插入
            if case let .error(message) = CharacterDatabaseManager.shared.executeQuery(
                insertSQL, parameters: parameters
            ) {
                Logger.error("批量插入钱包交易记录失败: \(message)")
                success = false
                break
            }
        }

        // 根据执行结果提交或回滚事务
        if success {
            _ = CharacterDatabaseManager.shared.executeQuery("COMMIT")
            Logger.info("成功插入\(newEntries.count)条钱包交易记录到数据库")
            return true
        } else {
            _ = CharacterDatabaseManager.shared.executeQuery("ROLLBACK")
            Logger.error("保存钱包交易记录失败，执行回滚")
            return false
        }
    }

    // 获取钱包交易记录
    func getWalletTransactions(characterId: Int, forceRefresh: Bool = false) async throws
        -> String?
    {
        // 检查数据库中是否有数据，以及是否需要刷新
        let checkQuery = "SELECT COUNT(*) as count FROM wallet_transactions WHERE character_id = ?"
        let result = CharacterDatabaseManager.shared.executeQuery(
            checkQuery, parameters: [characterId]
        )
        let isEmpty =
            if case let .success(rows) = result,
                let row = rows.first,
                let count = row["count"] as? Int64
            {
                count == 0
            } else {
                true
            }

        // 如果数据为空、强制刷新或达到查询间隔，则从网络获取
        if isEmpty || forceRefresh || shouldRefreshData(characterId: characterId, isJournal: false)
        {
            Logger.debug("钱包交易记录为空或需要刷新，从网络获取数据")
            let transactionData = try await fetchTransactionsFromServer(characterId: characterId)
            if !saveWalletTransactionsToDB(characterId: characterId, entries: transactionData) {
                Logger.error("保存钱包交易记录到数据库失败")
            }
            // 更新最后查询时间
            updateLastQueryTime(characterId: characterId, isJournal: false)
        } else {
            Logger.debug("使用数据库中的钱包交易记录数据")
        }

        // 从数据库获取数据并返回
        if let results = getWalletTransactionsFromDB(characterId: characterId) {
            let jsonData = try JSONSerialization.data(
                withJSONObject: results, options: [.prettyPrinted, .sortedKeys]
            )
            return String(data: jsonData, encoding: .utf8)
        }
        return nil
    }

    // 从服务器获取交易记录
    private func fetchTransactionsFromServer(characterId: Int) async throws -> [[String: Any]] {
        let urlString =
            "https://esi.evetech.net/latest/characters/\(characterId)/wallet/transactions/"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId
        )

        guard let transactions = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            throw NetworkError.invalidResponse
        }

        Logger.info("成功获取钱包交易记录，共\(transactions.count)条记录")
        return transactions
    }
}
