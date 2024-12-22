import Foundation

class ESIDataManager {
    static let shared = ESIDataManager()
    
    // 缓存结构
    private struct CacheEntry<T> {
        let value: T
        let timestamp: Date
    }
    
    // 缓存字典
    private var walletCache: [Int: CacheEntry<Double>] = [:]
    private let cacheTimeout: TimeInterval = 300 // 5分钟缓存
    
    private init() {}
    
    // 检查缓存是否有效
    private func isCacheValid<T>(_ cache: CacheEntry<T>?) -> Bool {
        guard let cache = cache else { return false }
        return Date().timeIntervalSince(cache.timestamp) < cacheTimeout
    }
    
    // 获取钱包余额
    func getWalletBalance(characterId: Int) async throws -> Double {
        // 检查缓存
        if let cachedEntry = walletCache[characterId], isCacheValid(cachedEntry) {
            Logger.info("使用缓存的钱包余额数据 - 角色ID: \(characterId)")
            return cachedEntry.value
        }
        
        Logger.info("在线获取钱包余额 - 角色ID: \(characterId)")
        // 使用NetworkManager的fetchDataWithToken方法获取原始数据
        let data = try await NetworkManager.shared.fetchData(
            from: URL(string: "https://esi.evetech.net/latest/characters/\(characterId)/wallet/")!,
            request: {
                var request = URLRequest(url: URL(string: "https://esi.evetech.net/latest/characters/\(characterId)/wallet/")!)
                let token = try await TokenManager.shared.getToken(for: characterId)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("tranquility", forHTTPHeaderField: "datasource")
                return request
            }()
        )
        // 将数据转换为字符串
        guard let stringValue = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let balance = Double(stringValue) else {
            Logger.error("无法解析钱包余额数据: \(String(data: data, encoding: .utf8) ?? "无数据")")
            throw NetworkError.invalidResponse
        }
        // 更新缓存
        walletCache[characterId] = CacheEntry(value: balance, timestamp: Date())
        return balance
    }
} 
