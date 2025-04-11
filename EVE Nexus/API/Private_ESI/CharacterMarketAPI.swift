import Foundation

class CharacterMarketAPI {
    static let shared = CharacterMarketAPI()

    private struct CachedData: Codable {
        let orders: [CharacterMarketOrder]
        let timestamp: Date
    }

    private let cachePrefix = "character_market_orders_cache_"
    private let cacheTimeout: TimeInterval = 8 * 60 * 60  // 8 小时缓存 UserDefaults

    private init() {}

    private func getCacheKey(characterId: Int64) -> String {
        return "\(cachePrefix)\(characterId)"
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
        let key = getCacheKey(characterId: characterId)

        // 1. 尝试获取并解码缓存数据
        guard let data = UserDefaults.standard.data(forKey: key),
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

        Logger.debug("获取市场订单缓存数据 - 角色ID: \(characterId), 订单数量: \(cache.orders.count)")
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
        let key = getCacheKey(characterId: characterId)

        if let encoded = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(encoded, forKey: key)
            Logger.debug("保存市场订单数据到缓存成功 - 角色ID: \(characterId)")
        }
    }

    private func fetchFromNetwork(characterId: Int64) async throws -> String {
        let urlString =
            "https://esi.evetech.net/latest/characters/\(characterId)/orders/?datasource=tranquility"
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
            let cachedJson = cachedData.jsonString
            let cache = cachedData.cache

            // 检查缓存是否有效
            if isCacheValid(cache) {
                Logger.debug("使用有效的市场订单缓存数据 - 角色ID: \(characterId)")
                return cachedJson
            } else {
                // 如果缓存过期，在后台刷新
                Logger.info("使用过期的市场订单数据，将在后台刷新 - 角色ID: \(characterId)")
                Task {
                    do {
                        progressCallback?(true)
                        let jsonString = try await fetchFromNetwork(characterId: characterId)
                        await mergeAndSaveOrders(
                            newJsonString: jsonString, existingJsonString: cachedJson,
                            characterId: characterId
                        )
                        progressCallback?(false)
                    } catch {
                        Logger.error("后台刷新市场订单数据失败: \(error)")
                        progressCallback?(false)
                    }
                }
                return cachedJson
            }
        }

        // 2. 如果强制刷新或没有缓存，从网络获取
        let jsonString = try await fetchFromNetwork(characterId: characterId)

        // 3. 如果有缓存数据，尝试合并
        if let cachedData = getCachedOrders(characterId: characterId) {
            await mergeAndSaveOrders(
                newJsonString: jsonString, existingJsonString: cachedData.jsonString,
                characterId: characterId
            )
            return jsonString
        }

        // 4. 如果没有缓存，直接保存新数据
        saveOrdersToCache(jsonString: jsonString, characterId: characterId)
        return jsonString
    }

    // 合并并保存订单数据
    private func mergeAndSaveOrders(
        newJsonString: String, existingJsonString: String, characterId: Int64
    ) async {
        guard let existingData = existingJsonString.data(using: .utf8),
            let existingOrders = try? JSONDecoder().decode(
                [CharacterMarketOrder].self, from: existingData
            ),
            let newData = newJsonString.data(using: .utf8),
            let newOrders = try? JSONDecoder().decode([CharacterMarketOrder].self, from: newData)
        else {
            // 如果合并失败，至少保存新数据
            saveOrdersToCache(jsonString: newJsonString, characterId: characterId)
            return
        }

        // 合并并去重
        let allOrders = Set(existingOrders).union(newOrders)
        let mergedOrders = Array(allOrders).sorted { $0.issued > $1.issued }

        // 保存合并后的数据
        if let mergedData = try? JSONEncoder().encode(mergedOrders),
            let mergedString = String(data: mergedData, encoding: .utf8)
        {
            saveOrdersToCache(jsonString: mergedString, characterId: characterId)
        } else {
            // 如果合并后的数据编码失败，保存新数据
            saveOrdersToCache(jsonString: newJsonString, characterId: characterId)
        }
    }
}
