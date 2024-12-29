import Foundation

class CharacterMiningAPI {
    static let shared = CharacterMiningAPI()
    private let databaseManager = CharacterDatabaseManager.shared
    
    // 缓存相关常量
    private let lastMiningQueryKey = "LastMiningLedgerQuery_"
    private let queryInterval: TimeInterval = 3600 // 1小时的查询间隔
    
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
        case .success(let rows):
            Logger.debug("从数据库获取到原始数据：\(rows.count)行")
            
            let entries = rows.compactMap { row -> MiningLedgerEntry? in
                Logger.debug("正在处理行：\(row)")
                
                // 尝试类型转换
                guard let date = row["date"] as? String,
                      let quantity = (row["quantity"] as? Int64).map(Int.init) ?? (row["quantity"] as? Int),
                      let solarSystemId = (row["solar_system_id"] as? Int64).map(Int.init) ?? (row["solar_system_id"] as? Int),
                      let typeId = (row["type_id"] as? Int64).map(Int.init) ?? (row["type_id"] as? Int) else {
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
            
        case .error(let message):
            Logger.error("查询挖矿记录失败：\(message)")
            return nil
        }
    }
    
    // 保存挖矿记录到数据库
    private func saveMiningLedgerToDB(characterId: Int, entries: [MiningLedgerEntry]) -> Bool {
        // 首先获取已存在的记录
        let checkQuery = """
            SELECT date, type_id 
            FROM mining_ledger 
            WHERE character_id = ?
        """
        
        guard case .success(let existingResults) = databaseManager.executeQuery(checkQuery, parameters: [characterId]) else {
            Logger.error("查询现有挖矿记录失败")
            return false
        }
        
        // 创建一个Set来存储已存在的记录的唯一标识（日期+类型ID）
        let existingRecords = Set(existingResults.compactMap { row -> String? in
            if let date = row["date"] as? String,
               let typeId = (row["type_id"] as? Int64).map(Int.init) ?? (row["type_id"] as? Int) {
                return "\(date)_\(typeId)"
            }
            return nil
        })
        
        let insertSQL = """
            INSERT OR REPLACE INTO mining_ledger (
                character_id, date, quantity, solar_system_id, type_id
            ) VALUES (?, ?, ?, ?, ?)
        """
        
        var newCount = 0
        for entry in entries {
            // 检查记录是否已存在
            let recordKey = "\(entry.date)_\(entry.type_id)"
            if existingRecords.contains(recordKey) {
                continue
            }
            
            let parameters: [Any] = [
                characterId,
                entry.date,
                entry.quantity,
                entry.solar_system_id,
                entry.type_id
            ]
            
            if case .error(let message) = databaseManager.executeQuery(insertSQL, parameters: parameters) {
                Logger.error("保存挖矿记录到数据库失败: \(message)")
                return false
            }
            newCount += 1
        }
        
        if newCount > 0 {
            Logger.info("新增\(newCount)条挖矿记录到数据库")
        }
        return true
    }
    
    // 从服务器获取挖矿记录
    private func fetchFromServer(characterId: Int) async throws -> [MiningLedgerEntry] {
        var allEntries: [MiningLedgerEntry] = []
        var page = 1
        
        while true {
            do {
                let urlString = "https://esi.evetech.net/latest/characters/\(characterId)/mining/?datasource=tranquility&page=\(page)"
                guard let url = URL(string: urlString) else {
                    throw NetworkError.invalidURL
                }
                
                let data = try await NetworkManager.shared.fetchDataWithToken(
                    from: url,
                    characterId: characterId,
                    noRetryKeywords: ["Requested page does not exist"]
                )
                
                let pageEntries = try JSONDecoder().decode([MiningLedgerEntry].self, from: data)
                if pageEntries.isEmpty {
                    break
                }
                
                // 转换API返回的日期格式为数据库格式
                let convertedEntries = pageEntries.map { entry -> MiningLedgerEntry in
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
                
                allEntries.append(contentsOf: convertedEntries)
                Logger.info("成功获取第\(page)页挖矿记录，本页包含\(pageEntries.count)条记录")
                
                page += 1
                try await Task.sleep(nanoseconds: UInt64(0.1 * 1_000_000_000))
                
            } catch let error as NetworkError {
                if case .httpError(let statusCode, let message) = error,
                   [500, 404].contains(statusCode),
                   message?.contains("Requested page does not exist") == true {
                    break
                }
                throw error
            }
        }
        
        Logger.info("成功获取挖矿记录，共\(allEntries.count)条记录")
        return allEntries
    }
    
    // 获取挖矿记录（公开方法）
    public func getMiningLedger(characterId: Int, forceRefresh: Bool = false) async throws -> [MiningLedgerEntry] {
        // 检查是否需要刷新数据
        if !forceRefresh {
            if let entries = getMiningLedgerFromDB(characterId: characterId),
               !entries.isEmpty,
               !shouldRefreshData(characterId: characterId) {
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
