import Foundation

class CharacterMarketAPI {
    static let shared = CharacterMarketAPI()
    
    private struct CachedData: Codable {
        let orders: [CharacterMarketOrder]
        let timestamp: Date
    }
    
    private let cachePrefix = "character_market_orders_cache_"
    private let cacheTimeout: TimeInterval = 3 * 24 * 60 * 60 // 3 天缓存
    
    private init() {}
    
    private func getCacheKey(characterId: Int64) -> String {
        return "\(cachePrefix)\(characterId)"
    }
    
    private func isCacheValid(_ cache: CachedData) -> Bool {
        return Date().timeIntervalSince(cache.timestamp) < cacheTimeout
    }
    
    private func getCachedOrders(characterId: Int64) -> String? {
        let key = getCacheKey(characterId: characterId)
        guard let data = UserDefaults.standard.data(forKey: key),
              let cache = try? JSONDecoder().decode(CachedData.self, from: data),
              isCacheValid(cache) else {
            return nil
        }
        
        // 将缓存的订单转换回JSON字符串
        guard let jsonData = try? JSONEncoder().encode(cache.orders),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return nil
        }
        
        return jsonString
    }
    
    private func saveOrdersToCache(jsonString: String, characterId: Int64) {
        // 将JSON字符串转换为订单数组
        guard let jsonData = jsonString.data(using: .utf8),
              let orders = try? JSONDecoder().decode([CharacterMarketOrder].self, from: jsonData) else {
            return
        }
        
        let cache = CachedData(orders: orders, timestamp: Date())
        let key = getCacheKey(characterId: characterId)
        
        if let encoded = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
    
    public func getMarketOrders(characterId: Int64, forceRefresh: Bool = false) async throws -> String? {
        // 检查缓存
        if !forceRefresh {
            if let cachedJson = getCachedOrders(characterId: characterId) {
                Logger.debug("使用缓存的市场订单数据")
                return cachedJson
            }
        }
        
        // 构建URL
        let urlString = "https://esi.evetech.net/latest/characters/\(characterId)/orders/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        
        // 获取数据
        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: Int(characterId)
        )
        
        // 验证返回的数据是否可以解码为订单数组
        _ = try JSONDecoder().decode([CharacterMarketOrder].self, from: data)
        
        // 转换为字符串
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw NetworkError.invalidResponse
        }
        
        // 保存到缓存
        saveOrdersToCache(jsonString: jsonString, characterId: characterId)
        
        return jsonString
    }
} 
