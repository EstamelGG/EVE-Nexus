import Foundation
import SwiftUI

// MARK: - 数据模型
struct MarketOrder: Codable {
    let duration: Int
    let isBuyOrder: Bool
    let issued: String
    let locationId: Int
    let minVolume: Int
    let orderId: Int
    let price: Double
    let range: String
    let systemId: Int
    let typeId: Int
    let volumeRemain: Int
    let volumeTotal: Int
    
    enum CodingKeys: String, CodingKey {
        case duration
        case isBuyOrder = "is_buy_order"
        case issued
        case locationId = "location_id"
        case minVolume = "min_volume"
        case orderId = "order_id"
        case price
        case range
        case systemId = "system_id"
        case typeId = "type_id"
        case volumeRemain = "volume_remain"
        case volumeTotal = "volume_total"
    }
}

// MARK: - 错误类型
enum MarketAPIError: LocalizedError {
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

// MARK: - 市场API
@globalActor actor MarketOrdersAPIActor {
    static let shared = MarketOrdersAPIActor()
}

@MarketOrdersAPIActor
class MarketOrdersAPI {
    static let shared = MarketOrdersAPI()
    
    // 缓存
    private var marketOrdersCache: [Int: [MarketOrder]] = [:]
    private var marketOrdersTimestamp: [Int: Date] = [:]
    private let marketOrdersCacheDuration: TimeInterval = 300 // 5分钟缓存
    
    private init() {}
    
    // MARK: - 公共方法
    
    /// 获取市场订单
    /// - Parameters:
    ///   - typeID: 物品类型ID
    ///   - regionID: 区域ID
    ///   - forceRefresh: 是否强制刷新
    /// - Returns: 市场订单数组
    func fetchMarketOrders(typeID: Int, regionID: Int, forceRefresh: Bool = false) async throws -> [MarketOrder] {
        // 检查缓存
        if !forceRefresh {
            if let cached = marketOrdersCache[typeID],
               let timestamp = marketOrdersTimestamp[typeID],
               Date().timeIntervalSince(timestamp) < marketOrdersCacheDuration {
                return cached
            }
        }
        
        // 构建URL
        let baseURL = "https://esi.evetech.net/latest/markets/\(regionID)/orders/"
        var components = URLComponents(string: baseURL)
        components?.queryItems = [
            URLQueryItem(name: "datasource", value: "tranquility"),
            URLQueryItem(name: "type_id", value: String(typeID))
        ]
        
        guard let url = components?.url else {
            throw MarketAPIError.invalidURL
        }
        
        // 执行请求
        let data = try await NetworkManager.shared.fetchData(from: url)
        let orders = try JSONDecoder().decode([MarketOrder].self, from: data)
        
        // 更新缓存
        marketOrdersCache[typeID] = orders
        marketOrdersTimestamp[typeID] = Date()
        
        return orders
    }
    
    /// 清除缓存
    func clearCache() {
        marketOrdersCache.removeAll()
        marketOrdersTimestamp.removeAll()
    }
} 