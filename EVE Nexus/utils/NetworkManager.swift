import Foundation
import SwiftUI

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
    
    // 通用的数据获取函数
    func fetchData(from url: URL, headers: [String: String]? = nil, forceRefresh: Bool = false) async throws -> Data {
        try await rateLimiter.waitForPermission()
        
        // 创建请求
        var request = URLRequest(url: url)
        if forceRefresh {
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        }
        
        // 添加基本请求头
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("tranquility", forHTTPHeaderField: "datasource")
        
        // 添加自定义请求头
        headers?.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        return try await retrier.execute {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                Logger.error("无效的HTTP响应 - URL: \(url.absoluteString)")
                throw NetworkError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                // 添加错误日志记录
                if let responseBody = String(data: data, encoding: .utf8) {
                    Logger.error("HTTP请求失败 - URL: \(url.absoluteString)")
                    Logger.error("状态码: \(httpResponse.statusCode)")
                    Logger.error("响应体: \(responseBody)")
                } else {
                    Logger.error("HTTP请求失败 - URL: \(url.absoluteString)")
                    Logger.error("状态码: \(httpResponse.statusCode)")
                    Logger.error("响应体无法解析")
                }
                throw NetworkError.httpError(statusCode: httpResponse.statusCode)
            }
            
            return data
        }
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
                    Logger.info("Deleting file: \(url.lastPathComponent) (Size: \(FormatUtil.formatFileSize(fileSize)))")
                    try? FileManager.default.removeItem(at: url)
                }
            }
            
            Logger.info("Finished clearing StaticDataSet directory")
        } catch {
            try? FileManager.default.createDirectory(at: staticDataSetPath, withIntermediateDirectories: true)
            Logger.error("Error accessing StaticDataSet directory: \(error)")
        }
    }
    
    // 专门用于需访问令牌的请求
    func fetchDataWithToken(from url: URL, characterId: Int, headers: [String: String]? = nil) async throws -> Data {
        // 获取角色的token
        let token = try await TokenManager.shared.getToken(for: characterId)
        
        // 创建基本请求头
        var allHeaders: [String: String] = [
            "Authorization": "Bearer \(token.access_token)",
            "datasource": "tranquility",
            "Accept": "application/json"
        ]
        
        // 添加自定义请求头
        headers?.forEach { key, value in
            allHeaders[key] = value
        }
        
        // 使用基础的 fetchData 方法获取数据
        return try await fetchData(from: url, headers: allHeaders)
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
