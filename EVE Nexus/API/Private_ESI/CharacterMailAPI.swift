import Foundation

struct EVEMailRecipient: Codable {
    let recipient_id: Int
    let recipient_type: String
}

struct EVEMail: Codable {
    let from: Int
    let is_read: Bool?
    let labels: [Int]
    let mail_id: Int
    let recipients: [EVEMailRecipient]
    let subject: String
    let timestamp: String
}

// 邮件标签响应模型
struct MailLabelsResponse: Codable {
    let labels: [MailLabel]
    let total_unread_count: Int
}

struct MailLabel: Codable {
    let color: String
    let label_id: Int
    let name: String
    let unread_count: Int?
}

@NetworkManagerActor
class CharacterMailAPI {
    static let shared = CharacterMailAPI()
    private let networkManager = NetworkManager.shared
    private let databaseManager = CharacterDatabaseManager.shared
    
    // 缓存邮件标签数据
    private var cachedLabels: [Int: MailLabelsResponse] = [:]
    private var labelsCacheTime: [Int: Date] = [:]
    private let cacheValidDuration: TimeInterval = 300 // 5分钟缓存有效期
    
    private init() {}
    
    /// 获取角色的所有邮件
    /// - Parameter characterId: 角色ID
    func fetchMails(characterId: Int) async throws {
        do {
            // 构建请求URL
            let urlString = "https://esi.evetech.net/latest/characters/\(characterId)/mail/?datasource=tranquility"
            guard let url = URL(string: urlString) else {
                throw NetworkError.invalidURL
            }
            
            // 发送请求获取数据
            let data = try await networkManager.fetchDataWithToken(from: url, characterId: characterId)
            
            // 解析响应数据
            let mails = try JSONDecoder().decode([EVEMail].self, from: data)
            
            // 将邮件保存到数据库
            try await saveMails(mails, for: characterId)
            
            Logger.info("成功获取并保存\(mails.count)封邮件")
        } catch {
            Logger.error("获取邮件失败: \(error)")
            throw error
        }
    }
    
    /// 获取邮件标签和未读数
    /// - Parameter characterId: 角色ID
    /// - Returns: 邮件标签响应数据
    func fetchMailLabels(characterId: Int) async throws -> MailLabelsResponse {
        // 检查缓存是否有效
        if let cachedResponse = cachedLabels[characterId],
           let cacheTime = labelsCacheTime[characterId],
           Date().timeIntervalSince(cacheTime) < cacheValidDuration {
            Logger.debug("使用缓存的邮件标签数据")
            return cachedResponse
        }
        
        do {
            // 构建请求URL
            let urlString = "https://esi.evetech.net/latest/characters/\(characterId)/mail/labels/?datasource=tranquility"
            guard let url = URL(string: urlString) else {
                throw NetworkError.invalidURL
            }
            
            // 发送请求获取数据
            let data = try await networkManager.fetchDataWithToken(from: url, characterId: characterId)
            
            // 解析响应数据
            let response = try JSONDecoder().decode(MailLabelsResponse.self, from: data)
            
            // 更新缓存
            cachedLabels[characterId] = response
            labelsCacheTime[characterId] = Date()
            
            Logger.info("成功获取邮件标签数据")
            return response
        } catch {
            Logger.error("获取邮件标签失败: \(error)")
            throw error
        }
    }
    
    /// 获取指定标签的未读邮件数
    /// - Parameters:
    ///   - characterId: 角色ID
    ///   - labelId: 标签ID
    /// - Returns: 未读邮件数，如果为0则返回nil
    func getUnreadCount(characterId: Int, labelId: Int) async throws -> Int? {
        let response = try await fetchMailLabels(characterId: characterId)
        
        if let label = response.labels.first(where: { $0.label_id == labelId }) {
            return label.unread_count == 0 ? nil : label.unread_count
        }
        return nil
    }
    
    /// 获取总未读邮件数
    /// - Parameter characterId: 角色ID
    /// - Returns: 总未读邮件数，如果为0则返回nil
    func getTotalUnreadCount(characterId: Int) async throws -> Int? {
        let response = try await fetchMailLabels(characterId: characterId)
        return response.total_unread_count == 0 ? nil : response.total_unread_count
    }
    
    /// 清除缓存
    func clearCache(for characterId: Int? = nil) {
        if let characterId = characterId {
            cachedLabels.removeValue(forKey: characterId)
            labelsCacheTime.removeValue(forKey: characterId)
        } else {
            cachedLabels.removeAll()
            labelsCacheTime.removeAll()
        }
    }
    
    /// 将邮件保存到数据库
    /// - Parameters:
    ///   - mails: 邮件数组
    ///   - characterId: 角色ID
    private func saveMails(_ mails: [EVEMail], for characterId: Int) async throws {
        // 构建SQL插入语句
        let insertSQL = """
            INSERT OR REPLACE INTO mailbox (
                mail_id,
                character_id,
                from_id,
                is_read,
                subject,
                recipients,
                timestamp,
                last_updated
            ) VALUES (?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
        """
        
        for mail in mails {
            // 将recipients转换为JSON字符串
            let recipientsData = try JSONEncoder().encode(mail.recipients)
            guard let recipientsString = String(data: recipientsData, encoding: .utf8) else {
                Logger.error("无法编码收件人数据")
                continue
            }
            
            // 执行插入操作
            let result = databaseManager.executeQuery(
                insertSQL,
                parameters: [
                    mail.mail_id,
                    characterId,
                    mail.from,
                    mail.is_read ?? true ? 1 : 0,
                    mail.subject,
                    recipientsString,
                    mail.timestamp
                ]
            )
            
            switch result {
            case .success:
                continue
            case .error(let error):
                Logger.error("保存邮件失败: \(error)")
                throw DatabaseError.insertError(error)
            }
        }
    }
}

enum DatabaseError: Error {
    case insertError(String)
} 