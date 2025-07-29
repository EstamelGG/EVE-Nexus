import Foundation

public struct LoyaltyPoint: Codable {
    public let corporation_id: Int
    public let loyalty_points: Int
}

public class CharacterLoyaltyPointsAPI {
    public static let shared = CharacterLoyaltyPointsAPI()

    private init() {}

    // 获取忠诚点缓存文件路径
    private func getLoyaltyPointsCacheFilePath(characterId: Int) -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let characterSkillsPath = documentsPath.appendingPathComponent("CharacterSkills")
        
        // 创建目录（如果不存在）
        try? FileManager.default.createDirectory(at: characterSkillsPath, withIntermediateDirectories: true)
        
        return characterSkillsPath.appendingPathComponent("\(characterId)_loyalty_points.json")
    }

    // 保存忠诚点数据到本地文件
    private func saveLoyaltyPointsToCache(characterId: Int, points: [LoyaltyPoint]) -> Bool {
        do {
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(points)
            
            let filePath = getLoyaltyPointsCacheFilePath(characterId: characterId)
            try jsonData.write(to: filePath)
            
            Logger.debug("成功缓存忠诚点数据到文件 - 角色ID: \(characterId), 路径: \(filePath.path)")
            return true
        } catch {
            Logger.error("保存忠诚点数据到文件失败: \(error)")
            return false
        }
    }

    // 从本地文件读取忠诚点数据
    private func loadLoyaltyPointsFromCache(characterId: Int) -> [LoyaltyPoint]? {
        let filePath = getLoyaltyPointsCacheFilePath(characterId: characterId)
        
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
                    Logger.debug("忠诚点缓存已过期 - 角色ID: \(characterId)")
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
            let points = try decoder.decode([LoyaltyPoint].self, from: jsonData)
            
            Logger.debug("从文件缓存加载忠诚点数据 - 角色ID: \(characterId), 文件路径: \(filePath.path)")
            return points
        } catch {
            Logger.error("从文件读取忠诚点数据失败: \(error)")
            return nil
        }
    }

    public func fetchLoyaltyPoints(characterId: Int, forceRefresh: Bool = false) async throws
        -> [LoyaltyPoint]
    {
        // 如果不是强制刷新，先检查缓存
        if !forceRefresh {
            if let cachedPoints = loadLoyaltyPointsFromCache(characterId: characterId) {
                Logger.debug("使用缓存的忠诚点数据 - 角色ID: \(characterId)")
                return cachedPoints
            }
        }

        let urlString =
            "https://esi.evetech.net/characters/\(characterId)/loyalty/points/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId
        )

        let points = try JSONDecoder().decode([LoyaltyPoint].self, from: data)

        // 保存到本地文件
        if saveLoyaltyPointsToCache(characterId: characterId, points: points) {
            Logger.debug("成功缓存忠诚点数据到文件 - 角色ID: \(characterId)")
        }

        return points
    }
}
