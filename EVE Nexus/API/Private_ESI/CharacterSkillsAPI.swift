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

    /// 技能ID到技能信息的映射，用于快速查找（O(1)时间复杂度）
    /// 此属性会被缓存到文件中，如果缓存文件中不存在则从 skills 数组自动创建
    public var skillsMap: [Int: CharacterSkill]

    private enum CodingKeys: String, CodingKey {
        case skills
        case total_sp
        case unallocated_sp
        case skillsMap
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        skills = try container.decode([CharacterSkill].self, forKey: .skills)
        total_sp = try container.decode(Int.self, forKey: .total_sp)
        unallocated_sp = try container.decode(Int.self, forKey: .unallocated_sp)

        // 尝试从缓存文件中读取 skillsMap，如果不存在则从 skills 数组创建（向后兼容）
        if let cachedMap = try? container.decode([Int: CharacterSkill].self, forKey: .skillsMap) {
            skillsMap = cachedMap
        } else {
            // 从 skills 数组创建技能ID到技能信息的映射
            skillsMap = Dictionary(uniqueKeysWithValues: skills.map { ($0.skill_id, $0) })
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(skills, forKey: .skills)
        try container.encode(total_sp, forKey: .total_sp)
        try container.encode(unallocated_sp, forKey: .unallocated_sp)
        // 将 skillsMap 也编码到缓存文件中
        try container.encode(skillsMap, forKey: .skillsMap)
    }
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
        let levelCurrentSP = currentSP - Double(levelStartSp) // 在该等级已获得的技能点
        let levelTotalSP = Double(levelEndSp - levelStartSp) // 该等级需要的总技能点

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

    /// 技能与技能队列本地缓存的有效期（秒），两者必须一致，避免只命中一侧导致数据不同步
    private static let pairedCacheValiditySeconds: TimeInterval = 2 * 60 * 60

    // 获取技能缓存文件路径
    private func getSkillsCacheFilePath(characterId: Int) -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first!
        let characterSkillsPath = documentsPath.appendingPathComponent("CharacterSkills")

        // 创建目录（如果不存在）
        try? FileManager.default.createDirectory(
            at: characterSkillsPath, withIntermediateDirectories: true
        )

        return characterSkillsPath.appendingPathComponent("\(characterId)_all_skills.json")
    }

    // 保存技能数据到本地文件
    private func saveSkillsToCache(characterId: Int, skills: CharacterSkillsResponse) -> Bool {
        do {
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(skills)

            let filePath = getSkillsCacheFilePath(characterId: characterId)
            try jsonData.write(to: filePath)

            Logger.success("成功缓存技能数据到文件 - 角色ID: \(characterId), 路径: \(filePath.path)")
            // 仅更新技能时使队列缓存失效，保证「技能+队列」成对有效
            invalidateSkillQueueCacheFile(characterId: characterId)
            return true
        } catch {
            Logger.error("保存技能数据到文件失败: \(error)")
            return false
        }
    }

    /// 删除技能队列缓存文件（与技能缓存配对失效）
    private func invalidateSkillQueueCacheFile(characterId: Int) {
        let path = getSkillQueueCacheFilePath(characterId: characterId)
        if FileManager.default.fileExists(atPath: path.path) {
            try? FileManager.default.removeItem(at: path)
            Logger.debug("已使技能队列缓存失效（与技能更新配对）- 角色ID: \(characterId)")
        }
    }

    /// 删除技能缓存文件（与队列缓存配对失效）
    private func invalidateSkillsCacheFile(characterId: Int) {
        let path = getSkillsCacheFilePath(characterId: characterId)
        if FileManager.default.fileExists(atPath: path.path) {
            try? FileManager.default.removeItem(at: path)
            Logger.debug("已使技能缓存失效（与队列更新配对）- 角色ID: \(characterId)")
        }
    }

    /// 同步从本地缓存读取技能数据（无网络请求、无阻塞）
    /// 用于装配等需要即时数据的场景，缓存未命中时返回 nil
    public func loadSkillsFromCacheIfAvailable(characterId: Int) -> CharacterSkillsResponse? {
        loadSkillsFromCache(characterId: characterId)
    }

    /// 同步从本地缓存读取技能和技能队列（无网络请求、无阻塞）
    /// 用于合并技能数据，任一缓存未命中时返回 nil
    public func loadSkillsAndQueueFromCacheIfAvailable(characterId: Int) -> (skills: CharacterSkillsResponse, queue: [SkillQueueItem])? {
        guard let skills = loadSkillsFromCache(characterId: characterId),
              let queue = loadSkillQueue(characterId: characterId)
        else {
            return nil
        }
        return (skills, queue)
    }

    // 从本地文件读取技能数据
    private func loadSkillsFromCache(characterId: Int) -> CharacterSkillsResponse? {
        let filePath = getSkillsCacheFilePath(characterId: characterId)

        // 检查文件是否存在
        guard FileManager.default.fileExists(atPath: filePath.path) else {
            return nil
        }

        // 检查文件修改时间（与技能队列缓存使用相同有效期）
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: filePath.path)
            if let modificationDate = attributes[.modificationDate] as? Date {
                let cacheExpirationDate = modificationDate.addingTimeInterval(Self.pairedCacheValiditySeconds)
                if Date() > cacheExpirationDate {
                    Logger.debug("技能缓存已过期 - 角色ID: \(characterId)")
                    return nil
                }
            }
        } catch {
            Logger.error("获取文件属性失败: \(error)")
            return nil
        }

        do {
            let jsonData = try Data(contentsOf: filePath)
            let decoder = JSONDecoder()
            let skills = try decoder.decode(CharacterSkillsResponse.self, from: jsonData)

            Logger.debug("从文件缓存加载技能数据 - 角色ID: \(characterId), 文件路径: \(filePath.path)")
            return skills
        } catch {
            Logger.error("从文件读取技能数据失败: \(error)")
            return nil
        }
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
        let urlString = "https://esi.evetech.net/characters/\(characterId)/skills/"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId
        )

        do {
            let skills = try JSONDecoder().decode(CharacterSkillsResponse.self, from: data)

            // 保存到本地文件
            if saveSkillsToCache(characterId: characterId, skills: skills) {
                Logger.success("成功缓存技能数据到文件")
            }

            return skills
        } catch {
            Logger.error("解析技能数据失败: \(error)")
            throw NetworkError.decodingError(error)
        }
    }

    /// 同时获取角色技能和技能队列（并行请求，一次调用完成合并所需数据）
    /// 缓存：两者共用同一有效期；仅当「技能+队列」缓存同时有效时才使用磁盘缓存。
    /// 网络拉取：始终同时强制刷新技能与队列，避免出现只更新一侧、与另一侧旧缓存混用的情况。
    /// - Parameters:
    ///   - characterId: 角色ID
    ///   - forceRefresh: 是否跳过合并缓存直接走网络（与内部对技能/队列的强制刷新一致）
    /// - Returns: (技能数据, 技能队列)
    public func fetchCharacterSkillsAndQueue(
        characterId: Int,
        forceRefresh: Bool = false
    ) async throws -> (skills: CharacterSkillsResponse, queue: [SkillQueueItem]) {
        if !forceRefresh {
            if let cached = loadSkillsAndQueueFromCacheIfAvailable(characterId: characterId) {
                return cached
            }
        }

        // 必须同时从网络拉取两组数据且均强制刷新，保证与磁盘缓存成对、时间一致
        async let skillsTask = fetchCharacterSkills(characterId: characterId, forceRefresh: true)
        async let queueTask = fetchSkillQueue(characterId: characterId, forceRefresh: true)

        return try await (skillsTask, queueTask)
    }

    // 获取技能队列缓存文件路径
    private func getSkillQueueCacheFilePath(characterId: Int) -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first!
        let characterSkillsPath = documentsPath.appendingPathComponent("CharacterSkills")

        // 创建目录（如果不存在）
        try? FileManager.default.createDirectory(
            at: characterSkillsPath, withIntermediateDirectories: true
        )

        return characterSkillsPath.appendingPathComponent("\(characterId)_skill_queue.json")
    }

    /// 同步从本地缓存读取技能队列（无网络请求、无阻塞）
    /// 用于合并技能数据时获取队列中已完成的技能等级
    public func loadSkillQueueFromCacheIfAvailable(characterId: Int) -> [SkillQueueItem]? {
        loadSkillQueue(characterId: characterId)
    }

    // 从本地文件读取技能队列
    private func loadSkillQueue(characterId: Int) -> [SkillQueueItem]? {
        let filePath = getSkillQueueCacheFilePath(characterId: characterId)

        // 检查文件是否存在
        guard FileManager.default.fileExists(atPath: filePath.path) else {
            return nil
        }

        // 检查文件修改时间（与技能缓存使用相同有效期）
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: filePath.path)
            if let modificationDate = attributes[.modificationDate] as? Date {
                let cacheExpirationDate = modificationDate.addingTimeInterval(Self.pairedCacheValiditySeconds)
                if Date() > cacheExpirationDate {
                    Logger.debug("技能队列缓存已过期 - 角色ID: \(characterId)")
                    return nil
                }
            }
        } catch {
            Logger.error("获取文件属性失败: \(error)")
            return nil
        }

        do {
            let jsonData = try Data(contentsOf: filePath)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            let queue = try decoder.decode([SkillQueueItem].self, from: jsonData)

            Logger.debug(
                "从文件缓存加载技能队列 - 角色ID: \(characterId), 文件路径: \(filePath.path), 队列长度: \(queue.count)")
            return queue
        } catch {
            Logger.error("从文件读取技能队列失败: \(error)")
            return nil
        }
    }

    // 从服务器获取技能队列
    private func fetchSkillQueueFromServer(characterId: Int) async throws -> [SkillQueueItem] {
        let url = URL(
            string:
            "https://esi.evetech.net/characters/\(characterId)/skillqueue/?datasource=tranquility"
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

        // 保存到本地文件
        if saveSkillQueue(characterId: characterId, queue: queue) {
            Logger.success("成功缓存技能队列到文件")
        }

        return queue
    }

    // 保存技能队列到本地文件（保存成功后使技能缓存失效，保证与技能缓存成对一致）
    private func saveSkillQueue(characterId: Int, queue: [SkillQueueItem]) -> Bool {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            let jsonData = try encoder.encode(queue)

            let filePath = getSkillQueueCacheFilePath(characterId: characterId)
            try jsonData.write(to: filePath)

            Logger.debug(
                "成功缓存技能队列到文件 - 角色ID: \(characterId), 路径: \(filePath.path), 队列长度: \(queue.count)")
            invalidateSkillsCacheFile(characterId: characterId)
            return true
        } catch {
            Logger.error("保存技能队列到文件失败: \(error)")
            return false
        }
    }

    private func getAttributesCacheFilePath(characterId: Int) -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first!
        let characterSkillsPath = documentsPath.appendingPathComponent("CharacterSkills")

        // 创建目录（如果不存在）
        try? FileManager.default.createDirectory(
            at: characterSkillsPath, withIntermediateDirectories: true
        )

        return characterSkillsPath.appendingPathComponent("\(characterId)_attributes.json")
    }

    // 保存角色属性到本地文件
    private func saveAttributesToCache(characterId: Int, attributes: CharacterAttributes) -> Bool {
        do {
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(attributes)

            let filePath = getAttributesCacheFilePath(characterId: characterId)
            try jsonData.write(to: filePath)

            Logger.success("成功缓存角色属性到文件 - 角色ID: \(characterId), 路径: \(filePath.path)")
            return true
        } catch {
            Logger.error("保存角色属性到文件失败: \(error)")
            return false
        }
    }

    // 从本地文件读取角色属性
    private func loadAttributesFromCache(characterId: Int) -> CharacterAttributes? {
        let filePath = getAttributesCacheFilePath(characterId: characterId)

        // 检查文件是否存在
        guard FileManager.default.fileExists(atPath: filePath.path) else {
            return nil
        }

        // 检查文件修改时间，缓存1小时
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: filePath.path)
            if let modificationDate = attributes[.modificationDate] as? Date {
                let cacheExpirationDate = modificationDate.addingTimeInterval(60 * 60) // 1小时
                if Date() > cacheExpirationDate {
                    Logger.debug("角色属性缓存已过期 - 角色ID: \(characterId)")
                    return nil
                }
            }
        } catch {
            Logger.error("获取文件属性失败: \(error)")
            return nil
        }

        do {
            let jsonData = try Data(contentsOf: filePath)
            let decoder = JSONDecoder()
            let attributes = try decoder.decode(CharacterAttributes.self, from: jsonData)

            Logger.debug("从文件缓存加载角色属性 - 角色ID: \(characterId), 文件路径: \(filePath.path)")
            return attributes
        } catch {
            Logger.error("从文件读取角色属性失败: \(error)")
            return nil
        }
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
            "https://esi.evetech.net/characters/\(characterId)/attributes/?datasource=tranquility"
        )!

        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId
        )

        do {
            let decoder = JSONDecoder()
            let response = try decoder.decode(CharacterAttributes.self, from: data)

            // 保存到本地文件
            if saveAttributesToCache(characterId: characterId, attributes: response) {
                Logger.success("成功缓存角色属性到文件")
            }

            return response
        } catch {
            Logger.error("解析角色属性数据失败: \(error)")
            throw NetworkError.decodingError(error)
        }
    }
}
