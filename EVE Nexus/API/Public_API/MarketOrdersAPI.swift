import Foundation
import SwiftUI

// MARK: - 数据模型
struct MarketOrder: Codable {
    let duration: Int
    let isBuyOrder: Bool
    let issued: String
    let locationId: Int64
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
    private let cacheDuration: TimeInterval = 3 * 60 * 60 // 3 小时缓存
    
    private init() {}
    
    private struct CachedData: Codable {
        let data: [MarketOrder]
        let timestamp: Date
    }
    
    // MARK: - 缓存方法
    private func getCacheDirectory() -> URL? {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let cacheDirectory = documentsDirectory.appendingPathComponent("MarketCache", isDirectory: true)
        
        // 确保缓存目录存在
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true, attributes: nil)
        
        return cacheDirectory
    }
    
    private func getCacheFilePath(typeID: Int, regionID: Int) -> URL? {
        guard let cacheDirectory = getCacheDirectory() else { return nil }
        return cacheDirectory.appendingPathComponent("market_orders_\(typeID)_\(regionID).json")
    }
    
    private func loadFromCache(typeID: Int, regionID: Int) -> [MarketOrder]? {
        guard let cacheFile = getCacheFilePath(typeID: typeID, regionID: regionID),
              let data = try? Data(contentsOf: cacheFile),
              let cached = try? JSONDecoder().decode(CachedData.self, from: data),
              cached.timestamp.addingTimeInterval(cacheDuration) > Date() else {
            return nil
        }
        
        Logger.info("使用缓存的市场订单数据")
        return cached.data
    }
    
    private func saveToCache(_ orders: [MarketOrder], typeID: Int, regionID: Int) {
        guard let cacheFile = getCacheFilePath(typeID: typeID, regionID: regionID) else { return }
        
        let cachedData = CachedData(data: orders, timestamp: Date())
        do {
            let encodedData = try JSONEncoder().encode(cachedData)
            try encodedData.write(to: cacheFile)
            Logger.info("市场订单数据已缓存到文件")
        } catch {
            Logger.error("保存市场订单缓存失败: \(error)")
        }
    }
    
    // MARK: - 公共方法
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
        saveToCache(orders, typeID: typeID, regionID: regionID)
        
        return orders
    }
} 
