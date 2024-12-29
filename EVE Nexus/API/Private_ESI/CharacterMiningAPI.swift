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
        
        if case .success(let results) = databaseManager.executeQuery(query, parameters: [characterId]) {
            return results.compactMap { row -> MiningLedgerEntry? in
                guard let date = row["date"] as? String,
                      let quantity = row["quantity"] as? Int,
                      let solarSystemId = row["solar_system_id"] as? Int,
                      let typeId = row["type_id"] as? Int else {
                    return nil
                }
                
                return MiningLedgerEntry(
                    date: date,
                    quantity: quantity,
                    solar_system_id: solarSystemId,
                    type_id: typeId
                )
            }
        }
        return nil
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
            guard let date = row["date"] as? String,
                  let typeId = row["type_id"] as? Int else {
                return nil
            }
            return "\(date)_\(typeId)"
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
                
                allEntries.append(contentsOf: pageEntries)
                Logger.info("成功获取第\(page)页挖矿记录，本页包含\(pageEntries.count)条记录")
                
                page += 1
                try await Task.sleep(nanoseconds: UInt64(0.1 * 1_000_000_000)) // 100ms延迟
                
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
