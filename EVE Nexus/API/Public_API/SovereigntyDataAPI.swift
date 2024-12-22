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

// MARK: - 主权数据API
@globalActor actor SovereigntyDataAPIActor {
    static let shared = SovereigntyDataAPIActor()
}

@SovereigntyDataAPIActor
class SovereigntyDataAPI {
    static let shared = SovereigntyDataAPI()
    private let session: URLSession
    private let rateLimiter: RateLimiter
    private let retrier: RequestRetrier
    
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
    
    /// 获取主权数据
    /// - Parameter forceRefresh: 是否强制刷新
    /// - Returns: 主权数据数组
    func fetchSovereigntyData(forceRefresh: Bool = false) async throws -> [SovereigntyData] {
        // 如果不是强制刷新，尝试从本地获取
        if !forceRefresh {
            if let sovereignty = StaticResourceManager.shared.getSovereignty() {
                return sovereignty
            }
        }
        
        // 构建URL
        let baseURL = "https://esi.evetech.net/latest/sovereignty/map/"
        var components = URLComponents(string: baseURL)
        components?.queryItems = [
            URLQueryItem(name: "datasource", value: "tranquility")
        ]
        
        guard let url = components?.url else {
            throw SovereigntyDataAPIError.invalidURL
        }
        
        // 执行请求
        let data = try await fetchData(from: url)
        let sovereignty = try JSONDecoder().decode([SovereigntyData].self, from: data)
        
        // 保存到本地
        try StaticResourceManager.shared.saveSovereignty(sovereignty)
        
        return sovereignty
    }
    
    // MARK: - 私有方法
    
    private func fetchData(from url: URL) async throws -> Data {
        // 等待速率限制
        try await rateLimiter.waitForPermission()
        
        return try await retrier.execute {
            let (data, response) = try await session.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw SovereigntyDataAPIError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                throw SovereigntyDataAPIError.httpError(httpResponse.statusCode)
            }
            
            return data
        }
    }
} 