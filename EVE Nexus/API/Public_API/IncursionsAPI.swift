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
    private init() {}
    
    // MARK: - 公共方法
    
    /// 获取入侵数据
    /// - Parameter forceRefresh: 是否强制刷新
    /// - Returns: 入侵数据数组
    func fetchIncursions(forceRefresh: Bool = false) async throws -> [Incursion] {
        // 如果不是强制刷新，尝试从缓存获取
        if !forceRefresh, let cached = StaticResourceManager.shared.getIncursions() {
            return cached
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
        let data = try await NetworkManager.shared.fetchData(from: url)
        let incursions = try JSONDecoder().decode([Incursion].self, from: data)
        
        // 保存到本地
        try StaticResourceManager.shared.saveIncursions(incursions)
        
        return incursions
    }
} 