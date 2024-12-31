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
    
    // 缓存超时时间
    private let cacheTimeout: TimeInterval = 1800 // 30分钟缓存
    
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
            
            if case .error(let error) = CharacterDatabaseManager.shared.executeQuery(
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
        
        if case .success(let rows) = CharacterDatabaseManager.shared.executeQuery(query, parameters: [characterId]),
           let row = rows.first,
           let jsonString = row["skills_data"] as? String {
            
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
    public func fetchCharacterSkills(characterId: Int, forceRefresh: Bool = false) async throws -> CharacterSkillsResponse {
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
                decoder.dateDecodingStrategy = .secondsSince1970
                let jsonData = jsonString.data(using: .utf8)!
                let queue = try decoder.decode([SkillQueueItem].self, from: jsonData)
                
                // 获取上次更新时间
                if let lastUpdated = row["last_updated"] as? String {
                    Logger.debug("从缓存加载当前技能队列 - 角色ID: \(characterId), 更新时间: \(lastUpdated)")
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
        decoder.dateDecodingStrategy = .secondsSince1970
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
