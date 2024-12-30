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

// 技能队列项目
public struct SkillQueueItem: Codable {
    public let skill_id: Int
    public let finished_level: Int
    public let queue_position: Int
    public let start_date: Date?
    public let finish_date: Date?
    public let level_start_sp: Int?
    public let level_end_sp: Int?
    public let training_start_sp: Int?
    
    // 判断当前时间点是否在训练这个技能
    public var isCurrentlyTraining: Bool {
        guard let startDate = start_date,
              let finishDate = finish_date else {
            return false
        }
        
        let now = Date()
        return now >= startDate && now <= finishDate
    }
    
    // 计算剩余时间
    public var remainingTime: TimeInterval? {
        guard let finishDate = finish_date else { return nil }
        return finishDate.timeIntervalSince(Date())
    }
    
    // 计算训练进度
    public var progress: Double {
        // 如果没有时间信息，使用技能点计算进度
        guard let startDate = start_date,
              let finishDate = finish_date,
              let levelStartSp = level_start_sp,
              let levelEndSp = level_end_sp,
              let trainingStartSp = training_start_sp else {
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
        
        // 正在训练：使用基于时间的进度计算
        let totalTrainingTime = finishDate.timeIntervalSince(startDate)
        let trainedTime = now.timeIntervalSince(startDate)
        let timeProgress = trainedTime / totalTrainingTime
        
        // 计算剩余需要训练的技能点
        let remainingSP = levelEndSp - trainingStartSp
        
        // 计算当前已训练的技能点
        let trainedSP = Double(remainingSP) * timeProgress
        
        // 计算总进度
        let totalLevelSP = levelEndSp - levelStartSp
        let currentTotalTrainedSP = Double(trainingStartSp - levelStartSp) + trainedSP
        
        return currentTotalTrainedSP / Double(totalLevelSP)
    }
    
    // 获取技能等级的罗马数字表示
    public var skillLevel: String {
        let romanNumerals = ["I", "II", "III", "IV", "V"]
        return romanNumerals[finished_level - 1]
    }
    
    public init(
        skill_id: Int,
        finished_level: Int,
        queue_position: Int,
        start_date: Date?,
        finish_date: Date?,
        level_start_sp: Int?,
        level_end_sp: Int?,
        training_start_sp: Int?
    ) {
        self.skill_id = skill_id
        self.finished_level = finished_level
        self.queue_position = queue_position
        self.start_date = start_date
        self.finish_date = finish_date
        self.level_start_sp = level_start_sp
        self.level_end_sp = level_end_sp
        self.training_start_sp = training_start_sp
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
            Logger.debug("正在写入 UserDefaults，键: \(key), 数据大小: \(encoded.count) bytes")
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
    
    // 保存技能队列缓存到UserDefaults
    private func saveQueueToDiskCache(characterId: Int, cache: QueueCacheEntry) {
        let key = queueCachePrefix + String(characterId)
        if let encoded = try? JSONEncoder().encode(cache) {
            Logger.debug("正在写入 UserDefaults，键: \(key), 数据大小: \(encoded.count) bytes")
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
    
    // 创建技能队列表
    private func setupSkillQueueTable() {
        let createTableSQL = """
            CREATE TABLE IF NOT EXISTS skill_queue_cache (
                character_id INTEGER PRIMARY KEY,
                queue_data TEXT,
                last_updated TEXT DEFAULT CURRENT_TIMESTAMP
            );
        """
        
        if case .error(let error) = CharacterDatabaseManager.shared.executeQuery(createTableSQL) {
            Logger.error("创建技能队列表失败: \(error)")
        }
    }
    
    // 保存技能队列到数据库
    private func saveSkillQueue(characterId: Int, queue: [SkillQueueItem]) -> Bool {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
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
            
            if case .error(let error) = CharacterDatabaseManager.shared.executeQuery(
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
        """
        
        if case .success(let rows) = CharacterDatabaseManager.shared.executeQuery(query, parameters: [characterId]),
           let row = rows.first,
           let jsonString = row["queue_data"] as? String {
            
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let jsonData = jsonString.data(using: .utf8)!
                let queue = try decoder.decode([SkillQueueItem].self, from: jsonData)
                
                // 获取上次更新时间
                if let lastUpdated = row["last_updated"] as? String {
                    Logger.debug("从缓存加载技能队列 - 角色ID: \(characterId), 更新时间: \(lastUpdated)")
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
        let url = URL(string: "https://esi.evetech.net/latest/characters/\(characterId)/skillqueue/?datasource=tranquility")!
        
        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId
        )
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([SkillQueueItem].self, from: data)
    }
    
    // 公开方法：获取技能队列
    public func fetchSkillQueue(characterId: Int, forceRefresh: Bool = false) async throws -> [SkillQueueItem] {
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
} 