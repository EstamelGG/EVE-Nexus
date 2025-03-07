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

// 邮件内容响应模型
struct EVEMailContent: Codable {
    let body: String
    let from: Int
    let labels: [Int]
    let recipients: [EVEMailRecipient]
    let subject: String
    let timestamp: String
}

// 邮件订阅列表响应模型
struct EVEMailList: Codable {
    let mailing_list_id: Int
    let name: String
}

// 邮件内容缓存包装类
final class CachedMailContent {
    let content: EVEMailContent

    init(_ content: EVEMailContent) {
        self.content = content
    }
}

@NetworkManagerActor
class CharacterMailAPI {
    static let shared = CharacterMailAPI()
    private let networkManager = NetworkManager.shared
    private let databaseManager = CharacterDatabaseManager.shared

    // 缓存邮件标签数据
    private var cachedLabels: [Int: MailLabelsResponse] = [:]
    private var labelsCacheTime: [Int: Date] = [:]
    private let cacheValidDuration: TimeInterval = 300  // 5分钟缓存有效期

    // 邮件内容缓存
    private let mailContentCache = NSCache<NSNumber, CachedMailContent>()

    private init() {
        // 设置缓存限制
        mailContentCache.countLimit = 100  // 最多缓存100封邮件
    }

    /// 从数据库加载邮件
    /// - Parameters:
    ///   - characterId: 角色ID
    ///   - labelId: 标签ID，如果为nil则加载所有邮件
    ///   - offset: 偏移量
    ///   - limit: 限制数量
    ///   - lastMailId: 最后一封邮件的ID，用于获取更旧的邮件
    /// - Returns: 邮件数组
    func loadMailsFromDatabase(
        characterId: Int, labelId: Int? = nil, offset: Int = 0, limit: Int = 20,
        lastMailId: Int? = nil
    ) async throws -> [EVEMail] {
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
        case let .success(rows):
            Logger.info(
                "从数据库读取到 \(rows.count) 条邮件记录 (offset: \(offset), limit: \(limit), lastMailId: \(lastMailId ?? 0))"
            )
            var mails: [EVEMail] = []

            for row in rows {
                // 转换数据类型
                let mailId =
                    (row["mail_id"] as? Int64).map(Int.init) ?? (row["mail_id"] as? Int) ?? 0
                let fromId =
                    (row["from_id"] as? Int64).map(Int.init) ?? (row["from_id"] as? Int) ?? 0
                let isRead =
                    (row["is_read"] as? Int64).map(Int.init) ?? (row["is_read"] as? Int) ?? 0

                guard mailId > 0,
                    fromId > 0,
                    let subject = row["subject"] as? String,
                    let timestamp = row["timestamp"] as? String,
                    let recipientsString = row["recipients"] as? String,
                    let recipientsData = recipientsString.data(using: .utf8)
                else {
                    Logger.error("邮件数据格式错误: \(row)")
                    continue
                }

                // 解析收件人数据
                guard
                    let recipients = try? JSONDecoder().decode(
                        [EVEMailRecipient].self, from: recipientsData
                    )
                else {
                    Logger.error("解析收件人数据失败: \(recipientsString)")
                    continue
                }

                let mail = EVEMail(
                    from: fromId,
                    is_read: isRead == 1,
                    labels: [],  // 不再需要处理标签
                    mail_id: mailId,
                    recipients: recipients,
                    subject: subject,
                    timestamp: timestamp
                )

                mails.append(mail)
            }

            Logger.info("成功从数据库加载 \(mails.count) 封邮件")
            return mails

        case let .error(error):
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
    func fetchLatestMails(characterId: Int, labelId: Int? = nil, lastMailId: Int? = nil)
        async throws -> [EVEMail]
    {
        Logger.info(
            "开始从网络获取邮件 - 角色ID: \(characterId), 标签ID: \(labelId ?? 0), 最后邮件ID: \(lastMailId ?? 0)")

        // 构建请求URL
        var urlString =
            "https://esi.evetech.net/latest/characters/\(characterId)/mail/?datasource=tranquility"
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

        // 在后台保存邮件到数据库
        if !mails.isEmpty {
            Task.detached {
                do {
                    try await self.saveMails(mails, for: characterId)
                    Logger.info("成功在后台处理 \(mails.count) 封邮件到数据库")
                } catch {
                    Logger.error("后台保存邮件失败: \(error)")
                }
            }
        }

        // 直接返回网络获取的邮件
        return mails
    }

    /// 获取邮件标签和未读数
    /// - Parameters:
    ///   - characterId: 角色ID
    ///   - forceRefresh: 是否强制刷新，忽略缓存
    /// - Returns: 邮件标签响应数据
    func fetchMailLabels(characterId: Int, forceRefresh: Bool = false) async throws
        -> MailLabelsResponse
    {
        // 检查缓存是否有效
        if !forceRefresh,
            let cachedResponse = cachedLabels[characterId],
            let cacheTime = labelsCacheTime[characterId],
            Date().timeIntervalSince(cacheTime) < cacheValidDuration
        {
            Logger.debug("使用缓存的邮件标签数据")
            return cachedResponse
        }

        do {
            // 构建请求URL
            let urlString =
                "https://esi.evetech.net/latest/characters/\(characterId)/mail/labels/?datasource=tranquility"
            guard let url = URL(string: urlString) else {
                throw NetworkError.invalidURL
            }

            // 发送请求获取数据
            let data = try await networkManager.fetchDataWithToken(
                from: url, characterId: characterId
            )

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
    func getUnreadCount(characterId: Int, labelId: Int, forceRefresh: Bool = false) async throws
        -> Int?
    {
        let response = try await fetchMailLabels(
            characterId: characterId, forceRefresh: forceRefresh
        )

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
        let response = try await fetchMailLabels(
            characterId: characterId, forceRefresh: forceRefresh
        )
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
        guard !mails.isEmpty else { return }

        // 构建批量查询SQL
        let mailIds = mails.map { String($0.mail_id) }.joined(separator: ",")
        let checkExistSQL = """
                SELECT mail_id FROM mailbox 
                WHERE mail_id IN (\(mailIds)) AND character_id = ?
            """

        // 批量查询已存在的邮件
        let existResult = databaseManager.executeQuery(checkExistSQL, parameters: [characterId])
        var existingMailIds: Set<Int> = []

        switch existResult {
        case let .success(rows):
            existingMailIds = Set(
                rows.compactMap {
                    ($0["mail_id"] as? Int64).map(Int.init) ?? ($0["mail_id"] as? Int)
                })
            Logger.info("找到 \(existingMailIds.count) 封已存在的邮件")

        case let .error(error):
            Logger.error("批量查询邮件是否存在时发生错误: \(error)")
            throw DatabaseError.insertError(error)
        }

        // 过滤出需要插入的新邮件
        let newMails = mails.filter { !existingMailIds.contains($0.mail_id) }
        guard !newMails.isEmpty else {
            Logger.info("没有需要插入的新邮件")
            return
        }

        // 构建批量插入SQL
        let valuePlaceholders = newMails.map { _ in "(?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)" }
            .joined(separator: ",")
        let insertMailSQL = """
                INSERT INTO mailbox (
                    mail_id,
                    character_id,
                    from_id,
                    is_read,
                    subject,
                    recipients,
                    timestamp,
                    last_updated
                ) VALUES \(valuePlaceholders)
            """

        // 准备批量插入的参数
        var insertParameters: [Any] = []
        var mailLabels: [(mailId: Int, labels: [Int])] = []

        for mail in newMails {
            let recipientsData = try JSONEncoder().encode(mail.recipients)
            guard let recipientsString = String(data: recipientsData, encoding: .utf8) else {
                Logger.error("无法编码收件人数据 - 邮件ID: \(mail.mail_id)")
                continue
            }

            insertParameters.append(contentsOf: [
                mail.mail_id,
                characterId,
                mail.from,
                mail.is_read == true ? 1 : 0,
                mail.subject,
                recipientsString,
                mail.timestamp,
            ])

            if !mail.labels.isEmpty {
                mailLabels.append((mailId: mail.mail_id, labels: mail.labels))
            }
        }

        // 执行批量插入
        let result = databaseManager.executeQuery(insertMailSQL, parameters: insertParameters)
        switch result {
        case .success:
            Logger.info("成功批量插入 \(newMails.count) 封新邮件")

            // 批量处理标签
            if !mailLabels.isEmpty {
                // 构建批量删除旧标签SQL
                let mailIdsForLabels = mailLabels.map { String($0.mailId) }.joined(separator: ",")
                let deleteLabelSQL =
                    "DELETE FROM mail_labels WHERE mail_id IN (\(mailIdsForLabels))"

                let deleteResult = databaseManager.executeQuery(deleteLabelSQL)
                if case let .error(error) = deleteResult {
                    Logger.error("批量删除旧邮件标签失败: \(error)")
                }

                // 构建批量插入标签SQL
                var labelValuePlaceholders: [String] = []
                var labelParameters: [Any] = []

                for mailLabel in mailLabels {
                    for labelId in mailLabel.labels {
                        labelValuePlaceholders.append("(?, ?)")
                        labelParameters.append(contentsOf: [mailLabel.mailId, labelId])
                    }
                }

                let insertLabelSQL = """
                        INSERT OR REPLACE INTO mail_labels (mail_id, label_id)
                        VALUES \(labelValuePlaceholders.joined(separator: ","))
                    """

                let labelResult = databaseManager.executeQuery(
                    insertLabelSQL, parameters: labelParameters
                )
                if case let .error(error) = labelResult {
                    Logger.error("批量保存邮件标签失败: \(error)")
                } else {
                    Logger.info("成功批量保存邮件标签")
                }
            }

        case let .error(error):
            Logger.error("批量保存邮件失败: \(error)")
            throw DatabaseError.insertError(error)
        }
    }

    /// 获取邮件内容
    /// - Parameters:
    ///   - characterId: 角色ID
    ///   - mailId: 邮件ID
    /// - Returns: 邮件内容
    func fetchMailContent(characterId: Int, mailId: Int) async throws -> EVEMailContent {
        // 1. 检查内存缓存
        if let cachedContent = mailContentCache.object(forKey: NSNumber(value: mailId)) {
            Logger.info("使用内存缓存的邮件内容 - 邮件ID: \(mailId)")
            return cachedContent.content
        }

        // 2. 检查数据库缓存
        if let dbContent = try await loadMailContentFromDatabase(mailId: mailId) {
            Logger.info("使用数据库缓存的邮件内容 - 邮件ID: \(mailId)")
            // 保存到内存缓存
            mailContentCache.setObject(
                CachedMailContent(dbContent), forKey: NSNumber(value: mailId)
            )
            return dbContent
        }

        Logger.info("开始从API获取邮件内容 - 角色ID: \(characterId), 邮件ID: \(mailId)")

        // 3. 从API获取数据
        let urlString =
            "https://esi.evetech.net/latest/characters/\(characterId)/mail/\(mailId)/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        let data = try await networkManager.fetchDataWithToken(from: url, characterId: characterId)
        let content = try JSONDecoder().decode(EVEMailContent.self, from: data)
        Logger.info("成功从API获取邮件内容 - 邮件ID: \(mailId)")

        // 4. 保存到缓存和数据库
        mailContentCache.setObject(CachedMailContent(content), forKey: NSNumber(value: mailId))
        try await saveMailContentToDatabase(content: content)

        return content
    }

    /// 从数据库加载邮件内容
    /// - Parameter mailId: 邮件ID
    /// - Returns: 邮件内容，如果不存在则返回nil
    private func loadMailContentFromDatabase(mailId: Int) async throws -> EVEMailContent? {
        let query = """
                SELECT * FROM mail_content 
                WHERE mail_id = ? 
                LIMIT 1
            """

        let result = databaseManager.executeQuery(query, parameters: [mailId])
        switch result {
        case let .success(rows):
            guard let row = rows.first,
                let body = row["body"] as? String,
                let fromId = (row["from_id"] as? Int64).map(Int.init) ?? (row["from_id"] as? Int),
                let subject = row["subject"] as? String,
                let recipientsString = row["recipients"] as? String,
                let labelsString = row["labels"] as? String,
                let timestamp = row["timestamp"] as? String,
                let recipients = try? JSONDecoder().decode(
                    [EVEMailRecipient].self, from: recipientsString.data(using: .utf8)!
                ),
                let labels = try? JSONDecoder().decode(
                    [Int].self, from: labelsString.data(using: .utf8)!
                )
            else {
                return nil
            }

            return EVEMailContent(
                body: body,
                from: fromId,
                labels: labels,
                recipients: recipients,
                subject: subject,
                timestamp: timestamp
            )

        case let .error(error):
            Logger.error("从数据库加载邮件内容失败: \(error)")
            return nil
        }
    }

    /// 保存邮件内容到数据库
    /// - Parameter content: 邮件内容
    private func saveMailContentToDatabase(content: EVEMailContent) async throws {
        let insertSQL = """
                INSERT OR REPLACE INTO mail_content (
                    mail_id,
                    body,
                    from_id,
                    subject,
                    recipients,
                    labels,
                    timestamp
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """

        // 将数组转换为JSON字符串
        let recipientsData = try JSONEncoder().encode(content.recipients)
        let labelsData = try JSONEncoder().encode(content.labels)

        guard let recipientsString = String(data: recipientsData, encoding: .utf8),
            let labelsString = String(data: labelsData, encoding: .utf8)
        else {
            throw DatabaseError.insertError("Failed to encode recipients or labels")
        }

        let result = databaseManager.executeQuery(
            insertSQL,
            parameters: [
                content.from,  // 使用from作为mail_id
                content.body,
                content.from,
                content.subject,
                recipientsString,
                labelsString,
                content.timestamp,
            ]
        )

        if case let .error(error) = result {
            Logger.error("保存邮件内容到数据库失败: \(error)")
            throw DatabaseError.insertError(error)
        }

        Logger.info("成功保存邮件内容到数据库 - 邮件ID: \(content.from)")
    }

    func fetchMailLists(characterId: Int) async throws -> [EVEMailList] {
        Logger.info("开始获取邮件订阅列表 - 角色ID: \(characterId)")

        // 构建请求URL
        let urlString =
            "https://esi.evetech.net/latest/characters/\(characterId)/mail/lists/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        // 发送请求获取数据
        let data = try await networkManager.fetchDataWithToken(from: url, characterId: characterId)

        // 解析响应数据
        let mailLists = try JSONDecoder().decode([EVEMailList].self, from: data)
        Logger.info("成功获取 \(mailLists.count) 个邮件订阅列表")

        // 在后台保存到数据库
        if !mailLists.isEmpty {
            Task.detached {
                do {
                    try await self.saveMailLists(mailLists, for: characterId)
                    Logger.info("成功保存邮件订阅列表到数据库")
                } catch {
                    Logger.error("保存邮件订阅列表失败: \(error)")
                }
            }
        }

        return mailLists
    }

    /// 将邮件订阅列表保存到数据库
    /// - Parameters:
    ///   - mailLists: 邮件订阅列表数组
    ///   - characterId: 角色ID
    private func saveMailLists(_ mailLists: [EVEMailList], for characterId: Int) async throws {
        // 构建SQL插入语句
        let insertSQL = """
                INSERT OR REPLACE INTO mail_lists (
                    list_id,
                    character_id,
                    name,
                    last_updated
                ) VALUES (?, ?, ?, CURRENT_TIMESTAMP)
            """

        // 先删除该角色的旧订阅列表
        let deleteSQL = "DELETE FROM mail_lists WHERE character_id = ?"
        let deleteResult = databaseManager.executeQuery(deleteSQL, parameters: [characterId])
        if case let .error(error) = deleteResult {
            Logger.error("删除旧邮件订阅列表失败: \(error)")
            throw DatabaseError.insertError(error)
        }

        // 保存新的订阅列表
        for list in mailLists {
            let result = databaseManager.executeQuery(
                insertSQL,
                parameters: [
                    list.mailing_list_id,
                    characterId,
                    list.name,
                ]
            )

            if case let .error(error) = result {
                Logger.error("保存邮件订阅列表失败: \(error)")
                throw DatabaseError.insertError(error)
            }
        }

        Logger.info("成功保存 \(mailLists.count) 个邮件订阅列表到数据库")
    }

    /// 从数据库获取邮件订阅列表
    /// - Parameter characterId: 角色ID
    /// - Returns: 邮件订阅列表数组
    func loadMailListsFromDatabase(characterId: Int) async throws -> [EVEMailList] {
        let query = """
                SELECT list_id, name 
                FROM mail_lists 
                WHERE character_id = ? 
                ORDER BY name
            """

        let result = databaseManager.executeQuery(query, parameters: [characterId])
        switch result {
        case let .success(rows):
            var mailLists: [EVEMailList] = []

            for row in rows {
                guard
                    let listId = (row["list_id"] as? Int64).map(Int.init)
                        ?? (row["list_id"] as? Int),
                    let name = row["name"] as? String
                else {
                    continue
                }

                let mailList = EVEMailList(
                    mailing_list_id: listId,
                    name: name
                )
                mailLists.append(mailList)
            }

            Logger.info("从数据库加载了 \(mailLists.count) 个邮件订阅列表")
            return mailLists

        case let .error(error):
            Logger.error("从数据库加载邮件订阅列表失败: \(error)")
            throw DatabaseError.fetchError(error)
        }
    }

    /// 发送新邮件
    /// - Parameters:
    ///   - characterId: 角色ID
    ///   - recipients: 收件人列表
    ///   - subject: 邮件主题
    ///   - body: 邮件正文
    /// - Returns: 发送结果
    func sendMail(characterId: Int, recipients: [EVEMailRecipient], subject: String, body: String)
        async throws
    {
        Logger.info("开始发送邮件 - 角色ID: \(characterId), 收件人数: \(recipients.count)")

        // 构建请求URL
        let urlString =
            "https://esi.evetech.net/latest/characters/\(characterId)/mail/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        // 构建请求体
        let mailData: [String: Any] = [
            "approved_cost": 0,
            "body": body,
            "recipients": recipients.map {
                [
                    "recipient_id": $0.recipient_id,
                    "recipient_type": $0.recipient_type,
                ]
            },
            "subject": subject,
        ]

        // 将请求体转换为JSON数据
        guard let jsonData = try? JSONSerialization.data(withJSONObject: mailData) else {
            throw NetworkError.invalidResponse
        }

        // 发送POST请求
        _ = try await networkManager.postDataWithToken(
            to: url, body: jsonData, characterId: characterId
        )
        Logger.info("邮件发送成功")
    }
}

enum DatabaseError: Error {
    case insertError(String)
    case fetchError(String)
}
