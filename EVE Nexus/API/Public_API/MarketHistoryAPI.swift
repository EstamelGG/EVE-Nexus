import Foundation
import SwiftUI

// MARK: - 数据模型
struct MarketHistory: Codable {
    let average: Double
    let date: String
    let volume: Int
}

// MARK: - 错误类型
enum MarketHistoryAPIError: LocalizedError {
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

// MARK: - 市场历史API
@globalActor actor MarketHistoryAPIActor {
    static let shared = MarketHistoryAPIActor()
}

@MarketHistoryAPIActor
class MarketHistoryAPI {
    static let shared = MarketHistoryAPI()
    private let marketHistoryCacheDuration: TimeInterval = 7 * 24 * 3600 // 1周缓存
    
    private init() {}
    
    // MARK: - 公共方法
    
    /// 获取市场历史数据
    /// - Parameters:
    ///   - typeID: 物品类型ID
    ///   - regionID: 区域ID
    ///   - forceRefresh: 是否强制刷新
    /// - Returns: 市场历史数据数组
    func fetchMarketHistory(typeID: Int, regionID: Int, forceRefresh: Bool = false) async throws -> [MarketHistory] {
        // 如果不是强制刷新，尝试从缓存获取
        if !forceRefresh {
            let key = StaticResourceManager.DefaultsKey.marketHistory(typeID: typeID, regionID: regionID)
            if let cached: [MarketHistory] = StaticResourceManager.shared.getFromDefaults(key, duration: marketHistoryCacheDuration) {
                return cached
            }
        }
        
        // 构建URL
        let baseURL = "https://esi.evetech.net/latest/markets/\(regionID)/history/"
        var components = URLComponents(string: baseURL)
        components?.queryItems = [
            URLQueryItem(name: "datasource", value: "tranquility"),
            URLQueryItem(name: "type_id", value: String(typeID))
        ]
        
        guard let url = components?.url else {
            throw MarketHistoryAPIError.invalidURL
        }
        
        // 执行请求
        let data = try await NetworkManager.shared.fetchData(from: url)
        let history = try JSONDecoder().decode([MarketHistory].self, from: data)
        
        // 保存到 UserDefaults
        let key = StaticResourceManager.DefaultsKey.marketHistory(typeID: typeID, regionID: regionID)
        try StaticResourceManager.shared.saveToDefaults(history, key: key)
        
        return history
    }
} 