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

// MARK: - 入侵API
@globalActor actor IncursionsAPIActor {
    static let shared = IncursionsAPIActor()
}

@IncursionsAPIActor
class IncursionsAPI {
    static let shared = IncursionsAPI()
    private let session: URLSession
    private let rateLimiter: RateLimiter
    private let retrier: RequestRetrier
    
    // 缓存
    private var incursionsCache: [Incursion] = []
    private var incursionsTimestamp: Date?
    private let incursionsCacheDuration: TimeInterval = StaticResourceManager.shared.INCURSIONS_CACHE_DURATION
    
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
    
    /// 获取入侵数据
    /// - Parameter forceRefresh: 是否强制刷新
    /// - Returns: 入侵数据数组
    func fetchIncursions(forceRefresh: Bool = false) async throws -> [Incursion] {
        // 如果不是强制刷新，检查缓存
        if !forceRefresh {
            if let incursions = StaticResourceManager.shared.getIncursions() {
                return incursions
            }
            
            if let timestamp = incursionsTimestamp,
               !incursionsCache.isEmpty,
               Date().timeIntervalSince(timestamp) < incursionsCacheDuration {
                return incursionsCache
            }
        }
        
        // 构建URL
        let baseURL = "https://esi.evetech.net/latest/incursions/"
        var components = URLComponents(string: baseURL)
        components?.queryItems = [
            URLQueryItem(name: "datasource", value: "tranquility")
        ]
        
        guard let url = components?.url else {
            throw IncursionsAPIError.invalidURL
        }
        
        // 执行请求
        let incursions = try await fetchData(from: url)
        
        // 更新缓存
        incursionsCache = incursions
        incursionsTimestamp = Date()
        
        // 保存到本地
        try StaticResourceManager.shared.saveIncursions(incursions)
        
        return incursions
    }
    
    /// 清除缓存
    func clearCache() {
        incursionsCache = []
        incursionsTimestamp = nil
    }
    
    // MARK: - 私有方法
    
    private func fetchData(from url: URL) async throws -> [Incursion] {
        // 等待速率限制
        try await rateLimiter.waitForPermission()
        
        return try await retrier.execute {
            let (data, response) = try await session.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw IncursionsAPIError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                throw IncursionsAPIError.httpError(httpResponse.statusCode)
            }
            
            do {
                return try JSONDecoder().decode([Incursion].self, from: data)
            } catch {
                throw IncursionsAPIError.decodingError(error)
            }
        }
    }
} 