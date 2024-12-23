import Foundation

// 角色位置信息模型
struct CharacterLocation: Codable {
    let solar_system_id: Int
    let structure_id: Int?
    let station_id: Int?
    
    var locationStatus: LocationStatus {
        if station_id != nil {
            return .inStation
        } else if structure_id != nil {
            return .inStructure
        } else {
            return .inSpace
        }
    }
    
    enum LocationStatus: String, Codable {
        case inStation
        case inStructure
        case inSpace
        
        var description: String {
            switch self {
            case .inStation:
                return "(\(NSLocalizedString("Character_in_station", comment: "")))"
            case .inStructure:
                return "(\(NSLocalizedString("Character_in_structure", comment: "")))"
            case .inSpace:
                return "(\(NSLocalizedString("Character_in_space", comment: "")))"
            }
        }
    }
}

class CharacterLocationAPI {
    static let shared = CharacterLocationAPI()
    
    // 缓存结构
    private struct CacheEntry {
        let value: CharacterLocation
        let timestamp: Date
    }
    
    // 缓存字典
    private var locationCache: [Int: CacheEntry] = [:]
    private let cacheTimeout: TimeInterval = 60 // 1分钟缓存
    
    private init() {}
    
    // 检查缓存是否有效
    private func isCacheValid(_ cache: CacheEntry?) -> Bool {
        guard let cache = cache else { return false }
        return Date().timeIntervalSince(cache.timestamp) < cacheTimeout
    }
    
    // 获取角色位置信息
    func fetchCharacterLocation(characterId: Int, forceRefresh: Bool = false) async throws -> CharacterLocation {
        // 检查缓存
        if !forceRefresh,
           let cachedEntry = locationCache[characterId],
           isCacheValid(cachedEntry) {
            Logger.info("使用缓存的位置信息 - 角色ID: \(characterId)")
            return cachedEntry.value
        }
        
        let urlString = "https://esi.evetech.net/latest/characters/\(characterId)/location/"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        
        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId
        )
        
        do {
            let location = try JSONDecoder().decode(CharacterLocation.self, from: data)
            // 更新缓存
            locationCache[characterId] = CacheEntry(value: location, timestamp: Date())
            return location
        } catch {
            Logger.error("解析角色位置信息失败: \(error)")
            throw NetworkError.decodingError(error)
        }
    }
    
    // 获取角色完整位置信息（包含星系名称等）
    func fetchCharacterLocationInfo(characterId: Int, databaseManager: DatabaseManager, forceRefresh: Bool = false) async throws -> SolarSystemInfo? {
        let location = try await fetchCharacterLocation(characterId: characterId, forceRefresh: forceRefresh)
        return await getSolarSystemInfo(solarSystemId: location.solar_system_id, databaseManager: databaseManager)
    }
} 
