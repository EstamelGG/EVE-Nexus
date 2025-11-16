import Foundation

class CharacterWalletAPI {
    static let shared = CharacterWalletAPI()

    // 缓存结构
    private struct CacheEntry: Codable {
        let value: String // 改用字符串存储以保持精度
        let timestamp: Date
    }

    // 添加并发队列用于同步访问
    private let cacheQueue = DispatchQueue(
        label: "com.eve-nexus.wallet-cache", attributes: .concurrent
    )

    // 内存缓存
    private var memoryCache: [Int: CacheEntry] = [:]
    private let cacheTimeout: TimeInterval = 20 * 60 // 20分钟缓存，钱包余额使用

    // UserDefaults键前缀
    private let walletCachePrefix = "wallet_cache_"

    /// 使指定角色的钱包相关缓存失效（包括流水、交易记录和钱包余额）
    /// - Parameters:
    ///   - characterId: 角色ID
    ///   - invalidateWalletBalance: 是否同时失效钱包余额缓存，默认为true
    private func invalidateCharacterWalletCache(characterId: Int, invalidateWalletBalance: Bool = true) {
        // 清除钱包流水的缓存
        WalletJournalAPI.shared.invalidateCache(characterId: characterId)

        // 清除交易记录的缓存
        WalletTransactionsAPI.shared.invalidateCache(characterId: characterId)

        // 删除角色钱包余额缓存（内存和磁盘）
        if invalidateWalletBalance {
            // 清除内存缓存
            cacheQueue.async(flags: .barrier) {
                self.memoryCache.removeValue(forKey: characterId)
            }

            // 清除磁盘缓存（UserDefaults）
            let cacheKey = walletCachePrefix + String(characterId)
            UserDefaults.standard.removeObject(forKey: cacheKey)
            Logger.info("已删除角色钱包余额缓存 - 角色ID: \(characterId)")
        }
    }

    private init() {
        // 从 UserDefaults 恢复缓存
        let defaults = UserDefaults.standard
        Logger.debug("正在从 UserDefaults 读取所有钱包缓存键")
        for key in defaults.dictionaryRepresentation().keys {
            if key.hasPrefix(walletCachePrefix),
               let data = defaults.data(forKey: key),
               let entry = try? JSONDecoder().decode(CacheEntry.self, from: data),
               let characterId = Int(key.replacingOccurrences(of: walletCachePrefix, with: ""))
            {
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
        Logger.info(
            "钱包缓存时间检查 - 缓存时间: \(cache.timestamp), 当前时间: \(Date()), 时间间隔: \(timeInterval)秒, 超时时间: \(cacheTimeout)秒, 是否有效: \(isValid)"
        )
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

        Logger.success("成功读取钱包磁盘缓存 - Key: \(key), 缓存时间: \(cache.timestamp), 值: \(cache.value)")
        return cache
    }

    // 保存缓存到UserDefaults
    private func saveToDiskCache(characterId: Int, cache: CacheEntry) {
        let key = walletCachePrefix + String(characterId)
        if let encoded = try? JSONEncoder().encode(cache) {
            Logger.info(
                "保存钱包缓存到磁盘 - Key: \(key), 缓存时间: \(cache.timestamp), 值: \(cache.value), 数据大小: \(encoded.count) bytes"
            )
            UserDefaults.standard.set(encoded, forKey: key)
        } else {
            Logger.error("保存钱包缓存到磁盘失败 - Key: \(key)")
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
        // 如果是强制刷新，先使关联缓存失效
        if forceRefresh {
            Logger.info("强制刷新角色钱包，使关联缓存失效 - 角色ID: \(characterId)")
            invalidateCharacterWalletCache(characterId: characterId)
        }

        // 如果不是强制刷新，检查缓存是否有效
        if !forceRefresh {
            // 检查缓存
            let cachedResult: Double? = {
                if let memoryCached = getWalletMemoryCache(characterId: characterId),
                   isCacheValid(memoryCached)
                {
                    Logger.info("使用内存缓存的钱包余额数据 - 角色ID: \(characterId)")
                    return Double(memoryCached.value)
                }

                if let diskCached = getDiskCache(characterId: characterId),
                   isCacheValid(diskCached)
                {
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

        let urlString = "https://esi.evetech.net/characters/\(characterId)/wallet/"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId
        )

        guard
            let stringValue = String(data: data, encoding: .utf8)?.trimmingCharacters(
                in: .whitespacesAndNewlines)
        else {
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

    // MARK: - 钱包流水和交易记录（委托给专门的API类）

    // 获取钱包流水
    func getWalletJournal(characterId: Int, forceRefresh: Bool = false) async throws -> String? {
        return try await WalletJournalAPI.shared.getWalletJournal(characterId: characterId, forceRefresh: forceRefresh)
    }

    // 获取钱包交易记录
    func getWalletTransactions(characterId: Int, forceRefresh: Bool = false) async throws -> String? {
        return try await WalletTransactionsAPI.shared.getWalletTransactions(characterId: characterId, forceRefresh: forceRefresh)
    }
}
