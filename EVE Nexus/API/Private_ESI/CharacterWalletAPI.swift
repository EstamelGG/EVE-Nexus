import Foundation

class CharacterWalletAPI {
    static let shared = CharacterWalletAPI()
    
    // 缓存结构
    private struct CacheEntry: Codable {
        let value: String  // 改用字符串存储以保持精度
        let timestamp: Date
    }
    
    // 添加并发队列用于同步访问
    private let cacheQueue = DispatchQueue(label: "com.eve-nexus.wallet-cache", attributes: .concurrent)
    
    // 内存缓存
    private var memoryCache: [Int: CacheEntry] = [:]
    private let cacheTimeout: TimeInterval = 8 * 3600 // 8 小时缓存
    
    // UserDefaults键前缀
    private let walletCachePrefix = "wallet_cache_"
    
    // MARK: - Wallet Journal Methods
    
    // 钱包日志缓存结构
    private struct WalletJournalCacheEntry: Codable {
        let jsonString: String
        let timestamp: Date
    }
    
    // 钱包日志缓存前缀
    private let walletJournalCachePrefix = "wallet_journal_cache_"
    
    // 钱包交易记录缓存前缀
    private let walletTransactionsCachePrefix = "wallet_transactions_cache_"
    
    // 钱包交易记录缓存结构
    private struct WalletTransactionsCacheEntry: Codable {
        let jsonString: String
        let timestamp: Date
    }
    
    private let lastJournalQueryKey = "LastWalletJournalQuery_"
    private let lastTransactionQueryKey = "LastWalletTransactionQuery_"
    private let queryInterval: TimeInterval = 3600 // 1小时的查询间隔
    
    // 获取最后查询时间
    private func getLastQueryTime(characterId: Int, isJournal: Bool) -> Date? {
        let key = isJournal ? lastJournalQueryKey + String(characterId) : lastTransactionQueryKey + String(characterId)
        return UserDefaults.standard.object(forKey: key) as? Date
    }
    
    // 更新最后查询时间
    private func updateLastQueryTime(characterId: Int, isJournal: Bool) {
        let key = isJournal ? lastJournalQueryKey + String(characterId) : lastTransactionQueryKey + String(characterId)
        UserDefaults.standard.set(Date(), forKey: key)
    }
    
    // 检查是否需要刷新数据
    private func shouldRefreshData(characterId: Int, isJournal: Bool) -> Bool {
        guard let lastQuery = getLastQueryTime(characterId: characterId, isJournal: isJournal) else {
            return true // 如果没有查询记录，需要刷新
        }
        return Date().timeIntervalSince(lastQuery) > queryInterval
    }
    
    private init() {
        // 从 UserDefaults 恢复缓存
        let defaults = UserDefaults.standard
        Logger.debug("正在从 UserDefaults 读取所有钱包缓存键")
        for key in defaults.dictionaryRepresentation().keys {
            if key.hasPrefix(walletCachePrefix),
               let data = defaults.data(forKey: key),
               let entry = try? JSONDecoder().decode(CacheEntry.self, from: data),
               let characterId = Int(key.replacingOccurrences(of: walletCachePrefix, with: "")) {
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
        Logger.info("钱包缓存时间检查 - 缓存时间: \(cache.timestamp), 当前时间: \(Date()), 时间间隔: \(timeInterval)秒, 超时时间: \(cacheTimeout)秒, 是否有效: \(isValid)")
        return isValid
    }
    
    // 检查日志缓存是否有效
    private func isJournalCacheValid(_ cache: WalletJournalCacheEntry) -> Bool {
        let timeInterval = Date().timeIntervalSince(cache.timestamp)
        return timeInterval < cacheTimeout
    }
    
    // 检查交易记录缓存是否有效
    private func isTransactionsCacheValid(_ cache: WalletTransactionsCacheEntry) -> Bool {
        let timeInterval = Date().timeIntervalSince(cache.timestamp)
        return timeInterval < cacheTimeout
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
            Logger.info("保存钱包缓存到磁盘 - Key: \(key), 缓存时间: \(cache.timestamp), 值: \(cache.value), 数据大小: \(encoded.count) bytes")
            UserDefaults.standard.set(encoded, forKey: key)
        } else {
            Logger.error("保存钱包缓存到磁盘失败 - Key: \(key)")
        }
    }
    
    // 清除缓存
    private func clearCache(characterId: Int) {
        cacheQueue.async(flags: .barrier) {
            self.memoryCache.removeValue(forKey: characterId)
            let key = self.walletCachePrefix + String(characterId)
            UserDefaults.standard.removeObject(forKey: key)
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
                   isCacheValid(memoryCached) {
                    Logger.info("使用内存缓存的钱包余额数据 - 角色ID: \(characterId)")
                    return Double(memoryCached.value)
                }
                
                if let diskCached = getDiskCache(characterId: characterId),
                   isCacheValid(diskCached) {
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
        
        guard let stringValue = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
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
    
    // 获取钱包日志的缓存键
    private func getJournalCacheKey(characterId: Int) -> String {
        return walletJournalCachePrefix + String(characterId)
    }
    
    // 获取缓存的钱包日志
    private func getCachedJournal(characterId: Int) -> String? {
        let key = getJournalCacheKey(characterId: characterId)
        guard let data = UserDefaults.standard.data(forKey: key),
              let cache = try? JSONDecoder().decode(WalletJournalCacheEntry.self, from: data),
              isJournalCacheValid(cache) else {
            return nil
        }
        return cache.jsonString
    }
    
    // 保存钱包日志到缓存
    private func saveJournalToCache(jsonString: String, characterId: Int) {
        let cache = WalletJournalCacheEntry(jsonString: jsonString, timestamp: Date())
        let key = getJournalCacheKey(characterId: characterId)
        if let encoded = try? JSONEncoder().encode(cache) {
            Logger.info("保存钱包日志到缓存 - Key: \(key), 数据大小: \(encoded.count) bytes")
            UserDefaults.standard.set(encoded, forKey: key)
        } else {
            Logger.error("保存钱包日志到缓存失败 - Key: \(key)")
        }
    }
    
    // 从数据库获取钱包日志
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
        
        if case .success(let results) = CharacterDatabaseManager.shared.executeQuery(query, parameters: [characterId]) {
            return results
        }
        return nil
    }
    
    // 保存钱包日志到数据库
    private func saveWalletJournalToDB(characterId: Int, entries: [[String: Any]]) -> Bool {
        // 首先获取已存在的日志ID
        let checkQuery = "SELECT id FROM wallet_journal WHERE character_id = ?"
        guard case .success(let existingResults) = CharacterDatabaseManager.shared.executeQuery(checkQuery, parameters: [characterId]) else {
            Logger.error("查询现有钱包日志失败")
            return false
        }
        
        let existingIds = Set(existingResults.compactMap { ($0["id"] as? Int64) })
        
        let insertSQL = """
            INSERT OR REPLACE INTO wallet_journal (
                id, character_id, amount, balance, context_id, context_id_type,
                date, description, first_party_id, reason, ref_type,
                second_party_id
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        
        var newCount = 0
        for entry in entries {
            let journalId = entry["id"] as? Int64 ?? 0
            // 如果日志ID已存在，跳过
            if existingIds.contains(journalId) {
                continue
            }
            
            let parameters: [Any] = [
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
                entry["second_party_id"] as? Int ?? 0
            ]
            
            if case .error(let message) = CharacterDatabaseManager.shared.executeQuery(insertSQL, parameters: parameters) {
                Logger.error("保存钱包日志到数据库失败: \(message)")
                return false
            }
            newCount += 1
        }
        
        if newCount > 0 {
            Logger.info("新增\(newCount)条钱包日志到数据库")
        }
        return true
    }
    
    // 获取钱包日志（公开方法）
    public func getWalletJournal(characterId: Int, forceRefresh: Bool = false) async throws -> String? {
        // 检查是否需要刷新
        let needsRefresh = forceRefresh || shouldRefreshData(characterId: characterId, isJournal: true)
        
        // 先尝试从数据库获取数据（无论是否需要刷新）
        if let results = getWalletJournalFromDB(characterId: characterId) {
            let jsonData = try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                // 如果需要刷新，在返回缓存数据的同时，启动后台刷新
                if needsRefresh {
                    Task {
                        do {
                            // 从服务器获取新数据
                            let journalData = try await fetchJournalFromServer(characterId: characterId)
                            
                            // 保存到数据库
                            if !saveWalletJournalToDB(characterId: characterId, entries: journalData) {
                                Logger.error("保存钱包日志到数据库失败")
                            }
                            
                            // 更新查询时间
                            updateLastQueryTime(characterId: characterId, isJournal: true)
                            
                            // 发送通知以刷新UI
                            await MainActor.run {
                                NotificationCenter.default.post(name: NSNotification.Name("WalletJournalUpdated"), object: nil, userInfo: ["characterId": characterId])
                            }
                        } catch {
                            Logger.error("后台刷新钱包日志失败: \(error)")
                        }
                    }
                }
                return jsonString
            }
        }
        
        // 如果没有缓存数据，或者转换JSON失败，则直接从服务器获取
        let journalData = try await fetchJournalFromServer(characterId: characterId)
        
        // 保存到数据库
        if !saveWalletJournalToDB(characterId: characterId, entries: journalData) {
            Logger.error("保存钱包日志到数据库失败")
        }
        
        // 更新查询时间
        updateLastQueryTime(characterId: characterId, isJournal: true)
        
        // 转换为JSON返回
        let jsonData = try JSONSerialization.data(withJSONObject: journalData, options: [.prettyPrinted, .sortedKeys])
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw NetworkError.invalidResponse
        }
        
        // 发送通知以刷新UI
        await MainActor.run {
            NotificationCenter.default.post(name: NSNotification.Name("WalletJournalUpdated"), object: nil, userInfo: ["characterId": characterId])
        }
        
        return jsonString
    }
    
    // 从服务器获取钱包日志
    private func fetchJournalFromServer(characterId: Int) async throws -> [[String: Any]] {
        var allJournalEntries: [[String: Any]] = []
        var page = 1
        
        while true {
            do {
                let urlString = "https://esi.evetech.net/latest/characters/\(characterId)/wallet/journal/?datasource=tranquility&page=\(page)"
                guard let url = URL(string: urlString) else {
                    throw NetworkError.invalidURL
                }
                
                let data = try await NetworkManager.shared.fetchDataWithToken(
                    from: url,
                    characterId: characterId,
                    noRetryKeywords: ["Requested page does not exist"]
                )
                
                // 解析JSON数据
                guard let pageEntries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                    throw NetworkError.invalidResponse
                }
                
                allJournalEntries.append(contentsOf: pageEntries)
                Logger.info("成功获取第\(page)页钱包日志，本页包含\(pageEntries.count)条记录")
                
                page += 1
                try await Task.sleep(nanoseconds: UInt64(0.1 * 1_000_000_000)) // 100ms延迟
                
            } catch let error as NetworkError {
                if case .httpError(let statusCode, let message) = error,
                   statusCode == 500,
                   message?.contains("Requested page does not exist") == true {
                    // 这是正常的分页结束情况
                    Logger.info("钱包日志获取完成，共\(allJournalEntries.count)条记录")
                    break
                }
                // 其他网络错误则抛出
                throw error
            } catch {
                throw error
            }
        }
        
        return allJournalEntries
    }
    
    // 获取钱包交易记录的缓存键
    private func getTransactionsCacheKey(characterId: Int) -> String {
        return walletTransactionsCachePrefix + String(characterId)
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
        
        if case .success(let results) = CharacterDatabaseManager.shared.executeQuery(query, parameters: [characterId]) {
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
        // 首先获取已存在的交易ID
        let checkQuery = "SELECT transaction_id FROM wallet_transactions WHERE character_id = ?"
        guard case .success(let existingResults) = CharacterDatabaseManager.shared.executeQuery(checkQuery, parameters: [characterId]) else {
            Logger.error("查询现有交易记录失败")
            return false
        }
        
        let existingIds = Set(existingResults.compactMap { ($0["transaction_id"] as? Int64) })
        
        let insertSQL = """
            INSERT OR REPLACE INTO wallet_transactions (
                transaction_id, character_id, client_id, date, is_buy,
                is_personal, journal_ref_id, location_id, quantity,
                type_id, unit_price
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        
        var newCount = 0
        for entry in entries {
            let transactionId = entry["transaction_id"] as? Int64 ?? 0
            // 如果交易ID已存在，跳过
            if existingIds.contains(transactionId) {
                continue
            }
            
            // 将布尔值转换为整数
            let isBuy = (entry["is_buy"] as? Bool ?? false) ? 1 : 0
            let isPersonal = (entry["is_personal"] as? Bool ?? false) ? 1 : 0
            
            let parameters: [Any] = [
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
                entry["unit_price"] as? Double ?? 0.0
            ]
            
            if case .error(let message) = CharacterDatabaseManager.shared.executeQuery(insertSQL, parameters: parameters) {
                Logger.error("保存钱包交易记录到数据库失败: \(message)")
                return false
            }
            newCount += 1
        }
        
        if newCount > 0 {
            Logger.info("新增\(newCount)条钱包交易记录到数据库")
        }
        return true
    }
    
    // 获取钱包交易记录（公开方法）
    public func getWalletTransactions(characterId: Int, forceRefresh: Bool = false) async throws -> String? {
        // 检查是否需要刷新
        let needsRefresh = forceRefresh || shouldRefreshData(characterId: characterId, isJournal: false)
        
        // 先尝试从数据库获取数据（无论是否需要刷新）
        if let results = getWalletTransactionsFromDB(characterId: characterId) {
            let jsonData = try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                // 如果需要刷新，在返回缓存数据的同时，启动后台刷新
                if needsRefresh {
                    Task {
                        do {
                            // 从服务器获取新数据
                            let transactionData = try await fetchTransactionsFromServer(characterId: characterId)
                            
                            // 保存到数据库
                            if !saveWalletTransactionsToDB(characterId: characterId, entries: transactionData) {
                                Logger.error("保存钱包交易记录到数据库失败")
                            }
                            
                            // 更新查询时间
                            updateLastQueryTime(characterId: characterId, isJournal: false)
                            
                            // 发送通知以刷新UI
                            await MainActor.run {
                                NotificationCenter.default.post(name: NSNotification.Name("WalletTransactionsUpdated"), object: nil, userInfo: ["characterId": characterId])
                            }
                        } catch {
                            Logger.error("后台刷新钱包交易记录失败: \(error)")
                        }
                    }
                }
                return jsonString
            }
        }
        
        // 如果没有缓存数据，或者转换JSON失败，则直接从服务器获取
        let transactionData = try await fetchTransactionsFromServer(characterId: characterId)
        
        // 保存到数据库
        if !saveWalletTransactionsToDB(characterId: characterId, entries: transactionData) {
            Logger.error("保存钱包交易记录到数据库失败")
        }
        
        // 更新查询时间
        updateLastQueryTime(characterId: characterId, isJournal: false)
        
        // 转换为JSON返回
        let jsonData = try JSONSerialization.data(withJSONObject: transactionData, options: [.prettyPrinted, .sortedKeys])
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw NetworkError.invalidResponse
        }
        
        // 发送通知以刷新UI
        await MainActor.run {
            NotificationCenter.default.post(name: NSNotification.Name("WalletTransactionsUpdated"), object: nil, userInfo: ["characterId": characterId])
        }
        
        return jsonString
    }
    
    // 从服务器获取交易记录
    private func fetchTransactionsFromServer(characterId: Int) async throws -> [[String: Any]] {
        let urlString = "https://esi.evetech.net/latest/characters/\(characterId)/wallet/transactions/"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        
        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId
        )
        
        guard let transactions = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NetworkError.invalidResponse
        }
        
        Logger.info("成功获取钱包交易记录，共\(transactions.count)条记录")
        return transactions
    }
    
    // 保存交易记录到缓存
    private func saveTransactionsToCache(jsonString: String, characterId: Int) {
        let cache = WalletTransactionsCacheEntry(jsonString: jsonString, timestamp: Date())
        let key = getTransactionsCacheKey(characterId: characterId)
        if let encoded = try? JSONEncoder().encode(cache) {
            Logger.info("保存钱包交易记录到缓存 - Key: \(key), 数据大小: \(encoded.count) bytes")
            UserDefaults.standard.set(encoded, forKey: key)
        } else {
            Logger.error("保存钱包交易记录到缓存失败 - Key: \(key)")
        }
    }
} 
