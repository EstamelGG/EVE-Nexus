import Foundation

class CharacterWalletAPI {
    static let shared = CharacterWalletAPI()
    
    // 缓存结构
    private struct CacheEntry: Codable {
        let value: String  // 改用字符串存储以保持精度
        let timestamp: Date
    }
    
    // 内存缓存
    private var memoryCache: [Int: CacheEntry] = [:]
    private let cacheTimeout: TimeInterval = 300 // 5分钟缓存
    
    // UserDefaults键前缀
    private let walletCachePrefix = "wallet_cache_"
    
    private init() {}
    
    // 检查缓存是否有效
    private func isCacheValid(_ cache: CacheEntry?) -> Bool {
        guard let cache = cache else { return false }
        return Date().timeIntervalSince(cache.timestamp) < cacheTimeout
    }
    
    // 从UserDefaults获取缓存
    private func getDiskCache(characterId: Int) -> CacheEntry? {
        let key = walletCachePrefix + String(characterId)
        guard let data = UserDefaults.standard.data(forKey: key),
              let cache = try? JSONDecoder().decode(CacheEntry.self, from: data) else {
            return nil
        }
        return cache
    }
    
    // 保存缓存到UserDefaults
    private func saveToDiskCache(characterId: Int, cache: CacheEntry) {
        let key = walletCachePrefix + String(characterId)
        if let encoded = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
    
    // 清除缓存
    private func clearCache(characterId: Int) {
        memoryCache.removeValue(forKey: characterId)
        let key = walletCachePrefix + String(characterId)
        UserDefaults.standard.removeObject(forKey: key)
    }
    
    // 获取钱包余额
    func getWalletBalance(characterId: Int, forceRefresh: Bool = false) async throws -> Double {
        // 如果不是强制刷新，先尝试使用缓存
        if !forceRefresh {
            // 1. 先检查内存缓存
            if let memoryCached = memoryCache[characterId], 
               isCacheValid(memoryCached) {
                Logger.info("使用内存缓存的钱包余额数据 - 角色ID: \(characterId)")
                return Double(memoryCached.value) ?? 0.0
            }
            
            // 2. 如果内存缓存不可用，检查磁盘缓存
            if let diskCached = getDiskCache(characterId: characterId),
               isCacheValid(diskCached) {
                Logger.info("使用磁盘缓存的钱包余额数据 - 角色ID: \(characterId)")
                // 更新内存缓存
                memoryCache[characterId] = diskCached
                return Double(diskCached.value) ?? 0.0
            }
            
            Logger.info("缓存未命中或已过期,需要从服务器获取钱包数据 - 角色ID: \(characterId)")
        }
        
        let urlString = "https://esi.evetech.net/latest/characters/\(characterId)/wallet/"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        
        // 使用NetworkManager的fetchDataWithToken方法获取数据
        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId
        )
        
        // 将数据转换为字符串
        guard let stringValue = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            Logger.error("无法解析钱包余额数据: \(String(data: data, encoding: .utf8) ?? "无数据")")
            throw NetworkError.invalidResponse
        }
        
        Logger.info("ESI响应: 钱包余额 = \(stringValue) ISK")
        
        // 创建新的缓存条目，直接存储字符串值
        let cacheEntry = CacheEntry(value: stringValue, timestamp: Date())
        
        // 更新内存缓存
        memoryCache[characterId] = cacheEntry
        
        // 更新磁盘缓存
        saveToDiskCache(characterId: characterId, cache: cacheEntry)
        
        // 返回时才转换为 Double
        return Double(stringValue) ?? 0.0
    }
} 
