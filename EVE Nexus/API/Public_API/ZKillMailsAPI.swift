import Foundation

// 击杀记录数据模型
struct KillMailInfo: Codable {
    let killmail_hash: String
    let killmail_id: Int
    let locationID: Int?
    let totalValue: Double?
    let npc: Bool?
    let solo: Bool?
    let awox: Bool?
    
    enum CodingKeys: String, CodingKey {
        case killmail_hash
        case killmail_id
        case locationID = "locationID"
        case totalValue = "zkb.totalValue"
        case npc = "zkb.npc"
        case solo = "zkb.solo"
        case awox = "zkb.awox"
    }
}

// 查询类型枚举
enum KillMailQueryType {
    case character(Int)
    case corporation(Int)
    
    var endpoint: String {
        switch self {
        case .character(let id):
            return "characterID/\(id)"
        case .corporation(let id):
            return "corporationID/\(id)"
        }
    }
    
    var tableName: String {
        switch self {
        case .character:
            return "killmails"
        case .corporation:
            return "corp_killmails"
        }
    }
    
    var idColumnName: String {
        switch self {
        case .character:
            return "character_id"
        case .corporation:
            return "corporation_id"
        }
    }
    
    var id: Int {
        switch self {
        case .character(let id), .corporation(let id):
            return id
        }
    }
}

class ZKillMailsAPI {
    static let shared = ZKillMailsAPI()
    
    // 通知名称常量
    static let killmailsUpdatedNotification = "KillmailsUpdatedNotification"
    static let killmailsUpdatedIdKey = "UpdatedId"
    static let killmailsUpdatedTypeKey = "UpdatedType"
    
    private let lastKillmailsQueryKey = "LastKillmailsQuery_"
    private let cacheTimeout: TimeInterval = 8 * 3600 // 8小时缓存有效期
    private let maxPages = 20 // zKillboard最大页数限制
    
    private init() {}
    
    // 获取最后查询时间
    private func getLastQueryTime(queryType: KillMailQueryType) -> Date? {
        let key = lastKillmailsQueryKey + String(queryType.id)
        return UserDefaults.standard.object(forKey: key) as? Date
    }
    
    // 更新最后查询时间
    private func updateLastQueryTime(queryType: KillMailQueryType) {
        let key = lastKillmailsQueryKey + String(queryType.id)
        UserDefaults.standard.set(Date(), forKey: key)
    }
    
    // 检查是否需要刷新数据
    private func shouldRefreshData(queryType: KillMailQueryType) -> Bool {
        guard let lastQueryTime = getLastQueryTime(queryType: queryType) else {
            return true
        }
        return Date().timeIntervalSince(lastQueryTime) >= cacheTimeout
    }
    
    // 从服务器获取击杀记录
    private func fetchKillMailsFromServer(queryType: KillMailQueryType, saveToDatabase: Bool) async throws -> [KillMailInfo] {
        var allKillMails: [KillMailInfo] = []
        var currentPage = 1
        
        // 获取数据库中最大的killmail_id
        var maxExistingKillmailId: Int = 0
        if saveToDatabase {
            let maxIdQuery = """
                SELECT MAX(killmail_id) as max_id 
                FROM \(queryType.tableName) 
                WHERE \(queryType.idColumnName) = ?
            """
            if case .success(let results) = CharacterDatabaseManager.shared.executeQuery(maxIdQuery, parameters: [queryType.id]),
               let row = results.first,
               let maxId = row["max_id"] as? Int64 {
                maxExistingKillmailId = Int(maxId)
                Logger.debug("数据库中最大的killmail_id: \(maxExistingKillmailId)")
            }
        }
        
        while currentPage <= maxPages {
            let pageKillMails = try await fetchKillMailsPage(queryType: queryType, page: currentPage)
            if pageKillMails.isEmpty {
                break // 如果返回空数组，说明没有更多数据
            }
            
            // 按killmail_id从大到小排序
            let sortedKillMails = pageKillMails.sorted { $0.killmail_id > $1.killmail_id }
            
            // 检查是否存在已知的最大killmail_id
            if maxExistingKillmailId > 0 {
                let containsExistingId = sortedKillMails.contains { $0.killmail_id <= maxExistingKillmailId }
                if containsExistingId {
                    // 只添加大于最大ID的记录
                    let newKillMails = sortedKillMails.filter { $0.killmail_id > maxExistingKillmailId }
                    allKillMails.append(contentsOf: newKillMails)
                    Logger.debug("发现已存在的killmail_id，停止获取更多页面")
                    break
                }
            }
            
            allKillMails.append(contentsOf: sortedKillMails)
            currentPage += 1
        }
        
        if saveToDatabase && !allKillMails.isEmpty {
            // 更新最后查询时间
            updateLastQueryTime(queryType: queryType)
            
            // 保存到数据库
            if !saveKillMailsToDB(queryType: queryType, killmails: allKillMails) {
                Logger.error("保存击杀记录到数据库失败")
            } else {
                // 发送数据更新通知
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: Notification.Name(ZKillMailsAPI.killmailsUpdatedNotification),
                        object: nil,
                        userInfo: [
                            ZKillMailsAPI.killmailsUpdatedIdKey: queryType.id,
                            ZKillMailsAPI.killmailsUpdatedTypeKey: String(describing: queryType)
                        ]
                    )
                }
            }
        }
        
        Logger.debug("成功从zKillboard获取击杀记录 - ID: \(queryType.id), 记录数量: \(allKillMails.count)")
        
        return allKillMails
    }
    
    // 获取单页击杀记录
    private func fetchKillMailsPage(queryType: KillMailQueryType, page: Int) async throws -> [KillMailInfo] {
        let url = URL(string: "https://zkillboard.com/api/\(queryType.endpoint)/page/\(page)/")!
        
        var request = URLRequest(url: url)
        request.setValue("EVE-Nexus", forHTTPHeaderField: "User-Agent") // zKillboard要求设置User-Agent
        
        let data = try await NetworkManager.shared.fetchData(from: url, headers: ["User-Agent": "EVE-Nexus"])
        let decoder = JSONDecoder()
        return try decoder.decode([KillMailInfo].self, from: data)
    }
    
    // 保存击杀记录到数据库
    private func saveKillMailsToDB(queryType: KillMailQueryType, killmails: [KillMailInfo]) -> Bool {
        var newCount = 0
        
        let insertSQL = """
            INSERT OR IGNORE INTO \(queryType.tableName) (
                \(queryType.idColumnName), killmail_id, killmail_hash,
                location_id, total_value, npc, solo, awox
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """
        
        // 按killmail_id从大到小排序
        let sortedKillMails = killmails.sorted { $0.killmail_id > $1.killmail_id }
        
        for killmail in sortedKillMails {
            let parameters: [Any] = [
                queryType.id,
                killmail.killmail_id,
                killmail.killmail_hash,
                killmail.locationID as Any,
                killmail.totalValue as Any,
                killmail.npc ?? false,
                killmail.solo ?? false,
                killmail.awox ?? false
            ]
            
            if case .error(let message) = CharacterDatabaseManager.shared.executeQuery(insertSQL, parameters: parameters) {
                Logger.error("保存击杀记录到数据库失败: \(message)")
                return false
            }
            
            newCount += 1
        }
        
        if newCount > 0 {
            Logger.info("数据库更新：新增\(newCount)条击杀记录")
        } else {
            Logger.debug("没有需要更新的击杀记录")
        }
        return true
    }
    
    // 从数据库获取击杀记录
    private func getKillMailsFromDB(queryType: KillMailQueryType) -> [KillMailInfo]? {
        let query = """
            SELECT killmail_id, killmail_hash, location_id, total_value, npc, solo, awox
            FROM \(queryType.tableName)
            WHERE \(queryType.idColumnName) = ?
            ORDER BY killmail_id DESC
        """
        
        if case .success(let results) = CharacterDatabaseManager.shared.executeQuery(query, parameters: [queryType.id]) {
            return results.compactMap { row -> KillMailInfo? in
                guard let killmailId = row["killmail_id"] as? Int64,
                      let killmailHash = row["killmail_hash"] as? String else {
                    return nil
                }
                
                let locationId = row["location_id"] as? Int64
                let totalValue = row["total_value"] as? Double
                let npc = row["npc"] as? Bool ?? false
                let solo = row["solo"] as? Bool ?? false
                let awox = row["awox"] as? Bool ?? false
                
                return KillMailInfo(
                    killmail_hash: killmailHash,
                    killmail_id: Int(killmailId),
                    locationID: locationId != nil ? Int(locationId!) : nil,
                    totalValue: totalValue,
                    npc: npc,
                    solo: solo,
                    awox: awox
                )
            }
        }
        return nil
    }
    
    // 获取角色击杀记录（公开方法）
    public func fetchCharacterKillMails(characterId: Int, forceRefresh: Bool = false, saveToDatabase: Bool = true) async throws -> [KillMailInfo] {
        return try await fetchKillMails(queryType: .character(characterId), forceRefresh: forceRefresh, saveToDatabase: saveToDatabase)
    }
    
    // 获取军团击杀记录（公开方法）
    public func fetchCorporationKillMails(characterId: Int, forceRefresh: Bool = false, saveToDatabase: Bool = true) async throws -> [KillMailInfo] {
        // 获取角色的军团ID
        guard let corporationId = try await CharacterDatabaseManager.shared.getCharacterCorporationId(characterId: characterId) else {
            throw NetworkError.authenticationError("无法获取军团ID")
        }
        
        return try await fetchKillMails(queryType: .corporation(corporationId), forceRefresh: forceRefresh, saveToDatabase: saveToDatabase)
    }
    
    // 通用获取击杀记录方法
    private func fetchKillMails(queryType: KillMailQueryType, forceRefresh: Bool, saveToDatabase: Bool) async throws -> [KillMailInfo] {
        if saveToDatabase {
            // 检查数据库中是否有数据
            let checkQuery = "SELECT COUNT(*) as count FROM \(queryType.tableName) WHERE \(queryType.idColumnName) = ?"
            let result = CharacterDatabaseManager.shared.executeQuery(checkQuery, parameters: [queryType.id])
            let isEmpty = if case .success(let rows) = result,
                            let row = rows.first,
                            let count = row["count"] as? Int64 {
                count == 0
            } else {
                true
            }
            
            // 如果数据为空或强制刷新，则从网络获取
            if isEmpty || forceRefresh {
                Logger.debug("击杀记录为空或强制刷新，从zKillboard获取数据")
                return try await fetchKillMailsFromServer(queryType: queryType, saveToDatabase: saveToDatabase)
            }
            
            // 检查是否需要在后台刷新
            if shouldRefreshData(queryType: queryType) {
                Logger.info("击杀记录数据已过期，在后台刷新 - ID: \(queryType.id)")
                
                // 在后台刷新数据
                Task {
                    do {
                        let _ = try await fetchKillMailsFromServer(queryType: queryType, saveToDatabase: saveToDatabase)
                        Logger.info("后台刷新击杀记录完成 - ID: \(queryType.id)")
                    } catch {
                        Logger.error("后台刷新击杀记录失败 - ID: \(queryType.id), 错误: \(error)")
                    }
                }
            }
            
            // 从数据库获取数据
            if let killmails = getKillMailsFromDB(queryType: queryType) {
                return killmails
            }
        } else {
            // 如果不保存到数据库，直接从服务器获取数据
            return try await fetchKillMailsFromServer(queryType: queryType, saveToDatabase: false)
        }
        
        return []
    }
    
    // 清除缓存
    func clearCache(queryType: KillMailQueryType) {
        let key = lastKillmailsQueryKey + String(queryType.id)
        UserDefaults.standard.removeObject(forKey: key)
        Logger.debug("清除击杀记录缓存 - ID: \(queryType.id)")
    }
} 
