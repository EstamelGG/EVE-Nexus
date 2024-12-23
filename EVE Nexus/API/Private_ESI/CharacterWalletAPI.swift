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
        guard let cache = cache else { 
            Logger.info("钱包缓存为空")
            return false
        }
        let timeInterval = Date().timeIntervalSince(cache.timestamp)
        let isValid = timeInterval < cacheTimeout
        Logger.info("钱包缓存时间检查 - 缓存时间: \(cache.timestamp), 当前时间: \(Date()), 时间间隔: \(timeInterval)秒, 超时时间: \(cacheTimeout)秒, 是否有效: \(isValid)")
        return isValid
    }
    
    // 从UserDefaults获取缓存
    private func getDiskCache(characterId: Int) -> CacheEntry? {
        let key = walletCachePrefix + String(characterId)
        guard let data = UserDefaults.standard.data(forKey: key) else {
            Logger.info("钱包磁盘缓存不存在 - Key: \(key)")
            return nil
        }
        
        guard let cache = try? JSONDecoder().decode(CacheEntry.self, from: data) else {
            Logger.error("钱包磁盘缓存解码失败 - Key: \(key)")
            return nil
        }
        
        Logger.info("成功读取钱包磁盘缓存 - Key: \(key), 缓存时间: \(cache.timestamp), 值: \(cache.value)")
        return cache
    }
    
    // 保存缓存到UserDefaults
    private func saveToDiskCache(characterId: Int, cache: CacheEntry) {
        let key = walletCachePrefix + String(characterId)
        if let encoded = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(encoded, forKey: key)
            Logger.info("保存钱包缓存到磁盘 - Key: \(key), 缓存时间: \(cache.timestamp), 值: \(cache.value)")
        } else {
            Logger.error("保存钱包缓存到磁盘失败 - Key: \(key)")
        }
    }
    
    // 清除缓存
    private func clearCache(characterId: Int) {
        memoryCache.removeValue(forKey: characterId)
        let key = walletCachePrefix + String(characterId)
        UserDefaults.standard.removeObject(forKey: key)
    }
    
    // 获取缓存的钱包余额（同步方法）
    func getCachedWalletBalance(characterId: Int) -> String {
        // 1. 先检查内存缓存
        if let memoryCached = memoryCache[characterId] {
            return memoryCached.value
        }
        
        // 2. 如果内存缓存不可用，检查磁盘缓存
        if let diskCached = getDiskCache(characterId: characterId) {
            // 更新内存缓存
            memoryCache[characterId] = diskCached
            return diskCached.value
        }
        
        return "-"
    }
    
    // 获取钱包余额（异步方法，用于后台刷新）
    func getWalletBalance(characterId: Int, forceRefresh: Bool = false) async throws -> Double {
        // 如果不是强制刷新，检查缓存是否有效
        if !forceRefresh {
            if let memoryCached = memoryCache[characterId], 
               isCacheValid(memoryCached) {
                Logger.info("使用内存缓存的钱包余额数据 - 角色ID: \(characterId)")
                return Double(memoryCached.value) ?? 0.0
            }
            
            if let diskCached = getDiskCache(characterId: characterId),
               isCacheValid(diskCached) {
                Logger.info("使用磁盘缓存的钱包余额数据 - 角色ID: \(characterId)")
                memoryCache[characterId] = diskCached
                return Double(diskCached.value) ?? 0.0
            }
            
            Logger.info("缓存未命中或已过期,需要从服务器获取钱包数据 - 角色ID: \(characterId)")
        }
        
        let urlString = "https://esi.evetech.net/latest/characters/\(characterId)/wallet/"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        
        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId
        )
        
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
        
        return Double(stringValue) ?? 0.0
    }
} 
