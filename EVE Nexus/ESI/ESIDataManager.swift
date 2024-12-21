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
            return cachedEntry.value
        }
        
        let urlString = "https://esi.evetech.net/latest/characters/\(characterId)/wallet/"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        
        // 从EVELogin获取角色的token
        guard EVELogin.shared.getCharacterByID(characterId) != nil else {
            throw NetworkError.unauthed
        }
        
        // 获取有效的token（如果过期会自动刷新）
        let validToken = try await EVELogin.shared.getValidToken()
        Logger.info("Token refreshed")
        var request = URLRequest(url: url)
        request.addValue("Bearer \(validToken)", forHTTPHeaderField: "Authorization")
        request.addValue("tranquility", forHTTPHeaderField: "datasource")
        
        let data = try await NetworkManager.shared.fetchData(from: url, request: request)
        
        guard let stringValue = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let balance = Double(stringValue) else {
            throw NetworkError.invalidResponse
        }
        
        // 更新缓存
        walletCache[characterId] = CacheEntry(value: balance, timestamp: Date())
        
        return balance
    }
} 
