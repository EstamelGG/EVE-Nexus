import Foundation

// 击杀记录数据模型
struct KillMailInfo: Codable {
    let killmail_hash: String
    let killmail_id: Int
}

class CharacterKillMailsAPI {
    static let shared = CharacterKillMailsAPI()
    
    // 通知名称常量
    static let killmailsUpdatedNotification = "KillmailsUpdatedNotification"
    static let killmailsUpdatedCharacterIdKey = "CharacterId"
    
    private let lastKillmailsQueryKey = "LastKillmailsQuery_"
    private let cacheTimeout: TimeInterval = 8 * 3600 // 8小时缓存有效期
    
    private init() {}
    
    // 获取最后查询时间
    private func getLastQueryTime(characterId: Int) -> Date? {
        let key = lastKillmailsQueryKey + String(characterId)
        return UserDefaults.standard.object(forKey: key) as? Date
    }
    
    // 更新最后查询时间
    private func updateLastQueryTime(characterId: Int) {
        let key = lastKillmailsQueryKey + String(characterId)
        UserDefaults.standard.set(Date(), forKey: key)
    }
    
    // 检查是否需要刷新数据
    private func shouldRefreshData(characterId: Int) -> Bool {
        guard let lastQueryTime = getLastQueryTime(characterId: characterId) else {
            return true
        }
        return Date().timeIntervalSince(lastQueryTime) >= cacheTimeout
    }
    
    // 从服务器获取击杀记录
    private func fetchKillMailsFromServer(characterId: Int) async throws -> [KillMailInfo] {
        var allKillMails: [KillMailInfo] = []
        var currentPage = 1
        var shouldContinue = true
        
        while shouldContinue {
            do {
                let pageKillMails = try await fetchKillMailsPage(characterId: characterId, page: currentPage)
                if pageKillMails.isEmpty {
                    shouldContinue = false
                } else {
                    allKillMails.append(contentsOf: pageKillMails)
                    currentPage += 1
                }
                if currentPage >= 1000 { // 最多取1000页
                    shouldContinue = false
                    break
                }
            } catch let error as NetworkError {
                if case .httpError(_, let message) = error,
                   message?.contains("Requested page does not exist") == true {
                    shouldContinue = false
                } else {
                    throw error
                }
            }
        }
        
        // 更新最后查询时间
        updateLastQueryTime(characterId: characterId)
        
        // 保存到数据库
        if !saveKillMailsToDB(characterId: characterId, killmails: allKillMails) {
            Logger.error("保存击杀记录到数据库失败")
        } else {
            // 发送数据更新通知
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Notification.Name(CharacterKillMailsAPI.killmailsUpdatedNotification),
                    object: nil,
                    userInfo: [CharacterKillMailsAPI.killmailsUpdatedCharacterIdKey: characterId]
                )
            }
        }
        
        Logger.debug("成功从服务器获取击杀记录 - 角色ID: \(characterId), 记录数量: \(allKillMails.count)")
        
        return allKillMails
    }
    
    // 获取单页击杀记录
    private func fetchKillMailsPage(characterId: Int, page: Int) async throws -> [KillMailInfo] {
        let url = URL(string: "https://esi.evetech.net/latest/characters/\(characterId)/killmails/recent/?datasource=tranquility&page=\(page)")!
        
        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId,
            noRetryKeywords: ["Requested page does not exist"]
        )
        
        let decoder = JSONDecoder()
        return try decoder.decode([KillMailInfo].self, from: data)
    }
    
    // 保存击杀记录到数据库
    private func saveKillMailsToDB(characterId: Int, killmails: [KillMailInfo]) -> Bool {
        var newCount = 0
        var updateCount = 0
        
        // 获取数据库中现有的击杀记录
        let checkQuery = "SELECT killmail_id FROM killmails WHERE character_id = ?"
        guard case .success(let existingResults) = CharacterDatabaseManager.shared.executeQuery(checkQuery, parameters: [characterId]) else {
            Logger.error("查询现有击杀记录失败")
            return false
        }
        
        // 构建现有击杀记录ID的集合，方便查找
        var existingKillmails = Set<Int>()
        for row in existingResults {
            if let killmailId = row["killmail_id"] as? Int64 {
                existingKillmails.insert(Int(killmailId))
            }
        }
        
        let insertSQL = """
            INSERT OR REPLACE INTO killmails (
                character_id, killmail_id, killmail_hash
            ) VALUES (?, ?, ?)
        """
        
        for killmail in killmails {
            // 检查记录是否已存在
            if existingKillmails.contains(killmail.killmail_id) {
                updateCount += 1
            } else {
                newCount += 1
            }
            
            let parameters: [Any] = [
                characterId,
                killmail.killmail_id,
                killmail.killmail_hash
            ]
            
            if case .error(let message) = CharacterDatabaseManager.shared.executeQuery(insertSQL, parameters: parameters) {
                Logger.error("保存击杀记录到数据库失败: \(message)")
                return false
            }
        }
        
        if newCount > 0 || updateCount > 0 {
            Logger.info("数据库更新：新增\(newCount)条击杀记录，更新\(updateCount)条记录")
        } else {
            Logger.debug("没有需要更新的击杀记录")
        }
        return true
    }
    
    // 从数据库获取击杀记录
    private func getKillMailsFromDB(characterId: Int) -> [KillMailInfo]? {
        let query = """
            SELECT killmail_id, killmail_hash
            FROM killmails 
            WHERE character_id = ?
            ORDER BY killmail_id DESC
        """
        
        if case .success(let results) = CharacterDatabaseManager.shared.executeQuery(query, parameters: [characterId]) {
            return results.compactMap { row -> KillMailInfo? in
                guard let killmailId = row["killmail_id"] as? Int64,
                      let killmailHash = row["killmail_hash"] as? String else {
                    return nil
                }
                
                return KillMailInfo(
                    killmail_hash: killmailHash,
                    killmail_id: Int(killmailId)
                )
            }
        }
        return nil
    }
    
    // 获取击杀记录（公开方法）
    public func fetchKillMails(characterId: Int, forceRefresh: Bool = false) async throws -> [KillMailInfo] {
        // 检查数据库中是否有数据
        let checkQuery = "SELECT COUNT(*) as count FROM killmails WHERE character_id = ?"
        let result = CharacterDatabaseManager.shared.executeQuery(checkQuery, parameters: [characterId])
        let isEmpty = if case .success(let rows) = result,
                        let row = rows.first,
                        let count = row["count"] as? Int64 {
            count == 0
        } else {
            true
        }
        
        // 如果数据为空或强制刷新，则从网络获取
        if isEmpty || forceRefresh {
            Logger.debug("击杀记录为空或强制刷新，从网络获取数据")
            return try await fetchKillMailsFromServer(characterId: characterId)
        }
        
        // 检查是否需要在后台刷新
        if shouldRefreshData(characterId: characterId) {
            Logger.info("击杀记录数据已过期，在后台刷新 - 角色ID: \(characterId)")
            
            // 在后台刷新数据
            Task {
                do {
                    let _ = try await fetchKillMailsFromServer(characterId: characterId)
                    Logger.info("后台刷新击杀记录完成 - 角色ID: \(characterId)")
                } catch {
                    Logger.error("后台刷新击杀记录失败 - 角色ID: \(characterId), 错误: \(error)")
                }
            }
        }
        
        // 从数据库获取数据
        if let killmails = getKillMailsFromDB(characterId: characterId) {
            return killmails
        }
        
        return []
    }
    
    // 清除指定角色的缓存
    func clearCache(for characterId: Int) {
        let key = lastKillmailsQueryKey + String(characterId)
        UserDefaults.standard.removeObject(forKey: key)
        Logger.debug("清除击杀记录缓存 - 角色ID: \(characterId)")
    }
} 