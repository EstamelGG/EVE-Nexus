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
            return 7 * 24 * 3600 // 1周
        case .serverStatus:
            return 300 // 5分钟
        }
    }
}

// 修改类定义，继承自NSObject
@globalActor actor NetworkManagerActor {
    static let shared = NetworkManagerActor()
}

@NetworkManagerActor
class NetworkManager: NSObject, @unchecked Sendable {
    static let shared = NetworkManager()
    var regionID: Int = 10000002 // 默认为 The Forge
    
    // 通用缓存（用于JSON数据）
    private let dataCache = NSCache<NSString, CachedData<Any>>()
    private var dataCacheKeys = Set<String>()  // 跟踪数据缓存的键
    
    // 图片缓存
    private let imageCache = NSCache<NSString, CachedData<UIImage>>()
    private var imageCacheKeys = Set<String>()  // 跟踪图片缓存的键
    
    // 同步队列
    private let cacheQueue = DispatchQueue(label: "com.eve.nexus.network.cache", attributes: .concurrent)
    private let imageQueue = DispatchQueue(label: "com.eve.nexus.network.image", attributes: .concurrent)
    private let marketQueue = DispatchQueue(label: "com.eve.nexus.network.market", attributes: .concurrent)
    private let serverStatusQueue = DispatchQueue(label: "com.eve.nexus.network.server", attributes: .concurrent)
    
    // 市场订单缓存
    private var marketOrdersCache: [Int: [MarketOrder]] = [:]
    private var marketOrdersTimestamp: [Int: Date] = [:]
    private let marketOrdersCacheDuration: TimeInterval = 300 // 市场订单缓存效期5分钟
    
    // 服务器状态缓存
    private var serverStatusCache: CachedData<ServerStatus>?
    
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
    
    // 通用的数据获取函数
    func fetchData(from url: URL, request customRequest: URLRequest? = nil, forceRefresh: Bool = false) async throws -> Data {
        Logger.info("Fetching data from URL: \(url.absoluteString)")
        
        var request = customRequest ?? URLRequest(url: url)
        if forceRefresh {
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            Logger.error("Invalid response type received")
            throw NetworkError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            Logger.error("HTTP error: \(url.absoluteString) [\(httpResponse.statusCode)]")
            throw NetworkError.httpError(statusCode: httpResponse.statusCode)
        }
        
        return data
    }
    
    // 专门用于获取图片的函数
    func fetchImage(from url: URL) async throws -> UIImage {
        do {
            let data = try await fetchData(from: url)
            if let image = UIImage(data: data) {
                return image
            }
            throw NetworkError.invalidImageData
        } catch {
            Logger.error("Error fetching image from \(url.absoluteString): \(error)")
            throw error
        }
    }
    
    // 通用的图片缓存处理方法
    private func fetchCachedImage(
        cacheKey: String,
        filename: String,
        cacheDuration: TimeInterval,
        imageURL: URL
    ) async throws -> UIImage {
        // 检查内存缓存
        if let cached = await getCachedImage(forKey: cacheKey) {
            return cached
        }
        
        // 检查文件缓存
        let fileManager = FileManager.default
        let fileURL = StaticResourceManager.shared.getStaticDataSetPath()
            .appendingPathComponent("allianceIcons")
            .appendingPathComponent(filename)
        
        if fileManager.fileExists(atPath: fileURL.path) {
            if let data = try? Data(contentsOf: fileURL),
               let image = UIImage(data: data) {
                // 更新内存缓存
                await setCachedImage(image, forKey: cacheKey)
                return image
            }
        }
        
        // 从网络获取
        let image = try await fetchImage(from: imageURL)
        
        // 更新缓存
        await setCachedImage(image, forKey: cacheKey)
        
        // 异步保存到文件
        Task {
            if let pngData = image.pngData() {
                try? FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try? pngData.write(to: fileURL)
            }
        }
        
        return image
    }
    
    // 异步安全的缓存访问方法
    private func getCachedImage(forKey key: String) async -> UIImage? {
        await withCheckedContinuation { continuation in
            imageQueue.async {
                if let cached = self.imageCache.object(forKey: key as NSString)?.data {
                    continuation.resume(returning: cached)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    private func setCachedImage(_ image: UIImage, forKey key: String) async {
        await withCheckedContinuation { continuation in
            imageQueue.async(flags: .barrier) {
                self.imageCache.setObject(CachedData(data: image, timestamp: Date()), forKey: key as NSString)
                self.imageCacheKeys.insert(key)
                continuation.resume()
            }
        }
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
        // 如果不是强制刷新，检查内存缓存
        if !forceRefresh {
            if let cached = await getCachedData(forKey: cacheKey) as? CachedData<T>,
               Date().timeIntervalSince(cached.timestamp) < cacheDuration {
                Logger.info("Using memory cached data for: \(cacheKey)")
                return cached.data
            }
            
            // 检查文件缓存
            let fileManager = FileManager.default
            let fileURL = StaticResourceManager.shared.getStaticDataSetPath().appendingPathComponent(filename)
            
            if fileManager.fileExists(atPath: fileURL.path) {
                do {
                    let data = try Data(contentsOf: fileURL)
                    let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
                    let modificationDate = attributes[.modificationDate] as! Date
                    
                    if Date().timeIntervalSince(modificationDate) < cacheDuration {
                        let decodedData = try JSONDecoder().decode(T.self, from: data)
                        // 更新内存缓存
                        await setCachedData(decodedData, forKey: cacheKey)
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
        await setCachedData(data, forKey: cacheKey)
        
        // 异步更新文件缓存
        Task {
            do {
                let fileManager = FileManager.default
                let fileURL = StaticResourceManager.shared.getStaticDataSetPath().appendingPathComponent(filename)
                
                try fileManager.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                
                let encodedData = try JSONEncoder().encode(data)
                try encodedData.write(to: fileURL)
                Logger.info("Successfully saved data to file for: \(cacheKey)")
            } catch {
                Logger.error("Error saving data to file for \(cacheKey): \(error)")
            }
        }
        
        return data
    }
    
    // 异步安全的缓存访问方法
    private func getCachedData(forKey key: String) async -> Any? {
        await withCheckedContinuation { continuation in
            cacheQueue.async {
                if let cached = self.dataCache.object(forKey: key as NSString) {
                    continuation.resume(returning: cached)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    private func setCachedData<T>(_ data: T, forKey key: String) async {
        await withCheckedContinuation { continuation in
            cacheQueue.async(flags: .barrier) {
                self.dataCache.setObject(CachedData(data: data, timestamp: Date()), forKey: key as NSString)
                self.dataCacheKeys.insert(key)
                continuation.resume()
            }
        }
    }
    
    // 获取主权数据
    func fetchSovereigntyData(forceRefresh: Bool = false) async throws -> [SovereigntyData] {
        let request = ResourceRequest<[SovereigntyData]>(
            resource: EVEResource.sovereignty,
            parameters: ["datasource": "tranquility"],
            cacheStrategy: forceRefresh ? .none : .both,  // 如果强制刷新，不使用任何缓存
            forceRefresh: forceRefresh
        )
        
        return try await fetchResource(request)
    }
    
    // 获取主权战役数据（使用内存和文件缓存）
    func fetchSovereigntyCampaigns(forceRefresh: Bool = false) async throws -> [SovereigntyCampaign] {
        let request = ResourceRequest<[SovereigntyCampaign]>(
            resource: EVEResource.sovereigntyCampaigns,
            parameters: ["datasource": "tranquility"],
            cacheStrategy: forceRefresh ? .none : .both,  // 如果强制刷新，不使用任何缓存
            forceRefresh: forceRefresh
        )
        
        return try await fetchResource(request)
    }
    
    // 获取入侵数据（使用内存和文件缓存）
    func fetchIncursions(forceRefresh: Bool = false) async throws -> [Incursion] {
        let request = ResourceRequest<[Incursion]>(
            resource: EVEResource.incursions,
            parameters: ["datasource": "tranquility"],
            cacheStrategy: forceRefresh ? .none : .both,  // 如果强制刷新，不使用任何缓存
            forceRefresh: forceRefresh
        )
        
        return try await fetchResource(request)
    }
    
    // 清除市场订单缓存
    func clearMarketOrdersCache() {
        marketQueue.async(flags: .barrier) {
            self.marketOrdersCache.removeAll()
            self.marketOrdersTimestamp.removeAll()
        }
    }
    
    // 清除所有缓存
    func clearAllCaches() {
        // 清除内存缓存
        cacheQueue.async(flags: .barrier) {
            self.dataCache.removeAllObjects()
            self.dataCacheKeys.removeAll()
        }
        
        imageQueue.async(flags: .barrier) {
            self.imageCache.removeAllObjects()
            self.imageCacheKeys.removeAll()
        }
        
        marketQueue.async(flags: .barrier) {
            self.marketOrdersCache.removeAll()
            self.marketOrdersTimestamp.removeAll()
        }
        
        serverStatusQueue.async(flags: .barrier) {
            self.serverStatusCache = nil
        }
        
        // 清除文件缓存
        Task {
            await clearFileCaches()
        }
    }
    
    private func clearFileCaches() async {
        let staticDataSetPath = StaticResourceManager.shared.getStaticDataSetPath()
        do {
            let fileManager = FileManager.default
            let contents = try fileManager.contentsOfDirectory(at: staticDataSetPath, includingPropertiesForKeys: nil)
            
            for url in contents {
                if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let fileSize = attributes[.size] as? Int64 {
                    Logger.info("Deleting file: \(url.lastPathComponent) (Size: \(NetworkManager.formatFileSize(fileSize)))")
                    try? FileManager.default.removeItem(at: url)
                }
            }
            
            Logger.info("Finished clearing StaticDataSet directory")
        } catch {
            try? FileManager.default.createDirectory(at: staticDataSetPath, withIntermediateDirectories: true)
            Logger.error("Error accessing StaticDataSet directory: \(error)")
        }
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
        let urlString = "https://esi.evetech.net/latest/status/"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.addValue("tranquility", forHTTPHeaderField: "datasource")
        // 设置不使用缓存
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        // 添加随机参数以避免任何可能的缓存
        request.url = URL(string: urlString + "?t=\(Date().timeIntervalSince1970)")
        
        do {
            // 直接从网络获取最新状态
            let data = try await fetchData(from: url, request: request, forceRefresh: true)
            let status = try JSONDecoder().decode(ServerStatus.self, from: data)
            
            // 如果响应中包含 error 字段，返回离线状态
            if status.error != nil {
                return ServerStatus(
                    players: 0,
                    serverVersion: "",
                    startTime: "",
                    error: "Server is offline",
                    timeout: nil
                )
            }
            
            return status
        } catch NetworkError.httpError(let statusCode) {
            // 对于 502、504 错误，返回离线状态
            if statusCode == 502 || statusCode == 504 {
                return ServerStatus(
                    players: 0,
                    serverVersion: "",
                    startTime: "",
                    error: "Server is offline (HTTP \(statusCode))",
                    timeout: nil
                )
            }
            throw NetworkError.httpError(statusCode: statusCode)
        } catch {
            throw error
        }
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
                let fileURL = StaticResourceManager.shared.getStaticDataSetPath().appendingPathComponent(request.resource.fileName)
                
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
        let data = try await fetchData(from: url, forceRefresh: request.forceRefresh)
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
                let fileURL = StaticResourceManager.shared.getStaticDataSetPath().appendingPathComponent(request.resource.fileName)
                
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
    
    // 获取角色头像
    func fetchCharacterPortrait(characterId: Int, size: Int = 128, forceRefresh: Bool = false) async throws -> UIImage {
        let urlString = "https://images.evetech.net/characters/\(characterId)/portrait?size=\(size)"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        
        let cacheKey = "character_portrait_\(characterId)_\(size)"
        
        // 如果不是强制刷新，先检查内存缓存
        if !forceRefresh {
            if let cached = imageCache.object(forKey: cacheKey as NSString) {
                return cached.data
            }
            
            // 检查文件缓存
            let fileURL = StaticResourceManager.shared.getStaticDataSetPath()
                .appendingPathComponent("allianceIcons")
                .appendingPathComponent("character_portrait_\(characterId)_\(size).png")
            
            if let data = try? Data(contentsOf: fileURL),
               let image = UIImage(data: data) {
                // 更新内存缓存
                imageCache.setObject(CachedData(data: image, timestamp: Date()), forKey: cacheKey as NSString)
                imageCacheKeys.insert(cacheKey)
                return image
            }
        }
        
        // 如果强制刷新或没有缓存，从网络获取
        let data = try await fetchData(from: url, forceRefresh: forceRefresh)
        guard let image = UIImage(data: data) else {
            throw NetworkError.invalidImageData
        }
        
        // 更新缓存
        imageCache.setObject(CachedData(data: image, timestamp: Date()), forKey: cacheKey as NSString)
        imageCacheKeys.insert(cacheKey)
        
        // 保存到文件
        if let pngData = image.pngData() {
            let fileURL = StaticResourceManager.shared.getStaticDataSetPath()
                .appendingPathComponent("allianceIcons")
                .appendingPathComponent("character_portrait_\(characterId)_\(size).png")
            try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? pngData.write(to: fileURL)
        }
        
        return image
    }
    
    // 获取角色技能信息
    func fetchCharacterSkills(characterId: Int) async throws -> CharacterSkillsResponse {
        // 检查 UserDefaults 缓存
        let skillsCacheKey = "character_\(characterId)_skills"
        let skillsUpdateTimeKey = "character_\(characterId)_skills_update_time"
        
        // 如果缓存存在且未过期（5分钟），直接返回缓存数据
        if let cachedData = UserDefaults.standard.data(forKey: skillsCacheKey),
           let lastUpdateTime = UserDefaults.standard.object(forKey: skillsUpdateTimeKey) as? Date,
           Date().timeIntervalSince(lastUpdateTime) < 300 { // 5分钟缓存
            do {
                let skills = try JSONDecoder().decode(CharacterSkillsResponse.self, from: cachedData)
                Logger.info("Using cached skills data for character \(characterId)")
                return skills
            } catch {
                Logger.error("Failed to decode cached skills data: \(error)")
            }
        }
        
        // 如果没有缓存或缓存已过期，从网络获取
        let skills: CharacterSkillsResponse = try await fetchDataWithToken(
            characterId: characterId,
            endpoint: "/characters/\(characterId)/skills/"
        )
        
        // 更新缓存
        if let encodedData = try? JSONEncoder().encode(skills) {
            UserDefaults.standard.set(encodedData, forKey: skillsCacheKey)
            UserDefaults.standard.set(Date(), forKey: skillsUpdateTimeKey)
        }
        
        return skills
    }
    
    // 角色位置信息模型
    struct CharacterLocation: Codable {
        let solar_system_id: Int
        let structure_id: Int?
        let station_id: Int?
        
        var locationStatus: LocationStatus {
            if station_id != nil {
                return .inStation
            } else if structure_id != nil {
                return .inStructure
            } else {
                return .inSpace
            }
        }
        
        enum LocationStatus: String, Codable {
            case inStation
            case inStructure
            case inSpace
            
            var description: String {
                switch self {
                case .inStation:
                    return "(\(NSLocalizedString("Character_in_station", comment: "")))"
                case .inStructure:
                    return "(\(NSLocalizedString("Character_in_structure", comment: "")))"
                case .inSpace:
                    return "(\(NSLocalizedString("Character_in_space", comment: "")))"
                }
            }
        }
    }
    
    // 获取角色位置信息
    func fetchCharacterLocation(characterId: Int) async throws -> CharacterLocation {
        return try await fetchDataWithToken(
            characterId: characterId,
            endpoint: "/characters/\(characterId)/location/"
        )
    }
    
    // 获取星系位置信息
    func getLocationInfo(solarSystemId: Int, databaseManager: DatabaseManager) async -> SolarSystemInfo? {
        let universeQuery = """
            SELECT u.region_id, u.constellation_id, u.system_security,
                   s.solarSystemName, c.constellationName, r.regionName
            FROM universe u
            JOIN solarsystems s ON s.solarSystemID = u.solarsystem_id
            JOIN constellations c ON c.constellationID = u.constellation_id
            JOIN regions r ON r.regionID = u.region_id
            WHERE u.solarsystem_id = ?
        """
        
        guard case .success(let rows) = databaseManager.executeQuery(universeQuery, parameters: [solarSystemId]),
              let row = rows.first,
              let security = row["system_security"] as? Double,
              let systemName = row["solarSystemName"] as? String,
              let constellationName = row["constellationName"] as? String,
              let regionName = row["regionName"] as? String else {
            return nil
        }
        
        return SolarSystemInfo(
            systemName: systemName,
            security: security,
            constellationName: constellationName,
            regionName: regionName
        )
    }
    
    // 获取角色完整位置信息（包含星系名称等）
    func fetchCharacterLocationInfo(characterId: Int, databaseManager: DatabaseManager) async throws -> SolarSystemInfo? {
        let location = try await fetchCharacterLocation(characterId: characterId)
        return await getLocationInfo(solarSystemId: location.solar_system_id, databaseManager: databaseManager)
    }
    
    // 专门用于需要访问令牌的请求
    func fetchDataWithToken<T: Codable>(characterId: Int, endpoint: String) async throws -> T {
        let urlString = "https://esi.evetech.net/latest\(endpoint)"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        
        // 从EVELogin获取角色的token
        guard let character = EVELogin.shared.getCharacterByID(characterId) else {
            throw NetworkError.unauthed
        }
        
        let token = character.token.access_token
        
        var request = URLRequest(url: url)
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("tranquility", forHTTPHeaderField: "datasource")
        
        do {
            let data = try await fetchData(from: url, request: request)
            return try JSONDecoder().decode(T.self, from: data)
        } catch NetworkError.httpError(let statusCode) {
            if statusCode == 403 {
                // 令牌过期，尝试刷新
                Logger.info("Token expired, attempting to refresh...")
                if let newToken = try? await EVELogin.shared.refreshToken(refreshToken: character.token.refresh_token, force: true) {
                    // 保存新token
                    EVELogin.shared.saveAuthInfo(token: newToken, character: character.character)
                    // 使用新令牌重试
                    request.setValue("Bearer \(newToken.access_token)", forHTTPHeaderField: "Authorization")
                    let data = try await fetchData(from: url, request: request)
                    Logger.info("Token refreshed.")
                    return try JSONDecoder().decode(T.self, from: data)
                } else {
                    Logger.info("New Token also failed ?...")
                    throw NetworkError.tokenExpired
                }
            }
            throw NetworkError.httpError(statusCode: statusCode)
        }
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
    case tokenExpired
    case unauthed
    
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
        case .tokenExpired:
            return NSLocalizedString("Network_Error_Token_Expired", comment: "")
        case .unauthed:
            return NSLocalizedString("Network_Error_Unauthed", comment: "")
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
        
        // 只检查 StaticDataSet 目录
        let staticDataSetPath = StaticResourceManager.shared.getStaticDataSetPath()
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: staticDataSetPath,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            
            for url in contents {
                let filename = url.lastPathComponent
                // 跳过系统缓存文件和隐藏文件
                if filename.starts(with: "Cache.db") || filename.starts(with: ".") {
                    continue
                }
                
                // 如果是目录，递归计算大小
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                    if isDirectory.boolValue {
                        if let enumerator = fileManager.enumerator(at: url, 
                                                                 includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                                                                 options: [.skipsHiddenFiles]) {
                            for case let fileURL as URL in enumerator {
                                if let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path) {
                                    if let fileSize = attributes[.size] as? Int64 {
                                        totalSize += fileSize
                                        count += 1
                                    }
                                    if let modificationDate = attributes[.modificationDate] as? Date {
                                        if lastModified == nil || modificationDate > lastModified! {
                                            lastModified = modificationDate
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        // 是文件，直接获取大小
                        if let attributes = try? fileManager.attributesOfItem(atPath: url.path) {
                            if let fileSize = attributes[.size] as? Int64 {
                                totalSize += fileSize
                                count += 1
                            }
                            if let modificationDate = attributes[.modificationDate] as? Date {
                                if lastModified == nil || modificationDate > lastModified! {
                                    lastModified = modificationDate
                                }
                            }
                        }
                    }
                }
            }
        } catch {
            Logger.error("Error calculating cache size: \(error)")
        }
        
        return CacheInfo(size: totalSize, count: count, lastModified: lastModified)
    }
    
    // 清理特定资源的缓存
    func clearCache(for resource: EVEResource) {
        // 清理内存缓存
        let cacheKey = resource.cacheKey
        dataCache.removeObject(forKey: cacheKey as NSString)
        dataCacheKeys.remove(cacheKey)
        
        // 清理文件缓存（只清理 StaticDataSet 目录中的文件）
        let fileManager = FileManager.default
        let fileURL = StaticResourceManager.shared.getStaticDataSetPath().appendingPathComponent(resource.fileName)
        
        try? fileManager.removeItem(at: fileURL)
        Logger.info("Cleared local cache for resource: \(resource)")
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
        
        // 检查文件缓存（只检查 StaticDataSet 目录）
        let fileManager = FileManager.default
        let fileURL = StaticResourceManager.shared.getStaticDataSetPath().appendingPathComponent(resource.fileName)
        
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
        
        return (inMemory, inFile, age)
    }
    
    // 格式化缓存大小
    static func formatFileSize(_ size: Int64) -> String {
        let units = ["bytes", "KB", "MB", "GB"]
        var size = Double(size)
        var unitIndex = 0
        
        while size >= 1024 && unitIndex < units.count - 1 {
            size /= 1024
            unitIndex += 1
        }
        
        // 根据大小使用不同的小数位数
        let formattedSize: String
        if unitIndex == 0 {
            formattedSize = String(format: "%.0f", size) // 字节不显示小数
        } else if size >= 100 {
            formattedSize = String(format: "%.0f", size) // 大于100时不显示小数
        } else if size >= 10 {
            formattedSize = String(format: "%.1f", size) // 大于10时显示1位小数
        } else {
            formattedSize = String(format: "%.2f", size) // 其他情况显示2位小数
        }
        
        return "\(formattedSize) \(units[unitIndex])"
    }
}

// 技能数据模型
struct CharacterSkill: Codable {
    let active_skill_level: Int
    let skill_id: Int
    let skillpoints_in_skill: Int
    let trained_skill_level: Int
}

struct CharacterSkillsResponse: Codable {
    let skills: [CharacterSkill]
    let total_sp: Int
    let unallocated_sp: Int
}
