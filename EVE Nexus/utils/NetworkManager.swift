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
    var regionID: Int = 10_000_002  // 默认为 The Forge
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
    private let cacheQueue = DispatchQueue(
        label: "com.eve.nexus.network.cache", attributes: .concurrent
    )
    private let imageQueue = DispatchQueue(
        label: "com.eve.nexus.network.image", attributes: .concurrent
    )
    private let marketQueue = DispatchQueue(
        label: "com.eve.nexus.network.market", attributes: .concurrent
    )

    // 添加并发控制信号量
    private let concurrentSemaphore = DispatchSemaphore(value: 8)

    override private init() {
        retrier = RequestRetrier()
        rateLimiter = RateLimiter()
        session = URLSession.shared
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
        noRetryKeywords: [String]? = nil,
        timeouts: [TimeInterval]? = nil
    ) async throws -> Data {
        // 等待信号量
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
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
            // 添加请求体日志
            if method == "POST", let jsonString = String(data: body, encoding: .utf8) {
                Logger.debug("POST Request Body: \(jsonString)")
            }
        }

        return try await retrier.execute(noRetryKeywords: noRetryKeywords, timeouts: timeouts) {
            Logger.info("HTTP \(method) Request to: \(url)")

            // 使用Task.detached确保在后台线程执行，并设置合适的QoS
            return try await Task.detached(priority: .userInitiated) {
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
                        throw NetworkError.httpError(
                            statusCode: httpResponse.statusCode, message: responseBody
                        )
                    } else {
                        Logger.error("HTTP请求失败 - URL: \(url.absoluteString)")
                        Logger.error("状态码: \(httpResponse.statusCode)")
                        Logger.error("响应体无法解析")
                        throw NetworkError.httpError(statusCode: httpResponse.statusCode)
                    }
                }
                Logger.debug("URL: \(url.absoluteString), Code: \(httpResponse.statusCode)")
                return data
            }.value
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
            let contents = try fileManager.contentsOfDirectory(
                at: staticDataSetPath, includingPropertiesForKeys: nil
            )

            for url in contents {
                if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                    let fileSize = attributes[.size] as? Int64
                {
                    Logger.info(
                        "Deleting file: \(url.lastPathComponent) (Size: \(FormatUtil.formatFileSize(fileSize)))"
                    )
                    try? FileManager.default.removeItem(at: url)
                }
            }

            Logger.info("Finished clearing StaticDataSet directory")
        } catch {
            try? FileManager.default.createDirectory(
                at: staticDataSetPath, withIntermediateDirectories: true
            )
            Logger.error("Error accessing StaticDataSet directory: \(error)")
        }
    }

    // 专门用于需访问令牌的请求
    func fetchDataWithToken(
        from url: URL,
        characterId: Int,
        headers: [String: String]? = nil,
        noRetryKeywords: [String]? = nil,
        timeouts: [TimeInterval]? = nil
    ) async throws -> Data {
        // 获取角色的token
        let token = try await AuthTokenManager.shared.getAccessToken(for: characterId)

        // 创建基本请求头
        var allHeaders: [String: String] = [
            "Authorization": "Bearer \(token)",
            "datasource": "tranquility",
            "Accept": "application/json",
        ]

        // 添加自定义请求头
        headers?.forEach { key, value in
            allHeaders[key] = value
        }
        Logger.debug("Fetch data with token \(token.prefix(32))")
        // 使用基础的 fetchData 方法获取数据
        return try await fetchData(
            from: url,
            headers: allHeaders,
            noRetryKeywords: noRetryKeywords,
            timeouts: timeouts
        )
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
            "Content-Type": "application/json",
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

    // DELETE请求带Token的方法
    func deleteDataWithToken(
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
            "Accept": "application/json",
        ]

        // 添加自定义请求头
        headers?.forEach { key, value in
            allHeaders[key] = value
        }

        // 使用基础的 fetchData 方法发送DELETE请求
        return try await fetchData(
            from: url,
            method: "DELETE",
            headers: allHeaders,
            noRetryKeywords: noRetryKeywords
        )
    }

    // 专门用于需访问令牌的请求，并返回响应头中的页数信息
    func fetchDataWithTokenAndPages(
        from url: URL,
        characterId: Int,
        headers: [String: String]? = nil,
        noRetryKeywords: [String]? = nil,
        timeouts: [TimeInterval]? = nil
    ) async throws -> (Data, Int) {
        // 获取角色的token
        let token = try await AuthTokenManager.shared.getAccessToken(for: characterId)

        // 创建基本请求头
        var allHeaders: [String: String] = [
            "Authorization": "Bearer \(token)",
            "datasource": "tranquility",
            "Accept": "application/json",
        ]

        // 添加自定义请求头
        headers?.forEach { key, value in
            allHeaders[key] = value
        }

        // 创建请求
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        // 添加请求头
        for (key, value) in allHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        return try await retrier.execute(noRetryKeywords: noRetryKeywords, timeouts: timeouts) {
            Logger.info("HTTP GET Request to: \(url)")

            return try await Task.detached(priority: .userInitiated) {
                let (data, response) = try await self.session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    Logger.error("无效的HTTP响应 - URL: \(url.absoluteString)")
                    throw NetworkError.invalidResponse
                }

                guard httpResponse.statusCode == 200 else {
                    if let responseBody = String(data: data, encoding: .utf8) {
                        Logger.error("HTTP请求失败 - URL: \(url.absoluteString)")
                        Logger.error("状态码: \(httpResponse.statusCode)")
                        Logger.error("响应体: \(responseBody)")
                        throw NetworkError.httpError(
                            statusCode: httpResponse.statusCode, message: responseBody
                        )
                    } else {
                        Logger.error("HTTP请求失败 - URL: \(url.absoluteString)")
                        Logger.error("状态码: \(httpResponse.statusCode)")
                        Logger.error("响应体无法解析")
                        throw NetworkError.httpError(statusCode: httpResponse.statusCode)
                    }
                }

                // 从响应头中获取总页数
                let totalPages = Int(httpResponse.value(forHTTPHeaderField: "X-Pages") ?? "1") ?? 1
                Logger.info("获取到总页数: \(totalPages)")

                return (data, totalPages)
            }.value
        }
    }

    /// 处理分页数据的通用方法
    /// - Parameters:
    ///   - baseUrl: 基础URL，不包含页码参数
    ///   - characterId: 角色ID，用于获取访问令牌
    ///   - maxConcurrentPages: 最大并发请求数
    ///   - decoder: 用于解码数据的闭包
    ///   - progressCallback: 进度回调闭包
    /// - Returns: 解码后的数据数组
    func fetchPaginatedData<T>(
        from baseUrl: URL,
        characterId: Int,
        maxConcurrentPages: Int = 3,
        decoder: @escaping (Data) throws -> [T],
        progressCallback: ((Int) -> Void)? = nil
    ) async throws -> [T] {
        var allItems: [T] = []

        // 构建第一页的URL
        let firstPageUrlString =
            baseUrl.absoluteString + (baseUrl.absoluteString.contains("?") ? "&" : "?") + "page=1"
        guard let firstPageUrl = URL(string: firstPageUrlString) else {
            throw NetworkError.invalidURL
        }

        progressCallback?(1)
        Logger.info("开始获取第1页数据")

        // 获取第一页数据和总页数
        let (firstPageData, totalPages) = try await fetchDataWithTokenAndPages(
            from: firstPageUrl,
            characterId: characterId,
            timeouts: [2, 10, 15, 15, 15]
        )

        let firstPageItems = try decoder(firstPageData)
        Logger.info("成功获取第1页数据，本页包含\(firstPageItems.count)个项目")
        allItems.append(contentsOf: firstPageItems)

        // 如果有多页，使用并发获取剩余页面
        if totalPages > 1 {
            Logger.info("检测到总共有\(totalPages)页数据，开始并发获取剩余页面")

            do {
                try await withThrowingTaskGroup(of: (page: Int, items: [T]).self) { group in
                    var currentPage = 2
                    var inProgressPages = 0
                    var completedPages = Set<Int>()
                    completedPages.insert(1)  // 第一页已完成

                    // 添加初始任务
                    while currentPage <= totalPages, inProgressPages < maxConcurrentPages {
                        let page = currentPage
                        group.addTask {
                            let pageUrlString =
                                baseUrl.absoluteString
                                + (baseUrl.absoluteString.contains("?") ? "&" : "?")
                                + "page=\(page)"
                            guard let pageUrl = URL(string: pageUrlString) else {
                                throw NetworkError.invalidURL
                            }

                            progressCallback?(page)
                            Logger.info("开始获取第\(page)页数据")

                            let data = try await self.fetchDataWithToken(
                                from: pageUrl,
                                characterId: characterId,
                                timeouts: [2, 10, 15, 15, 15]
                            )

                            let pageItems = try decoder(data)
                            Logger.info("成功获取第\(page)页数据，本页包含\(pageItems.count)个项目")

                            // 添加短暂延迟以避免请求过于频繁
                            try await Task.sleep(nanoseconds: UInt64(0.5 * 1_000_000_000))  // 500ms延迟

                            return (page: page, items: pageItems)
                        }
                        currentPage += 1
                        inProgressPages += 1
                    }

                    // 处理完成的任务并添加新任务
                    for try await result in group {
                        allItems.append(contentsOf: result.items)
                        completedPages.insert(result.page)
                        inProgressPages -= 1

                        // 如果还有更多页面要获取，添加新任务
                        if currentPage <= totalPages {
                            let page = currentPage
                            group.addTask {
                                let pageUrlString =
                                    baseUrl.absoluteString
                                    + (baseUrl.absoluteString.contains("?") ? "&" : "?")
                                    + "page=\(page)"
                                guard let pageUrl = URL(string: pageUrlString) else {
                                    throw NetworkError.invalidURL
                                }

                                progressCallback?(page)
                                Logger.info("开始获取第\(page)页数据")

                                let data = try await self.fetchDataWithToken(
                                    from: pageUrl,
                                    characterId: characterId,
                                    timeouts: [2, 10, 15, 15, 15]
                                )

                                let pageItems = try decoder(data)
                                Logger.info("成功获取第\(page)页数据，本页包含\(pageItems.count)个项目")

                                // 添加短暂延迟以避免请求过于频繁
                                try await Task.sleep(nanoseconds: UInt64(0.5 * 1_000_000_000))  // 500ms延迟

                                return (page: page, items: pageItems)
                            }
                            currentPage += 1
                            inProgressPages += 1
                        }
                    }

                    // 检查是否所有页面都已获取
                    if completedPages.count != totalPages {
                        let missingPages = Set(1...totalPages).subtracting(completedPages)
                        Logger.warning("部分页面未能获取: \(missingPages)")
                    }
                }
            } catch {
                // 如果是取消错误，直接抛出
                if error is CancellationError {
                    throw error
                }

                // 对于其他错误，如果已经获取了一些数据，记录错误但继续返回已获取的数据
                if !allItems.isEmpty {
                    Logger.error("获取部分页面时出错: \(error)，但已获取\(allItems.count)个项目")
                } else {
                    // 如果没有获取到任何数据，则抛出错误
                    throw error
                }
            }
        }

        Logger.info("数据获取完成，共\(allItems.count)个项目")
        return allItems
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
        case let .httpError(statusCode, message):
            if let message = message {
                return
                    "\(String(format: NSLocalizedString("Network_Error_HTTP_Error", comment: ""), statusCode)): \(message)"
            }
            return String(
                format: NSLocalizedString("Network_Error_HTTP_Error", comment: ""), statusCode
            )
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
        case let .invalidToken(reason):
            return "Token无效: \(reason)"
        case .maxRetriesExceeded:
            return "已达到最大重试次数"
        case let .authenticationError(reason):
            return "认证出错: \(reason)"
        case let .decodingError(error):
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
    private let defaultTimeouts: [TimeInterval]
    private let retryDelay: TimeInterval
    private var noRetryKeywords: [String]

    init(
        defaultTimeouts: [TimeInterval] = [1.5, 3, 5, 5, 5, 5], retryDelay: TimeInterval = 0,
        noRetryKeywords: [String] = []
    ) {
        self.defaultTimeouts = defaultTimeouts
        self.retryDelay = retryDelay
        self.noRetryKeywords = noRetryKeywords
    }

    func execute<T>(
        noRetryKeywords: [String]? = nil,
        timeouts: [TimeInterval]? = nil,
        _ operation: @escaping () async throws -> T
    ) async throws -> T {
        // 使用自定义超时序列或默认序列
        let effectiveTimeouts = timeouts ?? defaultTimeouts

        // 合并默认的和临时的不重试关键词
        let keywords = Set(self.noRetryKeywords + (noRetryKeywords ?? []))
        var attempts = 0
        var lastError: Error?

        while attempts < effectiveTimeouts.count {
            do {
                // 设置当前尝试的超时时间
                let timeout = effectiveTimeouts[attempts]
                Logger.info("尝试第 \(attempts + 1) 次请求，超时时间: \(timeout)秒")

                return try await withTimeout(timeout) {
                    try await operation()
                }
            } catch {
                lastError = error

                // 检查是否应该重试
                if !shouldRetry(error, keywords: keywords) {
                    throw error
                }

                attempts += 1
                if attempts < effectiveTimeouts.count {
                    let delay = UInt64(retryDelay * pow(2.0, Double(attempts))) * 1_000_000_000
                    try await Task.sleep(nanoseconds: delay)
                }
            }
        }

        throw lastError ?? NetworkError.maxRetriesExceeded
    }

    private func withTimeout<T>(_ timeout: TimeInterval, operation: @escaping () async throws -> T)
        async throws -> T
    {
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
                let result =
                    try await group.next()
                    ?? {
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

    private func shouldRetry(_ error: Error, keywords: Set<String>) -> Bool {
        // 首先检查是否是网络错误
        if case let NetworkError.httpError(statusCode, message) = error {
            // 如果响应中包含不重试的关键词，则不重试
            if let errorMessage = message,
                keywords.contains(where: { errorMessage.contains($0) })
            {
                Logger.info("检测到不重试关键词，停止重试")
                return false
            }

            // 对于特定状态码才重试
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
    private let refillRate: Double  // tokens per second

    init(maxTokens: Int = 150, refillRate: Double = 50) {
        self.maxTokens = maxTokens
        tokens = maxTokens
        lastRefill = Date()
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
            try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
        }
        tokens -= 1
    }
}
