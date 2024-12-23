import Foundation

// 技能数据模型
public struct CharacterSkill: Codable {
    public let active_skill_level: Int
    public let skill_id: Int
    public let skillpoints_in_skill: Int
    public let trained_skill_level: Int
    
    public init(active_skill_level: Int, skill_id: Int, skillpoints_in_skill: Int, trained_skill_level: Int) {
        self.active_skill_level = active_skill_level
        self.skill_id = skill_id
        self.skillpoints_in_skill = skillpoints_in_skill
        self.trained_skill_level = trained_skill_level
    }
}

public struct CharacterSkillsResponse: Codable {
    public let skills: [CharacterSkill]
    public let total_sp: Int
    public let unallocated_sp: Int
    
    public init(skills: [CharacterSkill], total_sp: Int, unallocated_sp: Int) {
        self.skills = skills
        self.total_sp = total_sp
        self.unallocated_sp = unallocated_sp
    }
}

// 技能队列数据模型
public struct SkillQueueItem: Codable {
    public let finish_date: String?
    public let start_date: String?
    public let finished_level: Int
    public let level_end_sp: Int
    public let level_start_sp: Int
    public let queue_position: Int
    public let skill_id: Int
    public let training_start_sp: Int
    
    public init(finish_date: String?, start_date: String?, finished_level: Int, level_end_sp: Int, level_start_sp: Int, queue_position: Int, skill_id: Int, training_start_sp: Int) {
        self.finish_date = finish_date
        self.start_date = start_date
        self.finished_level = finished_level
        self.level_end_sp = level_end_sp
        self.level_start_sp = level_start_sp
        self.queue_position = queue_position
        self.skill_id = skill_id
        self.training_start_sp = training_start_sp
    }
    
    // 判断当前时间点是否在训练这个技能
    public var isCurrentlyTraining: Bool {
        guard let finishDateString = finish_date,
              let startDateString = start_date else {
            return false
        }
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]
        
        guard let finishDate = dateFormatter.date(from: finishDateString),
              let startDate = dateFormatter.date(from: startDateString) else {
            return false
        }
        
        let now = Date()
        return now >= startDate && now <= finishDate
    }
    
    // 计算训练进度
    public var progress: Double {
        guard let finishDateString = finish_date,
              let startDateString = start_date else {
            return 0
        }
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]
        
        guard let finishDate = dateFormatter.date(from: finishDateString),
              let startDate = dateFormatter.date(from: startDateString) else {
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
        
        // 计算时间进度比例
        let totalTrainingTime = finishDate.timeIntervalSince(startDate)
        let trainedTime = now.timeIntervalSince(startDate)
        let timeProgress = trainedTime / totalTrainingTime
        
        // 计算剩余需要训练的技能点
        let remainingSP = level_end_sp - training_start_sp
        
        // 计算当前已训练的技能点
        let trainedSP = Double(remainingSP) * timeProgress
        
        // 计算总进度
        let totalLevelSP = level_end_sp - level_start_sp
        let currentTotalTrainedSP = Double(training_start_sp - level_start_sp) + trainedSP
        
        return currentTotalTrainedSP / Double(totalLevelSP)
    }
    
    public var remainingTime: TimeInterval? {
        guard let finishDateString = finish_date else { return nil }
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]
        
        guard let finishDate = dateFormatter.date(from: finishDateString) else { return nil }
        return finishDate.timeIntervalSince(Date())
    }
    
    public var skillLevel: String {
        let romanNumerals = ["I", "II", "III", "IV", "V"]
        return romanNumerals[finished_level - 1]
    }
}

public class CharacterSkillsAPI {
    public static let shared = CharacterSkillsAPI()
    
    // 缓存结构
    private struct CacheEntry {
        let value: CharacterSkillsResponse
        let timestamp: Date
    }
    
    // 缓存字典
    private var skillsCache: [Int: CacheEntry] = [:]
    private var skillQueueCache: [Int: (value: [SkillQueueItem], timestamp: Date)] = [:]
    private let skillsCacheTimeout: TimeInterval = 300 // 5分钟缓存
    private let queueCacheTimeout: TimeInterval = 1800 // 30分钟缓存
    
    private init() {}
    
    // 检查缓存是否有效
    private func isCacheValid(_ cache: CacheEntry?, timeout: TimeInterval) -> Bool {
        guard let cache = cache else { return false }
        return Date().timeIntervalSince(cache.timestamp) < timeout
    }
    
    private func isQueueCacheValid(_ cache: (value: [SkillQueueItem], timestamp: Date)?) -> Bool {
        guard let cache = cache else { return false }
        return Date().timeIntervalSince(cache.timestamp) < queueCacheTimeout
    }
    
    // 获取角色技能信息
    public func fetchCharacterSkills(characterId: Int, forceRefresh: Bool = false) async throws -> CharacterSkillsResponse {
        // 检查缓存
        if !forceRefresh,
           let cachedEntry = skillsCache[characterId],
           isCacheValid(cachedEntry, timeout: skillsCacheTimeout) {
            Logger.info("使用缓存的技能数据 - 角色ID: \(characterId)")
            return cachedEntry.value
        } else {
            Logger.info("缓存未命中或已过期,需要从服务器获取技能数据 - 角色ID: \(characterId)")
        }
        
        // 如果没有缓存或缓存已过期，从网络获取
        let urlString = "https://esi.evetech.net/latest/characters/\(characterId)/skills/"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        
        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId
        )
        
        // 解码数据
        do {
            let skills: CharacterSkillsResponse = try JSONDecoder().decode(CharacterSkillsResponse.self, from: data)
            
            // 更新缓存
            skillsCache[characterId] = CacheEntry(value: skills, timestamp: Date())
            Logger.info("已更新技能数据缓存 - 角色ID: \(characterId)")
            
            return skills
        } catch {
            Logger.error("解析技能数据失败: \(error)")
            throw NetworkError.decodingError(error)
        }
    }
    
    // 获取技能队列信息
    public func fetchSkillQueue(characterId: Int, forceRefresh: Bool = false) async throws -> [SkillQueueItem] {
        // 检查缓存
        if !forceRefresh,
           let cachedEntry = skillQueueCache[characterId],
           isQueueCacheValid(cachedEntry) {
            Logger.info("使用缓存的技能队列数据 - 角色ID: \(characterId)")
            return cachedEntry.value
        }
        
        // 如果没有缓存或缓存已过期，从网络获取
        Logger.info("在线获取技能队列数据 - 角色ID: \(characterId)")
        let urlString = "https://esi.evetech.net/latest/characters/\(characterId)/skillqueue/"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        
        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId
        )
        
        // 解码数据
        do {
            let queue: [SkillQueueItem] = try JSONDecoder().decode([SkillQueueItem].self, from: data)
            
            // 更新缓存
            skillQueueCache[characterId] = (value: queue, timestamp: Date())
            
            return queue
        } catch {
            Logger.error("解析技能队列数据失败: \(error)")
            throw NetworkError.decodingError(error)
        }
    }
} 