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

struct PlanetaryDetail: Codable {
    let links: [PlanetaryLink]  // maxItems: 500
    let pins: [PlanetaryPin]  // maxItems: 100
    let routes: [PlanetaryRoute]  // maxItems: 1000

    enum CodingKeys: String, CodingKey {
        case links, pins, routes
    }
}

struct PlanetaryPin: Codable {
    let contentTypeId: Int?
    let contents: [PlanetaryContent]?  // maxItems: 90
    let expiryTime: String?
    let extractorDetails: PlanetaryExtractor?
    let factoryDetails: PlanetaryFactory?
    let installTime: String?
    let lastCycleStart: String?
    let latitude: Double
    let longitude: Double
    let pinId: Int64
    let schematicId: Int?
    let typeId: Int

    enum CodingKeys: String, CodingKey {
        case contentTypeId = "content_type_id"
        case contents
        case expiryTime = "expiry_time"
        case extractorDetails = "extractor_details"
        case factoryDetails = "factory_details"
        case installTime = "install_time"
        case lastCycleStart = "last_cycle_start"
        case latitude
        case longitude
        case pinId = "pin_id"
        case schematicId = "schematic_id"
        case typeId = "type_id"
    }
}

struct PlanetaryContent: Codable {
    let amount: Int64
    let typeId: Int

    enum CodingKeys: String, CodingKey {
        case amount
        case typeId = "type_id"
    }
}

struct PlanetaryExtractor: Codable {
    let heads: [PlanetaryHead]  // maxItems: 10
    let productTypeId: Int?
    let cycleTime: Int?  // in seconds
    let headRadius: Double?
    let qtyPerCycle: Int?

    enum CodingKeys: String, CodingKey {
        case heads
        case productTypeId = "product_type_id"
        case cycleTime = "cycle_time"
        case headRadius = "head_radius"
        case qtyPerCycle = "qty_per_cycle"
    }
}

struct PlanetaryHead: Codable {
    let headId: Int  // maximum: 9, minimum: 0
    let latitude: Double
    let longitude: Double

    enum CodingKeys: String, CodingKey {
        case headId = "head_id"
        case latitude
        case longitude
    }
}

struct PlanetaryFactory: Codable {
    let schematicId: Int

    enum CodingKeys: String, CodingKey {
        case schematicId = "schematic_id"
    }
}

struct PlanetaryRoute: Codable {
    let contentTypeId: Int
    let destinationPinId: Int64
    let quantity: Double
    let routeId: Int64
    let sourcePinId: Int64
    let waypoints: [Int64]?  // maxItems: 5

    enum CodingKeys: String, CodingKey {
        case contentTypeId = "content_type_id"
        case destinationPinId = "destination_pin_id"
        case quantity
        case routeId = "route_id"
        case sourcePinId = "source_pin_id"
        case waypoints
    }
}

class CharacterPlanetaryAPI {
    static func fetchCharacterPlanetary(characterId: Int, forceRefresh: Bool = false) async throws
        -> [CharacterPlanetaryInfo]
    {
        let urlString =
            "https://esi.evetech.net/characters/\(characterId)/planets/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw AssetError.invalidURL
        }
        // 检查缓存（除非强制刷新）
        if !forceRefresh, let cachedData = checkCache(characterId: characterId) {
            Logger.info("Fetch Planets from cache.")
            return cachedData
        }

        // 使用fetchWithToken发起请求
        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId
        )
        Logger.debug("Fetched from Netowrk.")
        // 解析数据
        let planetaryInfo = try JSONDecoder().decode([CharacterPlanetaryInfo].self, from: data)

        // 缓存数据
        try? saveToCache(data: data, characterId: characterId)

        return planetaryInfo
    }

    static func fetchPlanetaryDetail(characterId: Int, planetId: Int, forceRefresh: Bool = false)
        async throws -> PlanetaryDetail
    {
        let urlString =
            "https://esi.evetech.net/characters/\(characterId)/planets/\(planetId)/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw AssetError.invalidURL
        }

        // 检查缓存（除非强制刷新）
        if !forceRefresh,
            let cachedData = checkPlanetCache(characterId: characterId, planetId: planetId)
        {
            Logger.info("Fetch Planetary Detail from cache.")
            return cachedData
        }

        // 使用fetchWithToken发起请求
        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId
        )
        Logger.debug("Fetched from Netowrk.")
        // 解析数据
        let planetaryDetail = try JSONDecoder().decode(PlanetaryDetail.self, from: data)

        // 缓存数据
        try? saveToPlanetCache(data: data, characterId: characterId, planetId: planetId)
        Logger.debug("Save to cache.")
        return planetaryDetail
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
            let modificationDate = attributes[.modificationDate] as? Date
        else {
            return nil
        }

        // 检查缓存是否过期（1天）
        if Date().timeIntervalSince(modificationDate) > 24 * 60 * 60 {
            try? fileManager.removeItem(at: cacheFile)
            return nil
        }

        // 读取缓存数据
        guard let data = try? Data(contentsOf: cacheFile),
            let planetaryInfo = try? JSONDecoder().decode([CharacterPlanetaryInfo].self, from: data)
        else {
            return nil
        }
        Logger.info("[CharacterPlanetaryAPI] Read data from cache: \(cacheFile.path())")
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

    // MARK: - Planet Cache Management

    private static func checkPlanetCache(characterId: Int, planetId: Int) -> PlanetaryDetail? {
        let fileManager = FileManager.default
        let cacheDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Planetary")

        let cacheFile = cacheDirectory.appendingPathComponent(
            "character_\(characterId)_planet_\(planetId).json")

        guard fileManager.fileExists(atPath: cacheFile.path) else {
            return nil
        }

        // 检查文件修改时间
        guard let attributes = try? fileManager.attributesOfItem(atPath: cacheFile.path),
            let modificationDate = attributes[.modificationDate] as? Date
        else {
            return nil
        }

        // 检查缓存是否过期（1天）
        if Date().timeIntervalSince(modificationDate) > 24 * 60 * 60 {
            try? fileManager.removeItem(at: cacheFile)
            return nil
        }

        // 读取缓存数据
        guard let data = try? Data(contentsOf: cacheFile),
            let planetaryDetail = try? JSONDecoder().decode(PlanetaryDetail.self, from: data)
        else {
            return nil
        }

        return planetaryDetail
    }

    private static func saveToPlanetCache(data: Data, characterId: Int, planetId: Int) throws {
        let fileManager = FileManager.default
        let cacheDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Planetary")

        // 创建缓存目录（如果不存在）
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }

        let cacheFile = cacheDirectory.appendingPathComponent(
            "character_\(characterId)_planet_\(planetId).json")
        try data.write(to: cacheFile)
    }
}
