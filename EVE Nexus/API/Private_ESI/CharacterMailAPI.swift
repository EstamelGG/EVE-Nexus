import Foundation

struct EVEMailRecipient: Codable {
    let recipient_id: Int
    let recipient_type: String
}

struct EVEMail: Codable {
    let from: Int
    let is_read: Bool
    let labels: [Int]
    let mail_id: Int
    let recipients: [EVEMailRecipient]
    let subject: String
    let timestamp: String
}

@NetworkManagerActor
class CharacterMailAPI {
    static let shared = CharacterMailAPI()
    private let networkManager = NetworkManager.shared
    private let databaseManager = CharacterDatabaseManager.shared
    
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
                    mail.is_read ? 1 : 0,
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