import Foundation
import SwiftUI

// MARK: - 数据模型
struct MarketHistory: Codable {
    let average: Double
    let date: String
    let highest: Double
    let lowest: Double
    let order_count: Int
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
    func fetchMarketHistory(typeID: Int, regionID: Int, forceRefresh: Bool = false, interpolate: Bool = true, fillToCurrentDate: Bool = true) async throws -> [MarketHistory] {
        // 如果不是强制刷新，尝试从缓存获取
        if !forceRefresh {
            if let cached = loadFromCache(typeID: typeID, regionID: regionID) {
                return interpolate ? interpolateMarketHistory(cached, fillToCurrentDate: fillToCurrentDate) : cached
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
        
        // 对原始数据进行插值处理
        let processedHistory = interpolate ? interpolateMarketHistory(history, fillToCurrentDate: fillToCurrentDate) : history
        
        // 保存原始数据到缓存（不保存插值后的数据，以便后续可以根据需要重新插值）
        saveToCache(history, typeID: typeID, regionID: regionID)
        
        // 返回处理后的数据
        return processedHistory
    }
    
    // MARK: - 数据插值处理
    func interpolateMarketHistory(_ history: [MarketHistory], fillToCurrentDate: Bool = true) -> [MarketHistory] {
        // 确保历史数据按日期排序（从早到晚）
        let sortedHistory = history.sorted { 
            guard let date1 = dateFromString($0.date), let date2 = dateFromString($1.date) else {
                return false
            }
            return date1 < date2
        }
        
        guard !sortedHistory.isEmpty else { return [] }
        
        // 获取最早和最晚的日期
        guard let firstDateString = sortedHistory.first?.date,
              let lastDateString = sortedHistory.last?.date,
              let firstDate = dateFromString(firstDateString),
              var lastDate = dateFromString(lastDateString) else {
            return sortedHistory
        }
        
        // 如果需要填充到当前日期，则使用当前日期作为最后日期
        if fillToCurrentDate {
            let currentDate = Date()
            if lastDate < currentDate {
                lastDate = currentDate
            }
        }
        
        // 创建日期到数据的映射
        var dateToHistoryMap = [String: MarketHistory]()
        for item in sortedHistory {
            dateToHistoryMap[item.date] = item
        }
        
        // 创建完整的日期序列
        var currentDate = firstDate
        var allDates = [String]()
        let calendar = Calendar.current
        
        while currentDate <= lastDate {
            let dateString = stringFromDate(currentDate)
            allDates.append(dateString)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }
        
        // 创建插值后的历史数据
        var interpolatedHistory = [MarketHistory]()
        var lastValidHistory: MarketHistory? = nil
        
        for dateString in allDates {
            if let historyItem = dateToHistoryMap[dateString] {
                // 如果当前日期有数据，则使用该数据
                interpolatedHistory.append(historyItem)
                lastValidHistory = historyItem
            } else if let lastValid = lastValidHistory {
                // 如果当前日期没有数据，则使用上一个有效数据点的值，但order_count设为0
                let interpolatedItem = MarketHistory(
                    average: lastValid.average,
                    date: dateString,
                    highest: lastValid.highest,
                    lowest: lastValid.lowest,
                    order_count: 0,
                    volume: 0
                )
                interpolatedHistory.append(interpolatedItem)
            }
        }
        Logger.info("插值完成，增加 \(interpolatedHistory.count - history.count) 条数据")
        return interpolatedHistory
    }
    
    // MARK: - 日期工具方法
    private func dateFromString(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString)
    }
    
    private func stringFromDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
} 