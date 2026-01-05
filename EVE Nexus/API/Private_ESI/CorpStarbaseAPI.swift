import Foundation

// 军团星堡信息模型
public struct StarbaseInfo: Codable {
    public let moon_id: Int?
    public let onlined_since: String?
    public let reinforced_until: String?
    public let starbase_id: Int
    public let state: String
    public let system_id: Int
    public let type_id: Int
    public let unanchor_at: String?
}

// 缓存数据结构
private struct StarbaseCacheData: Codable {
    let data: [StarbaseInfo]
    let timestamp: Date

    var isExpired: Bool {
        // 设置缓存有效期为1天
        return Date().timeIntervalSince(timestamp) > 24 * 3600
    }
}

@globalActor public actor CorpStarbaseActor {
    public static let shared = CorpStarbaseActor()
    private init() {}
}

@CorpStarbaseActor
public class CorpStarbaseAPI {
    public static let shared = CorpStarbaseAPI()

    private init() {}

    // MARK: - Public Methods

    public func fetchStarbases(characterId: Int, forceRefresh: Bool = false) async throws
        -> [StarbaseInfo]
    {
        // 1. 获取角色的军团ID
        guard
            let corporationId = try await CharacterDatabaseManager.shared.getCharacterCorporationId(
                characterId: characterId)
        else {
            throw NetworkError.authenticationError("无法获取军团ID")
        }

        // 2. 检查缓存
        if !forceRefresh, let cachedData = loadStarbasesFromCache(corporationId: corporationId) {
            Logger.info("使用缓存的星堡信息 - 军团ID: \(corporationId)")
            return cachedData
        }

        // 3. 从API获取
        return try await fetchStarbasesFromServer(
            corporationId: corporationId, characterId: characterId
        )
    }

    private func fetchStarbasesFromServer(corporationId: Int, characterId: Int) async throws
        -> [StarbaseInfo]
    {
        Logger.info("开始获取军团星堡信息 - 军团ID: \(corporationId)")

        let baseUrlString =
            "https://esi.evetech.net/corporations/\(corporationId)/starbases/?datasource=tranquility"
        guard let baseUrl = URL(string: baseUrlString) else {
            throw NetworkError.invalidURL
        }

        let allStarbases = try await NetworkManager.shared.fetchPaginatedData(
            from: baseUrl,
            characterId: characterId,
            maxConcurrentPages: 3,
            decoder: { try JSONDecoder().decode([StarbaseInfo].self, from: $0) },
            progressCallback: { currentPage, totalPages in
                Logger.debug("正在获取第 \(currentPage)/\(totalPages) 页军团星堡数据")
            }
        )

        // 保存到缓存
        saveStarbasesToCache(allStarbases, corporationId: corporationId)

        Logger.success("成功获取所有星堡信息 - 军团ID: \(corporationId), 总条数: \(allStarbases.count)")
        return allStarbases
    }

    // MARK: - Cache Methods

    private func getCacheDirectory() -> URL? {
        guard
            let documentsDirectory = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask
            ).first
        else {
            return nil
        }
        let cacheDirectory = documentsDirectory.appendingPathComponent(
            "CorpStarbase", isDirectory: true
        )

        // 确保缓存目录存在
        try? FileManager.default.createDirectory(
            at: cacheDirectory, withIntermediateDirectories: true, attributes: nil
        )

        return cacheDirectory
    }

    private func getCacheFilePath(corporationId: Int) -> URL? {
        guard let cacheDirectory = getCacheDirectory() else { return nil }
        return cacheDirectory.appendingPathComponent("corp_\(corporationId)_starbase.json")
    }

    private func loadStarbasesFromCache(corporationId: Int) -> [StarbaseInfo]? {
        guard let cacheFile = getCacheFilePath(corporationId: corporationId) else {
            Logger.error("获取缓存文件路径失败 - 军团ID: \(corporationId)")
            return nil
        }

        do {
            guard FileManager.default.fileExists(atPath: cacheFile.path) else {
                Logger.info("缓存文件不存在 - 军团ID: \(corporationId)")
                return nil
            }

            let data = try Data(contentsOf: cacheFile)
            let cached = try JSONDecoder().decode(StarbaseCacheData.self, from: data)

            if cached.isExpired {
                Logger.info("缓存已过期 - 军团ID: \(corporationId)")
                try? FileManager.default.removeItem(at: cacheFile)
                return nil
            }

            Logger.success("成功从缓存加载星堡信息 - 军团ID: \(corporationId)")
            return cached.data
        } catch {
            Logger.error("读取缓存文件失败 - 军团ID: \(corporationId), 错误: \(error)")
            try? FileManager.default.removeItem(at: cacheFile)
            return nil
        }
    }

    private func saveStarbasesToCache(_ starbases: [StarbaseInfo], corporationId: Int) {
        guard let cacheFile = getCacheFilePath(corporationId: corporationId) else {
            Logger.error("获取缓存文件路径失败 - 军团ID: \(corporationId)")
            return
        }

        do {
            let cachedData = StarbaseCacheData(data: starbases, timestamp: Date())
            let encodedData = try JSONEncoder().encode(cachedData)
            try encodedData.write(to: cacheFile)
            Logger.info("星堡信息已缓存到文件 - 军团ID: \(corporationId)")
        } catch {
            Logger.error("保存星堡信息缓存失败: \(error)")
            try? FileManager.default.removeItem(at: cacheFile)
        }
    }
}
