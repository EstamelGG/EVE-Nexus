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
    let factionId: Int?
    
    enum CodingKeys: String, CodingKey {
        case systemId = "system_id"
        case allianceId = "alliance_id"
        case corporationId = "corporation_id"
        case factionId = "faction_id"
    }
}

// 服务器状态数据模型
struct ServerStatus: Codable {
    let players: Int
    let serverVersion: String
    let startTime: String
    let error: String?
    let timeout: Int?
    
    enum CodingKeys: String, CodingKey {
        case players
        case serverVersion = "server_version"
        case startTime = "start_time"
        case error
        case timeout
    }
    
    var isOnline: Bool {
        return error == nil
    }
}

// 修改缓存包装类为泛型
class CachedData<T> {
    let data: T
    let timestamp: Date
    
    init(data: T, timestamp: Date) {
        self.data = data
        self.timestamp = timestamp
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
    private let cacheValidDuration: TimeInterval = 300 // 市场缓存有效期5分钟
    
    // 市场历史数据缓存
    private var marketHistoryCache: [Int: [MarketHistory]] = [:]
    private var marketHistoryTimestamp: [Int: Date] = [:]
    
    private let sovereigntyCache = NSCache<NSString, CachedData<Any>>()
    private let allianceLogoCache = NSCache<NSString, CachedAllianceLogo>()
    
    // 联盟图标缓存包装类
    class CachedAllianceLogo {
        let image: UIImage
        let timestamp: Date
        
        init(image: UIImage, timestamp: Date) {
            self.image = image
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
        let incursions = try JSONDecoder().decode([Incursion].self, from: data)
        Logger.info("Successfully fetched incursions data")
        
        return incursions
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
        sovereigntyCache.removeAllObjects()
        allianceLogoCache.removeAllObjects()
        Logger.info("Cleared all NetworkManager caches")
    }
    
    // 获取主权数据
    func fetchSovereigntyData(forceRefresh: Bool = false) async throws -> [SovereigntyData] {
        let cacheKey = "sovereignty_data" as NSString
        
        // 检查缓存
        if !forceRefresh, let cached = sovereigntyCache.object(forKey: cacheKey) {
            // 检查缓存是否过期（1小时有效期）
            if Date().timeIntervalSince(cached.timestamp) < 3600 {
                Logger.info("Using cached sovereignty data")
                return cached.data as! [SovereigntyData]
            }
        }
        
        let urlString = "https://esi.evetech.net/latest/sovereignty/map/"
        guard let url = URL(string: urlString) else {
            Logger.error("Invalid URL for sovereignty data")
            throw NetworkError.invalidURL
        }
        
        // 如果强制刷新，清除 URLCache 中的缓存
        if forceRefresh {
            URLCache.shared.removeCachedResponse(for: URLRequest(url: url))
        }
        
        let data = try await fetchData(from: url)
        let sovereigntyData = try JSONDecoder().decode([SovereigntyData].self, from: data)
        
        // 更新缓存
        sovereigntyCache.setObject(
            CachedData(data: sovereigntyData, timestamp: Date()),
            forKey: cacheKey
        )
        
        Logger.info("Successfully fetched sovereignty data")
        return sovereigntyData
    }
    
    // 获取缓存的主权数据
    func getCachedSovereigntyData() -> [SovereigntyData]? {
        let cacheKey = "sovereigntyData" as NSString
        guard let cachedData = sovereigntyCache.object(forKey: cacheKey),
              Date().timeIntervalSince(cachedData.timestamp) < 24 * 60 * 60 else {
            return nil
        }
        return cachedData.data as? [SovereigntyData]
    }
    
    // 获取联盟图标
    /// - Parameter allianceId: 联盟ID
    /// - Returns: 联盟图标
    func fetchAllianceLogo(allianceId: Int) async throws -> UIImage {
        // 1. 先尝试从静态资源目录获取
        if let cachedData = StaticResourceManager.shared.getAllianceIcon(allianceId: allianceId),
           let cachedImage = UIImage(data: cachedData) {
            Logger.debug("Got alliance logo from cache: \(allianceId)")
            return cachedImage
        }
        
        // 2. 从网络获取
        let urlString = "https://images.evetech.net/alliances/\(allianceId)/logo?size=128"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NetworkError.invalidResponse
        }
        
        guard let image = UIImage(data: data) else {
            throw NetworkError.invalidData
        }
        
        // 3. 保存到静态资源目录
        try StaticResourceManager.shared.saveAllianceIcon(data, allianceId: allianceId)
        Logger.debug("Got alliance logo from url: \(url) and save to cache.")
        return image
    }
    
    // 获取服务器状态
    func fetchServerStatus() async throws -> ServerStatus {
        let urlString = "https://esi.evetech.net/latest/status/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            Logger.error("Invalid URL for server status")
            throw NetworkError.invalidURL
        }
        
        let data = try await fetchData(from: url)
        let status = try JSONDecoder().decode(ServerStatus.self, from: data)
        Logger.info("Successfully fetched server status")
        
        return status
    }
    
    // 添加主权争夺缓存相关方法
    func fetchSovereigntyCampaigns(forceRefresh: Bool = false) async throws -> [SovereigntyCampaign] {
        let cacheKey = "sovereignty_campaigns" as NSString
        
        // 检查缓存
        if !forceRefresh, let cached = sovereigntyCache.object(forKey: cacheKey) {
            // 检查缓存是否过期（2小时有效期）
            if Date().timeIntervalSince(cached.timestamp) < StaticResourceManager.shared.SOVEREIGNTY_CAMPAIGNS_CACHE_DURATION {
                Logger.info("使用缓存的主权争夺数据")
                if let campaigns = cached.data as? [SovereigntyCampaign] {
                    return campaigns
                }
            }
        }
        
        // 如果没有强制刷新，尝试从本地文件加载
        if !forceRefresh {
            let filePath = StaticResourceManager.shared.getStaticDataSetPath()
                .appendingPathComponent(StaticResourceManager.ResourceType.sovereigntyCampaigns.filename)
            
            if FileManager.default.fileExists(atPath: filePath.path) {
                do {
                    let data = try Data(contentsOf: filePath)
                    let campaigns = try JSONDecoder().decode([SovereigntyCampaign].self, from: data)
                    
                    // 检查文件是否过期
                    if let attributes = try? FileManager.default.attributesOfItem(atPath: filePath.path),
                       let modificationDate = attributes[.modificationDate] as? Date,
                       Date().timeIntervalSince(modificationDate) < StaticResourceManager.shared.SOVEREIGNTY_CAMPAIGNS_CACHE_DURATION {
                        
                        // 更新内存缓存
                        sovereigntyCache.setObject(
                            CachedData(data: campaigns, timestamp: modificationDate),
                            forKey: cacheKey
                        )
                        
                        Logger.info("从本地文件加载主权争夺数据")
                        return campaigns
                    }
                } catch {
                    Logger.error("从本地文件加载主权争夺数据失败: \(error)")
                }
            }
        }
        
        let urlString = "https://esi.evetech.net/latest/sovereignty/campaigns/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            Logger.error("主权争夺数据URL无效")
            throw NetworkError.invalidURL
        }
        
        // 如果强制刷新，清除URLCache中的缓存
        if forceRefresh {
            URLCache.shared.removeCachedResponse(for: URLRequest(url: url))
        }
        
        let data = try await fetchData(from: url)
        let campaigns = try JSONDecoder().decode([SovereigntyCampaign].self, from: data)
        
        // 更新缓存
        sovereigntyCache.setObject(
            CachedData(data: campaigns, timestamp: Date()),
            forKey: cacheKey
        )
        
        // 保存到本地文件
        try StaticResourceManager.shared.saveToFile(
            data,
            filename: StaticResourceManager.ResourceType.sovereigntyCampaigns.filename
        )
        
        Logger.info("成功获取主权争夺数据")
        return campaigns
    }
}

// 网络错误枚举
enum NetworkError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case invalidImageData
    case noValidPrice
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return NSLocalizedString("Network_Error_Invalid_URL", comment: "")
        case .invalidResponse:
            return NSLocalizedString("Network_Error_Invalid_Response", comment: "")
        case .httpError(let statusCode):
            return String(format: NSLocalizedString("Network_Error_HTTP_Error", comment: ""), statusCode)
        case .invalidImageData:
            return NSLocalizedString("Network_Error_Invalid_Image", comment: "")
        case .noValidPrice:
            return NSLocalizedString("Network_Error_No_Price", comment: "")
        case .invalidData:
            return NSLocalizedString("Network_Error_Invalid_Data", comment: "")
        }
    }
}
