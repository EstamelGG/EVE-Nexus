import Foundation
import SwiftUI

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
    case serverStatus
    
    // 由于有关联值，我们需要手动实现 allCases
    static var allCases: [EVEResource] {
        return [
            .sovereignty,
            .incursions,
            .sovereigntyCampaigns,
            .serverStatus
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
    private let retrier: RequestRetrier
    private let rateLimiter: RateLimiter
    private let session: URLSession
    
    // 技能队列数据模型
    struct SkillQueueItem: Codable {
        let finish_date: String?
        let start_date: String?
        let finished_level: Int
        let level_end_sp: Int
        let level_start_sp: Int
        let queue_position: Int
        let skill_id: Int
        let training_start_sp: Int
        
        // 判断当前时间点是否在训练这个技能
        var isCurrentlyTraining: Bool {
            guard let finishDateString = finish_date,
                  let startDateString = start_date else {
                return false
            }
            
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime]
            
            guard let finishDate = dateFormatter.date(from: finishDateString),
                  let startDate = dateFormatter.date(from: startDateString) else {
                return false
            }
            
            let now = Date()
            return now >= startDate && now <= finishDate
        }
        
        // 计算训练进度
        var progress: Double {
            guard let finishDateString = finish_date,
                  let startDateString = start_date else {
                return 0
            }
            
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime]
            
            guard let finishDate = dateFormatter.date(from: finishDateString),
                  let startDate = dateFormatter.date(from: startDateString) else {
                return 0
            }
            
            let now = Date()
            
            // 如果还没开始训练，进度为0
            if now < startDate {
                return 0
            }
            
            // 如果已经完成训练，进度为1
            if now > finishDate {
                return 1
            }
            
            // 计算时间进度比例
            let totalTrainingTime = finishDate.timeIntervalSince(startDate) // A
            let trainedTime = now.timeIntervalSince(startDate) // B
            let timeProgress = trainedTime / totalTrainingTime
            
            // 计算剩余需要训练的技能点
            let remainingSP = level_end_sp - training_start_sp // C
            
            // 计算当前已训练的技能点
            let trainedSP = Double(remainingSP) * timeProgress
            
            // 计算总进度
            let totalLevelSP = level_end_sp - level_start_sp
            let currentTotalTrainedSP = Double(training_start_sp - level_start_sp) + trainedSP
            
            return currentTotalTrainedSP / Double(totalLevelSP)
        }
        
        var remainingTime: TimeInterval? {
            guard let finishDateString = finish_date else { return nil }
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime]
            
            guard let finishDate = dateFormatter.date(from: finishDateString) else { return nil }
            return finishDate.timeIntervalSince(Date())
        }
        
        var skillLevel: String {
            let romanNumerals = ["I", "II", "III", "IV", "V"]
            return romanNumerals[finished_level - 1]
        }
    }
    
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
    
    // 服务器状态缓存
    private var serverStatusCache: CachedData<ServerStatus>?
    
    private override init() {
        self.retrier = RequestRetrier()
        self.rateLimiter = RateLimiter()
        self.session = URLSession.shared
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
        try await rateLimiter.waitForPermission()
        
        var request = customRequest ?? URLRequest(url: url)
        if forceRefresh {
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        }
        
        return try await retrier.execute {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                Logger.error("HTTP error: \(url.absoluteString) [\(httpResponse.statusCode)]")
                throw NetworkError.httpError(statusCode: httpResponse.statusCode)
            }
            
            return data
        }
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
            .appendingPathComponent("FactionIcons")
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
    
    // 修改图片缓存相关的方法
    private func getCachedImage(forKey key: String) async -> UIImage? {
        return await withCheckedContinuation { continuation in
            Task { @NetworkManagerActor in
                if let cached = imageCache.object(forKey: key as NSString)?.data {
                    continuation.resume(returning: cached)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    private func setCachedImage(_ image: UIImage, forKey key: String) async {
        await withCheckedContinuation { continuation in
            Task { @NetworkManagerActor in
                imageCache.setObject(CachedData(data: image, timestamp: Date()), forKey: key as NSString)
                imageCacheKeys.insert(key)
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
        
        // 1. 检查内存缓存
        let cacheKey = "item_\(typeID)"
        if let cached = await getCachedImage(forKey: cacheKey) {
            return cached
        }
        
        // 2. 检查文件缓存
        if let data = StaticResourceManager.shared.getNetRender(typeId: typeID),
           let image = UIImage(data: data) {
            // 更新内存缓存
            await setCachedImage(image, forKey: cacheKey)
            return image
        }
        
        // 3. 从网络获取
        let data = try await fetchData(from: url)
        guard let image = UIImage(data: data) else {
            throw NetworkError.invalidImageData
        }
        
        // 4. 更新缓存
        await setCachedImage(image, forKey: cacheKey)
        try? StaticResourceManager.shared.saveNetRender(data, typeId: typeID)
        
        return image
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
        return await withCheckedContinuation { continuation in
            Task { @NetworkManagerActor in
                if let cached = dataCache.object(forKey: key as NSString) {
                    continuation.resume(returning: cached)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    private func setCachedData<T>(_ data: T, forKey key: String) async {
        await withCheckedContinuation { continuation in
            Task { @NetworkManagerActor in
                dataCache.setObject(CachedData(data: data, timestamp: Date()), forKey: key as NSString)
                dataCacheKeys.insert(key)
                continuation.resume()
            }
        }
    }
    
    // 在设置缓存时添加键
    private func setDataCache<T: Encodable>(_ data: T, forKey key: String) async {
        await setCachedData(data, forKey: key)
    }
    
    // 获取内存缓存信息
    func getMemoryCacheInfo() async -> CacheInfo {
        return await withCheckedContinuation { continuation in
            Task { @NetworkManagerActor in
                let fileManager = FileManager.default
                let staticDataSetPath = StaticResourceManager.shared.getStaticDataSetPath()
                var totalSize: Int64 = 0
                var count = 0
                var lastModified: Date? = nil
                
                if fileManager.fileExists(atPath: staticDataSetPath.path) {
                    if let enumerator = fileManager.enumerator(at: staticDataSetPath, 
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
                }
                
                continuation.resume(returning: CacheInfo(size: totalSize, count: count, lastModified: lastModified))
            }
        }
    }
    
    // 获取主权数据
    func fetchSovereigntyData(forceRefresh: Bool = false) async throws -> [SovereigntyData] {
        // 如果不是强制刷新，尝试从本地获取
        if !forceRefresh {
            if let sovereignty = StaticResourceManager.shared.getSovereignty() {
                return sovereignty
            }
        }
        
        // 从网络获取数据
        let request = ResourceRequest<[SovereigntyData]>(
            resource: EVEResource.sovereignty,
            parameters: ["datasource": "tranquility"],
            cacheStrategy: .memoryOnly,  // 只使用内存缓存
            forceRefresh: true
        )
        
        let sovereignty = try await fetchResource(request)
        
        // 保存到本地
        try StaticResourceManager.shared.saveSovereignty(sovereignty)
        
        return sovereignty
    }
    
    // 获取主权战役数据
    func fetchSovereigntyCampaigns(forceRefresh: Bool = false) async throws -> [SovereigntyCampaign] {
        // 如果不是强制刷新，尝试从本地获取
        if !forceRefresh {
            if let campaigns = StaticResourceManager.shared.getSovereigntyCampaigns() {
                return campaigns
            }
        }
        
        // 从网络获取数据
        let request = ResourceRequest<[SovereigntyCampaign]>(
            resource: EVEResource.sovereigntyCampaigns,
            parameters: ["datasource": "tranquility"],
            cacheStrategy: .memoryOnly,  // 只使用内存缓存
            forceRefresh: true
        )
        
        let campaigns = try await fetchResource(request)
        
        // 保存到本地
        try StaticResourceManager.shared.saveSovereigntyCampaigns(campaigns)
        
        return campaigns
    }
    
    // 获取入侵数据
    func fetchIncursions(forceRefresh: Bool = false) async throws -> [Incursion] {
        // 如果不是强制刷新，尝试从本地获取
        if !forceRefresh {
            if let incursions = StaticResourceManager.shared.getIncursions() {
                return incursions
            }
        }
        
        // 从网络获取数据
        let request = ResourceRequest<[Incursion]>(
            resource: EVEResource.incursions,
            parameters: ["datasource": "tranquility"],
            cacheStrategy: .memoryOnly,  // 只使用内存缓存
            forceRefresh: true
        )
        
        let incursions = try await fetchResource(request)
        
        // 保存到本地
        try StaticResourceManager.shared.saveIncursions(incursions)
        
        return incursions
    }
    
    // 清除所有缓存
    func clearAllCaches() async {
        await withCheckedContinuation { continuation in
            Task { @NetworkManagerActor in
                // 清除内存缓存
                dataCache.removeAllObjects()
                dataCacheKeys.removeAll()
                
                imageCache.removeAllObjects()
                imageCacheKeys.removeAll()
                
                serverStatusCache = nil
                
                continuation.resume()
            }
        }
        
        // 清除文件缓存
        await clearFileCaches()
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
        let urlString = "https://images.evetech.net/alliances/\(allianceID)/logo?size=64"
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
            let fileURL = StaticResourceManager.shared.getCharacterPortraitsPath()
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
            let fileURL = StaticResourceManager.shared.getCharacterPortraitsPath()
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
    
    // 获取技能队列信息
    func fetchSkillQueue(characterId: Int) async throws -> [SkillQueueItem] {
        // 检查 UserDefaults 缓存
        let queueCacheKey = "character_\(characterId)_skillqueue"
        let queueUpdateTimeKey = "character_\(characterId)_skillqueue_update_time"
        
        // 如果缓存存在且未过期（30分钟），直接返回缓存数据
        if let cachedData = UserDefaults.standard.data(forKey: queueCacheKey),
           let lastUpdateTime = UserDefaults.standard.object(forKey: queueUpdateTimeKey) as? Date,
           Date().timeIntervalSince(lastUpdateTime) < 30 * 60 { // 30 分钟缓存
            do {
                let queue = try JSONDecoder().decode([SkillQueueItem].self, from: cachedData)
                Logger.info("使用缓存的技能队列数据 - 角色ID: \(characterId)")
                return queue
            } catch {
                Logger.error("解码缓存的技能队列数据失败: \(error)")
            }
        }
        
        // 如果没有缓存或缓存已过期，从网络获取
        Logger.info("在线获取技能队列数据 - 角色ID: \(characterId)")
        let queue: [SkillQueueItem] = try await fetchDataWithToken(
            characterId: characterId,
            endpoint: "/characters/\(characterId)/skillqueue/"
        )
        
        // 更新缓存
        if let encodedData = try? JSONEncoder().encode(queue) {
            UserDefaults.standard.set(encodedData, forKey: queueCacheKey)
            UserDefaults.standard.set(Date(), forKey: queueUpdateTimeKey)
        }
        
        return queue
    }
    
    // 获取技能名称
    nonisolated static func getSkillName(skillId: Int, databaseManager: DatabaseManager) -> String? {
        let skillQuery = "SELECT name FROM types WHERE type_id = ?"
        guard case .success(let rows) = databaseManager.executeQuery(skillQuery, parameters: [skillId]),
              let row = rows.first,
              let skillName = row["name"] as? String else {
            return nil
        }
        return skillName
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
        try await rateLimiter.waitForPermission()
        
        let token = try await TokenManager.shared.getToken(for: characterId)
        let urlString = "https://esi.evetech.net/latest\(endpoint)"
        Logger.info("ESI请求: GET \(urlString)")
        
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token.access_token.prefix(32))...", forHTTPHeaderField: "Authorization")
        request.setValue("tranquility", forHTTPHeaderField: "datasource")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        Logger.info("ESI请求头: Authorization: Bearer \(token.access_token.prefix(32))...")
        
        return try await retrier.execute {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
            }
            
            Logger.info("ESI响应: \(httpResponse.statusCode) - \(endpoint)")
            
            if httpResponse.statusCode == 200 {
                do {
                    let decodedData = try JSONDecoder().decode(T.self, from: data)
                    return decodedData
                } catch {
                    Logger.error("ESI响应解析失败: \(error)")
                    throw NetworkError.decodingError(error)
                }
            } else {
                if let errorString = String(data: data, encoding: .utf8) {
                    Logger.error("ESI错误响应: \(errorString)")
                }
                throw NetworkError.httpError(statusCode: httpResponse.statusCode)
            }
        }
    }
    
    // 角色公开信息数据模型
    struct CharacterPublicInfo: Codable {
        let alliance_id: Int?
        let birthday: String
        let bloodline_id: Int
        let corporation_id: Int
        let description: String
        let gender: String
        let name: String
        let race_id: Int
        let security_status: Double
        let title: String?
    }
    
    // 联盟信息数据模型
    struct AllianceInfo: Codable {
        let name: String
        let ticker: String
        let creator_corporation_id: Int
        let creator_id: Int
        let date_founded: String
        let executor_corporation_id: Int
    }
    
    // 军团信息数据模型
    struct CorporationInfo: Codable {
        let name: String
        let ticker: String
        let member_count: Int
        let ceo_id: Int
        let creator_id: Int
        let date_founded: String?
        let description: String?
        let tax_rate: Double
        let url: String?
        let alliance_id: Int?
    }
    
    // 获取角色公开信息
    func fetchCharacterPublicInfo(characterId: Int, forceRefresh: Bool = false) async throws -> CharacterPublicInfo {
        let cacheKey = "character_public_info_\(characterId)"
        let cacheTimeKey = "character_public_info_\(characterId)_time"
        
        // 检查缓存是否存在且未过期（7天）
        if !forceRefresh,
           let cachedData = UserDefaults.standard.data(forKey: cacheKey),
           let lastUpdateTime = UserDefaults.standard.object(forKey: cacheTimeKey) as? Date,
           Date().timeIntervalSince(lastUpdateTime) < 7 * 24 * 3600 {
            do {
                let info = try JSONDecoder().decode(CharacterPublicInfo.self, from: cachedData)
                Logger.info("使用缓存的角色公开信息 - 角色ID: \(characterId)")
                return info
            } catch {
                Logger.error("解析缓存的角色公开信息失败: \(error)")
            }
        }
        
        // 从网络获取数据
        let urlString = "https://esi.evetech.net/latest/characters/\(characterId)/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        
        let data = try await fetchData(from: url)
        let info = try JSONDecoder().decode(CharacterPublicInfo.self, from: data)
        
        // 更新缓存
        UserDefaults.standard.set(data, forKey: cacheKey)
        UserDefaults.standard.set(Date(), forKey: cacheTimeKey)
        
        Logger.info("成功获取角色公开信息 - 角色ID: \(characterId)")
        return info
    }
    
    // 获取联盟信息
    func fetchAllianceInfo(allianceId: Int, forceRefresh: Bool = false) async throws -> AllianceInfo {
        let cacheKey = "alliance_info_\(allianceId)"
        let cacheTimeKey = "alliance_info_\(allianceId)_time"
        
        // 检查缓存
        if !forceRefresh,
           let cachedData = UserDefaults.standard.data(forKey: cacheKey),
           let lastUpdateTime = UserDefaults.standard.object(forKey: cacheTimeKey) as? Date,
           Date().timeIntervalSince(lastUpdateTime) < 7 * 24 * 3600 {
            do {
                let info = try JSONDecoder().decode(AllianceInfo.self, from: cachedData)
                Logger.info("使用缓存的联盟信息 - 联盟ID: \(allianceId)")
                return info
            } catch {
                Logger.error("解析缓存的联盟信息失败: \(error)")
            }
        }
        
        // 从网络获取数据
        let urlString = "https://esi.evetech.net/latest/alliances/\(allianceId)/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        
        let data = try await fetchData(from: url)
        let info = try JSONDecoder().decode(AllianceInfo.self, from: data)
        
        // 更新缓存
        UserDefaults.standard.set(data, forKey: cacheKey)
        UserDefaults.standard.set(Date(), forKey: cacheTimeKey)
        
        Logger.info("成功获取联盟信息 - 联盟ID: \(allianceId)")
        return info
    }
    
    // 获取军团信息
    func fetchCorporationInfo(corporationId: Int, forceRefresh: Bool = false) async throws -> CorporationInfo {
        let cacheKey = "corporation_info_\(corporationId)"
        let cacheTimeKey = "corporation_info_\(corporationId)_time"
        
        // 检查缓存
        if !forceRefresh,
           let cachedData = UserDefaults.standard.data(forKey: cacheKey),
           let lastUpdateTime = UserDefaults.standard.object(forKey: cacheTimeKey) as? Date,
           Date().timeIntervalSince(lastUpdateTime) < 7 * 24 * 3600 {
            do {
                let info = try JSONDecoder().decode(CorporationInfo.self, from: cachedData)
                Logger.info("使用缓存的军团信息 - 军团ID: \(corporationId)")
                return info
            } catch {
                Logger.error("解析缓存的军团信息失败: \(error)")
            }
        }
        
        // 从网络获取数据
        let urlString = "https://esi.evetech.net/latest/corporations/\(corporationId)/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        
        let data = try await fetchData(from: url)
        let info = try JSONDecoder().decode(CorporationInfo.self, from: data)
        
        // 更新缓存
        UserDefaults.standard.set(data, forKey: cacheKey)
        UserDefaults.standard.set(Date(), forKey: cacheTimeKey)
        
        Logger.info("成功获取军团信息 - 军团ID: \(corporationId)")
        return info
    }
    
    // 获取军团图标
    func fetchCorporationLogo(corporationId: Int) async throws -> UIImage {
        let urlString = "https://images.evetech.net/corporations/\(corporationId)/logo?size=64"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        
        return try await fetchCachedImage(
            cacheKey: "corporation_\(corporationId)",
            filename: "corporation_\(corporationId).png",
            cacheDuration: StaticResourceManager.shared.ALLIANCE_ICON_CACHE_DURATION,
            imageURL: url
        )
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
    case invalidToken(String)
    case maxRetriesExceeded
    case authenticationError(String)
    case decodingError(Error)
    
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
        case .invalidToken(let reason):
            return "Token无效: \(reason)"
        case .maxRetriesExceeded:
            return "已达到最大重试次数"
        case .authenticationError(let reason):
            return "认证出错: \(reason)"
        case .decodingError(let error):
            return "解码响应数据失败: \(error)"
        }
    }
}

extension NetworkManager: NSCacheDelegate {
    nonisolated func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject obj: Any) {
        // 当缓存项被移除时，从对应的键集合中移除键
        Task { @NetworkManagerActor in
            if cache === self.dataCache {
                if let key = obj as? NSString {
                    self.dataCacheKeys.remove(key as String)
                }
            } else if cache === self.imageCache {
                if let key = obj as? NSString {
                    self.imageCacheKeys.remove(key as String)
                }
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

// 添加 RequestRetrier 类
class RequestRetrier {
    private let maxAttempts: Int
    private let retryDelay: TimeInterval
    
    init(maxAttempts: Int = 3, retryDelay: TimeInterval = 1.0) {
        self.maxAttempts = maxAttempts
        self.retryDelay = retryDelay
    }
    
    func execute<T>(_ operation: () async throws -> T) async throws -> T {
        var attempts = 0
        var lastError: Error?
        
        while attempts < maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                
                // 判断是否应该重试
                guard shouldRetry(error) else { throw error }
                
                attempts += 1
                if attempts < maxAttempts {
                    // 使用指数退避策略计算延迟时间
                    let delay = UInt64(retryDelay * pow(2.0, Double(attempts))) * 1_000_000_000
                    try await Task.sleep(nanoseconds: delay)
                }
            }
        }
        
        throw lastError ?? NetworkError.maxRetriesExceeded
    }
    
    private func shouldRetry(_ error: Error) -> Bool {
        if case NetworkError.httpError(let statusCode) = error {
            // 对于特定状态码进行重试
            return [500, 502, 503, 504].contains(statusCode)
        }
        return false
    }
}

// 添加 RateLimiter 类
actor RateLimiter {
    private var tokens: Int
    private let maxTokens: Int
    private var lastRefill: Date
    private let refillRate: Double // tokens per second
    
    init(maxTokens: Int = 150, refillRate: Double = 50) {
        self.maxTokens = maxTokens
        self.tokens = maxTokens
        self.lastRefill = Date()
        self.refillRate = refillRate
    }
    
    private func refillTokens() {
        let now = Date()
        let timePassed = now.timeIntervalSince(lastRefill)
        let tokensToAdd = Int(timePassed * refillRate)
        
        tokens = min(maxTokens, tokens + tokensToAdd)
        lastRefill = now
    }
    
    func waitForPermission() async throws {
        while tokens <= 0 {
            refillTokens()
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
        tokens -= 1
    }
}
