import Foundation
import SwiftUI

// MARK: - 数据模型
struct ESIStatus: Codable {
    let endpoint: String
    let method: String
    let route: String
    let status: String
    let tags: [String]
    
    // 唯一标识符，结合route和method
    var uniqueID: String {
        return "\(method)_\(route)"
    }
    
    var isGreen: Bool {
        return status == "green"
    }
    
    var isYellow: Bool {
        return status == "yellow"
    }
    
    var isRed: Bool {
        return status == "red"
    }
}

// MARK: - 错误类型
enum ESIStatusAPIError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case decodingError(Error)
    case httpError(Int)
    case rateLimitExceeded
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的URL"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        case .invalidResponse:
            return "无效的响应"
        case .decodingError(let error):
            return "数据解码错误: \(error.localizedDescription)"
        case .httpError(let code):
            return "HTTP错误: \(code)"
        case .rateLimitExceeded:
            return "超出请求限制"
        }
    }
}

// MARK: - ESI状态API
@globalActor actor ESIStatusAPIActor {
    static let shared = ESIStatusAPIActor()
}

@ESIStatusAPIActor
class ESIStatusAPI {
    static let shared = ESIStatusAPI()
    private let cacheDuration: TimeInterval = 5 * 60 // 5分钟缓存
    
    private var cachedStatus: [ESIStatus]?
    private var lastFetchTime: Date?
    
    private init() {}
    
    // MARK: - 缓存方法
    private func getCacheDirectory() -> URL? {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let cacheDirectory = documentsDirectory.appendingPathComponent("ESICache", isDirectory: true)
        
        // 确保缓存目录存在
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true, attributes: nil)
        
        return cacheDirectory
    }
    
    private func getCacheFilePath() -> URL? {
        guard let cacheDirectory = getCacheDirectory() else { return nil }
        return cacheDirectory.appendingPathComponent("esi_status.json")
    }
    
    private struct CachedData: Codable {
        let data: [ESIStatus]
        let timestamp: Date
    }
    
    private func loadFromCache() -> [ESIStatus]? {
        guard let cacheFile = getCacheFilePath(),
              let data = try? Data(contentsOf: cacheFile),
              let cached = try? JSONDecoder().decode(CachedData.self, from: data),
              cached.timestamp.addingTimeInterval(cacheDuration) > Date() else {
            return nil
        }
        
        Logger.info("使用缓存的ESI状态数据")
        return cached.data
    }
    
    private func saveToCache(_ status: [ESIStatus]) {
        guard let cacheFile = getCacheFilePath() else { return }
        
        // 使用当前时间作为缓存时间戳
        let currentTime = Date()
        let cachedData = CachedData(data: status, timestamp: currentTime)
        
        do {
            let encodedData = try JSONEncoder().encode(cachedData)
            try encodedData.write(to: cacheFile)
            Logger.info("ESI状态数据已缓存到文件，时间戳: \(currentTime)")
        } catch {
            Logger.error("保存ESI状态缓存失败: \(error)")
        }
    }
    
    // MARK: - 公共方法
    func fetchESIStatus(forceRefresh: Bool = false) async throws -> [ESIStatus] {
        // 如果不是强制刷新，尝试从缓存获取
        if !forceRefresh {
            if let cached = loadFromCache() {
                Logger.info("使用缓存的ESI状态数据，共\(cached.count)个端点")
                return cached
            }
        }
        
        Logger.info("从网络获取ESI状态数据，强制刷新: \(forceRefresh)")
        
        // 构建URL
        var urlString = "https://esi.evetech.net/status.json?version=latest"
        
        // 添加随机参数，确保不使用浏览器缓存
        if forceRefresh {
            urlString += "&t=\(Date().timeIntervalSince1970)"
        }
        
        guard let url = URL(string: urlString) else {
            throw ESIStatusAPIError.invalidURL
        }
        
        // 执行请求
        let data = try await NetworkManager.shared.fetchData(from: url)
        let status = try JSONDecoder().decode([ESIStatus].self, from: data)
        
        // 保存到缓存
        saveToCache(status)
        
        // 更新内存缓存
        cachedStatus = status
        lastFetchTime = Date()
        
        Logger.info("成功获取ESI状态数据，共\(status.count)个端点")
        
        return status
    }
    
    // MARK: - 辅助方法
    
    /// 检查特定标签的ESI端点状态
    /// - Parameter tag: 要检查的标签（例如："market", "character", "corporation"等）
    /// - Returns: 该标签下所有端点的状态
    func getStatusForTag(_ tag: String, forceRefresh: Bool = false) async throws -> [ESIStatus] {
        let allStatus = try await fetchESIStatus(forceRefresh: forceRefresh)
        return allStatus.filter { $0.tags.contains(tag) }
    }
    
    /// 检查特定路由的ESI端点状态
    /// - Parameter route: 要检查的路由路径
    /// - Returns: 匹配的端点状态，如果没有找到则返回nil
    func getStatusForRoute(_ route: String, forceRefresh: Bool = false) async throws -> ESIStatus? {
        let allStatus = try await fetchESIStatus(forceRefresh: forceRefresh)
        return allStatus.first { $0.route == route }
    }
    
    /// 获取所有红色（故障）状态的端点
    /// - Returns: 所有状态为red的端点
    func getRedStatusEndpoints(forceRefresh: Bool = false) async throws -> [ESIStatus] {
        let allStatus = try await fetchESIStatus(forceRefresh: forceRefresh)
        return allStatus.filter { $0.isRed }
    }
    
    /// 获取所有黄色（降级）状态的端点
    /// - Returns: 所有状态为yellow的端点
    func getYellowStatusEndpoints(forceRefresh: Bool = false) async throws -> [ESIStatus] {
        let allStatus = try await fetchESIStatus(forceRefresh: forceRefresh)
        return allStatus.filter { $0.isYellow }
    }
    
    /// 检查ESI整体健康状态
    /// - Returns: 如果所有端点都是绿色，返回true；否则返回false
    func isESIHealthy(forceRefresh: Bool = false) async throws -> Bool {
        let allStatus = try await fetchESIStatus(forceRefresh: forceRefresh)
        return allStatus.allSatisfy { $0.isGreen }
    }
    
    /// 获取最后一次缓存的时间戳
    /// - Returns: 缓存时间戳，如果没有缓存则返回nil
    func getLastCacheTimestamp() -> Date? {
        guard let cacheFile = getCacheFilePath(),
              let data = try? Data(contentsOf: cacheFile),
              let cached = try? JSONDecoder().decode(CachedData.self, from: data) else {
            return nil
        }
        
        return cached.timestamp
    }
} 