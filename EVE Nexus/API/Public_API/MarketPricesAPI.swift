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
    case fileError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的URL"
        case let .networkError(error):
            return "网络错误: \(error.localizedDescription)"
        case .invalidResponse:
            return "无效的响应"
        case let .decodingError(error):
            return "数据解码错误: \(error.localizedDescription)"
        case let .httpError(code):
            return "HTTP错误: \(code)"
        case .rateLimitExceeded:
            return "超出请求限制"
        case let .fileError(message):
            return "文件错误: \(message)"
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
    private let cacheDuration: TimeInterval = 8 * 60 * 60  // 8小时缓存
    
    private init() {}
    
    // MARK: - 文件路径管理
    
    private var cacheDirectory: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsPath.appendingPathComponent("MarketCache")
    }
    
    private var cacheFileURL: URL {
        return cacheDirectory.appendingPathComponent("MarketAvgPrices.json")
    }
    
    // MARK: - 缓存管理
    
    private func ensureCacheDirectoryExists() throws {
        if !FileManager.default.fileExists(atPath: cacheDirectory.path) {
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
    }
    
    private func isCacheValid() -> Bool {
        guard FileManager.default.fileExists(atPath: cacheFileURL.path) else { 
            Logger.info("缓存文件不存在")
            return false 
        }
        
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: cacheFileURL.path)
            guard let modificationDate = attributes[.modificationDate] as? Date else { 
                Logger.info("无法获取文件修改时间")
                return false 
            }
            
            let isValid = Date().timeIntervalSince(modificationDate) < cacheDuration
            if isValid {
                Logger.info("市场估价信息有效，上次更新: \(modificationDate)")
            } else {
                Logger.info("缓存已过期，上次更新: \(modificationDate)")
            }
            return isValid
        } catch {
            Logger.error("检查缓存文件时出错: \(error)")
            return false
        }
    }
    
    // MARK: - 文件操作方法
    
    private func loadFromCache() -> [MarketPrice]? {
        // 检查缓存是否有效
        guard isCacheValid() else { return nil }
        
        do {
            let data = try Data(contentsOf: cacheFileURL)
            let prices = try JSONDecoder().decode([MarketPrice].self, from: data)
            Logger.info("从缓存文件加载市场价格数据，共 \(prices.count) 条记录")
            return prices
        } catch {
            Logger.error("从缓存文件加载数据失败: \(error)")
            return nil
        }
    }
    
    private func saveToCache(_ prices: [MarketPrice]) {
        do {
            // 确保缓存目录存在
            try ensureCacheDirectoryExists()
            
            // 编码数据
            let data = try JSONEncoder().encode(prices)
            
            // 写入文件
            try data.write(to: cacheFileURL)
            
            Logger.info("市场价格数据已保存到缓存文件，共 \(prices.count) 条记录")
        } catch {
            Logger.error("保存市场价格数据到缓存文件失败: \(error)")
        }
    }
    
    // MARK: - 公共方法
    
    func fetchMarketPrices(forceRefresh: Bool = false) async throws -> [MarketPrice] {
        // 如果不是强制刷新，尝试从缓存获取
        if !forceRefresh {
            if let cached = loadFromCache(), !cached.isEmpty {
                Logger.info("使用缓存文件的市场价格数据")
                return cached
            }
        }
        
        // 构建URL
        let baseURL = "https://esi.evetech.net/markets/prices/"
        var components = URLComponents(string: baseURL)
        components?.queryItems = [
            URLQueryItem(name: "datasource", value: "tranquility")
        ]
        
        guard let url = components?.url else {
            throw MarketPricesAPIError.invalidURL
        }
        
        // 执行请求
        let data = try await NetworkManager.shared.fetchData(
            from: url,
            timeouts: [5, 10, 10, 10, 10]
        )
        let prices = try JSONDecoder().decode([MarketPrice].self, from: data)
        
        // 保存到缓存文件
        saveToCache(prices)
        
        return prices
    }
}
