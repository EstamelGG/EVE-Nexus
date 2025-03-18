import Foundation

// 军团钱包数据模型
struct CorpWallet: Codable {
    let division: Int
    let balance: Double
    var name: String?
}

// 军团部门数据模型
struct CorpDivisions: Codable {
    let hangar: [DivisionInfo]
    let wallet: [DivisionInfo]
}

struct DivisionInfo: Codable {
    let division: Int
    let name: String?
}

@globalActor actor CorpWalletAPIActor {
    static let shared = CorpWalletAPIActor()
}

@CorpWalletAPIActor
class CorpWalletAPI {
    static let shared = CorpWalletAPI()

    private init() {}

    /// 获取军团钱包信息
    /// - Parameters:
    ///   - characterId: 角色ID
    ///   - forceRefresh: 是否强制刷新缓存
    /// - Returns: 军团钱包数组
    func fetchCorpWallets(characterId: Int, forceRefresh: Bool = false) async throws -> [CorpWallet]
    {
        // 1. 获取角色的军团ID
        guard
            let corporationId = try await CharacterDatabaseManager.shared.getCharacterCorporationId(
                characterId: characterId)
        else {
            throw NetworkError.authenticationError("无法获取军团ID")
        }

        // 2. 获取部门信息
        let divisions = try await fetchCorpDivisions(
            characterId: characterId, forceRefresh: forceRefresh
        )

        // 3. 检查缓存
        let cacheKey = "corp_wallets_\(corporationId)"
        let cacheTimeKey = "corp_wallets_\(corporationId)_time"

        if !forceRefresh,
            let cachedData = UserDefaults.standard.data(forKey: cacheKey),
            let lastUpdateTime = UserDefaults.standard.object(forKey: cacheTimeKey) as? Date,
            Date().timeIntervalSince(lastUpdateTime) < 60 * 60
        {  // 60 分钟缓存
            do {
                var wallets = try JSONDecoder().decode([CorpWallet].self, from: cachedData)
                // 添加部门名称
                for i in 0..<wallets.count {
                    let division = wallets[i].division
                    if let divisionInfo = divisions.wallet.first(where: { $0.division == division })
                    {
                        wallets[i].name = getDivisionName(
                            division: division, type: "wallet", customName: divisionInfo.name
                        )
                    }
                }
                Logger.info("使用缓存的军团钱包数据 - 军团ID: \(corporationId)")
                return wallets
            } catch {
                Logger.error("解析缓存的军团钱包数据失败: \(error)")
            }
        }

        // 4. 构建请求
        let urlString =
            "https://esi.evetech.net/latest/corporations/\(corporationId)/wallets/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        // 5. 发送请求
        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url, characterId: characterId
        )
        var wallets = try JSONDecoder().decode([CorpWallet].self, from: data)

        // 6. 添加部门名称
        for i in 0..<wallets.count {
            let division = wallets[i].division
            if let divisionInfo = divisions.wallet.first(where: { $0.division == division }) {
                wallets[i].name = getDivisionName(
                    division: division, type: "wallet", customName: divisionInfo.name
                )
            }
        }

        // 7. 更新缓存
        UserDefaults.standard.set(data, forKey: cacheKey)
        UserDefaults.standard.set(Date(), forKey: cacheTimeKey)

        Logger.info("成功获取军团钱包数据 - 军团ID: \(corporationId)")
        return wallets
    }

    /// 获取军团部门信息
    /// - Parameters:
    ///   - characterId: 角色ID
    ///   - forceRefresh: 是否强制刷新缓存
    /// - Returns: 军团部门信息
    func fetchCorpDivisions(characterId: Int, forceRefresh: Bool = false) async throws
        -> CorpDivisions
    {
        // 1. 获取角色的军团ID
        guard
            let corporationId = try await CharacterDatabaseManager.shared.getCharacterCorporationId(
                characterId: characterId)
        else {
            throw NetworkError.authenticationError("无法获取军团ID")
        }

        // 2. 检查缓存
        let cacheKey = "corp_divisions_\(corporationId)"
        let cacheTimeKey = "corp_divisions_\(corporationId)_time"

        if !forceRefresh,
            let cachedData = UserDefaults.standard.data(forKey: cacheKey),
            let lastUpdateTime = UserDefaults.standard.object(forKey: cacheTimeKey) as? Date,
            Date().timeIntervalSince(lastUpdateTime) < 60 * 60
        {  // 1小时缓存
            do {
                let divisions = try JSONDecoder().decode(CorpDivisions.self, from: cachedData)
                Logger.info("使用缓存的军团部门数据 - 军团ID: \(corporationId)")
                return divisions
            } catch {
                Logger.error("解析缓存的军团部门数据失败: \(error)")
            }
        }

        // 3. 构建请求
        let urlString =
            "https://esi.evetech.net/latest/corporations/\(corporationId)/divisions/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        // 4. 发送请求
        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url, characterId: characterId
        )
        let divisions = try JSONDecoder().decode(CorpDivisions.self, from: data)

        // 5. 更新缓存
        UserDefaults.standard.set(data, forKey: cacheKey)
        UserDefaults.standard.set(Date(), forKey: cacheTimeKey)

        Logger.info("成功获取军团部门数据 - 军团ID: \(corporationId)")
        return divisions
    }

    /// 获取部门名称
    /// - Parameters:
    ///   - division: 部门编号
    ///   - type: 部门类型 ("hangar" 或 "wallet")
    ///   - customName: 自定义名称
    /// - Returns: 本地化的部门名称
    func getDivisionName(division: Int, type: String, customName: String?) -> String {
        if let name = customName {
            return name
        }

        // 根据类型返回默认名称
        if type == "hangar" {
            return String(
                format: NSLocalizedString("Main_Corporation_Hangar_Default", comment: ""), division
            )
        } else {
            if division == 1 {
                return String(
                    format: NSLocalizedString("Main_Corporation_Wallet_Division1", comment: ""),
                    division
                )
            } else {
                return String(
                    format: NSLocalizedString("Main_Corporation_Wallet_Default", comment: ""),
                    division
                )
            }
        }
    }

    /// 清理缓存
    func clearCache() {
        let defaults = UserDefaults.standard
        let allKeys = defaults.dictionaryRepresentation().keys

        // 清理所有军团钱包相关的缓存
        for key in allKeys {
            if key.hasPrefix("corp_wallets_") {
                defaults.removeObject(forKey: key)
            }
        }

        Logger.info("已清理军团钱包缓存")
    }

    /// 从服务器获取军团钱包日志
    /// - Parameters:
    ///   - characterId: 角色ID
    ///   - division: 部门编号
    ///   - progressCallback: 加载进度回调
    /// - Returns: 钱包日志数组
    private func fetchCorpJournalFromServer(
        characterId: Int,
        corporationId: Int,
        division: Int,
        progressCallback: ((WalletLoadingProgress) -> Void)? = nil
    ) async throws -> [[String: Any]] {
        let baseUrlString =
            "https://esi.evetech.net/latest/corporations/\(corporationId)/wallets/\(division)/journal/?datasource=tranquility"
        guard let baseUrl = URL(string: baseUrlString) else {
            throw NetworkError.invalidURL
        }

        return try await NetworkManager.shared.fetchPaginatedData(
            from: baseUrl,
            characterId: characterId,
            maxConcurrentPages: 5,
            decoder: { data in
                guard
                    let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
                else {
                    throw NetworkError.invalidResponse
                }
                return entries
            },
            progressCallback: { page in
                progressCallback?(.loading(page: page))
            }
        )

        //        let urlString =
        //            "https://esi.evetech.net/latest/corporations/\(corporationId)/wallets/\(division)/journal/?datasource=tranquility&page=1"
        //        guard let url = URL(string: urlString) else {
        //            throw NetworkError.invalidURL
        //        }
        //
        //        // 通知进度回调
        //        progressCallback?(.loading(page: 1))
        //
        //        // 使用fetchDataWithToken获取数据
        //        let data = try await NetworkManager.shared.fetchDataWithToken(
        //            from: url, characterId: characterId
        //        )
        //
        //        // 解析返回的JSON数据
        //        guard let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
        //            throw NetworkError.invalidResponse
        //        }
        //
        //        Logger.info("成功获取军团钱包日志，共\(entries.count)条记录")
        //        return entries
    }

    /// 从数据库获取军团钱包日志
    /// - Parameters:
    ///   - corporationId: 军团ID
    ///   - division: 部门编号
    /// - Returns: 钱包日志数组
    /// 只取近30天的数据
    private func getCorpWalletJournalFromDB(corporationId: Int, division: Int) -> [[String: Any]]? {
        let query = """
                SELECT id, corporation_id, division, amount, balance, context_id,
                       context_id_type, date, description, first_party_id,
                       reason, ref_type, second_party_id
                FROM corp_wallet_journal 
                WHERE corporation_id = ? AND division = ?
                AND date >= datetime('now', '-30 days')
                ORDER BY date DESC
            """

        if case let .success(results) = CharacterDatabaseManager.shared.executeQuery(
            query, parameters: [corporationId, division]
        ) {
            return results
        }
        return nil
    }

    /// 保存军团钱包日志到数据库
    /// - Parameters:
    ///   - corporationId: 军团ID
    ///   - division: 部门编号
    ///   - entries: 日志条目
    /// - Returns: 是否保存成功
    private func saveCorpWalletJournalToDB(
        corporationId: Int, division: Int, entries: [[String: Any]]
    ) -> Bool {
        // 首先获取已存在的日志ID
        let checkQuery =
            "SELECT id FROM corp_wallet_journal WHERE corporation_id = ? AND division = ?"
        guard
            case let .success(existingResults) = CharacterDatabaseManager.shared.executeQuery(
                checkQuery, parameters: [corporationId, division]
            )
        else {
            Logger.error("查询现有军团钱包日志失败")
            return false
        }

        let existingIds = Set(existingResults.compactMap { ($0["id"] as? Int64) })

        // 过滤出需要插入的新记录
        let newEntries = entries.filter { entry in
            let journalId = entry["id"] as? Int64 ?? 0
            return !existingIds.contains(journalId)
        }

        if newEntries.isEmpty {
            Logger.info("无需新增军团钱包日志")
            return true
        }

        // 开始事务
        let beginTransaction = "BEGIN TRANSACTION"
        _ = CharacterDatabaseManager.shared.executeQuery(beginTransaction)

        // 计算每批次的大小（每条记录13个参数）
        let batchSize = 500  // 每批次处理500条记录
        var success = true

        // 分批处理数据
        for batchStart in stride(from: 0, to: newEntries.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, newEntries.count)
            let currentBatch = Array(newEntries[batchStart..<batchEnd])

            // 构建批量插入语句
            let placeholders = Array(
                repeating: "(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", count: currentBatch.count
            ).joined(separator: ",")
            let insertSQL = """
                    INSERT OR REPLACE INTO corp_wallet_journal (
                        id, corporation_id, division, amount, balance, context_id,
                        context_id_type, date, description, first_party_id,
                        reason, ref_type, second_party_id
                    ) VALUES \(placeholders)
                """

            // 准备参数数组
            var parameters: [Any] = []
            for entry in currentBatch {
                let journalId = entry["id"] as? Int64 ?? 0
                let params: [Any] = [
                    journalId,
                    corporationId,
                    division,
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

            Logger.debug("执行批量插入军团钱包日志，批次大小: \(currentBatch.count), 参数数量: \(parameters.count)")

            // 执行批量插入
            if case let .error(message) = CharacterDatabaseManager.shared.executeQuery(
                insertSQL, parameters: parameters
            ) {
                Logger.error("批量插入军团钱包日志失败: \(message)")
                success = false
                break
            }
        }

        // 根据执行结果提交或回滚事务
        if success {
            _ = CharacterDatabaseManager.shared.executeQuery("COMMIT")
            Logger.info("新增\(newEntries.count)条军团钱包日志到数据库")
            return true
        } else {
            _ = CharacterDatabaseManager.shared.executeQuery("ROLLBACK")
            Logger.error("保存军团钱包日志失败，执行回滚")
            return false
        }
    }

    /// 获取军团钱包日志（公开方法）
    /// - Parameters:
    ///   - characterId: 角色ID
    ///   - division: 部门编号
    ///   - forceRefresh: 是否强制刷新
    ///   - progressCallback: 加载进度回调
    /// - Returns: JSON格式的日志数据
    public func getCorpWalletJournal(
        characterId: Int,
        division: Int,
        forceRefresh: Bool = false,
        progressCallback: ((WalletLoadingProgress) -> Void)? = nil
    ) async throws -> String? {
        // 1. 获取军团ID
        guard
            let corporationId = try await CharacterDatabaseManager.shared.getCharacterCorporationId(
                characterId: characterId)
        else {
            throw NetworkError.authenticationError("无法获取军团ID")
        }

        // 2. 检查数据库中是否有数据
        let checkQuery =
            "SELECT COUNT(*) as count FROM corp_wallet_journal WHERE corporation_id = ? AND division = ?"
        let result = CharacterDatabaseManager.shared.executeQuery(
            checkQuery, parameters: [corporationId, division]
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

        // 3. 如果数据为空或强制刷新，则从网络获取
        if isEmpty || forceRefresh {
            Logger.debug("军团钱包日志为空或需要刷新，从网络获取数据")
            let journalData = try await fetchCorpJournalFromServer(
                characterId: characterId,
                corporationId: corporationId,
                division: division,
                progressCallback: progressCallback
            )
            if !saveCorpWalletJournalToDB(
                corporationId: corporationId, division: division, entries: journalData
            ) {
                Logger.error("保存军团钱包日志到数据库失败")
            }
        } else {
            Logger.debug("使用数据库中的军团钱包日志数据")
        }

        // 4. 从数据库获取数据并返回
        if let results = getCorpWalletJournalFromDB(
            corporationId: corporationId, division: division
        ) {
            let jsonData = try JSONSerialization.data(
                withJSONObject: results, options: [.prettyPrinted, .sortedKeys]
            )
            return String(data: jsonData, encoding: .utf8)
        }
        return nil
    }

    /// 获取军团钱包交易记录（公开方法）
    public func getCorpWalletTransactions(
        characterId: Int, division: Int, forceRefresh: Bool = false
    ) async throws -> String? {
        // 1. 获取军团ID
        guard
            let corporationId = try await CharacterDatabaseManager.shared.getCharacterCorporationId(
                characterId: characterId)
        else {
            throw NetworkError.authenticationError("无法获取军团ID")
        }

        // 2. 检查数据库中是否有数据
        let checkQuery =
            "SELECT COUNT(*) as count FROM corp_wallet_transactions WHERE corporation_id = ? AND division = ?"
        let result = CharacterDatabaseManager.shared.executeQuery(
            checkQuery, parameters: [corporationId, division]
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

        // 3. 如果数据为空或强制刷新，则从网络获取
        if isEmpty || forceRefresh {
            Logger.debug("军团钱包交易记录为空或需要刷新，从网络获取数据")
            let transactionData = try await fetchCorpTransactionsFromServer(
                characterId: characterId, corporationId: corporationId, division: division
            )
            if !saveCorpWalletTransactionsToDB(
                corporationId: corporationId, division: division, entries: transactionData
            ) {
                Logger.error("保存军团钱包交易记录到数据库失败")
            }
        } else {
            Logger.debug("使用数据库中的军团钱包交易记录数据")
        }

        // 4. 从数据库获取数据并返回
        if let results = getCorpWalletTransactionsFromDB(
            corporationId: corporationId, division: division
        ) {
            let jsonData = try JSONSerialization.data(
                withJSONObject: results, options: [.prettyPrinted, .sortedKeys]
            )
            return String(data: jsonData, encoding: .utf8)
        }
        return nil
    }

    /// 从服务器获取军团交易记录
    private func fetchCorpTransactionsFromServer(
        characterId: Int, corporationId: Int, division: Int
    ) async throws -> [[String: Any]] {
        let urlString =
            "https://esi.evetech.net/latest/corporations/\(corporationId)/wallets/\(division)/transactions/"
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

        Logger.info("成功获取军团钱包交易记录，共\(transactions.count)条记录")
        return transactions
    }

    /// 从数据库获取军团钱包交易记录
    private func getCorpWalletTransactionsFromDB(corporationId: Int, division: Int) -> [[String:
        Any]]?
    {
        let query = """
                SELECT transaction_id, client_id, date, is_buy, is_personal,
                       journal_ref_id, location_id, quantity, type_id,
                       unit_price, last_updated
                FROM corp_wallet_transactions 
                WHERE corporation_id = ? AND division = ?
                ORDER BY date DESC 
                LIMIT 1000
            """

        if case let .success(results) = CharacterDatabaseManager.shared.executeQuery(
            query, parameters: [corporationId, division]
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

    /// 保存军团钱包交易记录到数据库
    private func saveCorpWalletTransactionsToDB(
        corporationId: Int, division: Int, entries: [[String: Any]]
    ) -> Bool {
        // 首先获取已存在的交易ID
        let checkQuery =
            "SELECT transaction_id FROM corp_wallet_transactions WHERE corporation_id = ? AND division = ?"
        guard
            case let .success(existingResults) = CharacterDatabaseManager.shared.executeQuery(
                checkQuery, parameters: [corporationId, division]
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

        if newEntries.isEmpty {
            Logger.info("无需新增交易记录")
            return true
        }

        // 开始事务
        let beginTransaction = "BEGIN TRANSACTION"
        _ = CharacterDatabaseManager.shared.executeQuery(beginTransaction)

        // 计算每批次的大小（每条记录12个参数）
        let batchSize = 500  // 每批次处理500条记录
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
                    INSERT OR REPLACE INTO corp_wallet_transactions (
                        transaction_id, corporation_id, division, client_id, date, is_buy,
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
                    corporationId,
                    division,
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

            Logger.debug("执行批量插入军团钱包交易记录，批次大小: \(currentBatch.count), 参数数量: \(parameters.count)")

            // 执行批量插入
            if case let .error(message) = CharacterDatabaseManager.shared.executeQuery(
                insertSQL, parameters: parameters
            ) {
                Logger.error("批量插入军团钱包交易记录失败: \(message)")
                success = false
                break
            }
        }

        // 根据执行结果提交或回滚事务
        if success {
            _ = CharacterDatabaseManager.shared.executeQuery("COMMIT")
            Logger.info("新增\(newEntries.count)条军团钱包交易记录到数据库")
            return true
        } else {
            _ = CharacterDatabaseManager.shared.executeQuery("ROLLBACK")
            Logger.error("保存军团钱包交易记录失败，执行回滚")
            return false
        }
    }
}
