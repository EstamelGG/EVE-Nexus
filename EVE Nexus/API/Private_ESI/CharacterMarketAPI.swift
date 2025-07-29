import Foundation

class CharacterMarketAPI {
    static let shared = CharacterMarketAPI()

    private struct CachedData: Codable {
        let orders: [CharacterMarketOrder]
        let timestamp: Date
    }

    private let cacheTimeout: TimeInterval = 8 * 60 * 60  // 8 小时缓存
    private let cacheDirectory: URL = {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let ordersDirectory = paths[0].appendingPathComponent("CharacterOrders", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: ordersDirectory, withIntermediateDirectories: true)
        return ordersDirectory
    }()

    private init() {}

    private func getCacheFilePath(characterId: Int64) -> URL {
        return cacheDirectory.appendingPathComponent("\(characterId)_market_orders.json")
    }

    private func isCacheValid(_ cache: CachedData) -> Bool {
        let timeSinceLastUpdate = Date().timeIntervalSince(cache.timestamp)
        let isValid = timeSinceLastUpdate < cacheTimeout

        if isValid {
            // 计算并打印缓存剩余有效期
            let remainingTime = cacheTimeout - timeSinceLastUpdate
            let remainingHours = Int(remainingTime / 3600)
            let remainingMinutes = Int((remainingTime.truncatingRemainder(dividingBy: 3600)) / 60)
            Logger.info("市场订单缓存有效 - 剩余时间: \(remainingHours)小时\(remainingMinutes)分钟")
        }

        return isValid
    }

    private func getCachedOrders(characterId: Int64) -> (jsonString: String, cache: CachedData)? {
        let cacheFile = getCacheFilePath(characterId: characterId)

        // 1. 尝试从文件读取并解码缓存数据
        guard let data = try? Data(contentsOf: cacheFile),
            let cache = try? JSONDecoder().decode(CachedData.self, from: data)
        else {
            return nil
        }

        // 2. 将缓存的订单转换为JSON字符串
        guard let jsonData = try? JSONEncoder().encode(cache.orders),
            let jsonString = String(data: jsonData, encoding: .utf8)
        else {
            return nil
        }

        Logger.debug(
            "获取市场订单缓存数据 from: \(cacheFile) - 角色ID: \(characterId), 订单数量: \(cache.orders.count)")
        return (jsonString, cache)
    }

    private func saveOrdersToCache(jsonString: String, characterId: Int64) {
        // 将JSON字符串转换为订单数组
        guard let jsonData = jsonString.data(using: .utf8),
            let orders = try? JSONDecoder().decode([CharacterMarketOrder].self, from: jsonData)
        else {
            return
        }

        let cache = CachedData(orders: orders, timestamp: Date())
        let cacheFile = getCacheFilePath(characterId: characterId)

        do {
            let encoded = try JSONEncoder().encode(cache)
            try encoded.write(to: cacheFile)
            Logger.debug("保存市场订单数据到缓存成功 - 角色ID: \(characterId)")
        } catch {
            Logger.error("保存市场订单缓存失败: \(error)")
        }
    }

    private func fetchFromNetwork(characterId: Int64) async throws -> String {
        let urlString =
            "https://esi.evetech.net/characters/\(characterId)/orders/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: Int(characterId)
        )

        // 验证返回的数据是否可以解码为订单数组
        _ = try JSONDecoder().decode([CharacterMarketOrder].self, from: data)

        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw NetworkError.invalidResponse
        }

        return jsonString
    }

    func getMarketOrders(
        characterId: Int64,
        forceRefresh: Bool = false,
        progressCallback: ((Bool) -> Void)? = nil
    ) async throws -> String? {
        progressCallback?(true)
        defer { progressCallback?(false) }

        // 1. 检查缓存
        if !forceRefresh, let cachedData = getCachedOrders(characterId: characterId) {
            let cache = cachedData.cache

            // 检查缓存是否有效
            if isCacheValid(cache) {
                Logger.debug("使用有效的市场订单缓存数据 - 角色ID: \(characterId)")
                return cachedData.jsonString
            }
        }

        // 2. 如果强制刷新或缓存无效，从网络获取
        do {
            let jsonString = try await fetchFromNetwork(characterId: characterId)

            // 3. 保存新数据到缓存
            saveOrdersToCache(jsonString: jsonString, characterId: characterId)
            return jsonString
        } catch {
            Logger.error("获取市场订单数据失败: \(error)")
            throw error
        }
    }
}
