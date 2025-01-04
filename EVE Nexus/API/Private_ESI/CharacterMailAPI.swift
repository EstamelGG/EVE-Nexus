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
    
    /// 从数据库加载邮件
    /// - Parameters:
    ///   - characterId: 角色ID
    ///   - labelId: 标签ID，如果为nil则加载所有邮件
    ///   - offset: 偏移量
    ///   - limit: 限制数量
    ///   - lastMailId: 最后一封邮件的ID，用于获取更旧的邮件
    /// - Returns: 邮件数组
    func loadMailsFromDatabase(characterId: Int, labelId: Int? = nil, offset: Int = 0, limit: Int = 20, lastMailId: Int? = nil) async throws -> [EVEMail] {
        let query: String
        let parameters: [Any]
        
        if let labelId = labelId {
            // 如果指定了标签ID，只获取该标签的邮件
            if let lastMailId = lastMailId {
                // 获取比指定邮件更老的邮件
                query = """
                    SELECT m.* FROM mailbox m
                    INNER JOIN (
                        SELECT timestamp FROM mailbox WHERE mail_id = ?
                    ) last_mail ON m.timestamp <= last_mail.timestamp
                    WHERE m.character_id = ? 
                    AND m.mail_id IN (
                        SELECT mail_id FROM mail_labels WHERE label_id = ?
                    )
                    AND m.mail_id != ?
                    ORDER BY m.timestamp DESC
                    LIMIT ?
                """
                parameters = [lastMailId, characterId, labelId, lastMailId, limit]
            } else {
                // 正常分页查询
                query = """
                    SELECT * FROM mailbox 
                    WHERE character_id = ? AND mail_id IN (
                        SELECT mail_id FROM mail_labels 
                        WHERE label_id = ?
                    )
                    ORDER BY timestamp DESC
                    LIMIT ? OFFSET ?
                """
                parameters = [characterId, labelId, limit, offset]
            }
        } else {
            // 如果没有指定标签ID，获取所有邮件
            if let lastMailId = lastMailId {
                // 获取比指定邮件更老的邮件
                query = """
                    SELECT m.* FROM mailbox m
                    INNER JOIN (
                        SELECT timestamp FROM mailbox WHERE mail_id = ?
                    ) last_mail ON m.timestamp <= last_mail.timestamp
                    WHERE m.character_id = ?
                    AND m.mail_id != ?
                    ORDER BY m.timestamp DESC
                    LIMIT ?
                """
                parameters = [lastMailId, characterId, lastMailId, limit]
            } else {
                // 正常分页查询
                query = """
                    SELECT * FROM mailbox 
                    WHERE character_id = ? 
                    ORDER BY timestamp DESC
                    LIMIT ? OFFSET ?
                """
                parameters = [characterId, limit, offset]
            }
        }
        
        let result = databaseManager.executeQuery(query, parameters: parameters)
        switch result {
        case .success(let rows):
            Logger.info("从数据库读取到 \(rows.count) 条邮件记录 (offset: \(offset), limit: \(limit), lastMailId: \(lastMailId ?? 0))")
            var mails: [EVEMail] = []
            
            for row in rows {
                // 转换数据类型
                let mailId = (row["mail_id"] as? Int64).map(Int.init) ?? (row["mail_id"] as? Int) ?? 0
                let fromId = (row["from_id"] as? Int64).map(Int.init) ?? (row["from_id"] as? Int) ?? 0
                let isRead = (row["is_read"] as? Int64).map(Int.init) ?? (row["is_read"] as? Int) ?? 0
                
                guard mailId > 0,
                      fromId > 0,
                      let subject = row["subject"] as? String,
                      let timestamp = row["timestamp"] as? String,
                      let recipientsString = row["recipients"] as? String,
                      let recipientsData = recipientsString.data(using: .utf8) else {
                    Logger.error("邮件数据格式错误: \(row)")
                    continue
                }
                
                // 解析收件人数据
                guard let recipients = try? JSONDecoder().decode([EVEMailRecipient].self, from: recipientsData) else {
                    Logger.error("解析收件人数据失败: \(recipientsString)")
                    continue
                }
                
                let mail = EVEMail(
                    from: fromId,
                    is_read: isRead == 1,
                    labels: [], // 不再需要处理标签
                    mail_id: mailId,
                    recipients: recipients,
                    subject: subject,
                    timestamp: timestamp
                )
                
                mails.append(mail)
            }
            
            Logger.info("成功从数据库加载 \(mails.count) 封邮件")
            return mails
            
        case .error(let error):
            Logger.error("数据库查询失败: \(error)")
            throw DatabaseError.fetchError(error)
        }
    }
    
    /// 从网络获取邮件
    /// - Parameters:
    ///   - characterId: 角色ID
    ///   - labelId: 标签ID，如果为nil则获取所有邮件
    ///   - lastMailId: 最后一封邮件的ID，用于获取更旧的邮件
    /// - Returns: 邮件列表
    func fetchLatestMails(characterId: Int, labelId: Int? = nil, lastMailId: Int? = nil) async throws -> [EVEMail] {
        Logger.info("开始从网络获取邮件 - 角色ID: \(characterId), 标签ID: \(labelId ?? 0), 最后邮件ID: \(lastMailId ?? 0)")
        
        // 构建请求URL
        var urlString = "https://esi.evetech.net/latest/characters/\(characterId)/mail/?datasource=tranquility"
        if let labelId = labelId {
            urlString += "&labels=\(labelId)"
        }
        if let lastMailId = lastMailId {
            urlString += "&last_mail_id=\(lastMailId)"
        }
        
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        
        // 发送请求获取数据
        let data = try await networkManager.fetchDataWithToken(from: url, characterId: characterId)
        
        // 解析响应数据
        let mails = try JSONDecoder().decode([EVEMail].self, from: data)
        Logger.info("从API获取到 \(mails.count) 封邮件")
        
        // 直接返回所有邮件
        return mails
    }
    
    /// 获取邮件标签和未读数
    /// - Parameters:
    ///   - characterId: 角色ID
    ///   - forceRefresh: 是否强制刷新，忽略缓存
    /// - Returns: 邮件标签响应数据
    func fetchMailLabels(characterId: Int, forceRefresh: Bool = false) async throws -> MailLabelsResponse {
        // 检查缓存是否有效
        if !forceRefresh,
           let cachedResponse = cachedLabels[characterId],
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
    ///   - forceRefresh: 是否强制刷新，忽略缓存
    /// - Returns: 未读邮件数，如果为0则返回nil
    func getUnreadCount(characterId: Int, labelId: Int, forceRefresh: Bool = false) async throws -> Int? {
        let response = try await fetchMailLabels(characterId: characterId, forceRefresh: forceRefresh)
        
        if let label = response.labels.first(where: { $0.label_id == labelId }) {
            return label.unread_count == 0 ? nil : label.unread_count
        }
        return nil
    }
    
    /// 获取总未读邮件数
    /// - Parameters:
    ///   - characterId: 角色ID
    ///   - forceRefresh: 是否强制刷新，忽略缓存
    /// - Returns: 总未读邮件数，如果为0则返回nil
    func getTotalUnreadCount(characterId: Int, forceRefresh: Bool = false) async throws -> Int? {
        let response = try await fetchMailLabels(characterId: characterId, forceRefresh: forceRefresh)
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
        let insertMailSQL = """
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
        
        let insertLabelSQL = """
            INSERT OR REPLACE INTO mail_labels (
                mail_id,
                label_id
            ) VALUES (?, ?)
        """
        
        for mail in mails {
            Logger.info("开始处理邮件 - ID: \(mail.mail_id), 标签: \(mail.labels)")
            
            // 将recipients转换为JSON字符串
            let recipientsData = try JSONEncoder().encode(mail.recipients)
            guard let recipientsString = String(data: recipientsData, encoding: .utf8) else {
                Logger.error("无法编码收件人数据")
                continue
            }
            
            // 执行邮件插入操作
            let result = databaseManager.executeQuery(
                insertMailSQL,
                parameters: [
                    mail.mail_id,
                    characterId,
                    mail.from,
                    mail.is_read == true ? 1 : 0,
                    mail.subject,
                    recipientsString,
                    mail.timestamp
                ]
            )
            
            switch result {
            case .success:
                Logger.info("成功保存邮件基本信息 - ID: \(mail.mail_id)")
                
                // 先删除旧的标签关系
                let deleteLabelSQL = "DELETE FROM mail_labels WHERE mail_id = ?"
                let deleteResult = databaseManager.executeQuery(deleteLabelSQL, parameters: [mail.mail_id])
                if case .error(let error) = deleteResult {
                    Logger.error("删除旧邮件标签失败: \(error)")
                }
                
                // 保存新的标签关系
                for labelId in mail.labels {
                    let labelResult = databaseManager.executeQuery(
                        insertLabelSQL,
                        parameters: [mail.mail_id, labelId]
                    )
                    if case .error(let error) = labelResult {
                        Logger.error("保存邮件标签失败: \(error)")
                    } else {
                        Logger.info("成功保存邮件标签 - 邮件ID: \(mail.mail_id), 标签ID: \(labelId)")
                    }
                }
                
            case .error(let error):
                Logger.error("保存邮件失败: \(error)")
                throw DatabaseError.insertError(error)
            }
        }
    }
}

enum DatabaseError: Error {
    case insertError(String)
    case fetchError(String)
} 