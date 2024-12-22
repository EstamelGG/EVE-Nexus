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
    private init() {}
    
    // MARK: - 公共方法
    
    /// 获取主权战役数据
    /// - Parameter forceRefresh: 是否强制刷新
    /// - Returns: 主权战役数据数组
    func fetchSovereigntyCampaigns(forceRefresh: Bool = false) async throws -> [EVE_Nexus.SovereigntyCampaign] {
        // 如果不是强制刷新，尝试从缓存获取
        if !forceRefresh, let cached = StaticResourceManager.shared.getSovereigntyCampaigns() {
            return cached
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
        let data = try await NetworkManager.shared.fetchData(from: url)
        let campaigns = try JSONDecoder().decode([EVE_Nexus.SovereigntyCampaign].self, from: data)
        
        // 保存到本地
        try StaticResourceManager.shared.saveSovereigntyCampaigns(campaigns)
        
        return campaigns
    }
} 