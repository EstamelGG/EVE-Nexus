import Foundation

class CharacterMarketAPI {
    static let shared = CharacterMarketAPI()
    
    // 缓存结构
    private struct MarketOrdersCacheEntry: Codable {
        let jsonString: String
        let timestamp: Date
    }
    
    // 缓存前缀
    private let marketOrdersCachePrefix = "market_orders_cache_"
    
    // 缓存超时时间：3天
    private let cacheTimeout: TimeInterval = 3 * 24 * 60 * 60 // 3天，单位：秒
    
    private init() {
        Logger.debug("初始化 CharacterMarketAPI")
    }
    
    // 检查缓存是否有效
    private func isOrdersCacheValid(_ cache: MarketOrdersCacheEntry) -> Bool {
        let timeInterval = Date().timeIntervalSince(cache.timestamp)
        let isValid = timeInterval < cacheTimeout
        Logger.info("市场订单缓存时间检查 - 缓存时间: \(cache.timestamp), 当前时间: \(Date()), 时间间隔: \(timeInterval)秒, 超时时间: \(cacheTimeout)秒, 是否有效: \(isValid)")
        return isValid
    }
    
    // 获取缓存键
    private func getOrdersCacheKey(characterId: Int) -> String {
        return marketOrdersCachePrefix + String(characterId)
    }
    
    // 从缓存获取订单数据
    private func getCachedOrders(characterId: Int) -> String? {
        let key = getOrdersCacheKey(characterId: characterId)
        guard let data = UserDefaults.standard.data(forKey: key),
              let cache = try? JSONDecoder().decode(MarketOrdersCacheEntry.self, from: data),
              isOrdersCacheValid(cache) else {
            return nil
        }
        Logger.info("成功从缓存获取市场订单数据 - Key: \(key)")
        return cache.jsonString
    }
    
    // 保存订单数据到缓存
    private func saveOrdersToCache(jsonString: String, characterId: Int) {
        let cache = MarketOrdersCacheEntry(jsonString: jsonString, timestamp: Date())
        let key = getOrdersCacheKey(characterId: characterId)
        if let encoded = try? JSONEncoder().encode(cache) {
            Logger.info("保存市场订单到缓存 - Key: \(key), 数据大小: \(encoded.count) bytes")
            UserDefaults.standard.set(encoded, forKey: key)
        } else {
            Logger.error("保存市场订单到缓存失败 - Key: \(key)")
        }
    }
    
    // 获取市场订单（公开方法）
    public func getMarketOrders(characterId: Int, forceRefresh: Bool = false) async throws -> String? {
        // 检查缓存
        if !forceRefresh {
            if let cachedJson = getCachedOrders(characterId: characterId) {
                Logger.debug("使用缓存的市场订单数据")
                return cachedJson
            }
        }
        
        let urlString = "https://esi.evetech.net/latest/characters/\(characterId)/orders/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        
        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId
        )
        
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw NetworkError.invalidResponse
        }
        
        // 保存到缓存
        saveOrdersToCache(jsonString: jsonString, characterId: characterId)
        
        return jsonString
    }
} 