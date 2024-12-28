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
    private let cacheTimeout: TimeInterval = 8 * 3600 // 8 小时缓存
    
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
    
    // 钱包交易记录缓存前缀
    private let walletTransactionsCachePrefix = "wallet_transactions_cache_"
    
    // 钱包交易记录缓存结构
    private struct WalletTransactionsCacheEntry: Codable {
        let jsonString: String
        let timestamp: Date
    }
    
    private init() {
        // 从 UserDefaults 恢复缓存
        let defaults = UserDefaults.standard
        Logger.debug("正在从 UserDefaults 读取所有钱包缓存键")
        for key in defaults.dictionaryRepresentation().keys {
            if key.hasPrefix(walletCachePrefix),
               let data = defaults.data(forKey: key),
               let entry = try? JSONDecoder().decode(CacheEntry.self, from: data),
               let characterId = Int(key.replacingOccurrences(of: walletCachePrefix, with: "")) {
                memoryCache[characterId] = entry
            }
        }
    }
    
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
    
    // 检查日志缓存是否有效
    private func isJournalCacheValid(_ cache: WalletJournalCacheEntry) -> Bool {
        let timeInterval = Date().timeIntervalSince(cache.timestamp)
        return timeInterval < cacheTimeout
    }
    
    // 检查交易记录缓存是否有效
    private func isTransactionsCacheValid(_ cache: WalletTransactionsCacheEntry) -> Bool {
        let timeInterval = Date().timeIntervalSince(cache.timestamp)
        return timeInterval < cacheTimeout
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
            Logger.info("保存钱包缓存到磁盘 - Key: \(key), 缓存时间: \(cache.timestamp), 值: \(cache.value), 数据大小: \(encoded.count) bytes")
            UserDefaults.standard.set(encoded, forKey: key)
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
            Logger.info("保存钱包日志到缓存 - Key: \(key), 数据大小: \(encoded.count) bytes")
            UserDefaults.standard.set(encoded, forKey: key)
        } else {
            Logger.error("保存钱包日志到缓存失败 - Key: \(key)")
        }
    }
    
    // 获取钱包日志（公开方法）
    public func getWalletJournal(characterId: Int, forceRefresh: Bool = false) async throws -> String? {
        // 检查缓存
        if !forceRefresh {
            if let cachedJson = getCachedJournal(characterId: characterId) {
                Logger.info("使用缓存的钱包日志数据")
                
                // 检查缓存是否过期
                let key = getJournalCacheKey(characterId: characterId)
                if let data = UserDefaults.standard.data(forKey: key),
                   let cache = try? JSONDecoder().decode(WalletJournalCacheEntry.self, from: data),
                   Date().timeIntervalSince(cache.timestamp) > cacheTimeout {
                    // 如果缓存过期，在后台刷新
                    Task {
                        do {
                            // 获取新数据
                            let newJournalData = try await fetchJournalFromServer(characterId: characterId)
                            
                            // 解析现有缓存数据
                            if let existingData = cachedJson.data(using: .utf8),
                               let existingEntries = try? JSONSerialization.jsonObject(with: existingData) as? [[String: Any]] {
                                
                                // 合并新旧数据并去重
                                var allEntries = existingEntries
                                allEntries.append(contentsOf: newJournalData)
                                
                                // 根据 journal_ref_id 去重
                                let uniqueEntries = Dictionary(grouping: allEntries) { entry in
                                    return entry["id"] as? Int64 ?? 0
                                }.values.compactMap { $0.first }
                                
                                // 按时间排序
                                let sortedEntries = uniqueEntries.sorted { entry1, entry2 in
                                    let date1 = entry1["date"] as? String ?? ""
                                    let date2 = entry2["date"] as? String ?? ""
                                    return date1 > date2
                                }
                                
                                // 转换为JSON
                                let jsonData = try JSONSerialization.data(withJSONObject: sortedEntries, options: [.prettyPrinted, .sortedKeys])
                                if let jsonString = String(data: jsonData, encoding: .utf8) {
                                    // 保存到缓存
                                    saveJournalToCache(jsonString: jsonString, characterId: characterId)
                                    // 在主线程发送通知
                                    await MainActor.run {
                                        NotificationCenter.default.post(name: NSNotification.Name("WalletJournalUpdated"), object: nil, userInfo: ["characterId": characterId])
                                    }
                                }
                            }
                        } catch {
                            Logger.error("后台更新钱包日志失败: \(error)")
                        }
                    }
                }
                return cachedJson
            }
        }
        
        // 如果没有缓存或强制刷新，从服务器获取
        let journalData = try await fetchJournalFromServer(characterId: characterId)
        
        // 转换为JSON
        let jsonData = try JSONSerialization.data(withJSONObject: journalData, options: [.prettyPrinted, .sortedKeys])
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw NetworkError.invalidResponse
        }
        
        // 保存到缓存
        saveJournalToCache(jsonString: jsonString, characterId: characterId)
        return jsonString
    }
    
    // 从服务器获取钱包日志
    private func fetchJournalFromServer(characterId: Int) async throws -> [[String: Any]] {
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
        
        return allJournalEntries
    }
    
    // 获取钱包交易记录的缓存键
    private func getTransactionsCacheKey(characterId: Int) -> String {
        return walletTransactionsCachePrefix + String(characterId)
    }
    
    // 获取钱包交易记录（公开方法）
    public func getWalletTransactions(characterId: Int, forceRefresh: Bool = false) async throws -> String? {
        // 检查缓存
        if !forceRefresh {
            let key = getTransactionsCacheKey(characterId: characterId)
            if let data = UserDefaults.standard.data(forKey: key),
               let cache = try? JSONDecoder().decode(WalletTransactionsCacheEntry.self, from: data),
               isTransactionsCacheValid(cache) {
                Logger.debug("使用缓存的钱包交易记录")
                return cache.jsonString
            }
        }
        
        let urlString = "https://esi.evetech.net/latest/characters/\(characterId)/wallet/transactions/"
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
        let cache = WalletTransactionsCacheEntry(jsonString: jsonString, timestamp: Date())
        let key = getTransactionsCacheKey(characterId: characterId)
        if let encoded = try? JSONEncoder().encode(cache) {
            Logger.info("保存钱包交易记录到缓存 - Key: \(key), 数据大小: \(encoded.count) bytes")
            UserDefaults.standard.set(encoded, forKey: key)
        }
        
        return jsonString
    }
} 
