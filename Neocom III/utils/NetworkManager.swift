import Foundation
import SwiftUI

// 市场订单数据模型
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

class NetworkManager {
    static let shared = NetworkManager()
    
    // 市场订单缓存
    private var marketOrdersCache: [Int: [MarketOrder]] = [:]
    private var marketOrdersTimestamp: [Int: Date] = [:]
    private let cacheValidDuration: TimeInterval = 300 // 缓存有效期5分钟
    
    private init() {}
    
    // 通用的数据获取函数
    func fetchData(from url: URL) async throws -> Data {
        Logger.info("Fetching data from: \(url.absoluteString)")
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            Logger.error("Invalid response type received")
            throw NetworkError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            Logger.error("HTTP error: \(httpResponse.statusCode)")
            throw NetworkError.httpError(statusCode: httpResponse.statusCode)
        }
        
        Logger.info("Successfully fetched data from: \(url.absoluteString)")
        return data
    }
    
    // 专门用于获取图片的函数
    func fetchImage(from url: URL) async throws -> UIImage {
        Logger.info("Fetching image from: \(url.absoluteString)")
        let data = try await fetchData(from: url)
        
        guard let image = UIImage(data: data) else {
            Logger.error("Invalid image data received")
            throw NetworkError.invalidImageData
        }
        
        Logger.info("Successfully fetched image from: \(url.absoluteString)")
        return image
    }
    
    // 获取EVE物品渲染图
    func fetchEVEItemRender(typeID: Int) async throws -> UIImage {
        Logger.info("Fetching EVE item render for typeID: \(typeID)")
        let urlString = "https://images.evetech.net/types/\(typeID)/render"
        guard let url = URL(string: urlString) else {
            Logger.error("Invalid URL for typeID: \(typeID)")
            throw NetworkError.invalidURL
        }
        
        return try await fetchImage(from: url)
    }
    
    // 获取物品市场订单
    func fetchMarketOrders(typeID: Int, forceRefresh: Bool = false) async throws -> [MarketOrder] {
        Logger.info("Fetching market orders for typeID: \(typeID), forceRefresh: \(forceRefresh)")
        
        // 检查缓存是否有效
        if !forceRefresh,
           let timestamp = marketOrdersTimestamp[typeID],
           let cachedOrders = marketOrdersCache[typeID],
           Date().timeIntervalSince(timestamp) < cacheValidDuration {
            Logger.info("Using cached market orders for typeID: \(typeID)")
            return cachedOrders
        }
        
        let urlString = "https://esi.evetech.net/latest/markets/10000002/orders/?type_id=\(typeID)"
        guard let url = URL(string: urlString) else {
            Logger.error("Invalid URL for market orders, typeID: \(typeID)")
            throw NetworkError.invalidURL
        }
        
        let data = try await fetchData(from: url)
        let orders = try JSONDecoder().decode([MarketOrder].self, from: data)
        
        // 更新缓存
        marketOrdersCache[typeID] = orders
        marketOrdersTimestamp[typeID] = Date()
        Logger.info("Successfully fetched and cached \(orders.count) market orders for typeID: \(typeID)")
        
        return orders
    }
    
    // 获取物品最低售价
    func fetchLowestSellPrice(typeID: Int) async throws -> Double {
        let orders = try await fetchMarketOrders(typeID: typeID)
        
        // 筛选出售订单并找出最低价
        let sellOrders = orders.filter { !$0.isBuyOrder }
        guard let lowestPrice = sellOrders.map({ $0.price }).min() else {
            throw NetworkError.noValidPrice
        }
        
        return lowestPrice
    }
    
    // 清除缓存
    func clearMarketOrdersCache() {
        marketOrdersCache.removeAll()
        marketOrdersTimestamp.removeAll()
    }
}

// 网络错误枚举
enum NetworkError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case invalidImageData
    case noValidPrice
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的URL"
        case .invalidResponse:
            return "无效的响应"
        case .httpError(let statusCode):
            return "HTTP错误: \(statusCode)"
        case .invalidImageData:
            return "无效的图片数据"
        case .noValidPrice:
            return "没有有效的价格数据"
        }
    }
}