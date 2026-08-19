import Foundation

// MARK: - 错误类型

enum SovereigntyDataAPIError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case decodingError(Error)
    case httpError(Int)
    case rateLimitExceeded

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的URL"
        case let .networkError(error):
            return "网络错误: \(error.localizedDescription)"
        case .invalidResponse:
            return "无效的响应"
        case let .decodingError(error):
            return "数据解码错误: \(error.localizedDescription)"
        case let .httpError(code):
            return "HTTP错误: \(code)"
        case .rateLimitExceeded:
            return "超出请求限制"
        }
    }
}

// MARK: - 派系信息（universe/factions）

/// ESI universe/factions 返回的派系条目（仅取主权展示所需字段）
struct ESIFactionInfo: Codable {
    let faction_id: Int
    let corporation_id: Int?
    let militia_corporation_id: Int?
    let solar_system_id: Int?
    let name: String?
}

// MARK: - 主权数据API

@globalActor actor SovereigntyDataAPIActor {
    static let shared = SovereigntyDataAPIActor()
}

@SovereigntyDataAPIActor
class SovereigntyDataAPI {
    static let shared = SovereigntyDataAPI()

    private init() {}

    // 缓存相关常量
    private let cacheKey = "sovereignty_data"
    private let cacheDuration: TimeInterval = 3600 // 1小时缓存

    struct CachedData: Codable {
        let data: [SovereigntyData]
        let timestamp: Date
    }

    // MARK: - 公共方法

    /// 获取指定派系信息（universe/factions 全量接口 + 缓存，按 ID 过滤）
    func fetchFactionInfo(factionId: Int, forceRefresh: Bool = false) async throws -> ESIFactionInfo? {
        let factions = try await fetchAllFactions(forceRefresh: forceRefresh)
        return factions.first { $0.faction_id == factionId }
    }

    /// 获取主权数据
    /// - Parameter forceRefresh: 是否强制刷新
    /// - Returns: 主权数据数组
    func fetchSovereigntyData(forceRefresh: Bool = false) async throws -> [SovereigntyData] {
        // 如果不是强制刷新，尝试从本地获取
        if !forceRefresh {
            if let cached = try? loadFromCache() {
                return cached
            }
        }

        // 构建URL
        let baseURL = "https://esi.evetech.net/sovereignty/map/"
        var components = URLComponents(string: baseURL)
        components?.queryItems = [
            URLQueryItem(name: "datasource", value: "tranquility"),
        ]

        guard let url = components?.url else {
            throw SovereigntyDataAPIError.invalidURL
        }

        // 执行请求
        let data = try await NetworkManager.shared.fetchData(from: url)
        let sovereignty = try JSONDecoder().decode([SovereigntyData].self, from: data)

        // 保存到缓存
        try? saveToCache(sovereignty)

        return sovereignty
    }

    // MARK: - 私有方法

    /// 缓存的派系列表（派系数据极少变化）
    private struct CachedFactions: Codable {
        let data: [ESIFactionInfo]
        let timestamp: Date
    }

    private let factionsCacheKey = "universe_factions_data"
    private let factionsCacheDuration: TimeInterval = 86400 // 24 小时

    /// 拉取全部派系（带缓存）
    private func fetchAllFactions(forceRefresh: Bool) async throws -> [ESIFactionInfo] {
        if !forceRefresh, let cached = loadFactionsFromCache() {
            return cached
        }

        var components = URLComponents(string: "https://esi.evetech.net/universe/factions/")
        components?.queryItems = [
            URLQueryItem(name: "datasource", value: "tranquility"),
        ]

        guard let url = components?.url else {
            throw SovereigntyDataAPIError.invalidURL
        }

        let data = try await NetworkManager.shared.fetchData(from: url)
        let factions = try JSONDecoder().decode([ESIFactionInfo].self, from: data)
        saveFactionsToCache(factions)
        return factions
    }

    private func loadFactionsFromCache() -> [ESIFactionInfo]? {
        guard let cachedData = UserDefaults.standard.data(forKey: factionsCacheKey),
              let cached = try? JSONDecoder().decode(CachedFactions.self, from: cachedData),
              cached.timestamp.addingTimeInterval(factionsCacheDuration) > Date()
        else {
            return nil
        }

        Logger.info("使用缓存的派系数据")
        return cached.data
    }

    private func saveFactionsToCache(_ factions: [ESIFactionInfo]) {
        let cached = CachedFactions(data: factions, timestamp: Date())
        if let encoded = try? JSONEncoder().encode(cached) {
            UserDefaults.standard.set(encoded, forKey: factionsCacheKey)
        }
    }

    private func loadFromCache() throws -> [SovereigntyData]? {
        guard let cachedData = UserDefaults.standard.data(forKey: cacheKey),
              let cached = try? JSONDecoder().decode(CachedData.self, from: cachedData),
              cached.timestamp.addingTimeInterval(cacheDuration) > Date()
        else {
            return nil
        }

        Logger.info("使用缓存的主权数据")
        return cached.data
    }

    private func saveToCache(_ sovereignty: [SovereigntyData]) throws {
        let cachedData = CachedData(data: sovereignty, timestamp: Date())
        let encodedData = try JSONEncoder().encode(cachedData)
        Logger.info("正在缓存主权数据, key: \(cacheKey), 数据大小: \(encodedData.count) bytes")
        UserDefaults.standard.set(encodedData, forKey: cacheKey)
    }
}
