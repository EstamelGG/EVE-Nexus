import Foundation

// 月矿提取信息模型
public struct MoonExtractionInfo: Codable {
    public let chunk_arrival_time: String
    public let extraction_start_time: String
    public let moon_id: Int64
    public let natural_decay_time: String
    public let structure_id: Int64

    public init(
        chunk_arrival_time: String, extraction_start_time: String, moon_id: Int64,
        natural_decay_time: String, structure_id: Int64
    ) {
        self.chunk_arrival_time = chunk_arrival_time
        self.extraction_start_time = extraction_start_time
        self.moon_id = moon_id
        self.natural_decay_time = natural_decay_time
        self.structure_id = structure_id
    }
}

// ESI错误响应
private struct ESIErrorResponse: Codable {
    let error: String
}

// 缓存数据结构
private struct MoonExtractionCacheData: Codable {
    let data: [MoonExtractionInfo]
    let timestamp: Date

    var isExpired: Bool {
        // 设置缓存有效期为7天
        return Date().timeIntervalSince(timestamp) > 7 * 24 * 3600
    }
}

@globalActor public actor CorpMoonExtractionActor {
    public static let shared = CorpMoonExtractionActor()
    private init() {}
}

@CorpMoonExtractionActor
public class CorpMoonExtractionAPI {
    public static let shared = CorpMoonExtractionAPI()
    private let itemsPerPage = 50  // ESI API 通常每页返回50条数据

    private init() {}

    // MARK: - Public Methods

    public func fetchMoonExtractions(characterId: Int, forceRefresh: Bool = false) async throws
        -> [MoonExtractionInfo]
    {
        // 1. 获取角色的军团ID
        guard
            let corporationId = try await CharacterDatabaseManager.shared.getCharacterCorporationId(
                characterId: characterId)
        else {
            throw NetworkError.authenticationError("无法获取军团ID")
        }

        // 2. 检查缓存
        if !forceRefresh, let cachedData = loadExtractionsFromCache(corporationId: corporationId) {
            Logger.info("使用缓存的月矿提取信息 - 军团ID: \(corporationId)")
            return cachedData
        }

        // 3. 从API获取
        return try await fetchFromAPI(corporationId: corporationId, characterId: characterId)
    }

    private func fetchFromAPI(corporationId: Int, characterId: Int) async throws
        -> [MoonExtractionInfo]
    {
        var allExtractions: [MoonExtractionInfo] = []
        var currentPage = 1
        var hasMorePages = true

        Logger.info("开始获取军团月矿提取信息 - 军团ID: \(corporationId)")

        while hasMorePages {
            Logger.debug("正在获取第 \(currentPage) 页数据")

            let urlString =
                "https://esi.evetech.net/latest/corporation/\(corporationId)/mining/extractions/?datasource=tranquility&page=\(currentPage)"
            guard let url = URL(string: urlString) else {
                throw NetworkError.invalidURL
            }

            do {
                let headers = [
                    "Accept": "application/json",
                    "Content-Type": "application/json",
                ]

                let data = try await NetworkManager.shared.fetchDataWithToken(
                    from: url,
                    characterId: characterId,
                    headers: headers,
                    noRetryKeywords: ["Requested page does not exist"]
                )

                let extractions = try JSONDecoder().decode([MoonExtractionInfo].self, from: data)
                Logger.debug("成功获取第 \(currentPage) 页数据，共 \(extractions.count) 条记录")
                allExtractions.append(contentsOf: extractions)
                currentPage += 1

            } catch let error as NetworkError {
                if case let .httpError(_, message) = error,
                    message?.contains("Requested page does not exist") == true
                {
                    Logger.debug("第 \(currentPage) 页不存在，停止获取")
                    hasMorePages = false
                    break
                }
                Logger.error(
                    "获取月矿提取信息失败 - 军团ID: \(corporationId), 页码: \(currentPage), 错误: \(error)")
                throw error
            }
        }

        // 保存到缓存
        saveExtractionsToCache(allExtractions, corporationId: corporationId)

        Logger.info("成功获取所有月矿提取信息 - 军团ID: \(corporationId), 总条数: \(allExtractions.count)")
        return allExtractions
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
            "CorpMoon", isDirectory: true
        )

        // 确保缓存目录存在
        try? FileManager.default.createDirectory(
            at: cacheDirectory, withIntermediateDirectories: true, attributes: nil
        )

        return cacheDirectory
    }

    private func getCacheFilePath(corporationId: Int) -> URL? {
        guard let cacheDirectory = getCacheDirectory() else { return nil }
        return cacheDirectory.appendingPathComponent("Corp_\(corporationId)_moonextra.json")
    }

    private func loadExtractionsFromCache(corporationId: Int) -> [MoonExtractionInfo]? {
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
            let cached = try JSONDecoder().decode(MoonExtractionCacheData.self, from: data)

            if cached.isExpired {
                Logger.info("缓存已过期 - 军团ID: \(corporationId)")
                try? FileManager.default.removeItem(at: cacheFile)
                return nil
            }

            Logger.info("成功从缓存加载月矿提取信息 - 军团ID: \(corporationId)")
            return cached.data
        } catch {
            Logger.error("读取缓存文件失败 - 军团ID: \(corporationId), 错误: \(error)")
            try? FileManager.default.removeItem(at: cacheFile)
            return nil
        }
    }

    private func saveExtractionsToCache(_ extractions: [MoonExtractionInfo], corporationId: Int) {
        guard let cacheFile = getCacheFilePath(corporationId: corporationId) else {
            Logger.error("获取缓存文件路径失败 - 军团ID: \(corporationId)")
            return
        }

        do {
            let cachedData = MoonExtractionCacheData(data: extractions, timestamp: Date())
            let encodedData = try JSONEncoder().encode(cachedData)
            try encodedData.write(to: cacheFile)
            Logger.info("月矿提取信息已缓存到文件 - 军团ID: \(corporationId)")
        } catch {
            Logger.error("保存月矿提取信息缓存失败: \(error)")
            try? FileManager.default.removeItem(at: cacheFile)
        }
    }

    // MARK: - Helper Methods

    public func clearCache() {
        guard let cacheDirectory = getCacheDirectory() else { return }
        do {
            let fileManager = FileManager.default
            let cacheFiles = try fileManager.contentsOfDirectory(
                at: cacheDirectory, includingPropertiesForKeys: nil
            )
            for file in cacheFiles {
                try fileManager.removeItem(at: file)
            }
            Logger.info("月矿提取信息缓存已清除")
        } catch {
            Logger.error("清除月矿提取信息缓存失败: \(error)")
        }
    }
}
