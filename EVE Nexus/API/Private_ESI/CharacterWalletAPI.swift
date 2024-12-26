import Foundation

class CharacterWalletAPI {
    static let shared = CharacterWalletAPI()
    
    // 缓存结构
    private struct CacheEntry: Codable {
        let value: String  // 改用字符串存储以保持精度
        let timestamp: Date
    }
    
    // 添加并发队列用于同步访问
    private let cacheQueue = DispatchQueue(label: "com.eve-nexus.wallet-cache", attributes: .concurrent)
    
    // 内存缓存
    private var memoryCache: [Int: CacheEntry] = [:]
    private let cacheTimeout: TimeInterval = 30 * 60 // 30分钟缓存
    
    // UserDefaults键前缀
    private let walletCachePrefix = "wallet_cache_"
    
    // MARK: - Wallet Journal Methods
    
    // 钱包日志缓存结构
    private struct WalletJournalCacheEntry: Codable {
        let jsonString: String
        let timestamp: Date
    }
    
    // 钱包日志缓存前缀
    private let walletJournalCachePrefix = "wallet_journal_cache_"
    
    private init() {}
    
    // 安全地获取钱包缓存
    private func getWalletMemoryCache(characterId: Int) -> CacheEntry? {
        var result: CacheEntry?
        cacheQueue.sync {
            result = memoryCache[characterId]
        }
        return result
    }
    
    // 安全地设置钱包缓存
    private func setWalletMemoryCache(characterId: Int, cache: CacheEntry) {
        cacheQueue.async(flags: .barrier) {
            self.memoryCache[characterId] = cache
        }
    }
    
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
        cacheQueue.async(flags: .barrier) {
            self.memoryCache.removeValue(forKey: characterId)
            let key = self.walletCachePrefix + String(characterId)
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
    
    // 获取缓存的钱包余额（异步方法）
    func getCachedWalletBalance(characterId: Int) async -> String {
        // 1. 先检查内存缓存
        if let memoryCached = getWalletMemoryCache(characterId: characterId) {
            return memoryCached.value
        }
        
        // 2. 如果内存缓存不可用，检查磁盘缓存
        if let diskCached = getDiskCache(characterId: characterId) {
            // 更新内存缓存
            setWalletMemoryCache(characterId: characterId, cache: diskCached)
            return diskCached.value
        }
        
        return "-"
    }
    
    // 获取钱包余额（异步方法，用于后台刷新）
    func getWalletBalance(characterId: Int, forceRefresh: Bool = false) async throws -> Double {
        // 如果不是强制刷新，检查缓存是否有效
        if !forceRefresh {
            // 检查缓存
            let cachedResult: Double? = {
                if let memoryCached = getWalletMemoryCache(characterId: characterId), 
                   isCacheValid(memoryCached) {
                    Logger.info("使用内存缓存的钱包余额数据 - 角色ID: \(characterId)")
                    return Double(memoryCached.value)
                }
                
                if let diskCached = getDiskCache(characterId: characterId),
                   isCacheValid(diskCached) {
                    Logger.info("使用磁盘缓存的钱包余额数据 - 角色ID: \(characterId)")
                    setWalletMemoryCache(characterId: characterId, cache: diskCached)
                    return Double(diskCached.value)
                }
                
                return nil
            }()
            
            if let cachedValue = cachedResult {
                return cachedValue
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
        setWalletMemoryCache(characterId: characterId, cache: cacheEntry)
        
        // 更新磁盘缓存
        saveToDiskCache(characterId: characterId, cache: cacheEntry)
        
        return Double(stringValue) ?? 0.0
    }
    
    // 获取钱包日志的缓存键
    private func getJournalCacheKey(characterId: Int) -> String {
        return walletJournalCachePrefix + String(characterId)
    }
    
    // 检查钱包日志缓存是否有效
    private func isJournalCacheValid(_ cache: WalletJournalCacheEntry) -> Bool {
        return Date().timeIntervalSince(cache.timestamp) < cacheTimeout
    }
    
    // 获取缓存的钱包日志
    private func getCachedJournal(characterId: Int) -> String? {
        let key = getJournalCacheKey(characterId: characterId)
        guard let data = UserDefaults.standard.data(forKey: key),
              let cache = try? JSONDecoder().decode(WalletJournalCacheEntry.self, from: data),
              isJournalCacheValid(cache) else {
            return nil
        }
        return cache.jsonString
    }
    
    // 保存钱包日志到缓存
    private func saveJournalToCache(jsonString: String, characterId: Int) {
        let cache = WalletJournalCacheEntry(jsonString: jsonString, timestamp: Date())
        let key = getJournalCacheKey(characterId: characterId)
        if let encoded = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(encoded, forKey: key)
            Logger.info("保存钱包日志到缓存 - Key: \(key)")
        } else {
            Logger.error("保存钱包日志到缓存失败 - Key: \(key)")
        }
    }
    
    // 获取钱包日志（公开方法）
    public func getWalletJournal(characterId: Int, forceRefresh: Bool = false) async throws -> String? {
        // 检查缓存
        if !forceRefresh {
            if let cachedJson = getCachedJournal(characterId: characterId) {
                Logger.debug("使用缓存的钱包日志")
                return cachedJson
            }
        }
        
        var allJournalEntries: [[String: Any]] = []
        var page = 1
        
        while true {
            do {
                let urlString = "https://esi.evetech.net/latest/characters/\(characterId)/wallet/journal/?datasource=tranquility&page=\(page)"
                guard let url = URL(string: urlString) else {
                    throw NetworkError.invalidURL
                }
                
                let data = try await NetworkManager.shared.fetchDataWithToken(
                    from: url,
                    characterId: characterId,
                    noRetryKeywords: ["Requested page does not exist"]
                )
                
                // 解析JSON数据
                guard let pageEntries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                    throw NetworkError.invalidResponse
                }
                
                allJournalEntries.append(contentsOf: pageEntries)
                Logger.info("成功获取第\(page)页钱包日志，本页包含\(pageEntries.count)条记录")
                
                page += 1
                try await Task.sleep(nanoseconds: UInt64(0.1 * 1_000_000_000)) // 100ms延迟
                
            } catch let error as NetworkError {
                if case .httpError(let statusCode, let message) = error,
                   statusCode == 500,
                   message?.contains("Requested page does not exist") == true {
                    // 这是正常的分页结束情况
                    Logger.info("钱包日志获取完成，共\(allJournalEntries.count)条记录")
                    break
                }
                // 其他网络错误则抛出
                throw error
            } catch {
                throw error
            }
        }
        
        // 如果没有获取到任何数据，返回空数组
        if allJournalEntries.isEmpty {
            let emptyJsonData = try JSONSerialization.data(withJSONObject: [], options: [.prettyPrinted, .sortedKeys])
            guard let jsonString = String(data: emptyJsonData, encoding: .utf8) else {
                throw NetworkError.invalidResponse
            }
            return jsonString
        }
        
        // 转换为JSON字符串
        let jsonData = try JSONSerialization.data(withJSONObject: allJournalEntries, options: [.prettyPrinted, .sortedKeys])
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw NetworkError.invalidResponse
        }
        
        // 保存到缓存
        saveJournalToCache(jsonString: jsonString, characterId: characterId)
        Logger.debug("Wallet journey: \(jsonString)")
        return jsonString
    }
} 
