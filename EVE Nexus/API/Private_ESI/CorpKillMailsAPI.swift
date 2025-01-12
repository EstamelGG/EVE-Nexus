import Foundation

// 军团击杀记录数据模型
struct CorpKillMailInfo: Codable {
    let killmail_hash: String
    let killmail_id: Int
}

class CorpKillMailsAPI {
    static let shared = CorpKillMailsAPI()
    
    // 通知名称常量
    static let killmailsUpdatedNotification = "CorpKillmailsUpdatedNotification"
    static let killmailsUpdatedCorpIdKey = "CorporationId"
    
    private let lastKillmailsQueryKey = "LastCorpKillmailsQuery_"
    private let cacheTimeout: TimeInterval = 8 * 3600 // 8小时缓存有效期
    
    private init() {}
    
    // 获取最后查询时间
    private func getLastQueryTime(corporationId: Int) -> Date? {
        let key = lastKillmailsQueryKey + String(corporationId)
        return UserDefaults.standard.object(forKey: key) as? Date
    }
    
    // 更新最后查询时间
    private func updateLastQueryTime(corporationId: Int) {
        let key = lastKillmailsQueryKey + String(corporationId)
        UserDefaults.standard.set(Date(), forKey: key)
    }
    
    // 检查是否需要刷新数据
    private func shouldRefreshData(corporationId: Int) -> Bool {
        guard let lastQueryTime = getLastQueryTime(corporationId: corporationId) else {
            return true
        }
        return Date().timeIntervalSince(lastQueryTime) >= cacheTimeout
    }
    
    // 从服务器获取击杀记录
    private func fetchKillMailsFromServer(characterId: Int, corporationId: Int) async throws -> [CorpKillMailInfo] {
        var allKillMails: [CorpKillMailInfo] = []
        var currentPage = 1
        var shouldContinue = true
        
        while shouldContinue {
            do {
                let pageKillMails = try await fetchKillMailsPage(characterId: characterId, corporationId: corporationId, page: currentPage)
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
        updateLastQueryTime(corporationId: corporationId)
        
        // 保存到数据库
        if !saveKillMailsToDB(corporationId: corporationId, killmails: allKillMails) {
            Logger.error("保存军团击杀记录到数据库失败")
        } else {
            // 发送数据更新通知
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Notification.Name(CorpKillMailsAPI.killmailsUpdatedNotification),
                    object: nil,
                    userInfo: [CorpKillMailsAPI.killmailsUpdatedCorpIdKey: corporationId]
                )
            }
        }
        
        Logger.debug("成功从服务器获取军团击杀记录 - 军团ID: \(corporationId), 记录数量: \(allKillMails.count)")
        
        return allKillMails
    }
    
    // 获取单页击杀记录
    private func fetchKillMailsPage(characterId: Int, corporationId: Int, page: Int) async throws -> [CorpKillMailInfo] {
        let url = URL(string: "https://esi.evetech.net/latest/corporations/\(corporationId)/killmails/recent/?datasource=tranquility&page=\(page)")!
        
        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId,
            noRetryKeywords: ["Requested page does not exist"]
        )
        
        let decoder = JSONDecoder()
        return try decoder.decode([CorpKillMailInfo].self, from: data)
    }
    
    // 保存击杀记录到数据库
    private func saveKillMailsToDB(corporationId: Int, killmails: [CorpKillMailInfo]) -> Bool {
        var newCount = 0
        var updateCount = 0
        
        // 获取数据库中现有的击杀记录
        let checkQuery = "SELECT killmail_id FROM corp_killmails WHERE corporation_id = ?"
        guard case .success(let existingResults) = CharacterDatabaseManager.shared.executeQuery(checkQuery, parameters: [corporationId]) else {
            Logger.error("查询现有军团击杀记录失败")
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
            INSERT OR REPLACE INTO corp_killmails (
                corporation_id, killmail_id, killmail_hash
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
                corporationId,
                killmail.killmail_id,
                killmail.killmail_hash
            ]
            
            if case .error(let message) = CharacterDatabaseManager.shared.executeQuery(insertSQL, parameters: parameters) {
                Logger.error("保存军团击杀记录到数据库失败: \(message)")
                return false
            }
        }
        
        if newCount > 0 || updateCount > 0 {
            Logger.info("数据库更新：新增\(newCount)条军团击杀记录，更新\(updateCount)条记录")
        } else {
            Logger.debug("没有需要更新的军团击杀记录")
        }
        return true
    }
    
    // 从数据库获取击杀记录
    private func getKillMailsFromDB(corporationId: Int) -> [CorpKillMailInfo]? {
        let query = """
            SELECT killmail_id, killmail_hash
            FROM corp_killmails 
            WHERE corporation_id = ?
            ORDER BY killmail_id DESC
        """
        
        if case .success(let results) = CharacterDatabaseManager.shared.executeQuery(query, parameters: [corporationId]) {
            return results.compactMap { row -> CorpKillMailInfo? in
                guard let killmailId = row["killmail_id"] as? Int64,
                      let killmailHash = row["killmail_hash"] as? String else {
                    return nil
                }
                
                return CorpKillMailInfo(
                    killmail_hash: killmailHash,
                    killmail_id: Int(killmailId)
                )
            }
        }
        return nil
    }
    
    // 获取击杀记录（公开方法）
    public func fetchKillMails(characterId: Int, forceRefresh: Bool = false) async throws -> [CorpKillMailInfo] {
        // 获取角色的军团ID
        guard let corporationId = try await CharacterDatabaseManager.shared.getCharacterCorporationId(characterId: characterId) else {
            throw NetworkError.authenticationError("无法获取军团ID")
        }
        
        // 检查数据库中是否有数据
        let checkQuery = "SELECT COUNT(*) as count FROM corp_killmails WHERE corporation_id = ?"
        let result = CharacterDatabaseManager.shared.executeQuery(checkQuery, parameters: [corporationId])
        let isEmpty = if case .success(let rows) = result,
                        let row = rows.first,
                        let count = row["count"] as? Int64 {
            count == 0
        } else {
            true
        }
        
        // 如果数据为空或强制刷新，则从网络获取
        if isEmpty || forceRefresh {
            Logger.debug("军团击杀记录为空或强制刷新，从网络获取数据")
            return try await fetchKillMailsFromServer(characterId: characterId, corporationId: corporationId)
        }
        
        // 检查是否需要在后台刷新
        if shouldRefreshData(corporationId: corporationId) {
            Logger.info("军团击杀记录数据已过期，在后台刷新 - 军团ID: \(corporationId)")
            
            // 在后台刷新数据
            Task {
                do {
                    let _ = try await fetchKillMailsFromServer(characterId: characterId, corporationId: corporationId)
                    Logger.info("后台刷新军团击杀记录完成 - 军团ID: \(corporationId)")
                } catch {
                    Logger.error("后台刷新军团击杀记录失败 - 军团ID: \(corporationId), 错误: \(error)")
                }
            }
        }
        
        // 从数据库获取数据
        if let killmails = getKillMailsFromDB(corporationId: corporationId) {
            return killmails
        }
        
        return []
    }
    
    // 清除指定军团的缓存
    func clearCache(for corporationId: Int) {
        let key = lastKillmailsQueryKey + String(corporationId)
        UserDefaults.standard.removeObject(forKey: key)
        Logger.debug("清除军团击杀记录缓存 - 军团ID: \(corporationId)")
    }
} 