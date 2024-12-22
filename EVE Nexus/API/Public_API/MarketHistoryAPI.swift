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
    
    // 缓存
    private var marketHistoryCache: [Int: [MarketHistory]] = [:]
    private var marketHistoryTimestamp: [Int: Date] = [:]
    private let marketHistoryCacheDuration: TimeInterval = 7 * 24 * 3600 // 1周缓存
    
    private init() {}
    
    // MARK: - 公共方法
    
    /// 获取市场历史数据
    /// - Parameters:
    ///   - typeID: 物品类型ID
    ///   - regionID: 区域ID
    ///   - forceRefresh: 是否强制刷新
    /// - Returns: 市场历史数据数组
    func fetchMarketHistory(typeID: Int, regionID: Int, forceRefresh: Bool = false) async throws -> [MarketHistory] {
        // 检查缓存
        if !forceRefresh {
            if let cached = marketHistoryCache[typeID],
               let timestamp = marketHistoryTimestamp[typeID],
               Date().timeIntervalSince(timestamp) < marketHistoryCacheDuration {
                return cached
            }
        }
        
        // 构建URL
        let baseURL = "https://esi.evetech.net/latest/markets/\(regionID)/history/"
        var components = URLComponents(string: baseURL)
        components?.queryItems = [
            URLQueryItem(name: "datasource", value: "tranquility"),
            URLQueryItem(name: "type_id", value: String(typeID))
        ]
        
        guard let url = components?.url else {
            throw MarketHistoryAPIError.invalidURL
        }
        
        // 执行请求
        let data = try await NetworkManager.shared.fetchData(from: url)
        let history = try JSONDecoder().decode([MarketHistory].self, from: data)
        
        // 更新缓存
        marketHistoryCache[typeID] = history
        marketHistoryTimestamp[typeID] = Date()
        
        // 保存到文件
        try await saveToFile(history, typeID: typeID, regionID: regionID)
        
        return history
    }
    
    /// 清除缓存
    func clearCache() {
        marketHistoryCache.removeAll()
        marketHistoryTimestamp.removeAll()
    }
    
    // MARK: - 私有方法
    
    private func saveToFile(_ history: [MarketHistory], typeID: Int, regionID: Int) async throws {
        let fileManager = FileManager.default
        let baseURL = StaticResourceManager.shared.getStaticDataSetPath()
            .appendingPathComponent("Market")
        
        // 创建Market目录（如果不存在）
        try? fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        
        // 构建文件路径
        let fileName = "history_\(typeID)_\(regionID).json"
        let fileURL = baseURL.appendingPathComponent(fileName)
        
        // 编码数据
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(history)
        
        // 写入文件
        try data.write(to: fileURL)
    }
    
    private func loadFromFile(typeID: Int, regionID: Int) throws -> [MarketHistory]? {
        let fileURL = StaticResourceManager.shared.getStaticDataSetPath()
            .appendingPathComponent("Market")
            .appendingPathComponent("history_\(typeID)_\(regionID).json")
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([MarketHistory].self, from: data)
    }
} 