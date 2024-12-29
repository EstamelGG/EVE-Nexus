import Foundation

class CharacterMarketAPI {
    static let shared = CharacterMarketAPI()
    
    private struct CachedData: Codable {
        let orders: [CharacterMarketOrder]
        let timestamp: Date
    }
    
    private let cachePrefix = "character_market_orders_cache_"
    private let cacheTimeout: TimeInterval = 8 * 60 * 60 // 8 小时缓存 UserDefaults
    
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
              let cache = try? JSONDecoder().decode(CachedData.self, from: data) else {
            return nil
        }
        
        // 计算并打印缓存剩余有效期
        let remainingTime = cacheTimeout - Date().timeIntervalSince(cache.timestamp)
        let remainingHours = Int(remainingTime / 3600)
        let remainingMinutes = Int((remainingTime.truncatingRemainder(dividingBy: 3600)) / 60)
        Logger.debug("市场订单缓存剩余有效期: \(remainingHours)小时 \(remainingMinutes)分钟 - 角色ID: \(characterId)")
        
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
            Logger.debug("保存市场订单数据到缓存成功 - 角色ID: \(characterId)")
        }
    }
    
    private func fetchFromNetwork(characterId: Int64) async throws -> String {
        let urlString = "https://esi.evetech.net/latest/characters/\(characterId)/orders/?datasource=tranquility"
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
    
    public func getMarketOrders(
        characterId: Int64,
        forceRefresh: Bool = false,
        progressCallback: ((Bool) -> Void)? = nil
    ) async throws -> String? {
        // 1. 先尝试获取缓存
        if !forceRefresh {
            if let cachedJson = getCachedOrders(characterId: characterId) {
                // 检查缓存是否过期
                let key = getCacheKey(characterId: characterId)
                if let data = UserDefaults.standard.data(forKey: key),
                   let cache = try? JSONDecoder().decode(CachedData.self, from: data),
                   !isCacheValid(cache) {
                    
                    // 如果缓存过期，在后台刷新
                    Logger.info("使用过期的市场订单缓存数据，将在后台刷新 - 角色ID: \(characterId)")
                    Task {
                        do {
                            progressCallback?(true)
                            let jsonString = try await fetchFromNetwork(characterId: characterId)
                            
                            // 合并新旧数据
                            if let existingData = cachedJson.data(using: .utf8),
                               let existingOrders = try? JSONDecoder().decode([CharacterMarketOrder].self, from: existingData),
                               let newData = jsonString.data(using: .utf8),
                               let newOrders = try? JSONDecoder().decode([CharacterMarketOrder].self, from: newData) {
                                
                                // 合并并去重
                                let allOrders = Set(existingOrders).union(newOrders)
                                let mergedOrders = Array(allOrders).sorted { $0.issued > $1.issued }
                                
                                // 保存合并后的数据
                                if let mergedData = try? JSONEncoder().encode(mergedOrders),
                                   let mergedString = String(data: mergedData, encoding: .utf8) {
                                    saveOrdersToCache(jsonString: mergedString, characterId: characterId)
                                }
                            } else {
                                // 如果合并失败，至少保存新数据
                                saveOrdersToCache(jsonString: jsonString, characterId: characterId)
                            }
                            
                            progressCallback?(false)
                        } catch {
                            Logger.error("后台刷新市场订单数据失败: \(error)")
                            progressCallback?(false)
                        }
                    }
                } else {
                    Logger.info("使用有效的市场订单缓存数据 - 角色ID: \(characterId)")
                }
                
                return cachedJson
            }
        }
        
        // 2. 如果强制刷新或没有缓存，从网络获取
        progressCallback?(true)
        let jsonString = try await fetchFromNetwork(characterId: characterId)
        
        // 3. 如果有缓存数据，尝试合并
        if let cachedJson = getCachedOrders(characterId: characterId),
           let existingData = cachedJson.data(using: .utf8),
           let existingOrders = try? JSONDecoder().decode([CharacterMarketOrder].self, from: existingData),
           let newData = jsonString.data(using: .utf8),
           let newOrders = try? JSONDecoder().decode([CharacterMarketOrder].self, from: newData) {
            
            // 合并并去重
            let allOrders = Set(existingOrders).union(newOrders)
            let mergedOrders = Array(allOrders).sorted { $0.issued > $1.issued }
            
            // 保存并返回合并后的数据
            if let mergedData = try? JSONEncoder().encode(mergedOrders),
               let mergedString = String(data: mergedData, encoding: .utf8) {
                saveOrdersToCache(jsonString: mergedString, characterId: characterId)
                progressCallback?(false)
                return mergedString
            }
        }
        
        // 4. 如果没有缓存或合并失败，使用新数据
        saveOrdersToCache(jsonString: jsonString, characterId: characterId)
        progressCallback?(false)
        return jsonString
    }
} 
