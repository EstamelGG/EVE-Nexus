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
            // 暂停状态：使用技能点计算进度
            let totalLevelSP = level_end_sp - level_start_sp
            let currentTrainedSP = training_start_sp - level_start_sp
            return Double(currentTrainedSP) / Double(totalLevelSP)
        }
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]
        
        guard let finishDate = dateFormatter.date(from: finishDateString),
              let startDate = dateFormatter.date(from: startDateString) else {
            // 日期解析失败：使用技能点计算进度
            let totalLevelSP = level_end_sp - level_start_sp
            let currentTrainedSP = training_start_sp - level_start_sp
            return Double(currentTrainedSP) / Double(totalLevelSP)
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
        
        // 正在训练：使用基于时间的进度计算
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
    private struct SkillsCacheEntry: Codable {
        let value: CharacterSkillsResponse
        let timestamp: Date
    }
    
    private struct QueueCacheEntry: Codable {
        let value: [SkillQueueItem]
        let timestamp: Date
    }
    
    // 添加并发队列用于同步访问
    private let cacheQueue = DispatchQueue(label: "com.eve-nexus.cache", attributes: .concurrent)
    
    // 内存缓存
    private var skillsMemoryCache: [Int: SkillsCacheEntry] = [:]
    private var queueMemoryCache: [Int: QueueCacheEntry] = [:]
    
    // 缓存超时时间
    private let cacheTimeout: TimeInterval = 1800 // 30分钟缓存
    
    // UserDefaults键前缀
    private let skillsCachePrefix = "skills_cache_"
    private let queueCachePrefix = "queue_cache_"
    
    // 检查缓存是否有效
    private func isSkillsCacheValid(_ cache: SkillsCacheEntry?) -> Bool {
        guard let cache = cache else { return false }
        return Date().timeIntervalSince(cache.timestamp) < cacheTimeout
    }
    
    private func isQueueCacheValid(_ cache: QueueCacheEntry?) -> Bool {
        guard let cache = cache else { return false }
        return Date().timeIntervalSince(cache.timestamp) < cacheTimeout
    }
    
    // 从UserDefaults获取技能缓存
    private func getSkillsDiskCache(characterId: Int) -> SkillsCacheEntry? {
        let key = skillsCachePrefix + String(characterId)
        guard let data = UserDefaults.standard.data(forKey: key),
              let cache = try? JSONDecoder().decode(SkillsCacheEntry.self, from: data) else {
            return nil
        }
        return cache
    }
    
    // 从UserDefaults获取技能队列缓存
    private func getQueueDiskCache(characterId: Int) -> QueueCacheEntry? {
        let key = queueCachePrefix + String(characterId)
        guard let data = UserDefaults.standard.data(forKey: key),
              let cache = try? JSONDecoder().decode(QueueCacheEntry.self, from: data) else {
            return nil
        }
        return cache
    }
    
    // 保存技能缓存到UserDefaults
    private func saveSkillsToDiskCache(characterId: Int, cache: SkillsCacheEntry) {
        let key = skillsCachePrefix + String(characterId)
        if let encoded = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
    
    // 保存技能队列缓存到UserDefaults
    private func saveQueueToDiskCache(characterId: Int, cache: QueueCacheEntry) {
        let key = queueCachePrefix + String(characterId)
        if let encoded = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
    
    // 安全地获取队列缓存
    private func getQueueMemoryCache(characterId: Int) -> QueueCacheEntry? {
        var result: QueueCacheEntry?
        cacheQueue.sync {
            result = queueMemoryCache[characterId]
        }
        return result
    }
    
    // 安全地设置队列缓存
    private func setQueueMemoryCache(characterId: Int, cache: QueueCacheEntry) {
        cacheQueue.async(flags: .barrier) {
            self.queueMemoryCache[characterId] = cache
        }
    }
    
    // 安全地获取技能缓存
    private func getSkillsMemoryCache(characterId: Int) -> SkillsCacheEntry? {
        var result: SkillsCacheEntry?
        cacheQueue.sync {
            result = skillsMemoryCache[characterId]
        }
        return result
    }
    
    // 安全地设置技能缓存
    private func setSkillsMemoryCache(characterId: Int, cache: SkillsCacheEntry) {
        cacheQueue.async(flags: .barrier) {
            self.skillsMemoryCache[characterId] = cache
        }
    }
    
    // 清除缓存
    private func clearCache(characterId: Int) {
        cacheQueue.async(flags: .barrier) {
            // 清除内存缓存
            self.skillsMemoryCache.removeValue(forKey: characterId)
            self.queueMemoryCache.removeValue(forKey: characterId)
            
            // 清除磁盘缓存
            let skillsKey = self.skillsCachePrefix + String(characterId)
            let queueKey = self.queueCachePrefix + String(characterId)
            UserDefaults.standard.removeObject(forKey: skillsKey)
            UserDefaults.standard.removeObject(forKey: queueKey)
        }
    }
    
    private init() {}
    
    // 获取角色技能信息
    public func fetchCharacterSkills(characterId: Int, forceRefresh: Bool = false) async throws -> CharacterSkillsResponse {
        // 如果不是强制刷新，先尝试使用缓存
        if !forceRefresh {
            // 1. 先检查内存缓存
            if let memoryCached = getSkillsMemoryCache(characterId: characterId),
               isSkillsCacheValid(memoryCached) {
                Logger.info("使用内存缓存的技能数据 - 角色ID: \(characterId)")
                return memoryCached.value
            }
            
            // 2. 如果内存缓存不可用，检查磁盘缓存
            if let diskCached = getSkillsDiskCache(characterId: characterId),
               isSkillsCacheValid(diskCached) {
                Logger.info("使用磁盘缓存的技能数据 - 角色ID: \(characterId)")
                // 更新内存缓存
                setSkillsMemoryCache(characterId: characterId, cache: diskCached)
                return diskCached.value
            }
            
            Logger.info("缓存未命中或已过期,需要从服务器获取技能数据 - 角色ID: \(characterId)")
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
            
            // 创建新的缓存条目
            let cacheEntry = SkillsCacheEntry(value: skills, timestamp: Date())
            
            // 更新内存缓存
            setSkillsMemoryCache(characterId: characterId, cache: cacheEntry)
            
            // 更新磁盘缓存
            saveSkillsToDiskCache(characterId: characterId, cache: cacheEntry)
            
            Logger.info("已更新技能数据缓存 - 角色ID: \(characterId)")
            
            return skills
        } catch {
            Logger.error("解析技能数据失败: \(error)")
            throw NetworkError.decodingError(error)
        }
    }
    
    // 获取技能队列信息
    public func fetchSkillQueue(characterId: Int, forceRefresh: Bool = false) async throws -> [SkillQueueItem] {
        // 如果不是强制刷新，先尝试使用缓存
        if !forceRefresh {
            // 1. 先检查内存缓存
            if let memoryCached = getQueueMemoryCache(characterId: characterId),
               isQueueCacheValid(memoryCached) {
                Logger.info("使用内存缓存的技能队列数据 - 角色ID: \(characterId)")
                return memoryCached.value
            }
            
            // 2. 如果内存缓存不可用，检查磁盘缓存
            if let diskCached = getQueueDiskCache(characterId: characterId),
               isQueueCacheValid(diskCached) {
                Logger.info("使用磁盘缓存的技能队列数据 - 角色ID: \(characterId)")
                // 更新内存缓存
                setQueueMemoryCache(characterId: characterId, cache: diskCached)
                return diskCached.value
            }
            
            Logger.info("缓存未命中或已过期,需要从服务器获取技能队列数据 - 角色ID: \(characterId)")
        }
        
        // 从网络获取数据
        let urlString = "https://esi.evetech.net/latest/characters/\(characterId)/skillqueue/"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        
        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId
        )
        
        do {
            let queue = try JSONDecoder().decode([SkillQueueItem].self, from: data)
            
            // 创建新的缓存条目
            let cacheEntry = QueueCacheEntry(value: queue, timestamp: Date())
            
            // 更新内存缓存
            setQueueMemoryCache(characterId: characterId, cache: cacheEntry)
            
            // 更新磁盘缓存
            saveQueueToDiskCache(characterId: characterId, cache: cacheEntry)
            
            return queue
        } catch {
            Logger.error("解析技能队列数据失败: \(error)")
            throw NetworkError.decodingError(error)
        }
    }
} 