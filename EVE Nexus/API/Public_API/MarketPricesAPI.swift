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
    case databaseError(String)

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
        case let .databaseError(message):
            return "数据库错误: \(message)"
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
    private let lastUpdateKey = "MarketPrices_LastUpdate"

    private init() {}

    // MARK: - 缓存管理

    private var lastUpdateTime: Date? {
        get {
            UserDefaults.standard.object(forKey: lastUpdateKey) as? Date
        }
        set {
            UserDefaults.standard.set(newValue, forKey: lastUpdateKey)
        }
    }

    private func isCacheValid() -> Bool {
        guard let lastUpdate = lastUpdateTime else { return false }
        let res = Date().timeIntervalSince(lastUpdate) < cacheDuration
        if res {
            Logger.info("市场估价信息有效，上次更新: \(lastUpdate)")
        }
        return res
    }

    // MARK: - 数据库方法

    private func loadFromDatabase() -> [MarketPrice]? {
        // 检查缓存是否有效
        guard isCacheValid() else { return nil }

        // 缓存有效，加载所有价格
        let query = "SELECT type_id, adjusted_price, average_price FROM market_prices"
        if case let .success(rows) = CharacterDatabaseManager.shared.executeQuery(query) {
            return rows.compactMap { row in
                guard let typeId = row["type_id"] as? Int64 else { return nil }
                let adjustedPrice = row["adjusted_price"] as? Double
                let averagePrice = row["average_price"] as? Double
                return MarketPrice(
                    adjusted_price: adjustedPrice,
                    average_price: averagePrice,
                    type_id: Int(typeId)
                )
            }
        }
        return nil
    }

    private func saveToDatabase(_ prices: [MarketPrice]) {
        // 开始事务
        let beginTransaction = "BEGIN TRANSACTION"
        _ = CharacterDatabaseManager.shared.executeQuery(beginTransaction)

        // 清除旧数据
        let clearQuery = "DELETE FROM market_prices"
        _ = CharacterDatabaseManager.shared.executeQuery(clearQuery)

        // 计算每批次的大小（考虑到每条记录需要3个参数）
        let batchSize = 300  // 每批次处理300条记录，对应900个参数
        var success = true

        // 分批处理数据
        for batchStart in stride(from: 0, to: prices.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, prices.count)
            let currentBatch = Array(prices[batchStart..<batchEnd])

            // 构建批量插入语句
            let placeholders = Array(repeating: "(?, ?, ?)", count: currentBatch.count).joined(
                separator: ",")
            let insertQuery = """
                    INSERT INTO market_prices (type_id, adjusted_price, average_price)
                    VALUES \(placeholders)
                """

            // 准备参数数组，处理可选值
            var parameters: [Any] = []
            for price in currentBatch {
                parameters.append(price.type_id)
                // 使用 NSNull() 替代 nil
                parameters.append(price.adjusted_price ?? NSNull())
                parameters.append(price.average_price ?? NSNull())
            }

            Logger.debug("执行批量插入，批次大小: \(currentBatch.count), 参数数量: \(parameters.count)")

            // 执行批量插入
            if case let .error(error) = CharacterDatabaseManager.shared.executeQuery(
                insertQuery, parameters: parameters
            ) {
                Logger.error("批量插入失败: \(error)")
                Logger.error("SQL: \(insertQuery)")
                Logger.error("参数数量: \(parameters.count)")
                if !parameters.isEmpty {
                    Logger.error(
                        "第一条记录参数: type_id=\(parameters[0]), adjusted_price=\(parameters[1]), average_price=\(parameters[2])"
                    )
                }
                success = false
                break
            }
        }

        // 根据执行结果提交或回滚事务
        if success {
            _ = CharacterDatabaseManager.shared.executeQuery("COMMIT")
            // 更新最后更新时间
            lastUpdateTime = Date()
            Logger.info("市场价格数据已保存到数据库，共 \(prices.count) 条记录")
        } else {
            _ = CharacterDatabaseManager.shared.executeQuery("ROLLBACK")
            Logger.error("保存市场价格数据失败，执行回滚")
        }
    }

    // MARK: - 公共方法

    func fetchMarketPrices(forceRefresh: Bool = false) async throws -> [MarketPrice] {
        // 如果不是强制刷新，尝试从数据库获取
        if !forceRefresh {
            if let cached = loadFromDatabase(), !cached.isEmpty {
                Logger.info("使用数据库缓存的市场价格数据")
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

        // 保存到数据库
        saveToDatabase(prices)

        return prices
    }
}
