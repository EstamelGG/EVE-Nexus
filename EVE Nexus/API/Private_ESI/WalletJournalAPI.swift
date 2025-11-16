import Foundation

class WalletJournalAPI {
    static let shared = WalletJournalAPI()

    private let journalLastUpdatePrefix = "wallet_journal_last_update_"
    private let journalCacheTimeout: TimeInterval = 3600 // 1小时的流水缓存超时时间

    private init() {}

    // MARK: - UserDefaults 管理

    // 获取/设置上次更新时间
    private func getJournalLastUpdateTime(characterId: Int) -> Date? {
        let key = journalLastUpdatePrefix + String(characterId)
        if let timestamp = UserDefaults.standard.object(forKey: key) as? Date {
            return timestamp
        }
        return nil
    }

    private func setJournalLastUpdateTime(characterId: Int, date: Date) {
        let key = journalLastUpdatePrefix + String(characterId)
        UserDefaults.standard.set(date, forKey: key)
        Logger.info("更新钱包流水最后更新时间 - 角色ID: \(characterId), 时间: \(date)")
    }

    // MARK: - 数据库操作

    // 从数据库获取某角色的所有钱包流水数据
    private func getWalletJournalFromDatabase(characterId: Int) -> [[String: Any]]? {
        let query = """
            SELECT id, character_id, amount, balance, date, description, first_party_id,
                   reason, ref_type, second_party_id, context_id, context_id_type
            FROM char_wallet_journal
            WHERE character_id = ?
            ORDER BY date DESC, id DESC
        """

        if case let .success(rows) = CharacterDatabaseManager.shared.executeQuery(query, parameters: [characterId]) {
            let entries = rows.map { row -> [String: Any] in
                var entry: [String: Any] = [:]

                if let id = row["id"] as? Int64 {
                    entry["id"] = id
                }
                if let amount = row["amount"] as? Double {
                    entry["amount"] = amount
                }
                if let balance = row["balance"] as? Double {
                    entry["balance"] = balance
                }
                if let date = row["date"] as? String {
                    entry["date"] = date
                }
                if let description = row["description"] as? String {
                    entry["description"] = description
                }
                if let firstPartyId = row["first_party_id"] as? Int64 {
                    entry["first_party_id"] = Int(firstPartyId)
                }
                if let reason = row["reason"] as? String {
                    entry["reason"] = reason
                }
                if let refType = row["ref_type"] as? String {
                    entry["ref_type"] = refType
                }
                if let secondPartyId = row["second_party_id"] as? Int64 {
                    entry["second_party_id"] = Int(secondPartyId)
                }
                if let contextId = row["context_id"] as? Int64 {
                    entry["context_id"] = contextId
                } else if row["context_id"] is NSNull {
                    entry["context_id"] = NSNull()
                }
                if let contextIdType = row["context_id_type"] as? String {
                    entry["context_id_type"] = contextIdType
                } else if row["context_id_type"] is NSNull {
                    entry["context_id_type"] = NSNull()
                }

                return entry
            }

            Logger.info("成功从数据库读取钱包流水 - 角色ID: \(characterId), 记录数量: \(entries.count)")
            return entries
        }

        Logger.error("从数据库读取钱包流水失败 - 角色ID: \(characterId)")
        return nil
    }

    // 获取某角色的最大流水ID
    private func getMaxJournalId(characterId: Int) -> Int64? {
        let query = """
            SELECT MAX(id) as max_id FROM char_wallet_journal
            WHERE character_id = ?
        """

        if case let .success(rows) = CharacterDatabaseManager.shared.executeQuery(query, parameters: [characterId]) {
            if let row = rows.first,
               let maxId = row["max_id"] as? Int64
            {
                Logger.info("获取最大流水ID - 角色ID: \(characterId), 最大ID: \(maxId)")
                return maxId
            }
        }

        Logger.info("数据库中暂无流水记录或查询失败 - 角色ID: \(characterId)")
        return nil
    }

    // 批量插入钱包流水到数据库（增量更新）
    private func saveWalletJournalToDatabase(characterId: Int, entries: [[String: Any]]) -> Bool {
        Logger.info("开始保存钱包流水到数据库（增量更新） - 角色ID: \(characterId), 记录数量: \(entries.count)")

        guard !entries.isEmpty else {
            Logger.info("没有钱包流水记录需要保存")
            return true
        }

        // 获取当前最大ID，过滤增量数据
        let maxId = getMaxJournalId(characterId: characterId) ?? 0
        let incrementalEntries = entries.filter { entry in
            if let id = entry["id"] as? Int64 {
                return id > maxId
            }
            return false
        }

        guard !incrementalEntries.isEmpty else {
            Logger.info("没有新的流水记录需要插入 - 角色ID: \(characterId), 当前最大ID: \(maxId)")
            return true
        }

        Logger.info("准备插入 \(incrementalEntries.count) 条新记录 - 角色ID: \(characterId)")

        // 开始事务
        _ = CharacterDatabaseManager.shared.executeQuery("BEGIN TRANSACTION")

        // 批量插入大小
        let batchSize = 500
        var success = true

        // 分批处理数据
        for batchStart in stride(from: 0, to: incrementalEntries.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, incrementalEntries.count)
            let currentBatch = Array(incrementalEntries[batchStart ..< batchEnd])

            // 先过滤出有效的记录
            var validEntries: [[String: Any]] = []
            for entry in currentBatch {
                guard entry["id"] as? Int64 != nil else {
                    Logger.warning("钱包流水记录缺少id字段，跳过")
                    continue
                }
                validEntries.append(entry)
            }

            guard !validEntries.isEmpty else {
                continue
            }

            // 构建批量插入语句
            let placeholders = Array(repeating: "(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", count: validEntries.count)
                .joined(separator: ",")
            let insertSQL = """
                INSERT OR IGNORE INTO char_wallet_journal (
                    id, character_id, amount, balance, date, description, first_party_id,
                    reason, ref_type, second_party_id, context_id, context_id_type
                ) VALUES \(placeholders)
            """

            // 准备参数数组
            var parameters: [Any] = []
            for entry in validEntries {
                guard let id = entry["id"] as? Int64 else {
                    continue
                }

                parameters.append(contentsOf: [
                    id,
                    characterId,
                    (entry["amount"] as? Double) ?? 0.0,
                    (entry["balance"] as? Double) ?? 0.0,
                    (entry["date"] as? String) ?? "",
                    (entry["description"] as? String) ?? "",
                    (entry["first_party_id"] as? Int) ?? 0,
                    (entry["reason"] as? String) ?? "",
                    (entry["ref_type"] as? String) ?? "",
                    (entry["second_party_id"] as? Int) ?? 0,
                    (entry["context_id"] as? Int64) ?? NSNull(),
                    (entry["context_id_type"] as? String) ?? NSNull(),
                ])
            }

            // 执行批量插入
            if case let .error(message) = CharacterDatabaseManager.shared.executeQuery(insertSQL, parameters: parameters) {
                Logger.error("批量插入钱包流水失败: \(message)")
                success = false
                break
            }
        }

        // 根据执行结果提交或回滚事务
        if success {
            _ = CharacterDatabaseManager.shared.executeQuery("COMMIT")
            // 更新最后更新时间
            setJournalLastUpdateTime(characterId: characterId, date: Date())
            Logger.success("钱包流水保存完成 - 角色ID: \(characterId), 新增: \(incrementalEntries.count), 总记录: \(entries.count)")
            return true
        } else {
            _ = CharacterDatabaseManager.shared.executeQuery("ROLLBACK")
            Logger.error("保存钱包流水失败，执行回滚 - 角色ID: \(characterId)")
            return false
        }
    }

    // MARK: - 缓存检查

    // 检查钱包流水缓存是否过期（基于数据库和UserDefaults）
    private func isJournalCacheExpired(characterId: Int) -> Bool {
        // 检查UserDefaults中的最后更新时间
        if let lastUpdate = getJournalLastUpdateTime(characterId: characterId) {
            let timeInterval = Date().timeIntervalSince(lastUpdate)
            let isExpired = timeInterval > journalCacheTimeout

            Logger.info(
                "钱包流水缓存状态检查 - 角色ID: \(characterId), 最后更新时间: \(lastUpdate), 时间间隔: \(Int(timeInterval))秒, 是否过期: \(isExpired)"
            )
            return isExpired
        }

        // 如果没有更新时间记录，检查数据库中是否有数据
        if getMaxJournalId(characterId: characterId) != nil {
            // 数据库有数据但没有更新时间记录，认为已过期需要刷新
            Logger.info("数据库中有数据但缺少更新时间记录，需要刷新 - 角色ID: \(characterId)")
            return true
        }

        // 数据库中没有数据，需要刷新
        Logger.info("数据库中暂无流水记录，需要刷新 - 角色ID: \(characterId)")
        return true
    }

    // MARK: - 网络请求

    // 从服务器获取钱包流水
    private func fetchJournalFromServer(characterId: Int) async throws -> [[String: Any]] {
        let baseUrlString =
            "https://esi.evetech.net/characters/\(characterId)/wallet/journal/?datasource=tranquility"
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

    // MARK: - 公开接口

    // 获取钱包流水
    func getWalletJournal(characterId: Int, forceRefresh: Bool = false) async throws -> String? {
        Logger.info("开始获取钱包流水 - 角色ID: \(characterId), 强制刷新: \(forceRefresh)")

        // 检查是否需要从网络获取数据
        var needRefresh = forceRefresh || isJournalCacheExpired(characterId: characterId)

        // 如果缓存未过期，检查数据库中是否有记录
        if !needRefresh {
            if let results = getWalletJournalFromDatabase(characterId: characterId) {
                if results.isEmpty {
                    // 缓存未过期但数据库中没有记录，可能是数据库被清空，需要重新加载
                    Logger.warning("缓存未过期但数据库中无记录，忽略缓存时间重新加载 - 角色ID: \(characterId)")
                    needRefresh = true
                }
            } else {
                // 数据库查询失败，需要重新加载
                Logger.warning("数据库查询失败，重新加载 - 角色ID: \(characterId)")
                needRefresh = true
            }
        }

        // 如果需要刷新，则从网络获取
        if needRefresh {
            Logger.info("钱包流水需要刷新，从网络获取数据 - 角色ID: \(characterId)")
            let journalData = try await fetchJournalFromServer(characterId: characterId)
            if !saveWalletJournalToDatabase(characterId: characterId, entries: journalData) {
                Logger.error("保存钱包流水到数据库失败 - 角色ID: \(characterId)")
            }
        } else {
            Logger.info("使用数据库中的钱包流水数据 - 角色ID: \(characterId)")
        }

        // 从数据库获取数据并返回
        if let results = getWalletJournalFromDatabase(characterId: characterId) {
            let jsonData = try JSONSerialization.data(
                withJSONObject: results, options: [.prettyPrinted, .sortedKeys]
            )
            Logger.info("钱包流水数据处理完成 - 角色ID: \(characterId), JSON大小: \(jsonData.count) bytes")
            return String(data: jsonData, encoding: .utf8)
        }

        Logger.error("无法获取钱包流水数据 - 角色ID: \(characterId)")
        return nil
    }

    // 使缓存失效
    func invalidateCache(characterId: Int) {
        let journalLastUpdateKey = journalLastUpdatePrefix + String(characterId)
        UserDefaults.standard.removeObject(forKey: journalLastUpdateKey)
        Logger.info("已清除钱包流水最后更新时间 - 角色ID: \(characterId)")
    }

    // MARK: - 数据清理

    /// 清理超过1年的旧数据（仅在应用初始化时调用）
    /// - Returns: 清理的记录数量
    func cleanupOldData() -> Int {
        Logger.info("开始清理钱包流水旧数据...")

        // 检查总记录数
        let countQuery = "SELECT COUNT(*) as total FROM char_wallet_journal"
        guard case let .success(countRows) = CharacterDatabaseManager.shared.executeQuery(countQuery) else {
            Logger.error("查询钱包流水总记录数失败")
            return 0
        }

        guard let totalCountValue = countRows.first?["total"] as? Int64 else {
            Logger.info("无法获取钱包流水总记录数，跳过清理")
            return 0
        }

        guard totalCountValue >= 1000 else {
            Logger.info("钱包流水总记录数(\(totalCountValue))少于1000条，跳过清理")
            return 0
        }

        let totalCount = totalCountValue

        // 计算1年前的日期（ISO8601格式）
        let oneYearAgo = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]
        let cutoffDate = dateFormatter.string(from: oneYearAgo)

        Logger.info("清理钱包流水：总记录数 \(totalCount)，删除日期早于 \(cutoffDate) 的记录")

        // 开始事务
        _ = CharacterDatabaseManager.shared.executeQuery("BEGIN TRANSACTION")

        // 删除超过1年的记录
        let deleteQuery = "DELETE FROM char_wallet_journal WHERE date < ?"
        let result = CharacterDatabaseManager.shared.executeQuery(deleteQuery, parameters: [cutoffDate])

        switch result {
        case .success:
            // 获取删除的记录数
            let changesQuery = "SELECT changes() as deleted_count"
            if case let .success(changeRows) = CharacterDatabaseManager.shared.executeQuery(changesQuery),
               let deletedCount = changeRows.first?["deleted_count"] as? Int64
            {
                _ = CharacterDatabaseManager.shared.executeQuery("COMMIT")
                Logger.success("钱包流水清理完成，删除了 \(deletedCount) 条记录")
                return Int(deletedCount)
            } else {
                _ = CharacterDatabaseManager.shared.executeQuery("COMMIT")
                Logger.info("钱包流水清理完成")
                return 0
            }
        case let .error(message):
            _ = CharacterDatabaseManager.shared.executeQuery("ROLLBACK")
            Logger.error("钱包流水清理失败: \(message)")
            return 0
        }
    }
}
