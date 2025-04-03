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

// 角色在线状态模型
struct CharacterOnlineStatus: Codable {
    let online: Bool
}

// 当前飞船信息模型
struct CharacterShipInfo: Codable {
    let ship_item_id: Int64  // 飞船的item_id，用于查询装备
    let ship_name: String  // 飞船名称
    let ship_type_id: Int  // 飞船类型ID
}

class CharacterLocationAPI {
    static let shared = CharacterLocationAPI()

    // 缓存结构
    private struct LocationCacheEntry: Codable {
        let value: CharacterLocation
        let timestamp: Date
    }

    // 在线状态缓存结构
    private struct OnlineStatusCacheEntry: Codable {
        let value: CharacterOnlineStatus
        let timestamp: Date
    }

    // 添加并发队列用于同步访问
    private let cacheQueue = DispatchQueue(
        label: "com.eve-nexus.location-cache", attributes: .concurrent
    )

    // 内存缓存
    private var locationMemoryCache: [Int: LocationCacheEntry] = [:]
    private var onlineStatusMemoryCache: [Int: OnlineStatusCacheEntry] = [:]
    private let cacheTimeout: TimeInterval = 20 * 60  // 20 分钟缓存
    private let onlineStatusCacheTimeout: TimeInterval = 60  // 1 分钟缓存

    // UserDefaults键前缀
    private let locationCachePrefix = "location_cache_"
    private let onlineStatusCachePrefix = "online_status_cache_"

    private init() {}

    // 安全地获取位置缓存
    private func getLocationMemoryCache(characterId: Int) -> LocationCacheEntry? {
        var result: LocationCacheEntry?
        cacheQueue.sync {
            result = locationMemoryCache[characterId]
        }
        return result
    }

    // 安全地设置位置缓存
    private func setLocationMemoryCache(characterId: Int, cache: LocationCacheEntry) {
        cacheQueue.async(flags: .barrier) {
            self.locationMemoryCache[characterId] = cache
        }
    }

    // 检查缓存是否有效
    private func isCacheValid(_ cache: LocationCacheEntry?) -> Bool {
        guard let cache = cache else { return false }
        return Date().timeIntervalSince(cache.timestamp) < cacheTimeout
    }

    // 从UserDefaults获取缓存
    private func getDiskCache(characterId: Int) -> LocationCacheEntry? {
        let key = locationCachePrefix + String(characterId)
        Logger.debug("正在从 UserDefaults 读取键: \(key)")
        guard let data = UserDefaults.standard.data(forKey: key),
            let cache = try? JSONDecoder().decode(LocationCacheEntry.self, from: data)
        else {
            return nil
        }
        return cache
    }

    // 保存缓存到UserDefaults
    private func saveToDiskCache(characterId: Int, cache: LocationCacheEntry) {
        let key = locationCachePrefix + String(characterId)
        if let encoded = try? JSONEncoder().encode(cache) {
            Logger.debug("正在写入 UserDefaults，键: \(key), 数据大小: \(encoded.count) bytes")
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }

    // 获取角色位置信息
    func fetchCharacterLocation(characterId: Int, forceRefresh: Bool = false) async throws
        -> CharacterLocation
    {
        // 如果不是强制刷新，先尝试使用缓存
        if !forceRefresh {
            // 1. 先检查内存缓存
            if let memoryCached = getLocationMemoryCache(characterId: characterId),
                isCacheValid(memoryCached)
            {
                Logger.info("使用内存缓存的位置信息 - 角色ID: \(characterId)")
                return memoryCached.value
            }

            // 2. 如果内存缓存不可用，检查磁盘缓存
            if let diskCached = getDiskCache(characterId: characterId),
                isCacheValid(diskCached)
            {
                Logger.info("使用磁盘缓存的位置信息 - 角色ID: \(characterId)")
                // 更新内存缓存
                setLocationMemoryCache(characterId: characterId, cache: diskCached)
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
            setLocationMemoryCache(characterId: characterId, cache: cacheEntry)

            // 更新磁盘缓存
            saveToDiskCache(characterId: characterId, cache: cacheEntry)
            Logger.debug("Location: \(location)")
            return location
        } catch {
            Logger.error("解析角色位置信息失败: \(error)")
            throw NetworkError.decodingError(error)
        }
    }

    // 获取角色在线状态
    func fetchCharacterOnlineStatus(characterId: Int, forceRefresh: Bool = false) async throws
        -> CharacterOnlineStatus
    {
        // 如果不是强制刷新，先尝试使用缓存
        if !forceRefresh {
            // 1. 先检查内存缓存
            if let memoryCached = getOnlineStatusMemoryCache(characterId: characterId),
                isCacheValid(memoryCached, timeout: onlineStatusCacheTimeout)
            {
                Logger.info("使用内存缓存的在线状态 - 角色ID: \(characterId)")
                return memoryCached.value
            }

            // 2. 如果内存缓存不可用，检查磁盘缓存
            if let diskCached = getOnlineStatusDiskCache(characterId: characterId),
                isCacheValid(diskCached, timeout: onlineStatusCacheTimeout)
            {
                Logger.info("使用磁盘缓存的在线状态 - 角色ID: \(characterId)")
                // 更新内存缓存
                setOnlineStatusMemoryCache(characterId: characterId, cache: diskCached)
                return diskCached.value
            }

            Logger.info("缓存未命中或已过期,需要从服务器获取在线状态 - 角色ID: \(characterId)")
        }

        let urlString = "https://esi.evetech.net/latest/characters/\(characterId)/online/"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId
        )

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let onlineStatus = try decoder.decode(CharacterOnlineStatus.self, from: data)

            // 创建新的缓存条目
            let cacheEntry = OnlineStatusCacheEntry(value: onlineStatus, timestamp: Date())

            // 更新内存缓存
            setOnlineStatusMemoryCache(characterId: characterId, cache: cacheEntry)

            // 更新磁盘缓存
            saveOnlineStatusToDiskCache(characterId: characterId, cache: cacheEntry)

            return onlineStatus
        } catch {
            Logger.error("解析角色在线状态失败: \(error)")
            throw NetworkError.decodingError(error)
        }
    }

    // 检查缓存是否有效（带超时参数）
    private func isCacheValid(_ cache: OnlineStatusCacheEntry?, timeout: TimeInterval) -> Bool {
        guard let cache = cache else { return false }
        return Date().timeIntervalSince(cache.timestamp) < timeout
    }

    // 安全地获取在线状态缓存
    private func getOnlineStatusMemoryCache(characterId: Int) -> OnlineStatusCacheEntry? {
        var result: OnlineStatusCacheEntry?
        cacheQueue.sync {
            result = onlineStatusMemoryCache[characterId]
        }
        return result
    }

    // 安全地设置在线状态缓存
    private func setOnlineStatusMemoryCache(characterId: Int, cache: OnlineStatusCacheEntry) {
        cacheQueue.async(flags: .barrier) {
            self.onlineStatusMemoryCache[characterId] = cache
        }
    }

    // 从UserDefaults获取在线状态缓存
    private func getOnlineStatusDiskCache(characterId: Int) -> OnlineStatusCacheEntry? {
        let key = onlineStatusCachePrefix + String(characterId)
        Logger.debug("正在从 UserDefaults 读取在线状态键: \(key)")
        guard let data = UserDefaults.standard.data(forKey: key),
            let cache = try? JSONDecoder().decode(OnlineStatusCacheEntry.self, from: data)
        else {
            return nil
        }
        return cache
    }

    // 保存在线状态缓存到UserDefaults
    private func saveOnlineStatusToDiskCache(characterId: Int, cache: OnlineStatusCacheEntry) {
        let key = onlineStatusCachePrefix + String(characterId)
        if let encoded = try? JSONEncoder().encode(cache) {
            Logger.debug("正在写入在线状态到 UserDefaults，键: \(key), 数据大小: \(encoded.count) bytes")
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }

    // 获取当前飞船信息
    func fetchCharacterShip(characterId: Int) async throws -> CharacterShipInfo {
        let urlString = "https://esi.evetech.net/latest/characters/\(characterId)/ship/"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId
        )

        do {
            let decoder = JSONDecoder()
            let shipInfo = try decoder.decode(CharacterShipInfo.self, from: data)
            return shipInfo
        } catch {
            Logger.error("解析角色飞船信息失败: \(error)")
            throw NetworkError.decodingError(error)
        }
    }
}
