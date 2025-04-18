import Foundation

// 技能数据模型
public struct CharacterSkill: Codable {
    public let active_skill_level: Int
    public let skill_id: Int
    public let skillpoints_in_skill: Int
    public let trained_skill_level: Int
}

public struct CharacterSkillsResponse: Codable {
    public let skills: [CharacterSkill]
    public let total_sp: Int
    public let unallocated_sp: Int
}

// 技能队列项目
public struct SkillQueueItem: Codable, Identifiable {
    public let queue_position: Int
    public let skill_id: Int
    public let finished_level: Int
    public let training_start_sp: Int?
    public let level_end_sp: Int?
    public let level_start_sp: Int?
    public let start_date: Date?
    public let finish_date: Date?

    public var id: Int { queue_position }

    public var isCurrentlyTraining: Bool {
        guard let startDate = start_date,
            let finishDate = finish_date
        else {
            return false
        }
        let now = Date()
        return now >= startDate && now <= finishDate
    }

    public var remainingTime: TimeInterval? {
        guard let finishDate = finish_date else {
            return nil
        }
        return finishDate.timeIntervalSinceNow
    }

    // 获取技能等级的罗马数字表示
    public var skillLevel: String {
        let romanNumerals = ["I", "II", "III", "IV", "V"]
        return romanNumerals[finished_level - 1]
    }

    // 计算训练进度
    public var progress: Double {
        guard let startDate = start_date,
            let finishDate = finish_date,
            let trainingStartSp = training_start_sp,
            let levelEndSp = level_end_sp,
            let levelStartSp = level_start_sp
        else {
            return 0
        }

        let now = Date()

        // 如果还没开始训练，进度为0
        if now < startDate {
            return 0
        }

        // 如果已经完成训练，进度为1
        if now > finishDate {
            return 1
        }

        // 正在训练中：使用基于时间的进度计算
        let totalTrainingTime = finishDate.timeIntervalSince(startDate)
        let trainedTime = now.timeIntervalSince(startDate)
        let timeProgress = trainedTime / totalTrainingTime

        // 计算剩余需要训练的技能点
        let remainingSP = levelEndSp - trainingStartSp

        // 计算当前已训练的技能点
        let trainedSP = Double(remainingSP) * timeProgress
        let currentSP = Double(trainingStartSp) + trainedSP

        // 计算当前等级的进度
        let levelCurrentSP = currentSP - Double(levelStartSp)  // 在该等级已获得的技能点
        let levelTotalSP = Double(levelEndSp - levelStartSp)  // 该等级需要的总技能点

        return levelCurrentSP / levelTotalSP
    }
}

struct CharacterAttributes: Codable {
    let charisma: Int
    let intelligence: Int
    let memory: Int
    let perception: Int
    let willpower: Int
    let bonus_remaps: Int?
    let accrued_remap_cooldown_date: String?
    let last_remap_date: String?
}

public class CharacterSkillsAPI {
    public static let shared = CharacterSkillsAPI()
    private init() {}

    // 保存技能数据到数据库
    private func saveSkillsToCache(characterId: Int, skills: CharacterSkillsResponse) -> Bool {
        do {
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(skills)

            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                Logger.error("技能数据JSON编码失败")
                return false
            }

            let query = """
                    INSERT OR REPLACE INTO character_skills (
                        character_id, skills_data, unallocated_sp, total_sp, last_updated
                    ) VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)
                """

            if case let .error(error) = CharacterDatabaseManager.shared.executeQuery(
                query,
                parameters: [characterId, jsonString, skills.unallocated_sp, skills.total_sp]
            ) {
                Logger.error("保存技能数据失败: \(error)")
                return false
            }

            Logger.debug("成功保存技能数据 - 角色ID: \(characterId)")
            return true
        } catch {
            Logger.error("技能数据序列化失败: \(error)")
            return false
        }
    }

    // 从数据库读取技能数据
    private func loadSkillsFromCache(characterId: Int) -> CharacterSkillsResponse? {
        let query = """
                SELECT skills_data, last_updated 
                FROM character_skills 
                WHERE character_id = ? 
                AND datetime(last_updated) > datetime('now', '-30 minutes')
            """

        if case let .success(rows) = CharacterDatabaseManager.shared.executeQuery(
            query, parameters: [characterId]
        ),
            let row = rows.first,
            let jsonString = row["skills_data"] as? String
        {
            do {
                let decoder = JSONDecoder()
                let jsonData = jsonString.data(using: .utf8)!
                let skills = try decoder.decode(CharacterSkillsResponse.self, from: jsonData)

                if let lastUpdated = row["last_updated"] as? String {
                    Logger.debug("从缓存加载总技能数据 - 角色ID: \(characterId), 更新时间: \(lastUpdated)")
                }

                return skills
            } catch {
                Logger.error("技能数据解析失败: \(error)")
            }
        }
        return nil
    }

    // 获取角色技能信息
    public func fetchCharacterSkills(characterId: Int, forceRefresh: Bool = false) async throws
        -> CharacterSkillsResponse
    {
        // 如果不是强制刷新，尝试从缓存加载
        if !forceRefresh {
            if let cachedSkills = loadSkillsFromCache(characterId: characterId) {
                return cachedSkills
            }
        }

        // 从网络获取数据
        let urlString = "https://esi.evetech.net/latest/characters/\(characterId)/skills/"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId
        )

        do {
            let skills = try JSONDecoder().decode(CharacterSkillsResponse.self, from: data)

            // 保存到数据库
            if saveSkillsToCache(characterId: characterId, skills: skills) {
                Logger.debug("成功缓存技能数据")
            }

            return skills
        } catch {
            Logger.error("解析技能数据失败: \(error)")
            throw NetworkError.decodingError(error)
        }
    }

    // 保存技能队列到数据库
    private func saveSkillQueue(characterId: Int, queue: [SkillQueueItem]) -> Bool {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            let jsonData = try encoder.encode(queue)

            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                Logger.error("技能队列JSON编码失败")
                return false
            }

            let query = """
                    INSERT OR REPLACE INTO character_skill_queue (
                        character_id, queue_data, last_updated
                    ) VALUES (?, ?, CURRENT_TIMESTAMP)
                """

            if case let .error(error) = CharacterDatabaseManager.shared.executeQuery(
                query,
                parameters: [characterId, jsonString]
            ) {
                Logger.error("保存技能队列失败: \(error)")
                return false
            }

            Logger.debug("成功保存技能队列 - 角色ID: \(characterId), 队列长度: \(queue.count)")
            return true
        } catch {
            Logger.error("技能队列序列化失败: \(error)")
            return false
        }
    }

    // 从数据库读取技能队列
    private func loadSkillQueue(characterId: Int) -> [SkillQueueItem]? {
        let query = """
                SELECT queue_data, last_updated 
                FROM character_skill_queue 
                WHERE character_id = ?
                AND datetime(last_updated) > datetime('now', '-1 hours')
            """

        if case let .success(rows) = CharacterDatabaseManager.shared.executeQuery(
            query, parameters: [characterId]
        ),
            let row = rows.first,
            let jsonString = row["queue_data"] as? String
        {
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .secondsSince1970
                let jsonData = jsonString.data(using: .utf8)!
                let queue = try decoder.decode([SkillQueueItem].self, from: jsonData)

                // 获取上次更新时间
                if let lastUpdated = row["last_updated"] as? String {
                    Logger.debug(
                        "从缓存加载技能队列 - 角色ID: \(characterId), 更新时间: \(lastUpdated), 队列长度: \(queue.count)"
                    )
                }

                return queue
            } catch {
                Logger.error("技能队列解析失败: \(error)")
            }
        }
        return nil
    }

    // 从服务器获取技能队列
    private func fetchSkillQueueFromServer(characterId: Int) async throws -> [SkillQueueItem] {
        let url = URL(
            string:
                "https://esi.evetech.net/latest/characters/\(characterId)/skillqueue/?datasource=tranquility"
        )!

        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([SkillQueueItem].self, from: data)
    }

    // 公开方法：获取技能队列
    public func fetchSkillQueue(characterId: Int, forceRefresh: Bool = false) async throws
        -> [SkillQueueItem]
    {
        // 如果不是强制刷新，尝试从缓存加载
        if !forceRefresh {
            if let cachedQueue = loadSkillQueue(characterId: characterId) {
                return cachedQueue
            }
        }

        // 从服务器获取新数据
        Logger.debug("从服务器获取技能队列 - 角色ID: \(characterId)")
        let queue = try await fetchSkillQueueFromServer(characterId: characterId)

        // 保存到数据库
        if saveSkillQueue(characterId: characterId, queue: queue) {
            Logger.debug("成功缓存技能队列")
        }

        return queue
    }

    // 从数据库读取属性数据
    private func loadAttributesFromCache(characterId: Int) -> CharacterAttributes? {
        let query = """
                SELECT charisma, intelligence, memory, perception, willpower,
                       bonus_remaps, accrued_remap_cooldown_date, last_remap_date, last_updated
                FROM character_attributes 
                WHERE character_id = ? 
                AND datetime(last_updated) > datetime('now', '-1 hours')
            """

        if case let .success(rows) = CharacterDatabaseManager.shared.executeQuery(
            query, parameters: [characterId]
        ),
            let row = rows.first
        {
            // 使用 NSNumber 转换来处理不同的数字类型
            let charisma = (row["charisma"] as? NSNumber)?.intValue ?? 19
            let intelligence = (row["intelligence"] as? NSNumber)?.intValue ?? 20
            let memory = (row["memory"] as? NSNumber)?.intValue ?? 20
            let perception = (row["perception"] as? NSNumber)?.intValue ?? 20
            let willpower = (row["willpower"] as? NSNumber)?.intValue ?? 20
            let bonusRemaps = (row["bonus_remaps"] as? NSNumber)?.intValue ?? 0

            return CharacterAttributes(
                charisma: charisma,
                intelligence: intelligence,
                memory: memory,
                perception: perception,
                willpower: willpower,
                bonus_remaps: bonusRemaps,
                accrued_remap_cooldown_date: row["accrued_remap_cooldown_date"] as? String,
                last_remap_date: row["last_remap_date"] as? String
            )
        }
        return nil
    }

    /// 获取角色属性点
    /// - Parameters:
    ///   - characterId: 角色ID
    ///   - forceRefresh: 是否强制刷新，默认为false
    /// - Returns: 角色属性数据
    func fetchAttributes(characterId: Int, forceRefresh: Bool = false) async throws
        -> CharacterAttributes
    {
        // 如果不是强制刷新，尝试从缓存加载
        if !forceRefresh {
            if let cachedAttributes = loadAttributesFromCache(characterId: characterId) {
                Logger.debug("从缓存加载角色属性 - 角色ID: \(characterId)")
                return cachedAttributes
            }
        }

        Logger.debug("从服务器获取角色属性 - 角色ID: \(characterId)")
        let url = URL(
            string:
                "https://esi.evetech.net/latest/characters/\(characterId)/attributes/?datasource=tranquility"
        )!

        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId
        )

        do {
            let decoder = JSONDecoder()
            let response = try decoder.decode(CharacterAttributes.self, from: data)

            // 保存到数据库
            let query = """
                    INSERT OR REPLACE INTO character_attributes (
                        character_id, charisma, intelligence, memory, perception, willpower,
                        bonus_remaps, accrued_remap_cooldown_date, last_remap_date, last_updated
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
                """

            // 处理可选值，将nil转换为NSNull()
            let parameters: [Any] = [
                characterId,
                response.charisma,
                response.intelligence,
                response.memory,
                response.perception,
                response.willpower,
                response.bonus_remaps.map { $0 } ?? NSNull(),
                response.accrued_remap_cooldown_date.map { $0 } ?? NSNull(),
                response.last_remap_date.map { $0 } ?? NSNull(),
            ]

            if case let .error(error) = CharacterDatabaseManager.shared.executeQuery(
                query, parameters: parameters
            ) {
                Logger.error("保存角色属性失败: \(error)")
            } else {
                Logger.debug("成功缓存角色属性数据")
            }

            return response
        } catch {
            Logger.error("解析角色属性数据失败: \(error)")
            throw NetworkError.decodingError(error)
        }
    }
}
