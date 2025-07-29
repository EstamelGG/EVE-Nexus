import Foundation
import SwiftUI

// MARK: - 错误类型

enum IncursionsAPIError: LocalizedError {
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

// MARK: - 入侵API

@globalActor actor IncursionsAPIActor {
    static let shared = IncursionsAPIActor()
}

@IncursionsAPIActor
class IncursionsAPI {
    static let shared = IncursionsAPI()
    private init() {}

    // 缓存相关常量
    private let cacheKey = "incursions_data"
    private let cacheDuration: TimeInterval = 30 * 60  // 30 分钟缓存

    struct CachedData: Codable {
        let data: [Incursion]
        let timestamp: Date
    }

    // MARK: - 公共方法

    /// 获取入侵数据
    /// - Parameter forceRefresh: 是否强制刷新
    /// - Returns: 入侵数据数组
    func fetchIncursions(forceRefresh: Bool = false) async throws -> [Incursion] {
        // 如果不是强制刷新，尝试从缓存获取
        if !forceRefresh {
            if let cached = try? loadFromCache() {
                return cached
            }
        }

        // 构建URL
        let baseURL = "https://esi.evetech.net/incursions/"
        var components = URLComponents(string: baseURL)
        components?.queryItems = [
            URLQueryItem(name: "datasource", value: "tranquility")
        ]

        guard let url = components?.url else {
            throw IncursionsAPIError.invalidURL
        }

        // 执行请求
        let data = try await NetworkManager.shared.fetchData(from: url)
        let incursions = try JSONDecoder().decode([Incursion].self, from: data)

        // 保存到缓存
        try? saveToCache(incursions)

        return incursions
    }

    // MARK: - 私有方法

    private func loadFromCache() throws -> [Incursion]? {
        guard let cachedData = UserDefaults.standard.data(forKey: cacheKey),
            let cached = try? JSONDecoder().decode(CachedData.self, from: cachedData),
            cached.timestamp.addingTimeInterval(cacheDuration) > Date()
        else {
            return nil
        }

        Logger.info("使用缓存的入侵数据")
        return cached.data
    }

    private func saveToCache(_ incursions: [Incursion]) throws {
        let cachedData = CachedData(data: incursions, timestamp: Date())
        let encodedData = try JSONEncoder().encode(cachedData)
        Logger.info("正在缓存入侵数据, key: \(cacheKey), 数据大小: \(encodedData.count) bytes")
        UserDefaults.standard.set(encodedData, forKey: cacheKey)
    }
}
