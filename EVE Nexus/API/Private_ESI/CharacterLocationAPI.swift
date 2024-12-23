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
    private struct LocationCacheEntry: Codable {
        let value: CharacterLocation
        let timestamp: Date
    }
    
    // 内存缓存
    private var locationMemoryCache: [Int: LocationCacheEntry] = [:]
    private let cacheTimeout: TimeInterval = 60 // 1分钟缓存
    
    // UserDefaults键前缀
    private let locationCachePrefix = "location_cache_"
    
    private init() {}
    
    // 检查缓存是否有效
    private func isCacheValid(_ cache: LocationCacheEntry?) -> Bool {
        guard let cache = cache else { return false }
        return Date().timeIntervalSince(cache.timestamp) < cacheTimeout
    }
    
    // 从UserDefaults获取缓存
    private func getDiskCache(characterId: Int) -> LocationCacheEntry? {
        let key = locationCachePrefix + String(characterId)
        guard let data = UserDefaults.standard.data(forKey: key),
              let cache = try? JSONDecoder().decode(LocationCacheEntry.self, from: data) else {
            return nil
        }
        return cache
    }
    
    // 保存缓存到UserDefaults
    private func saveToDiskCache(characterId: Int, cache: LocationCacheEntry) {
        let key = locationCachePrefix + String(characterId)
        if let encoded = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
    
    // 清除缓存
    private func clearCache(characterId: Int) {
        // 清除内存缓存
        locationMemoryCache.removeValue(forKey: characterId)
        
        // 清除磁盘缓存
        let key = locationCachePrefix + String(characterId)
        UserDefaults.standard.removeObject(forKey: key)
    }
    
    // 获取角色位置信息
    func fetchCharacterLocation(characterId: Int, forceRefresh: Bool = false) async throws -> CharacterLocation {
        // 如果不是强制刷新，先尝试使用缓存
        if !forceRefresh {
            // 1. 先检查内存缓存
            if let memoryCached = locationMemoryCache[characterId],
               isCacheValid(memoryCached) {
                Logger.info("使用内存缓存的位置信息 - 角色ID: \(characterId)")
                return memoryCached.value
            }
            
            // 2. 如果内存缓存不可用，检查磁盘缓存
            if let diskCached = getDiskCache(characterId: characterId),
               isCacheValid(diskCached) {
                Logger.info("使用磁盘缓存的位置信息 - 角色ID: \(characterId)")
                // 更新内存缓存
                locationMemoryCache[characterId] = diskCached
                return diskCached.value
            }
            
            Logger.info("缓存未命中或已过期,需要从服务器获取位置信息 - 角色ID: \(characterId)")
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
            
            // 创建新的缓存条目
            let cacheEntry = LocationCacheEntry(value: location, timestamp: Date())
            
            // 更新内存缓存
            locationMemoryCache[characterId] = cacheEntry
            
            // 更新磁盘缓存
            saveToDiskCache(characterId: characterId, cache: cacheEntry)
            
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
