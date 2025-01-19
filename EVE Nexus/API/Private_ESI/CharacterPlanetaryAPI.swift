import Foundation

// MARK: - Data Models
struct CharacterPlanetaryInfo: Codable {
    let lastUpdate: String
    let numPins: Int
    let ownerId: Int
    let planetId: Int
    let planetType: String
    let solarSystemId: Int
    let upgradeLevel: Int
    
    enum CodingKeys: String, CodingKey {
        case lastUpdate = "last_update"
        case numPins = "num_pins"
        case ownerId = "owner_id"
        case planetId = "planet_id"
        case planetType = "planet_type"
        case solarSystemId = "solar_system_id"
        case upgradeLevel = "upgrade_level"
    }
}

class CharacterPlanetaryAPI {
    static func fetchCharacterPlanetary(characterId: Int) async throws -> [CharacterPlanetaryInfo] {
        let url = "https://esi.evetech.net/latest/characters/\(characterId)/planets/?datasource=tranquility"
        
        // 检查缓存
        if let cachedData = checkCache(characterId: characterId) {
            return cachedData
        }
        
        // 使用fetchWithToken发起请求
        let data = try await fetchWithToken(url: url)
        
        // 解析数据
        let planetaryInfo = try JSONDecoder().decode([CharacterPlanetaryInfo].self, from: data)
        
        // 缓存数据
        try? saveToCache(data: data, characterId: characterId)
        
        return planetaryInfo
    }
    
    // MARK: - Cache Management
    private static func checkCache(characterId: Int) -> [CharacterPlanetaryInfo]? {
        let fileManager = FileManager.default
        let cacheDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Planetary")
        
        let cacheFile = cacheDirectory.appendingPathComponent("\(characterId)_planetary.json")
        
        guard fileManager.fileExists(atPath: cacheFile.path) else {
            return nil
        }
        
        // 检查文件修改时间
        guard let attributes = try? fileManager.attributesOfItem(atPath: cacheFile.path),
              let modificationDate = attributes[.modificationDate] as? Date else {
            return nil
        }
        
        // 检查缓存是否过期（1天）
        if Date().timeIntervalSince(modificationDate) > 24 * 60 * 60 {
            try? fileManager.removeItem(at: cacheFile)
            return nil
        }
        
        // 读取缓存数据
        guard let data = try? Data(contentsOf: cacheFile),
              let planetaryInfo = try? JSONDecoder().decode([CharacterPlanetaryInfo].self, from: data) else {
            return nil
        }
        
        return planetaryInfo
    }
    
    private static func saveToCache(data: Data, characterId: Int) throws {
        let fileManager = FileManager.default
        let cacheDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Planetary")
        
        // 创建缓存目录（如果不存在）
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
        
        let cacheFile = cacheDirectory.appendingPathComponent("\(characterId)_planetary.json")
        try data.write(to: cacheFile)
    }
} 