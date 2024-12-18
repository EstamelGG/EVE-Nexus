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
    
    // 市场订单缓存（仅内存）
    private var marketOrdersCache: [Int: [MarketOrder]] = [:]
    private var marketOrdersTimestamp: [Int: Date] = [:]
    private let marketOrdersCacheDuration: TimeInterval = 300 // 市场订单缓存有效期5分钟
    
    // 市场历史数据缓存
    private var marketHistoryCache: [Int: [MarketHistory]] = [:]
    private var marketHistoryTimestamp: [Int: Date] = [:]
    
    // 服务器状态缓存（仅内存）
    private var serverStatusCache: CachedData<ServerStatus>?
    
    // 通缓存（用于JSON数据）
    private let dataCache = NSCache<NSString, CachedData<Any>>()
    
    // 图片缓存
    private let imageCache = NSCache<NSString, CachedData<UIImage>>()
    
    private init() {
        // 设置缓存限制
        dataCache.countLimit = 100
        imageCache.countLimit = 200
    }
    
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
        let cacheKey = "item_\(typeID)" as NSString
        
        // 检查内存缓存
        if let cached = imageCache.object(forKey: cacheKey),
           Date().timeIntervalSince(cached.timestamp) < StaticResourceManager.shared.RENDER_CACHE_DURATION {
            Logger.info("Using memory cached item render for ID: \(typeID)")
            return cached.data
        }
        
        // 检查本地文件缓存
        let fileName = "item_\(typeID).png"
        let fileManager = FileManager.default
        let cacheDirectory = try fileManager.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let fileURL = cacheDirectory.appendingPathComponent(fileName)
        
        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
                let modificationDate = attributes[.modificationDate] as! Date
                
                if Date().timeIntervalSince(modificationDate) < StaticResourceManager.shared.RENDER_CACHE_DURATION,
                   let image = UIImage(data: data) {
                    // 更新内存缓存
                    imageCache.setObject(
                        CachedData(data: image, timestamp: modificationDate),
                        forKey: cacheKey
                    )
                    Logger.info("Using file cached item render for ID: \(typeID)")
                    return image
                }
            } catch {
                Logger.error("Error reading item render cache file: \(error)")
            }
        }
        
        // 从网络获取数据
        let urlString = "https://images.evetech.net/types/\(typeID)/render?size=512"
        guard let url = URL(string: urlString) else {
            Logger.error("Invalid URL for item render")
            throw NetworkError.invalidURL
        }
        
        let data = try await fetchData(from: url)
        guard let image = UIImage(data: data) else {
            throw NetworkError.invalidResponse
        }
        
        // 更新内存缓存
        imageCache.setObject(
            CachedData(data: image, timestamp: Date()),
            forKey: cacheKey
        )
        
        // 更新文件缓存
        do {
            try data.write(to: fileURL)
            Logger.info("Successfully saved item render to file for ID: \(typeID)")
        } catch {
            Logger.error("Error saving item render to file: \(error)")
        }
        
        Logger.info("Successfully fetched item render for ID: \(typeID)")
        return image
    }
    
    // 获取市场订单
    func fetchMarketOrders(typeID: Int, forceRefresh: Bool = false) async throws -> [MarketOrder] {
        // 如果不是强制刷新，检查内存缓存
        if !forceRefresh,
           let timestamp = marketOrdersTimestamp[typeID],
           let cachedOrders = marketOrdersCache[typeID],
           Date().timeIntervalSince(timestamp) < marketOrdersCacheDuration {
            Logger.info("Using cached market orders for typeID: \(typeID)")
            return cachedOrders
        }
        
        let urlString = "https://esi.evetech.net/latest/markets/\(regionID)/orders/?datasource=tranquility&type_id=\(typeID)"
        guard let url = URL(string: urlString) else {
            Logger.error("Invalid URL for market orders")
            throw NetworkError.invalidURL
        }
        
        // 如果强制刷新，清除 URLCache 中的缓存
        if forceRefresh {
            URLCache.shared.removeCachedResponse(for: URLRequest(url: url))
        }
        
        let data = try await fetchData(from: url)
        let orders = try JSONDecoder().decode([MarketOrder].self, from: data)
        
        // 更新内存缓存
        marketOrdersCache[typeID] = orders
        marketOrdersTimestamp[typeID] = Date()
        
        Logger.info("Successfully fetched market orders for typeID: \(typeID)")
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
        // 如果不是强制刷新，检查内存缓存
        if !forceRefresh,
           let timestamp = marketHistoryTimestamp[typeID],
           let cachedHistory = marketHistoryCache[typeID],
           Date().timeIntervalSince(timestamp) < StaticResourceManager.shared.MARKET_HISTORY_CACHE_DURATION {
            Logger.info("Using memory cached market history for typeID: \(typeID)")
            return cachedHistory
        }
        
        // 如果不是强制刷新，检查本地文件缓存
        if !forceRefresh {
            let fileName = "market_history_\(typeID)_\(regionID).json"
            let fileManager = FileManager.default
            let cacheDirectory = try fileManager.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let fileURL = cacheDirectory.appendingPathComponent(fileName)
            
            if fileManager.fileExists(atPath: fileURL.path) {
                do {
                    let data = try Data(contentsOf: fileURL)
                    let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
                    let modificationDate = attributes[.modificationDate] as! Date
                    
                    if Date().timeIntervalSince(modificationDate) < StaticResourceManager.shared.MARKET_HISTORY_CACHE_DURATION {
                        let history = try JSONDecoder().decode([MarketHistory].self, from: data)
                        // 更新内存缓存
                        marketHistoryCache[typeID] = history
                        marketHistoryTimestamp[typeID] = modificationDate
                        Logger.info("Using file cached market history for typeID: \(typeID)")
                        return history
                    }
                } catch {
                    Logger.error("Error reading market history cache file: \(error)")
                }
            }
        }
        
        // 从网络获取数据
        let urlString = "https://esi.evetech.net/latest/markets/\(regionID)/history/?datasource=tranquility&type_id=\(typeID)"
        guard let url = URL(string: urlString) else {
            Logger.error("Invalid URL for market history")
            throw NetworkError.invalidURL
        }
        
        // 如果强制刷新，清除 URLCache 中的缓存
        if forceRefresh {
            URLCache.shared.removeCachedResponse(for: URLRequest(url: url))
        }
        
        let data = try await fetchData(from: url)
        let history = try JSONDecoder().decode([MarketHistory].self, from: data)
        
        // 更新内存缓存
        marketHistoryCache[typeID] = history
        marketHistoryTimestamp[typeID] = Date()
        
        // 更新文件缓存
        let fileName = "market_history_\(typeID)_\(regionID).json"
        let fileManager = FileManager.default
        let cacheDirectory = try fileManager.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let fileURL = cacheDirectory.appendingPathComponent(fileName)
        
        do {
            try data.write(to: fileURL)
            Logger.info("Successfully saved market history to file for typeID: \(typeID)")
        } catch {
            Logger.error("Error saving market history to file: \(error)")
        }
        
        Logger.info("Successfully fetched market history for typeID: \(typeID)")
        return history
    }
    
    // 获取入侵数据
    func fetchIncursions() async throws -> [Incursion] {
        let cacheKey = "incursions" as NSString
        
        // 检查内存缓存
        if let cached = dataCache.object(forKey: cacheKey) as? CachedData<[Incursion]>,
           Date().timeIntervalSince(cached.timestamp) < StaticResourceManager.shared.INCURSIONS_CACHE_DURATION {
            Logger.info("Using memory cached incursions data")
            return cached.data
        }
        
        // 检查本地文件缓存
        let fileName = "Incursions.json"
        let fileManager = FileManager.default
        let cacheDirectory = try fileManager.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let fileURL = cacheDirectory.appendingPathComponent(fileName)
        
        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
                let modificationDate = attributes[.modificationDate] as! Date
                
                if Date().timeIntervalSince(modificationDate) < StaticResourceManager.shared.INCURSIONS_CACHE_DURATION {
                    let incursions = try JSONDecoder().decode([Incursion].self, from: data)
                    // 更新内存缓存
                    dataCache.setObject(
                        CachedData(data: incursions, timestamp: modificationDate),
                        forKey: cacheKey
                    )
                    Logger.info("Using file cached incursions data")
                    return incursions
                }
            } catch {
                Logger.error("Error reading incursions cache file: \(error)")
            }
        }
        
        // 从网络获取数据
        let urlString = "https://esi.evetech.net/latest/incursions/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            Logger.error("Invalid URL for incursions")
            throw NetworkError.invalidURL
        }
        
        let data = try await fetchData(from: url)
        let incursions = try JSONDecoder().decode([Incursion].self, from: data)
        
        // 更新内存缓存
        dataCache.setObject(
            CachedData(data: incursions, timestamp: Date()),
            forKey: cacheKey
        )
        
        // 更新文件缓存
        do {
            try data.write(to: fileURL)
            Logger.info("Successfully saved incursions data to file")
        } catch {
            Logger.error("Error saving incursions data to file: \(error)")
        }
        
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
        dataCache.removeAllObjects()
        imageCache.removeAllObjects()
        serverStatusCache = nil
        Logger.info("Cleared all NetworkManager caches")
    }
    
    // 获取主权数据
    func fetchSovereigntyData(forceRefresh: Bool = false) async throws -> [SovereigntyData] {
        let cacheKey = "sovereigntyData" as NSString
        
        // 如果不是强制刷新，检查内存缓存
        if !forceRefresh,
           let cached = dataCache.object(forKey: cacheKey) as? CachedData<[SovereigntyData]>,
           Date().timeIntervalSince(cached.timestamp) < StaticResourceManager.shared.SOVEREIGNTY_CACHE_DURATION {
            Logger.info("Using memory cached sovereignty data")
            return cached.data
        }
        
        // 如果不是强制刷新，检查本地文件缓存
        if !forceRefresh {
            let fileName = "SovereigntyData.json"
            let fileManager = FileManager.default
            let cacheDirectory = try fileManager.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let fileURL = cacheDirectory.appendingPathComponent(fileName)
            
            if fileManager.fileExists(atPath: fileURL.path) {
                do {
                    let data = try Data(contentsOf: fileURL)
                    let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
                    let modificationDate = attributes[.modificationDate] as! Date
                    
                    if Date().timeIntervalSince(modificationDate) < StaticResourceManager.shared.SOVEREIGNTY_CACHE_DURATION {
                        let sovereigntyData = try JSONDecoder().decode([SovereigntyData].self, from: data)
                        // 更新内存缓存
                        dataCache.setObject(
                            CachedData(data: sovereigntyData, timestamp: modificationDate),
                            forKey: cacheKey
                        )
                        Logger.info("Using file cached sovereignty data")
                        return sovereigntyData
                    }
                } catch {
                    Logger.error("Error reading sovereignty data cache file: \(error)")
                }
            }
        }
        
        // 从网络获取数据
        let urlString = "https://esi.evetech.net/latest/sovereignty/map/?datasource=tranquility"
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
        
        // 更新内存缓存
        dataCache.setObject(
            CachedData(data: sovereigntyData, timestamp: Date()),
            forKey: cacheKey
        )
        
        // 更新文件缓存
        let fileName = "SovereigntyData.json"
        let fileManager = FileManager.default
        let cacheDirectory = try fileManager.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let fileURL = cacheDirectory.appendingPathComponent(fileName)
        
        do {
            try data.write(to: fileURL)
            Logger.info("Successfully saved sovereignty data to file")
        } catch {
            Logger.error("Error saving sovereignty data to file: \(error)")
        }
        
        Logger.info("Successfully fetched sovereignty data")
        return sovereigntyData
    }
    
    // 获取主权战役数据
    func fetchSovereigntyCampaigns(forceRefresh: Bool = false) async throws -> [SovereigntyCampaign] {
        let cacheKey = "sovereigntyCampaigns" as NSString
        
        // 如果不是强制刷新，检查内存缓存
        if !forceRefresh,
           let cached = dataCache.object(forKey: cacheKey) as? CachedData<[SovereigntyCampaign]>,
           Date().timeIntervalSince(cached.timestamp) < StaticResourceManager.shared.SOVEREIGNTY_CAMPAIGNS_CACHE_DURATION {
            Logger.info("Using memory cached sovereignty campaigns")
            return cached.data
        }
        
        // 如果不是强制刷新，检查本地文件缓存
        if !forceRefresh {
            let fileName = "SovereigntyCampaigns.json"
            let fileManager = FileManager.default
            let cacheDirectory = try fileManager.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let fileURL = cacheDirectory.appendingPathComponent(fileName)
            
            if fileManager.fileExists(atPath: fileURL.path) {
                do {
                    let data = try Data(contentsOf: fileURL)
                    let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
                    let modificationDate = attributes[.modificationDate] as! Date
                    
                    if Date().timeIntervalSince(modificationDate) < StaticResourceManager.shared.SOVEREIGNTY_CAMPAIGNS_CACHE_DURATION {
                        let campaigns = try JSONDecoder().decode([SovereigntyCampaign].self, from: data)
                        // 更新内存缓存
                        dataCache.setObject(
                            CachedData(data: campaigns, timestamp: modificationDate),
                            forKey: cacheKey
                        )
                        Logger.info("Using file cached sovereignty campaigns")
                        return campaigns
                    }
                } catch {
                    Logger.error("Error reading sovereignty campaigns cache file: \(error)")
                }
            }
        }
        
        // 从网络获取数据
        let urlString = "https://esi.evetech.net/latest/sovereignty/campaigns/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            Logger.error("Invalid URL for sovereignty campaigns")
            throw NetworkError.invalidURL
        }
        
        // 如果强制刷新，清除 URLCache 中的缓存
        if forceRefresh {
            URLCache.shared.removeCachedResponse(for: URLRequest(url: url))
        }
        
        let data = try await fetchData(from: url)
        let campaigns = try JSONDecoder().decode([SovereigntyCampaign].self, from: data)
        
        // 更新内存缓存
        dataCache.setObject(
            CachedData(data: campaigns, timestamp: Date()),
            forKey: cacheKey
        )
        
        // 更新文件缓存
        let fileName = "SovereigntyCampaigns.json"
        let fileManager = FileManager.default
        let cacheDirectory = try fileManager.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let fileURL = cacheDirectory.appendingPathComponent(fileName)
        
        do {
            try data.write(to: fileURL)
            Logger.info("Successfully saved sovereignty campaigns to file")
        } catch {
            Logger.error("Error saving sovereignty campaigns to file: \(error)")
        }
        
        Logger.info("Successfully fetched sovereignty campaigns")
        return campaigns
    }
    
    // 获取联盟图标
    func fetchAllianceLogo(allianceID: Int) async throws -> UIImage {
        let cacheKey = "alliance_\(allianceID)" as NSString
        
        // 检查内存缓存
        if let cached = imageCache.object(forKey: cacheKey),
           Date().timeIntervalSince(cached.timestamp) < StaticResourceManager.shared.ALLIANCE_ICON_CACHE_DURATION {
            Logger.info("Using memory cached alliance logo for ID: \(allianceID)")
            return cached.data
        }
        
        // 检查本地文件缓存
        let fileName = "alliance_\(allianceID).png"
        let fileManager = FileManager.default
        let cacheDirectory = try fileManager.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let fileURL = cacheDirectory.appendingPathComponent(fileName)
        
        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
                let modificationDate = attributes[.modificationDate] as! Date
                
                if Date().timeIntervalSince(modificationDate) < StaticResourceManager.shared.ALLIANCE_ICON_CACHE_DURATION,
                   let image = UIImage(data: data) {
                    // 更新内存缓存
                    imageCache.setObject(
                        CachedData(data: image, timestamp: modificationDate),
                        forKey: cacheKey
                    )
                    Logger.info("Using file cached alliance logo for ID: \(allianceID)")
                    return image
                }
            } catch {
                Logger.error("Error reading alliance logo cache file: \(error)")
            }
        }
        
        // 从网络获取数据
        let urlString = "https://images.evetech.net/alliances/\(allianceID)/logo?size=128"
        guard let url = URL(string: urlString) else {
            Logger.error("Invalid URL for alliance logo")
            throw NetworkError.invalidURL
        }
        
        let data = try await fetchData(from: url)
        guard let image = UIImage(data: data) else {
            throw NetworkError.invalidResponse
        }
        
        // 更新内存缓存
        imageCache.setObject(
            CachedData(data: image, timestamp: Date()),
            forKey: cacheKey
        )
        
        // 更新文件缓存
        do {
            try data.write(to: fileURL)
            Logger.info("Successfully saved alliance logo to file for ID: \(allianceID)")
        } catch {
            Logger.error("Error saving alliance logo to file: \(error)")
        }
        
        Logger.info("Successfully fetched alliance logo for ID: \(allianceID)")
        return image
    }
    
    // 获取服务器状态
    func fetchServerStatus() async throws -> ServerStatus {
        // 检查内存缓存
        if let cached = serverStatusCache?.data {
            return cached
        }
        
        let urlString = "https://esi.evetech.net/latest/status/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            Logger.error("Invalid URL for server status")
            throw NetworkError.invalidURL
        }
        
        let data = try await fetchData(from: url)
        let status = try JSONDecoder().decode(ServerStatus.self, from: data)
        
        // 更新缓存
        serverStatusCache = CachedData(data: status, timestamp: Date())
        
        Logger.info("Successfully fetched server status")
        return status
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
