import Foundation

public struct Standing: Codable {
    public let from_id: Int
    public let from_type: String
    public let standing: Double
}

public class CharacterStandingsAPI {
    public static let shared = CharacterStandingsAPI()
    
    private let cacheDirectory: URL
    private let cacheTimeout: TimeInterval = 8 * 60 * 60 // 8小时
    
    private init() {
        // 创建缓存目录
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        cacheDirectory = documentsPath.appendingPathComponent("char_standings")
        
        // 确保目录存在
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    public func fetchStandings(characterId: Int, forceRefresh: Bool = false) async throws -> [Standing] {
        // 如果不是强制刷新，先检查缓存
        if !forceRefresh {
            if let cachedData = try loadFromCache(characterId: characterId) {
                return cachedData
            }
        }
        
        let urlString = "https://esi.evetech.net/characters/\(characterId)/standings/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        
        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId
        )
        
        let standings = try JSONDecoder().decode([Standing].self, from: data)
        
        // 保存到缓存
        try saveToCache(characterId: characterId, data: data)
        
        return standings
    }
    
    private func getCacheFileURL(characterId: Int) -> URL {
        return cacheDirectory.appendingPathComponent("\(characterId)_standings.json")
    }
    
    private func loadFromCache(characterId: Int) throws -> [Standing]? {
        let fileURL = getCacheFileURL(characterId: characterId)
        
        // 检查文件是否存在
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            Logger.info("缓存文件不存在 - 角色ID: \(characterId)")
            return nil
        }
        
        // 检查文件修改时间
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let modificationDate = attributes[.modificationDate] as? Date else {
            Logger.warning("无法获取缓存文件修改时间 - 角色ID: \(characterId)")
            return nil
        }
        
        let timeSinceModification = Date().timeIntervalSince(modificationDate)
        if timeSinceModification > cacheTimeout {
            Logger.info("缓存已过期 - 角色ID: \(characterId), 已过期: \(Int(timeSinceModification))秒")
            return nil
        }
        
        // 读取并解析缓存文件
        let data = try Data(contentsOf: fileURL)
        let standings = try JSONDecoder().decode([Standing].self, from: data)
        
        Logger.info("使用缓存的声望数据 - 角色ID: \(characterId), 记录数: \(standings.count), 缓存时间: \(Int(timeSinceModification))秒")
        return standings
    }
    
    private func saveToCache(characterId: Int, data: Data) throws {
        let fileURL = getCacheFileURL(characterId: characterId)
        
        try data.write(to: fileURL)
        
        Logger.info("声望数据已保存到缓存 - 角色ID: \(characterId), 文件: \(fileURL.lastPathComponent)")
    }
} 
