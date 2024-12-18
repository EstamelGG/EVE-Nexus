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

// 缓存策略枚举
enum CacheStrategy {
    case none                    // 不使用缓存
    case memoryOnly             // 仅使用内存缓存
    case fileOnly               // 仅使用文件缓存
    case both                   // 同时使用内存和文件缓存
}

// 资源类型协议
protocol NetworkResource {
    var baseURL: String { get }
    var cacheKey: String { get }
    var fileName: String { get }
    var cacheDuration: TimeInterval { get }
}

// 通用资源请求配置
struct ResourceRequest<T: Codable> {
    let resource: NetworkResource
    let parameters: [String: Any]
    let cacheStrategy: CacheStrategy
    let forceRefresh: Bool
    
    init(resource: NetworkResource, 
         parameters: [String: Any] = [:], 
         cacheStrategy: CacheStrategy = .both,
         forceRefresh: Bool = false) {
        self.resource = resource
        self.parameters = parameters
        self.cacheStrategy = cacheStrategy
        self.forceRefresh = forceRefresh
    }
}

// 具体的资源类型实现
enum EVEResource: CaseIterable, NetworkResource {
    case sovereignty
    case incursions
    case sovereigntyCampaigns
    case marketOrders(regionId: Int, typeId: Int)
    case marketHistory(regionId: Int, typeId: Int)
    case serverStatus
    
    // 由于有关联值，我们需要手动实现 allCases
    static var allCases: [EVEResource] {
        return [
            .sovereignty,
            .incursions,
            .sovereigntyCampaigns,
            .serverStatus,
            // 为市场订单和历史数据使用默认值
            .marketOrders(regionId: 10000002, typeId: 0),
            .marketHistory(regionId: 10000002, typeId: 0)
        ]
    }
    
    var baseURL: String {
        switch self {
        case .sovereignty:
            return "https://esi.evetech.net/latest/sovereignty/map/"
        case .incursions:
            return "https://esi.evetech.net/latest/incursions/"
        case .sovereigntyCampaigns:
            return "https://esi.evetech.net/latest/sovereignty/campaigns/"
        case .marketOrders(let regionId, _):
            return "https://esi.evetech.net/latest/markets/\(regionId)/orders/"
        case .marketHistory(let regionId, _):
            return "https://esi.evetech.net/latest/markets/\(regionId)/history/"
        case .serverStatus:
            return "https://esi.evetech.net/latest/status/"
        }
    }
    
    var cacheKey: String {
        switch self {
        case .sovereignty:
            return "sovereignty"
        case .incursions:
            return "incursions"
        case .sovereigntyCampaigns:
            return "sovereigntyCampaigns"
        case .marketOrders(let regionId, let typeId):
            return "marketOrders_\(regionId)_\(typeId)"
        case .marketHistory(let regionId, let typeId):
            return "marketHistory_\(regionId)_\(typeId)"
        case .serverStatus:
            return "serverStatus"
        }
    }
    
    var fileName: String {
        switch self {
        case .sovereignty:
            return "sovereignty.json"
        case .incursions:
            return "incursions.json"
        case .sovereigntyCampaigns:
            return "sovereigntyCampaigns.json"
        case .marketOrders(let regionId, let typeId):
            return "Market_\(typeId)/orders_\(regionId).json"
        case .marketHistory(let regionId, let typeId):
            return "Market_\(typeId)/history_\(regionId).json"
        case .serverStatus:
            return "serverStatus.json"
        }
    }
    
    var cacheDuration: TimeInterval {
        switch self {
        case .sovereignty:
            return StaticResourceManager.shared.SOVEREIGNTY_CACHE_DURATION
        case .incursions:
            return StaticResourceManager.shared.INCURSIONS_CACHE_DURATION
        case .sovereigntyCampaigns:
            return StaticResourceManager.shared.SOVEREIGNTY_CAMPAIGNS_CACHE_DURATION
        case .marketOrders:
            return 300 // 5分钟
        case .marketHistory:
            return 3600 // 1小时
        case .serverStatus:
            return 60 // 1分钟
        }
    }
}

// 修改类定义，继承自NSObject
class NetworkManager: NSObject {
    static let shared = NetworkManager()
    private var regionID: Int = 10000002 // 默认为 The Forge
    
    // 通用缓存（用于JSON数据）
    private let dataCache = NSCache<NSString, CachedData<Any>>()
    private var dataCacheKeys = Set<String>()  // 跟踪数据缓存的键
    
    // 图片缓存
    private let imageCache = NSCache<NSString, CachedData<UIImage>>()
    private var imageCacheKeys = Set<String>()  // 跟踪图片缓存的键
    
    private override init() {
        super.init()
        // 设置缓存限制
        dataCache.countLimit = 100
        imageCache.countLimit = 200
        
        // 设置缓存删除时的回调
        dataCache.delegate = self
        imageCache.delegate = self
    }
    
    func setRegionID(_ id: Int) {
        regionID = id
    }
    
    // 市场订单缓存（仅内存）
    private var marketOrdersCache: [Int: [MarketOrder]] = [:]
    private var marketOrdersTimestamp: [Int: Date] = [:]
    private let marketOrdersCacheDuration: TimeInterval = 300 // 市场订单缓存有效期5分钟
    
    // 服务器状态缓存（仅内存）
    private var serverStatusCache: CachedData<ServerStatus>?
    
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
    
    // 通用的图片缓存处理方法
    private func fetchCachedImage(
        cacheKey: String,
        filename: String,
        cacheDuration: TimeInterval,
        imageURL: URL
    ) async throws -> UIImage {
        // 检查内存缓存
        if let cached = imageCache.object(forKey: cacheKey as NSString),
           Date().timeIntervalSince(cached.timestamp) < cacheDuration {
            Logger.info("Using memory cached image for: \(cacheKey)")
            return cached.data
        }
        
        // 检查本地文件缓存
        let fileManager = FileManager.default
        let fileURL: URL
        
        // 根据缓存键类型选择存储位置
        if cacheKey.starts(with: "alliance_") {
            // 联盟图标存储在 StaticDataSet/AllianceIcons 目录
            fileURL = StaticResourceManager.shared.getAllianceIconPath().appendingPathComponent(filename)
        } else {
            // 其他图片存储在系统缓存目录
            let cacheDirectory = try fileManager.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            fileURL = cacheDirectory.appendingPathComponent(filename)
        }
        
        // 确保目录存在
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        
        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
                let modificationDate = attributes[.modificationDate] as! Date
                
                if Date().timeIntervalSince(modificationDate) < cacheDuration,
                   let image = UIImage(data: data) {
                    // 更新内存缓存
                    imageCache.setObject(
                        CachedData(data: image, timestamp: modificationDate),
                        forKey: cacheKey as NSString
                    )
                    Logger.info("Using file cached image for: \(cacheKey)")
                    return image
                }
            } catch {
                Logger.error("Error reading image cache file for \(cacheKey): \(error)")
            }
        }
        
        // 从网络获取数据
        Logger.info("Fetching image from network for: \(cacheKey)")
        let data = try await fetchData(from: imageURL)
        guard let image = UIImage(data: data) else {
            throw NetworkError.invalidImageData
        }
        
        // 更新内存缓存
        imageCache.setObject(
            CachedData(data: image, timestamp: Date()),
            forKey: cacheKey as NSString
        )
        
        // 更新文件缓存
        do {
            try data.write(to: fileURL)
            Logger.info("Successfully saved image to file for: \(cacheKey) to \(fileURL)")
        } catch {
            Logger.error("Error saving image to file for \(cacheKey): \(error)")
        }
        
        return image
    }
    
    // 获取EVE物品渲染图
    func fetchEVEItemRender(typeID: Int) async throws -> UIImage {
        let urlString = "https://images.evetech.net/types/\(typeID)/render?size=512"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        
        return try await fetchCachedImage(
            cacheKey: "item_\(typeID)",
            filename: "item_\(typeID).png",
            cacheDuration: StaticResourceManager.shared.RENDER_CACHE_DURATION,
            imageURL: url
        )
    }
    
    // 获取市场订单（仅使用内存缓存）
    func fetchMarketOrders(typeID: Int, forceRefresh: Bool = false) async throws -> [MarketOrder] {
        let request = ResourceRequest<[MarketOrder]>(
            resource: EVEResource.marketOrders(regionId: regionID, typeId: typeID),
            parameters: [
                "datasource": "tranquility",
                "type_id": typeID
            ],
            cacheStrategy: .memoryOnly,  // 仅使用内存缓存
            forceRefresh: forceRefresh
        )
        
        return try await fetchResource(request)
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
    
    // 获取市场历史数据（使用内存和文件缓存）
    func fetchMarketHistory(typeID: Int, forceRefresh: Bool = false) async throws -> [MarketHistory] {
        let request = ResourceRequest<[MarketHistory]>(
            resource: EVEResource.marketHistory(regionId: regionID, typeId: typeID),
            parameters: [
                "datasource": "tranquility",
                "type_id": typeID
            ],
            cacheStrategy: .both,  // 同时使用内存和文件缓存
            forceRefresh: forceRefresh
        )
        
        return try await fetchResource(request)
    }
    
    // 通用的缓存处理方法
    private func fetchCachedData<T: Codable>(
        cacheKey: String,
        filename: String,
        cacheDuration: TimeInterval,
        forceRefresh: Bool = false,
        networkFetch: () async throws -> T
    ) async throws -> T {
        let dataCache = self.dataCache
        
        // 如果不是强制刷新，检查内存缓存
        if !forceRefresh,
           let cached = dataCache.object(forKey: cacheKey as NSString) as? CachedData<T>,
           Date().timeIntervalSince(cached.timestamp) < cacheDuration {
            Logger.info("Using memory cached data for: \(cacheKey)")
            return cached.data
        }
        
        // 如果不是强制刷新，检查本地文件缓存
        if !forceRefresh {
            let fileManager = FileManager.default
            let cacheDirectory = try fileManager.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let fileURL = cacheDirectory.appendingPathComponent(filename)
            
            if fileManager.fileExists(atPath: fileURL.path) {
                do {
                    let data = try Data(contentsOf: fileURL)
                    let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
                    let modificationDate = attributes[.modificationDate] as! Date
                    
                    if Date().timeIntervalSince(modificationDate) < cacheDuration {
                        let decodedData = try JSONDecoder().decode(T.self, from: data)
                        // 更新内存缓存
                        dataCache.setObject(
                            CachedData(data: decodedData, timestamp: modificationDate),
                            forKey: cacheKey as NSString
                        )
                        Logger.info("Using file cached data for: \(cacheKey)")
                        return decodedData
                    }
                } catch {
                    Logger.error("Error reading cache file for \(cacheKey): \(error)")
                }
            }
        }
        
        // 从网络获取数据
        Logger.info("Fetching data from network for: \(cacheKey)")
        let data = try await networkFetch()
        
        // 更新内存缓存
        dataCache.setObject(
            CachedData(data: data, timestamp: Date()),
            forKey: cacheKey as NSString
        )
        
        // 更新文件缓存
        do {
            let fileManager = FileManager.default
            let cacheDirectory = try fileManager.url(for: .cachesDirectory, 
                                                       in: .userDomainMask, 
                                                       appropriateFor: nil, 
                                                       create: true)
            let fileURL = cacheDirectory.appendingPathComponent(filename)
            let encodedData = try JSONEncoder().encode(data)
            try encodedData.write(to: fileURL)
            Logger.info("Successfully saved data to file for: \(cacheKey)")
        } catch {
            Logger.error("Error saving data to file for \(cacheKey): \(error)")
        }
        
        return data
    }
    
    // 获取主权数据
    func fetchSovereigntyData(forceRefresh: Bool = false) async throws -> [SovereigntyData] {
        let request = ResourceRequest<[SovereigntyData]>(
            resource: EVEResource.sovereignty,
            parameters: ["datasource": "tranquility"],
            cacheStrategy: .both,
            forceRefresh: forceRefresh
        )
        
        return try await fetchResource(request)
    }
    
    // 获取主权战役数据（使用内存和文件缓存）
    func fetchSovereigntyCampaigns(forceRefresh: Bool = false) async throws -> [SovereigntyCampaign] {
        let request = ResourceRequest<[SovereigntyCampaign]>(
            resource: EVEResource.sovereigntyCampaigns,
            parameters: ["datasource": "tranquility"],
            cacheStrategy: .both,
            forceRefresh: forceRefresh
        )
        
        return try await fetchResource(request)
    }
    
    // 获取入侵数据（使用内存和文件缓存）
    func fetchIncursions(forceRefresh: Bool = false) async throws -> [Incursion] {
        let request = ResourceRequest<[Incursion]>(
            resource: EVEResource.incursions,
            parameters: ["datasource": "tranquility"],
            cacheStrategy: .both,
            forceRefresh: forceRefresh
        )
        
        return try await fetchResource(request)
    }
    
    // 清除缓存
    func clearMarketOrdersCache() {
        marketOrdersCache.removeAll()
        marketOrdersTimestamp.removeAll()
    }
    
    // 清除所有缓存
    func clearAllCaches() {
        // 清理内存缓存
        clearMarketOrdersCache()
        dataCache.removeAllObjects()
        imageCache.removeAllObjects()
        dataCacheKeys.removeAll()
        imageCacheKeys.removeAll()
        serverStatusCache = nil
        
        let fileManager = FileManager.default
        
        // 1. 清理系统缓存目录
        if let cacheDirectory = try? fileManager.url(for: .cachesDirectory, 
                                                   in: .userDomainMask, 
                                                   appropriateFor: nil, 
                                                   create: false) {
            try? fileManager.removeItem(at: cacheDirectory)
            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
        
        // 2. 清理StaticDataSet目录
        let staticDataSetPath = StaticResourceManager.shared.getStaticDataSetPath()
        try? fileManager.removeItem(at: staticDataSetPath)
        try? fileManager.createDirectory(at: staticDataSetPath, withIntermediateDirectories: true)
        
        Logger.info("Cleared all NetworkManager caches")
    }
    
    // 获取联盟图标
    func fetchAllianceLogo(allianceID: Int) async throws -> UIImage {
        let urlString = "https://images.evetech.net/alliances/\(allianceID)/logo?size=128"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        
        return try await fetchCachedImage(
            cacheKey: "alliance_\(allianceID)",
            filename: "alliance_\(allianceID).png",
            cacheDuration: StaticResourceManager.shared.ALLIANCE_ICON_CACHE_DURATION,
            imageURL: url
        )
    }
    
    // 获取服务器状态（不使用任何缓存）
    func fetchServerStatus() async throws -> ServerStatus {
        let request = ResourceRequest<ServerStatus>(
            resource: EVEResource.serverStatus,
            parameters: ["datasource": "tranquility"],
            cacheStrategy: .none,  // 不使用缓存
            forceRefresh: true     // 总是从网络获取
        )
        
        return try await fetchResource(request)
    }
    
    // 通用数据获取方法
    func fetchResource<T: Codable>(_ request: ResourceRequest<T>) async throws -> T {
        let cacheKey = request.resource.cacheKey + "_" + request.parameters.description
        
        // 如果不是强制刷新，试从缓存获取
        if !request.forceRefresh {
            // 1. 检查内存缓存
            if request.cacheStrategy == .memoryOnly || request.cacheStrategy == .both,
               let cached = dataCache.object(forKey: cacheKey as NSString) as? CachedData<T>,
               Date().timeIntervalSince(cached.timestamp) < request.resource.cacheDuration {
                Logger.info("Using memory cached data for: \(cacheKey)")
                return cached.data
            }
            
            // 2. 检查文件缓存
            if request.cacheStrategy == .fileOnly || request.cacheStrategy == .both {
                let fileManager = FileManager.default
                let fileURL: URL
                
                // 根据资源类型选择存储位置
                if let resource = request.resource as? EVEResource {
                    switch resource {
                    case .sovereignty, .incursions, .sovereigntyCampaigns:
                        // 这些资源存储在 StaticDataSet 目录
                        fileURL = StaticResourceManager.shared.getStaticDataSetPath().appendingPathComponent(resource.fileName)
                    default:
                        // 其他资源存储在系统缓存目录
                        guard let cacheDirectory = try? fileManager.url(for: .cachesDirectory, 
                                                                      in: .userDomainMask, 
                                                                      appropriateFor: nil, 
                                                                      create: true) else {
                            throw NetworkError.invalidData
                        }
                        fileURL = cacheDirectory.appendingPathComponent(resource.fileName)
                    }
                } else {
                    guard let cacheDirectory = try? fileManager.url(for: .cachesDirectory, 
                                                                  in: .userDomainMask, 
                                                                  appropriateFor: nil, 
                                                                  create: true) else {
                        throw NetworkError.invalidData
                    }
                    fileURL = cacheDirectory.appendingPathComponent(request.resource.fileName)
                }
                
                if fileManager.fileExists(atPath: fileURL.path) {
                    do {
                        let data = try Data(contentsOf: fileURL)
                        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
                        let modificationDate = attributes[.modificationDate] as! Date
                        
                        if Date().timeIntervalSince(modificationDate) < request.resource.cacheDuration {
                            let decodedData = try JSONDecoder().decode(T.self, from: data)
                            
                            // 如果策略包含内存缓存，更新内存缓存
                            if request.cacheStrategy == .both {
                                dataCache.setObject(
                                    CachedData(data: decodedData, timestamp: modificationDate),
                                    forKey: cacheKey as NSString
                                )
                            }
                            
                            Logger.info("Using file cached data for: \(cacheKey)")
                            return decodedData
                        }
                    } catch {
                        Logger.error("Error reading cache file for \(cacheKey): \(error)")
                    }
                }
            }
        }
        
        // 3. 从网络获取数据
        var urlComponents = URLComponents(string: request.resource.baseURL)!
        urlComponents.queryItems = request.parameters.map { 
            URLQueryItem(name: $0.key, value: String(describing: $0.value))
        }
        
        guard let url = urlComponents.url else {
            throw NetworkError.invalidURL
        }
        
        Logger.info("Fetching data from network for: \(cacheKey)")
        let data = try await fetchData(from: url)
        let decodedData = try JSONDecoder().decode(T.self, from: data)
        
        // 根据缓存策略保存数据
        if request.cacheStrategy == .memoryOnly || request.cacheStrategy == .both {
            dataCache.setObject(
                CachedData(data: decodedData, timestamp: Date()),
                forKey: cacheKey as NSString
            )
        }
        
        if request.cacheStrategy == .fileOnly || request.cacheStrategy == .both {
            do {
                let fileManager = FileManager.default
                let fileURL: URL
                
                // 根据资源类型选择存储位置
                if let resource = request.resource as? EVEResource {
                    switch resource {
                    case .sovereignty, .incursions, .sovereigntyCampaigns:
                        // 这些资源存储在 StaticDataSet 目录
                        fileURL = StaticResourceManager.shared.getStaticDataSetPath().appendingPathComponent(resource.fileName)
                    default:
                        // 其他资源存储在系统缓存目录
                        guard let cacheDirectory = try? fileManager.url(for: .cachesDirectory, 
                                                                      in: .userDomainMask, 
                                                                      appropriateFor: nil, 
                                                                      create: true) else {
                            throw NetworkError.invalidData
                        }
                        fileURL = cacheDirectory.appendingPathComponent(resource.fileName)
                    }
                } else {
                    guard let cacheDirectory = try? fileManager.url(for: .cachesDirectory, 
                                                                  in: .userDomainMask, 
                                                                  appropriateFor: nil, 
                                                                  create: true) else {
                        throw NetworkError.invalidData
                    }
                    fileURL = cacheDirectory.appendingPathComponent(request.resource.fileName)
                }
                
                // 确保目录存在
                try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), 
                                             withIntermediateDirectories: true)
                
                let encodedData = try JSONEncoder().encode(decodedData)
                try encodedData.write(to: fileURL)
                Logger.info("Successfully saved data to file for: \(cacheKey)")
                
                // 如果是静态资源，更新下载时间
                if let resource = request.resource as? EVEResource {
                    switch resource {
                    case .sovereignty, .incursions, .sovereigntyCampaigns:
                        UserDefaults.standard.set(Date(), forKey: "StaticResource_\(resource.cacheKey)_DownloadTime")
                    default:
                        break
                    }
                }
            } catch {
                Logger.error("Error saving data to file for \(cacheKey): \(error)")
            }
        }
        
        return decodedData
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

extension NetworkManager: NSCacheDelegate {
    func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject obj: Any) {
        // 当缓存项被移除时，从对应的键集合中移除键
        if cache === dataCache {
            if let key = obj as? NSString {
                dataCacheKeys.remove(key as String)
            }
        } else if cache === imageCache {
            if let key = obj as? NSString {
                imageCacheKeys.remove(key as String)
            }
        }
    }
}

extension NetworkManager {
    // 缓存信息结构
    struct CacheInfo {
        let size: Int64
        let count: Int
        let lastModified: Date?
    }
    
    // 在设置缓存时添加键
    private func setDataCache<T: Encodable>(_ data: T, forKey key: String) {
        dataCache.setObject(CachedData(data: data, timestamp: Date()), forKey: key as NSString)
        dataCacheKeys.insert(key)
    }
    
    private func setImageCache(_ image: UIImage, forKey key: String) {
        imageCache.setObject(CachedData(data: image, timestamp: Date()), forKey: key as NSString)
        imageCacheKeys.insert(key)
    }
    
    // 获取内存缓存信息
    func getMemoryCacheInfo() -> CacheInfo {
        var totalSize: Int64 = 0
        var count = 0
        var lastModified: Date? = nil
        
        // 遍历数据缓存
        for key in dataCacheKeys {
            if let cached = dataCache.object(forKey: key as NSString) {
                count += 1
                // 由于无法准确计算内存中对象的大小，我们使用估算值
                totalSize += 1024  // 假设每个缓存项平均1KB
                // 更新最后修改时间
                if lastModified == nil || cached.timestamp > lastModified! {
                    lastModified = cached.timestamp
                }
            }
        }
        
        // 遍历图片缓存
        for key in imageCacheKeys {
            if let cached = imageCache.object(forKey: key as NSString) {
                count += 1
                if let imageData = cached.data.pngData() {
                    totalSize += Int64(imageData.count)
                } else {
                    // 如果无法获取图片数据，使用估算值
                    totalSize += 100 * 1024  // 假设每张图片平均100KB
                }
                if lastModified == nil || cached.timestamp > lastModified! {
                    lastModified = cached.timestamp
                }
            }
        }
        
        return CacheInfo(size: totalSize, count: count, lastModified: lastModified)
    }
    
    // 获取文件缓存信息
    func getFileCacheInfo() -> CacheInfo {
        var totalSize: Int64 = 0
        var count = 0
        var lastModified: Date? = nil
        let fileManager = FileManager.default
        
        // 1. 检查 StaticDataSet 目录
        let staticDataSetPath = StaticResourceManager.shared.getStaticDataSetPath()
        if let enumerator = fileManager.enumerator(at: staticDataSetPath, 
                                                 includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                                                 options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                do {
                    let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
                    if let fileSize = attributes[.size] as? Int64 {
                        totalSize += fileSize
                        count += 1
                    }
                    if let modificationDate = attributes[.modificationDate] as? Date {
                        if lastModified == nil || modificationDate > lastModified! {
                            lastModified = modificationDate
                        }
                    }
                } catch {
                    Logger.error("Error getting file attributes for \(fileURL.path): \(error)")
                }
            }
        }
        
        // 2. 检查系统缓存目录中的其他资源
        if let cacheDirectory = try? fileManager.url(for: .cachesDirectory, 
                                                   in: .userDomainMask, 
                                                   appropriateFor: nil, 
                                                   create: false) {
            for resource in EVEResource.allCases {
                switch resource {
                case .sovereignty, .incursions, .sovereigntyCampaigns:
                    continue // 这些已经在StaticDataSet目录中检查过了
                default:
                    let fileURL = cacheDirectory.appendingPathComponent(resource.fileName)
                    if fileManager.fileExists(atPath: fileURL.path) {
                        do {
                            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
                            if let fileSize = attributes[.size] as? Int64 {
                                totalSize += fileSize
                                count += 1
                            }
                            if let modificationDate = attributes[.modificationDate] as? Date {
                                if lastModified == nil || modificationDate > lastModified! {
                                    lastModified = modificationDate
                                }
                            }
                        } catch {
                            Logger.error("Error getting file attributes: \(error)")
                        }
                    }
                }
            }
        }
        
        return CacheInfo(size: totalSize, count: count, lastModified: lastModified)
    }
    
    // 清理特定资源的缓存
    func clearCache(for resource: EVEResource) {
        // 清理内存缓存
        let cacheKey = resource.cacheKey
        dataCache.removeObject(forKey: cacheKey as NSString)
        dataCacheKeys.remove(cacheKey)
        
        // 清理文件缓存
        let fileManager = FileManager.default
        let fileURL: URL
        
        switch resource {
        case .sovereignty, .incursions, .sovereigntyCampaigns:
            // 这些资源存储在 StaticDataSet 目录
            fileURL = StaticResourceManager.shared.getStaticDataSetPath().appendingPathComponent(resource.fileName)
        default:
            // 其他资源存储在系统缓存目录
            guard let cacheDirectory = try? fileManager.url(for: .cachesDirectory, 
                                                          in: .userDomainMask, 
                                                          appropriateFor: nil, 
                                                          create: false) else {
                return
            }
            fileURL = cacheDirectory.appendingPathComponent(resource.fileName)
        }
        
        try? fileManager.removeItem(at: fileURL)
        Logger.info("Cleared cache for resource: \(resource)")
    }
    
    // 重新加载特定资源
    func reloadResource<T: Codable>(_ resource: EVEResource) async throws -> T {
        let request = ResourceRequest<T>(
            resource: resource,
            parameters: ["datasource": "tranquility"],
            cacheStrategy: .both,
            forceRefresh: true  // 强制从网络重新加载
        )
        
        return try await fetchResource(request)
    }
    
    // 获取特定资源的缓存状态
    func getCacheStatus(for resource: EVEResource) -> (inMemory: Bool, inFile: Bool, age: TimeInterval?) {
        var inMemory = false
        var inFile = false
        var age: TimeInterval? = nil
        
        // 检查内存缓存
        if let cached = dataCache.object(forKey: resource.cacheKey as NSString) {
            inMemory = true
            age = Date().timeIntervalSince(cached.timestamp)
        }
        
        // 检查文件缓存
        let fileManager = FileManager.default
        if let cacheDirectory = try? fileManager.url(for: .cachesDirectory, 
                                                   in: .userDomainMask, 
                                                   appropriateFor: nil, 
                                                   create: false) {
            let fileURL = cacheDirectory.appendingPathComponent(resource.fileName)
            if fileManager.fileExists(atPath: fileURL.path) {
                inFile = true
                if let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
                   let modificationDate = attributes[.modificationDate] as? Date {
                    // 如果没有内存缓存的年龄，使用文件缓存的年龄
                    if age == nil {
                        age = Date().timeIntervalSince(modificationDate)
                    }
                }
            }
        }
        
        return (inMemory, inFile, age)
    }
    
    // 格式化缓存大小
    static func formatFileSize(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}
