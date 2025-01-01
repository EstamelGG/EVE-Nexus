import Foundation
import SwiftUI

// MARK: - 数据模型
struct MarketPrice: Codable {
    let adjusted_price: Double?
    let average_price: Double?
    let type_id: Int
}

// MARK: - 错误类型
enum MarketPricesAPIError: LocalizedError {
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

// MARK: - 市场价格API
@globalActor actor MarketPricesAPIActor {
    static let shared = MarketPricesAPIActor()
}

@MarketPricesAPIActor
class MarketPricesAPI {
    static let shared = MarketPricesAPI()
    private let cacheDuration: TimeInterval = 8 * 60 * 60 // 8小时缓存
    
    private init() {}
    
    private struct CachedData: Codable {
        let data: [MarketPrice]
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
    
    private func getCacheFilePath() -> URL? {
        guard let cacheDirectory = getCacheDirectory() else { return nil }
        return cacheDirectory.appendingPathComponent("market_prices.json")
    }
    
    private func loadFromCache() -> [MarketPrice]? {
        guard let cacheFile = getCacheFilePath(),
              let data = try? Data(contentsOf: cacheFile),
              let cached = try? JSONDecoder().decode(CachedData.self, from: data),
              cached.timestamp.addingTimeInterval(cacheDuration) > Date() else {
            return nil
        }
        
        Logger.info("使用缓存的市场价格数据")
        return cached.data
    }
    
    private func saveToCache(_ prices: [MarketPrice]) {
        guard let cacheFile = getCacheFilePath() else { return }
        
        let cachedData = CachedData(data: prices, timestamp: Date())
        do {
            let encodedData = try JSONEncoder().encode(cachedData)
            try encodedData.write(to: cacheFile)
            Logger.info("市场价格数据已缓存到文件")
        } catch {
            Logger.error("保存市场价格缓存失败: \(error)")
        }
    }
    
    // MARK: - 公共方法
    func fetchMarketPrices(forceRefresh: Bool = false) async throws -> [MarketPrice] {
        // 如果不是强制刷新，尝试从缓存获取
        if !forceRefresh {
            if let cached = loadFromCache() {
                return cached
            }
        }
        
        // 构建URL
        let baseURL = "https://esi.evetech.net/latest/markets/prices/"
        var components = URLComponents(string: baseURL)
        components?.queryItems = [
            URLQueryItem(name: "datasource", value: "tranquility")
        ]
        
        guard let url = components?.url else {
            throw MarketPricesAPIError.invalidURL
        }
        
        // 执行请求
        let data = try await NetworkManager.shared.fetchData(from: url)
        let prices = try JSONDecoder().decode([MarketPrice].self, from: data)
        
        // 保存到缓存
        saveToCache(prices)
        
        return prices
    }
} 