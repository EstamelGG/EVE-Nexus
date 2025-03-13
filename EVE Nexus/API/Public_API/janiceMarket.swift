import CryptoKit
import Foundation

// 添加响应模型
struct JaniceResponse: Codable {
    let id: Int
    let result: JaniceResult
}

struct JaniceResult: Codable {
    let code: String
    let created: String
    let name: String?
    let immediatePrices: JanicePrices
    let pricerMarket: PricerMarket
}

struct PricerMarket: Codable {
    let id: Int
    let name: String
    let enablePricer: Bool
    let enableListedValue: Bool
    let enableTradedValue: Bool
    let enableOverpricedStock: Bool
    let order: Int
}

struct JanicePrices: Codable {
    let totalBuyPrice: Double
    let totalSplitPrice: Double
    let totalSellPrice: Double
}

// 添加缓存管理器
class JaniceCache {
    static let shared = JaniceCache()

    private struct CacheItem {
        let data: Data
        let timestamp: Date
    }

    private var cache: [String: CacheItem] = [:]
    private let cacheDuration: TimeInterval = 30 * 60  // 30分钟

    func getCache(for key: String) -> Data? {
        guard let cacheItem = cache[key] else { return nil }

        // 检查缓存是否过期
        let now = Date()
        if now.timeIntervalSince(cacheItem.timestamp) > cacheDuration {
            // 缓存已过期，移除
            cache.removeValue(forKey: key)
            return nil
        }

        return cacheItem.data
    }

    func setCache(for key: String, data: Data) {
        let cacheItem = CacheItem(data: data, timestamp: Date())
        cache[key] = cacheItem
    }
}

// 添加MD5计算扩展
extension String {
    func md5() -> String {
        let data = Data(utf8)
        let hash = Insecure.MD5.hash(data: data)
        return hash.map { String(format: "%02hhx", $0) }.joined()
    }
}

class JaniceMarketAPI {
    static let shared = JaniceMarketAPI()
    private let baseURL = "https://janice.e-351.com/api/rpc/v1"
    let databaseManager: DatabaseManager

    private init(databaseManager: DatabaseManager = DatabaseManager.shared) {
        self.databaseManager = databaseManager
    }

    private func generateBoundary() -> String {
        let length = 16
        let characters = "abcdef0123456789"
        let randomString = (0..<length).map { _ in
            String(characters.randomElement()!)
        }.joined()
        return "geckoformboundary\(randomString)"
    }

    struct AppraisalRequest: Codable {
        let id: Int
        let method: String
        let params: AppraisalParams
    }

    struct AppraisalParams: Codable {
        let marketId: Int
        let designation: Int
        let pricing: Int
        let pricingVariant: Int
        let pricePercentage: Int
        let input: String
        let comment: String
        let compactize: Bool
    }

    func createAppraisal(items: [String: Int]) async throws -> Data {
        // 1. 生成随机boundary
        let boundary = generateBoundary()
        Logger.debug("items: \(items)")

        // 2. 从数据库获取物品名称
        let itemIds = Array(items.keys)
        let query =
            "SELECT type_id, en_name FROM types WHERE type_id IN (\(itemIds.sorted().joined(separator: ",")))"
        let result = databaseManager.executeQuery(query)

        // 3. 构建input字符串
        var itemsMap: [Int: (name: String, quantity: Int)] = [:]

        if case let .success(rows) = result {
            for row in rows {
                let typeIdInt =
                    (row["type_id"] as? Int64).map(Int.init) ?? (row["type_id"] as? Int) ?? 0
                let typeId = String(typeIdInt)

                if let name = row["en_name"] as? String,
                    let quantity = items[typeId]
                {
                    itemsMap[typeIdInt] = (name: name, quantity: quantity)
                }
            }
        }

        // 按type_id排序并构建input字符串
        let sortedItems = itemsMap.sorted { $0.key < $1.key }
        let inputLines = sortedItems.map { "\($0.value.name) \($0.value.quantity)" }
        let inputString = inputLines.joined(separator: "\n")

        Logger.debug("inputString: \(inputString)")

        // 计算缓存键
        let cacheKey = inputString.md5()

        // 检查缓存
        if let cachedData = JaniceCache.shared.getCache(for: cacheKey) {
            Logger.debug("使用缓存数据，缓存键: \(cacheKey)")
            return cachedData
        }

        // 缓存不存在或已过期，执行网络请求
        Logger.debug("缓存未命中，执行网络请求，缓存键: \(cacheKey)")

        // 3. 构建请求体
        let requestBody = AppraisalRequest(
            id: 4097,
            method: "Appraisal.create",
            params: AppraisalParams(
                marketId: 2,
                designation: 100,
                pricing: 200,
                pricingVariant: 100,
                pricePercentage: 1,
                input: inputString,
                comment: "",
                compactize: true
            )
        )

        // 4. 编码请求体为JSON
        let jsonData = try JSONEncoder().encode(requestBody)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        // 5. 构建multipart/form-data请求
        var requestData = Data()
        requestData.append("------\(boundary)\r\n".data(using: .utf8)!)
        requestData.append(
            "Content-Disposition: form-data; name=\"~request~\"\r\n\r\n".data(using: .utf8)!)
        requestData.append(jsonString.data(using: .utf8)!)
        requestData.append("\r\n------\(boundary)--\r\n".data(using: .utf8)!)

        // 6. 创建URLRequest
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue(
            "multipart/form-data; boundary=----\(boundary)", forHTTPHeaderField: "Content-Type"
        )
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue(
            "zh-CN,zh;q=0.8,zh-TW;q=0.7,zh-HK;q=0.5,en-US;q=0.3,en;q=0.2",
            forHTTPHeaderField: "Accept-Language"
        )
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")  // 使用 identity 表示不接受压缩
        request.httpBody = requestData

        // 7. 发送请求
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
            (200...299).contains(httpResponse.statusCode)
        else {
            throw NSError(
                domain: "JaniceMarketAPI", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "HTTP请求失败"]
            )
        }

        // 打印响应数据
        if let responseString = String(data: data, encoding: .utf8) {
            Logger.debug("响应数据: \(responseString)")
        } else {
            Logger.debug("响应数据无法转换为字符串，原始数据大小: \(data.count) bytes")
            // 打印原始数据的十六进制表示
            let hexString = data.map { String(format: "%02x", $0) }.joined()
            Logger.debug("原始数据(Hex): \(hexString)")
        }

        // 保存到缓存
        JaniceCache.shared.setCache(for: cacheKey, data: data)
        Logger.debug("已将响应数据保存到缓存，缓存键: \(cacheKey)")

        return data
    }
}
