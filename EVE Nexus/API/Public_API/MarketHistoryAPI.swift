import Foundation
import SwiftUI

// MARK: - 数据模型
struct MarketHistory: Codable {
    let average: Double
    let date: String
    let volume: Int
}

// MARK: - 错误类型
enum MarketHistoryAPIError: LocalizedError {
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

// MARK: - 市场历史API
@globalActor actor MarketHistoryAPIActor {
    static let shared = MarketHistoryAPIActor()
}

@MarketHistoryAPIActor
class MarketHistoryAPI {
    static let shared = MarketHistoryAPI()
    private let cacheDuration: TimeInterval = 60 * 60 // 1小时缓存
    
    private init() {}
    
    private struct CachedData: Codable {
        let data: [MarketHistory]
        let timestamp: Date
    }
    
    // MARK: - 缓存方法
    private func getCacheDirectory() -> URL? {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let cacheDirectory = documentsDirectory.appendingPathComponent("MarketCache", isDirectory: true)
        
        // 确保缓存目录存在
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true, attributes: nil)
        
        return cacheDirectory
    }
    
    private func getCacheFilePath(typeID: Int, regionID: Int) -> URL? {
        guard let cacheDirectory = getCacheDirectory() else { return nil }
        return cacheDirectory.appendingPathComponent("market_history_\(typeID)_\(regionID).json")
    }
    
    private func loadFromCache(typeID: Int, regionID: Int) -> [MarketHistory]? {
        guard let cacheFile = getCacheFilePath(typeID: typeID, regionID: regionID),
              let data = try? Data(contentsOf: cacheFile),
              let cached = try? JSONDecoder().decode(CachedData.self, from: data),
              cached.timestamp.addingTimeInterval(cacheDuration) > Date() else {
            return nil
        }
        
        Logger.info("使用缓存的市场历史数据")
        return cached.data
    }
    
    private func saveToCache(_ history: [MarketHistory], typeID: Int, regionID: Int) {
        guard let cacheFile = getCacheFilePath(typeID: typeID, regionID: regionID) else { return }
        
        let cachedData = CachedData(data: history, timestamp: Date())
        do {
            let encodedData = try JSONEncoder().encode(cachedData)
            try encodedData.write(to: cacheFile)
            Logger.info("市场历史数据已缓存到文件")
        } catch {
            Logger.error("保存市场历史缓存失败: \(error)")
        }
    }
    
    // MARK: - 公共方法
    func fetchMarketHistory(typeID: Int, regionID: Int, forceRefresh: Bool = false) async throws -> [MarketHistory] {
        // 如果不是强制刷新，尝试从缓存获取
        if !forceRefresh {
            if let cached = loadFromCache(typeID: typeID, regionID: regionID) {
                return cached
            }
        }
        
        // 构建URL
        let baseURL = "https://esi.evetech.net/latest/markets/\(regionID)/history/"
        var components = URLComponents(string: baseURL)
        components?.queryItems = [
            URLQueryItem(name: "type_id", value: "\(typeID)"),
            URLQueryItem(name: "datasource", value: "tranquility")
        ]
        
        guard let url = components?.url else {
            throw MarketHistoryAPIError.invalidURL
        }
        
        // 执行请求
        let data = try await NetworkManager.shared.fetchData(from: url)
        let history = try JSONDecoder().decode([MarketHistory].self, from: data)
        
        // 保存到缓存
        saveToCache(history, typeID: typeID, regionID: regionID)
        
        return history
    }
} 