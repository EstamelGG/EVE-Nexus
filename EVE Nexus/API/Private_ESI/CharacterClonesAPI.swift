import Foundation

// 克隆体数据模型
struct CharacterCloneInfo: Codable {
    let home_location: CloneLocation
    let jump_clones: [JumpClone]
    let last_clone_jump_date: String?
    let last_station_change_date: String?
}

struct CloneLocation: Codable {
    let location_id: Int
    let location_type: String
}

struct JumpClone: Codable {
    let implants: [Int]
    let jump_clone_id: Int
    let location_id: Int
    let location_type: String
    let name: String?
}

class CharacterClonesAPI {
    static let shared = CharacterClonesAPI()
    private init() {}

    // 获取克隆体缓存文件路径
    private func getClonesCacheFilePath(characterId: Int) -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let characterSkillsPath = documentsPath.appendingPathComponent("CharacterSkills")
        
        // 创建目录（如果不存在）
        try? FileManager.default.createDirectory(at: characterSkillsPath, withIntermediateDirectories: true)
        
        return characterSkillsPath.appendingPathComponent("\(characterId)_clones.json")
    }

    // 保存克隆体数据到本地文件
    private func saveClonesToCache(characterId: Int, clones: CharacterCloneInfo) -> Bool {
        do {
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(clones)
            
            let filePath = getClonesCacheFilePath(characterId: characterId)
            try jsonData.write(to: filePath)
            
            Logger.debug("成功缓存克隆体数据到文件 - 角色ID: \(characterId), 路径: \(filePath.path)")
            return true
        } catch {
            Logger.error("保存克隆体数据到文件失败: \(error)")
            return false
        }
    }

    // 从本地文件读取克隆体数据
    private func loadClonesFromCache(characterId: Int) -> CharacterCloneInfo? {
        let filePath = getClonesCacheFilePath(characterId: characterId)
        
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
                    Logger.debug("克隆体缓存已过期 - 角色ID: \(characterId)")
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
            let clones = try decoder.decode(CharacterCloneInfo.self, from: jsonData)
            
            Logger.debug("从文件缓存加载克隆体数据 - 角色ID: \(characterId), 文件路径: \(filePath.path)")
            return clones
        } catch {
            Logger.error("从文件读取克隆体数据失败: \(error)")
            return nil
        }
    }

    // 获取克隆体信息
    func fetchCharacterClones(characterId: Int, forceRefresh: Bool = false) async throws
        -> CharacterCloneInfo
    {
        // 如果不是强制刷新，先尝试从缓存加载
        if !forceRefresh {
            if let cachedClones = loadClonesFromCache(characterId: characterId) {
                Logger.debug("使用缓存的克隆体数据 - 角色ID: \(characterId)")
                return cachedClones
            }
        }

        let urlString =
            "https://esi.evetech.net/characters/\(characterId)/clones/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId
        )

        let clones = try JSONDecoder().decode(CharacterCloneInfo.self, from: data)

        // 保存到本地文件
        if saveClonesToCache(characterId: characterId, clones: clones) {
            Logger.debug("成功缓存克隆体数据到文件 - 角色ID: \(characterId)")
        }

        return clones
    }
}
