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

// 市场历史数据模型
struct MarketHistory: Codable {
    let average: Double
    let date: String
    let volume: Int
}

// 主权数据模型
struct SovereigntyData: Codable {
    let systemId: Int
    let allianceId: Int?
    let corporationId: Int?
    
    enum CodingKeys: String, CodingKey {
        case systemId = "system_id"
        case allianceId = "alliance_id"
        case corporationId = "corporation_id"
    }
}

class NetworkManager {
    static let shared = NetworkManager()
    private var regionID: Int = 10000002 // 默认为 The Forge
    
    func setRegionID(_ id: Int) {
        regionID = id
    }
    
    // 市场订单缓存
    private var marketOrdersCache: [Int: [MarketOrder]] = [:]
    private var marketOrdersTimestamp: [Int: Date] = [:]
    private let cacheValidDuration: TimeInterval = 300 // 缓存有效期5分钟
    
    // 市场历史数据缓存
    private var marketHistoryCache: [Int: [MarketHistory]] = [:]
    private var marketHistoryTimestamp: [Int: Date] = [:]
    
    private let sovereigntyCache = NSCache<NSString, CachedSovereigntyData>()
    
    // 缓存包装类
    class CachedSovereigntyData {
        let data: [SovereigntyData]
        let timestamp: Date
        
        init(data: [SovereigntyData], timestamp: Date) {
            self.data = data
            self.timestamp = timestamp
        }
    }
    
    private init() {}
    
    // 通用的数据获取函数
    func fetchData(from url: URL) async throws -> Data {
        Logger.info("Fetching data from URL: \(url.absoluteString)")
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            Logger.error("Invalid response type received")
            throw NetworkError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            Logger.error("HTTP error: \(url.absoluteString) [\(httpResponse.statusCode)]")
            throw NetworkError.httpError(statusCode: httpResponse.statusCode)
        }
        
        Logger.info("Successfully fetched data from: \(url.absoluteString)")
        return data
    }
    
    // 专门用于获取图片的函数
    func fetchImage(from url: URL) async throws -> UIImage {
        let data = try await fetchData(from: url)
        
        guard let image = UIImage(data: data) else {
            Logger.error("Invalid image data received")
            throw NetworkError.invalidImageData
        }
        
        return image
    }
    
    // 获取EVE物品渲染图
    func fetchEVEItemRender(typeID: Int) async throws -> UIImage {
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
        
        let urlString = "https://esi.evetech.net/latest/markets/\(regionID)/orders/?type_id=\(typeID)"
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
    
    // 获取市场历史数据
    func fetchMarketHistory(typeID: Int, forceRefresh: Bool = false) async throws -> [MarketHistory] {
        Logger.info("Fetching market history for typeID: \(typeID), forceRefresh: \(forceRefresh)")
        
        // 检查缓存是否有效
        if !forceRefresh,
           let timestamp = marketHistoryTimestamp[typeID],
           let cachedHistory = marketHistoryCache[typeID],
           Date().timeIntervalSince(timestamp) < cacheValidDuration {
            Logger.info("Using cached market history for typeID: \(typeID)")
            return cachedHistory
        }
        
        let urlString = "https://esi.evetech.net/latest/markets/\(regionID)/history/?type_id=\(typeID)"
        guard let url = URL(string: urlString) else {
            Logger.error("Invalid URL for market history, typeID: \(typeID)")
            throw NetworkError.invalidURL
        }
        
        let data = try await fetchData(from: url)
        var history = try JSONDecoder().decode([MarketHistory].self, from: data)
        
        // 只保留最近一年的数据
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        let calendar = Calendar.current
        let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: Date())
        
        history = history.filter { historyItem in
            guard let itemDate = dateFormatter.date(from: historyItem.date),
                  let oneYearAgo = oneYearAgo else { return false }
            return itemDate >= oneYearAgo
        }
        
        // 按日期排序
        history.sort { $0.date < $1.date }
        
        // 更新缓存
        marketHistoryCache[typeID] = history
        marketHistoryTimestamp[typeID] = Date()
        Logger.info("Successfully fetched and cached \(history.count) market history records for typeID: \(typeID)")
        
        return history
    }
    
    // 获取入侵数据
    func fetchIncursions() async throws -> [Incursion] {
        let urlString = "https://esi.evetech.net/latest/incursions/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            Logger.error("Invalid URL for incursions")
            throw NetworkError.invalidURL
        }
        
        let data = try await fetchData(from: url)
        return try JSONDecoder().decode([Incursion].self, from: data)
    }
    
    // 清除缓存
    func clearMarketOrdersCache() {
        marketOrdersCache.removeAll()
        marketOrdersTimestamp.removeAll()
    }
    
    // 清除所有缓存
    func clearAllCaches() {
        clearMarketOrdersCache()
        marketHistoryCache.removeAll()
        marketHistoryTimestamp.removeAll()
    }
    
    // 获取主权数据
    func fetchSovereigntyData() async {
        let cacheKey = "sovereigntyData" as NSString
        let cacheValidDuration: TimeInterval = 24 * 60 * 60 // 24小时
        
        // 检查缓存
        if let cachedData = sovereigntyCache.object(forKey: cacheKey),
           Date().timeIntervalSince(cachedData.timestamp) < cacheValidDuration {
            Logger.info("Using cached sovereignty data")
            return
        }
        
        let urlString = "https://esi.evetech.net/latest/sovereignty/map/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            Logger.error("Invalid URL for sovereignty data")
            return
        }
        
        do {
            let data = try await fetchData(from: url)
            let sovereigntyData = try JSONDecoder().decode([SovereigntyData].self, from: data)
            
            // 更新缓存
            let cachedData = CachedSovereigntyData(data: sovereigntyData, timestamp: Date())
            sovereigntyCache.setObject(cachedData, forKey: cacheKey)
            Logger.info("Successfully fetched and cached sovereignty data")
        } catch {
            Logger.error("Error fetching sovereignty data: \(error)")
        }
    }
    
    // 获取缓存的主权数据
    func getCachedSovereigntyData() -> [SovereigntyData]? {
        let cacheKey = "sovereigntyData" as NSString
        return sovereigntyCache.object(forKey: cacheKey)?.data
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
