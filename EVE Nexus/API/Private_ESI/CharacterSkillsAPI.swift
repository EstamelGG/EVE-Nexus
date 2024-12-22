import Foundation

// 技能数据模型
struct CharacterSkill: Codable {
    let active_skill_level: Int
    let skill_id: Int
    let skillpoints_in_skill: Int
    let trained_skill_level: Int
}

struct CharacterSkillsResponse: Codable {
    let skills: [CharacterSkill]
    let total_sp: Int
    let unallocated_sp: Int
}

class CharacterSkillsAPI {
    static let shared = CharacterSkillsAPI()
    
    private init() {}
    
    // 获取角色技能信息
    func fetchCharacterSkills(characterId: Int) async throws -> CharacterSkillsResponse {
        // 检查 UserDefaults 缓存
        let skillsCacheKey = "character_\(characterId)_skills"
        let skillsUpdateTimeKey = "character_\(characterId)_skills_update_time"
        
        // 如果缓存存在且未过期（5分钟），直接返回缓存数据
        if let cachedData = UserDefaults.standard.data(forKey: skillsCacheKey),
           let lastUpdateTime = UserDefaults.standard.object(forKey: skillsUpdateTimeKey) as? Date,
           Date().timeIntervalSince(lastUpdateTime) < 300 { // 5分钟缓存
            do {
                let skills = try JSONDecoder().decode(CharacterSkillsResponse.self, from: cachedData)
                Logger.info("Using cached skills data for character \(characterId)")
                return skills
            } catch {
                Logger.error("Failed to decode cached skills data: \(error)")
            }
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
            let skills = try JSONDecoder().decode(CharacterSkillsResponse.self, from: data)
            
            // 更新缓存
            if let encodedData = try? JSONEncoder().encode(skills) {
                UserDefaults.standard.set(encodedData, forKey: skillsCacheKey)
                UserDefaults.standard.set(Date(), forKey: skillsUpdateTimeKey)
            }
            
            return skills
        } catch {
            Logger.error("解析技能数据失败: \(error)")
            throw NetworkError.decodingError(error)
        }
    }
    
    // 获取技能队列信息
    func fetchSkillQueue(characterId: Int) async throws -> [SkillQueueItem] {
        // 检查 UserDefaults 缓存
        let queueCacheKey = "character_\(characterId)_skillqueue"
        let queueUpdateTimeKey = "character_\(characterId)_skillqueue_update_time"
        
        // 如果缓存存在且未过期（30分钟），直接返回缓存数据
        if let cachedData = UserDefaults.standard.data(forKey: queueCacheKey),
           let lastUpdateTime = UserDefaults.standard.object(forKey: queueUpdateTimeKey) as? Date,
           Date().timeIntervalSince(lastUpdateTime) < 30 * 60 { // 30 分钟缓存
            do {
                let queue = try JSONDecoder().decode([SkillQueueItem].self, from: cachedData)
                Logger.info("使用缓存的技能队列数据 - 角色ID: \(characterId)")
                return queue
            } catch {
                Logger.error("解码缓存的技能队列数据失败: \(error)")
            }
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
            let queue = try JSONDecoder().decode([SkillQueueItem].self, from: data)
            
            // 更新缓存
            if let encodedData = try? JSONEncoder().encode(queue) {
                UserDefaults.standard.set(encodedData, forKey: queueCacheKey)
                UserDefaults.standard.set(Date(), forKey: queueUpdateTimeKey)
            }
            
            return queue
        } catch {
            Logger.error("解析技能队列数据失败: \(error)")
            throw NetworkError.decodingError(error)
        }
    }
} 