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
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        case .invalidResponse:
            return "无效的响应"
        case .decodingError(let error):
            return "数据解码错误: \(error.localizedDescription)"
        case .httpError(let code):
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
    private let session: URLSession
    private let rateLimiter: RateLimiter
    private let retrier: RequestRetrier
    
    // 缓存
    private var campaignsCache: [EVE_Nexus.SovereigntyCampaign] = []
    private var campaignsTimestamp: Date?
    private let campaignsCacheDuration: TimeInterval = StaticResourceManager.shared.SOVEREIGNTY_CAMPAIGNS_CACHE_DURATION
    
    private init() {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
        self.rateLimiter = RateLimiter()
        self.retrier = RequestRetrier()
    }
    
    // MARK: - 公共方法
    
    /// 获取主权战役数据
    /// - Parameter forceRefresh: 是否强制刷新
    /// - Returns: 主权战役数据数组
    func fetchSovereigntyCampaigns(forceRefresh: Bool = false) async throws -> [EVE_Nexus.SovereigntyCampaign] {
        // 如果不是强制刷新，检查缓存
        if !forceRefresh {
            if let campaigns = StaticResourceManager.shared.getSovereigntyCampaigns() {
                return campaigns
            }
            
            if let timestamp = campaignsTimestamp,
               !campaignsCache.isEmpty,
               Date().timeIntervalSince(timestamp) < campaignsCacheDuration {
                return campaignsCache
            }
        }
        
        // 构建URL
        let baseURL = "https://esi.evetech.net/latest/sovereignty/campaigns/"
        var components = URLComponents(string: baseURL)
        components?.queryItems = [
            URLQueryItem(name: "datasource", value: "tranquility")
        ]
        
        guard let url = components?.url else {
            throw SovereigntyCampaignsAPIError.invalidURL
        }
        
        // 执行请求
        let campaigns = try await fetchData(from: url)
        
        // 更新缓存
        campaignsCache = campaigns
        campaignsTimestamp = Date()
        
        // 保存到本地
        try StaticResourceManager.shared.saveSovereigntyCampaigns(campaigns)
        
        return campaigns
    }
    
    /// 清除缓存
    func clearCache() {
        campaignsCache = []
        campaignsTimestamp = nil
    }
    
    // MARK: - 私有方法
    
    private func fetchData(from url: URL) async throws -> [EVE_Nexus.SovereigntyCampaign] {
        // 等待速率限制
        try await rateLimiter.waitForPermission()
        
        return try await retrier.execute {
            let (data, response) = try await session.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw SovereigntyCampaignsAPIError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                throw SovereigntyCampaignsAPIError.httpError(httpResponse.statusCode)
            }
            
            do {
                return try JSONDecoder().decode([EVE_Nexus.SovereigntyCampaign].self, from: data)
            } catch {
                throw SovereigntyCampaignsAPIError.decodingError(error)
            }
        }
    }
} 