import Foundation

class CharacterMiningAPI {
    static let shared = CharacterMiningAPI()
    private let databaseManager = CharacterDatabaseManager.shared

    // 缓存相关常量
    private let lastMiningQueryKey = "LastMiningLedgerQuery_"
    private let queryInterval: TimeInterval = 3600  // 1小时的查询间隔

    // 挖矿记录数据模型
    struct MiningLedgerEntry: Codable {
        let date: String
        let quantity: Int
        let solar_system_id: Int
        let type_id: Int
    }

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"  // 修改为与数据库匹配的格式
        formatter.timeZone = TimeZone(identifier: "UTC")!
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    // 用于API响应的日期格式化器
    private let apiDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")!
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private init() {}

    // 获取最后查询时间
    private func getLastQueryTime(characterId: Int) -> Date? {
        let key = lastMiningQueryKey + String(characterId)
        let lastQuery = UserDefaults.standard.object(forKey: key) as? Date

        if let lastQuery = lastQuery {
            let timeInterval = Date().timeIntervalSince(lastQuery)
            let remainingTime = queryInterval - timeInterval
            let remainingMinutes = Int(remainingTime / 60)
            let remainingSeconds = Int(remainingTime.truncatingRemainder(dividingBy: 60))

            if remainingTime > 0 {
                Logger.debug("挖矿记录下次刷新剩余时间: \(remainingMinutes)分\(remainingSeconds)秒")
            } else {
                Logger.debug("挖矿记录已过期，需要刷新")
            }
        } else {
            Logger.debug("没有找到挖矿记录的最后更新时间记录")
        }

        return lastQuery
    }

    // 更新最后查询时间
    private func updateLastQueryTime(characterId: Int) {
        let key = lastMiningQueryKey + String(characterId)
        UserDefaults.standard.set(Date(), forKey: key)
    }

    // 检查是否需要刷新数据
    private func shouldRefreshData(characterId: Int) -> Bool {
        guard let lastQuery = getLastQueryTime(characterId: characterId) else {
            return true
        }
        return Date().timeIntervalSince(lastQuery) >= queryInterval
    }

    // 从数据库获取挖矿记录
    private func getMiningLedgerFromDB(characterId: Int) -> [MiningLedgerEntry]? {
        let query = """
                SELECT date, quantity, solar_system_id, type_id
                FROM mining_ledger 
                WHERE character_id = ? 
                ORDER BY date DESC 
                LIMIT 1000
            """

        let result = CharacterDatabaseManager.shared.executeQuery(query, parameters: [characterId])

        switch result {
        case let .success(rows):
            Logger.debug("从数据库获取到原始数据：\(rows.count)行")

            let entries = rows.compactMap { row -> MiningLedgerEntry? in
                // Logger.debug("正在处理行：\(row)")

                // 尝试类型转换
                guard let date = row["date"] as? String,
                    let quantity = (row["quantity"] as? Int64).map(Int.init)
                        ?? (row["quantity"] as? Int),
                    let solarSystemId = (row["solar_system_id"] as? Int64).map(Int.init)
                        ?? (row["solar_system_id"] as? Int),
                    let typeId = (row["type_id"] as? Int64).map(Int.init)
                        ?? (row["type_id"] as? Int)
                else {
                    Logger.error("转换挖矿记录失败：\(row)")
                    return nil
                }

                return MiningLedgerEntry(
                    date: date,
                    quantity: quantity,
                    solar_system_id: solarSystemId,
                    type_id: typeId
                )
            }

            Logger.debug("成功转换记录数：\(entries.count)")
            return entries

        case let .error(message):
            Logger.error("查询挖矿记录失败：\(message)")
            return nil
        }
    }

    // 保存挖矿记录到数据库
    private func saveMiningLedgerToDB(characterId: Int, entries: [MiningLedgerEntry]) -> Bool {
        let insertSQL = """
                INSERT OR REPLACE INTO mining_ledger (
                    character_id, date, quantity, solar_system_id, type_id
                ) VALUES (?, ?, ?, ?, ?)
            """

        var updateCount = 0
        for entry in entries {
            let parameters: [Any] = [
                characterId,
                entry.date,
                entry.quantity,
                entry.solar_system_id,
                entry.type_id,
            ]

            if case let .error(message) = databaseManager.executeQuery(
                insertSQL, parameters: parameters
            ) {
                Logger.error("保存挖矿记录到数据库失败: \(message)")
                return false
            }
            updateCount += 1
        }

        Logger.info("更新了\(updateCount)条挖矿记录")
        return true
    }

    // 从服务器获取挖矿记录
    private func fetchFromServer(characterId: Int) async throws -> [MiningLedgerEntry] {
        let baseUrlString =
            "https://esi.evetech.net/latest/characters/\(characterId)/mining/?datasource=tranquility"
        guard let baseUrl = URL(string: baseUrlString) else {
            throw NetworkError.invalidURL
        }

        let entries = try await NetworkManager.shared.fetchPaginatedData(
            from: baseUrl,
            characterId: characterId,
            maxConcurrentPages: 3,  // 设置合理的并发数
            decoder: { data in
                try JSONDecoder().decode([MiningLedgerEntry].self, from: data)
            }
        )

        // 转换API返回的日期格式为数据库格式
        let convertedEntries = entries.map { entry -> MiningLedgerEntry in
            if let date = apiDateFormatter.date(from: entry.date) {
                let convertedDate = dateFormatter.string(from: date)
                return MiningLedgerEntry(
                    date: convertedDate,
                    quantity: entry.quantity,
                    solar_system_id: entry.solar_system_id,
                    type_id: entry.type_id
                )
            }
            return entry
        }

        Logger.info("成功获取挖矿记录，共\(convertedEntries.count)条记录")
        return convertedEntries
    }

    // 获取挖矿记录（公开方法）
    public func getMiningLedger(characterId: Int, forceRefresh: Bool = false) async throws
        -> [MiningLedgerEntry]
    {
        // 检查是否需要刷新数据
        if !forceRefresh {
            if let entries = getMiningLedgerFromDB(characterId: characterId),
                !entries.isEmpty,
                !shouldRefreshData(characterId: characterId)
            {
                return entries
            }
        }

        // 从服务器获取数据
        let entries = try await fetchFromServer(characterId: characterId)
        if !saveMiningLedgerToDB(characterId: characterId, entries: entries) {
            Logger.error("保存挖矿记录到数据库失败")
        }

        // 更新最后查询时间
        updateLastQueryTime(characterId: characterId)

        return getMiningLedgerFromDB(characterId: characterId) ?? []
    }

    // 清除缓存
    func clearCache() {
        // 只清除 UserDefaults 中的查询时间记录
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys {
            if key.hasPrefix(lastMiningQueryKey) {
                defaults.removeObject(forKey: key)
            }
        }

        Logger.debug("清除挖矿记录查询时间记录")
    }
}
