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
    private let defaults = CoreDataManager.shared
    private let cacheDuration: TimeInterval = 5 * 60 // 5分钟缓存
    
    private init() {}
    
    private struct CachedData: Codable {
        let data: [MarketOrder]
        let timestamp: Date
    }
    
    // MARK: - 公共方法
    
    /// 获取市场订单数据
    /// - Parameters:
    ///   - typeID: 物品ID
    ///   - regionID: 星域ID
    ///   - forceRefresh: 是否强制刷新
    /// - Returns: 市场订单数据数组
    func fetchMarketOrders(typeID: Int, regionID: Int, forceRefresh: Bool = false) async throws -> [MarketOrder] {
        // 如果不是强制刷新，尝试从缓存获取
        if !forceRefresh {
            if let cached = loadFromCache(typeID: typeID, regionID: regionID) {
                return cached
            }
        }
        
        // 构建URL
        let baseURL = "https://esi.evetech.net/latest/markets/\(regionID)/orders/"
        var components = URLComponents(string: baseURL)
        components?.queryItems = [
            URLQueryItem(name: "type_id", value: "\(typeID)"),
            URLQueryItem(name: "datasource", value: "tranquility")
        ]
        
        guard let url = components?.url else {
            throw MarketAPIError.invalidURL
        }
        
        // 执行请求
        let data = try await NetworkManager.shared.fetchData(from: url)
        let orders = try JSONDecoder().decode([MarketOrder].self, from: data)
        
        // 保存到缓存
        try? saveToCache(orders, typeID: typeID, regionID: regionID)
        
        return orders
    }
    
    // MARK: - 私有方法
    
    private func getCacheKey(typeID: Int, regionID: Int) -> String {
        return "market_orders_\(typeID)_\(regionID)"
    }
    
    private func loadFromCache(typeID: Int, regionID: Int) -> [MarketOrder]? {
        let key = getCacheKey(typeID: typeID, regionID: regionID)
        guard let data = defaults.data(forKey: key),
              let cached = try? JSONDecoder().decode(CachedData.self, from: data),
              cached.timestamp.addingTimeInterval(cacheDuration) > Date() else {
            return nil
        }
        
        Logger.info("使用缓存的市场订单数据")
        return cached.data
    }
    
    private func saveToCache(_ orders: [MarketOrder], typeID: Int, regionID: Int) throws {
        let key = getCacheKey(typeID: typeID, regionID: regionID)
        let cachedData = CachedData(data: orders, timestamp: Date())
        let encodedData = try JSONEncoder().encode(cachedData)
        defaults.set(encodedData, forKey: key)
        Logger.info("市场订单数据已缓存")
    }
} 
