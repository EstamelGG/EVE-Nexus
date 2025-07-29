import Foundation
import SwiftUI

// MARK: - 错误类型

enum SovereigntyCampaignsAPIError: LocalizedError {
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

// MARK: - 主权战役API

@globalActor actor SovereigntyCampaignsAPIActor {
    static let shared = SovereigntyCampaignsAPIActor()
}

@SovereigntyCampaignsAPIActor
class SovereigntyCampaignsAPI {
    static let shared = SovereigntyCampaignsAPI()
    private init() {}

    // 缓存相关常量
    private let cacheKey = "sovereignty_campaigns_data"
    private let cacheDuration: TimeInterval = 3600 * 8  // 8小时缓存

    struct CachedData: Codable {
        let data: [SovereigntyCampaign]
        let timestamp: Date
    }

    // MARK: - 公共方法

    /// 获取主权战役数据
    /// - Parameter forceRefresh: 是否强制刷新
    /// - Returns: 主权战役数据数组
    func fetchSovereigntyCampaigns(forceRefresh: Bool = false) async throws -> [EVE_Nexus
        .SovereigntyCampaign]
    {
        // 如果不是强制刷新，尝试从缓存获取
        if !forceRefresh {
            if let cached = try? loadFromCache() {
                return cached
            }
        }

        // 构建URL
        let baseURL = "https://esi.evetech.net/sovereignty/campaigns/"
        var components = URLComponents(string: baseURL)
        components?.queryItems = [
            URLQueryItem(name: "datasource", value: "tranquility")
        ]

        guard let url = components?.url else {
            throw SovereigntyCampaignsAPIError.invalidURL
        }

        // 执行请求
        let data = try await NetworkManager.shared.fetchData(from: url)
        let campaigns = try JSONDecoder().decode([EVE_Nexus.SovereigntyCampaign].self, from: data)

        // 保存到缓存
        try? saveToCache(campaigns)

        return campaigns
    }

    // MARK: - 私有方法

    private func loadFromCache() throws -> [SovereigntyCampaign]? {
        guard let cachedData = UserDefaults.standard.data(forKey: cacheKey),
            let cached = try? JSONDecoder().decode(CachedData.self, from: cachedData),
            cached.timestamp.addingTimeInterval(cacheDuration) > Date()
        else {
            return nil
        }

        Logger.info("使用缓存的主权战役数据")
        return cached.data
    }

    private func saveToCache(_ campaigns: [SovereigntyCampaign]) throws {
        let cachedData = CachedData(data: campaigns, timestamp: Date())
        let encodedData = try JSONEncoder().encode(cachedData)
        Logger.info("正在缓存主权战争数据, key: \(cacheKey), 数据大小: \(encodedData.count) bytes")
        UserDefaults.standard.set(encodedData, forKey: cacheKey)
    }
}
