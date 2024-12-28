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
    
    // 添加并发控制信号量
    private let concurrentSemaphore = DispatchSemaphore(value: 8)
    
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
    func fetchData(
        from url: URL,
        method: String = "GET",
        body: Data? = nil,
        headers: [String: String]? = nil,
        forceRefresh: Bool = false,
        timeout: TimeInterval = 15.0,
        noRetryKeywords: [String]? = nil
    ) async throws -> Data {
        // 等待信号量
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                self.concurrentSemaphore.wait()
                continuation.resume()
            }
        }
        
        defer {
            // 完成后释放信号量
            concurrentSemaphore.signal()
        }
        
        try await rateLimiter.waitForPermission()
        
        // 创建请求
        var request = URLRequest(url: url)
        request.httpMethod = method
        
        if forceRefresh {
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        }
        
        // 设置超时时间
        request.timeoutInterval = timeout
        
        // 添加基本请求头
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("tranquility", forHTTPHeaderField: "datasource")
        
        // 如果是 POST 请求且有请求体，设置 Content-Type
        if method == "POST" && body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        
        // 添加自定义请求头
        headers?.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        // 设置请求体
        if let body = body {
            request.httpBody = body
        }
        
        return try await retrier.execute(noRetryKeywords: noRetryKeywords) {
            Logger.info("HTTP \(method) Request to: \(url)")
            let (data, response) = try await self.session.data(for: request)
            
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
                    
                    // 将响应体包含在错误中
                    throw NetworkError.httpError(statusCode: httpResponse.statusCode, message: responseBody)
                } else {
                    Logger.error("HTTP请求失败 - URL: \(url.absoluteString)")
                    Logger.error("状态码: \(httpResponse.statusCode)")
                    Logger.error("响应体无法解析")
                    throw NetworkError.httpError(statusCode: httpResponse.statusCode)
                }
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
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let staticDataSetPath = paths[0].appendingPathComponent("StaticDataSet")
        
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
    func fetchDataWithToken(
        from url: URL,
        characterId: Int,
        headers: [String: String]? = nil,
        noRetryKeywords: [String]? = nil
    ) async throws -> Data {
        // 获取角色的token
        let token = try await AuthTokenManager.shared.getAccessToken(for: characterId)
        
        // 创建基本请求头
        var allHeaders: [String: String] = [
            "Authorization": "Bearer \(token)",
            "datasource": "tranquility",
            "Accept": "application/json"
        ]
        
        // 添加自定义请求头
        headers?.forEach { key, value in
            allHeaders[key] = value
        }
        Logger.debug("Fetch data with token \(token.prefix(32))")
        // 使用基础的 fetchData 方法获取数据
        return try await fetchData(from: url, headers: allHeaders, noRetryKeywords: noRetryKeywords)
    }

    // POST请求带Token的方法
    func postDataWithToken(
        to url: URL,
        body: Data,
        characterId: Int,
        headers: [String: String]? = nil
    ) async throws -> Data {
        // 获取角色的token
        let token = try await AuthTokenManager.shared.getAccessToken(for: characterId)
        
        // 创建基本请求头
        var allHeaders: [String: String] = [
            "Authorization": "Bearer \(token)",
            "datasource": "tranquility",
            "Accept": "application/json",
            "Content-Type": "application/json"
        ]
        
        // 添加自定义请求头
        headers?.forEach { key, value in
            allHeaders[key] = value
        }
        
        // 使用基础的 fetchData 方法获取数据
        return try await fetchData(
            from: url,
            method: "POST",
            body: body,
            headers: allHeaders
        )
    }
}

// 网络错误枚举
enum NetworkError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, message: String? = nil)
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
        case .httpError(let statusCode, let message):
            if let message = message {
                return "\(String(format: NSLocalizedString("Network_Error_HTTP_Error", comment: ""), statusCode)): \(message)"
            }
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

// 添加 RequestRetrier 类
class RequestRetrier {
    private let timeouts: [TimeInterval]
    private let retryDelay: TimeInterval
    private var noRetryKeywords: [String]
    
    init(timeouts: [TimeInterval] = [1.5, 5.0, 10.0], retryDelay: TimeInterval = 1.0, noRetryKeywords: [String] = []) {
        self.timeouts = timeouts
        self.retryDelay = retryDelay
        self.noRetryKeywords = noRetryKeywords
    }
    
    func execute<T>(
        noRetryKeywords: [String]? = nil,
        _ operation: @escaping () async throws -> T
    ) async throws -> T {
        // 合并默认的和临时的不重试关键词
        let keywords = Set(self.noRetryKeywords + (noRetryKeywords ?? []))
        var attempts = 0
        var lastError: Error?
        
        while attempts < timeouts.count {
            do {
                // 设置当前尝试的超时时间
                let timeout = timeouts[attempts]
                Logger.info("尝试第 \(attempts + 1) 次请求，超时时间: \(timeout)秒")
                
                return try await withTimeout(timeout) {
                    try await operation()
                }
            } catch {
                lastError = error
                
                // 检查响应中是否包含不重试的关键词
                if let networkError = error as? NetworkError,
                   case .httpError(_, let message) = networkError,
                   let errorMessage = message {
                    if keywords.contains(where: { errorMessage.contains($0) }) {
                        throw error // 如果包含关键词，直接抛出错误不重试
                    }
                }
                
                // 判断是否应该重试
                guard shouldRetry(error) else { throw error }
                
                attempts += 1
                if attempts < timeouts.count {
                    let delay = UInt64(retryDelay * pow(2.0, Double(attempts))) * 1_000_000_000
                    try await Task.sleep(nanoseconds: delay)
                }
            }
        }
        
        throw lastError ?? NetworkError.maxRetriesExceeded
    }
    
    private func withTimeout<T>(_ timeout: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            // 添加实际操作任务
            group.addTask {
                try await operation()
            }
            
            // 添加超时任务
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw NetworkError.httpError(statusCode: 408, message: "请求超时")
            }
            
            defer { 
                group.cancelAll()
            }
            
            // 等待第一个完成的任务
            do {
                let result = try await group.next() ?? {
                    throw NetworkError.httpError(statusCode: 408, message: "请求超时")
                }()
                return result
            } catch {
                // 取消所有任务并抛出错误
                group.cancelAll()
                throw error
            }
        }
    }
    
    private func shouldRetry(_ error: Error) -> Bool {
        if case NetworkError.httpError(let statusCode, _) = error {
            return [408, 500, 502, 503, 504].contains(statusCode)
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
