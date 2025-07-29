import Foundation

class CharacterImplantsAPI {
    static let shared = CharacterImplantsAPI()
    private init() {}

    // 获取植入体缓存文件路径
    private func getImplantsCacheFilePath(characterId: Int) -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let characterSkillsPath = documentsPath.appendingPathComponent("CharacterSkills")
        
        // 创建目录（如果不存在）
        try? FileManager.default.createDirectory(at: characterSkillsPath, withIntermediateDirectories: true)
        
        return characterSkillsPath.appendingPathComponent("\(characterId)_implants.json")
    }

    // 保存植入体数据到本地文件
    private func saveImplantsToCache(characterId: Int, implants: [Int]) -> Bool {
        do {
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(implants)
            
            let filePath = getImplantsCacheFilePath(characterId: characterId)
            try jsonData.write(to: filePath)
            
            Logger.debug("成功缓存植入体数据到文件 - 角色ID: \(characterId), 路径: \(filePath.path)")
            return true
        } catch {
            Logger.error("保存植入体数据到文件失败: \(error)")
            return false
        }
    }

    // 从本地文件读取植入体数据
    private func loadImplantsFromCache(characterId: Int) -> [Int]? {
        let filePath = getImplantsCacheFilePath(characterId: characterId)
        
        // 检查文件是否存在
        guard FileManager.default.fileExists(atPath: filePath.path) else {
            return nil
        }
        
        // 检查文件修改时间，缓存12小时
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: filePath.path)
            if let modificationDate = attributes[.modificationDate] as? Date {
                let cacheExpirationDate = modificationDate.addingTimeInterval(12 * 60 * 60) // 12小时
                if Date() > cacheExpirationDate {
                    Logger.debug("植入体缓存已过期 - 角色ID: \(characterId)")
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
            let implants = try decoder.decode([Int].self, from: jsonData)
            
            Logger.debug("从文件缓存加载植入体数据 - 角色ID: \(characterId), 文件路径: \(filePath.path)")
            return implants
        } catch {
            Logger.error("从文件读取植入体数据失败: \(error)")
            return nil
        }
    }

    // 获取植入体信息
    func fetchCharacterImplants(characterId: Int, forceRefresh: Bool = false) async throws -> [Int]
    {
        // 如果不是强制刷新，先尝试从缓存加载
        if !forceRefresh {
            if let cachedImplants = loadImplantsFromCache(characterId: characterId) {
                Logger.debug("使用缓存的植入体数据 - 角色ID: \(characterId)")
                return cachedImplants
            }
        }

        let urlString =
            "https://esi.evetech.net/characters/\(characterId)/implants/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId
        )

        let implants = try JSONDecoder().decode([Int].self, from: data)

        // 保存到本地文件
        if saveImplantsToCache(characterId: characterId, implants: implants) {
            Logger.debug("成功缓存植入体数据到文件 - 角色ID: \(characterId)")
        }

        return implants.sorted()
    }
}
