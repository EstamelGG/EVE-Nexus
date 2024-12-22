import Foundation

@MainActor
class TokenManager {
    static let shared = TokenManager()
    private var tokenCache: [Int: CachedToken] = [:]
    private let lock = NSLock()
    private var tokenRefreshTasks: [Int: Task<EVEAuthToken, Error>] = [:]
    
    private init() {}
    
    struct CachedToken {
        let token: EVEAuthToken
        let expirationDate: Date
        
        var isValid: Bool {
            return Date() < expirationDate
        }
    }
    
    // 获取有效的token
    func getToken(for characterId: Int) async throws -> EVEAuthToken {
        // 检查缓存
        if let cachedToken = tokenCache[characterId], cachedToken.isValid {
            return cachedToken.token
        }
        
        // 如果已经有正在进行的刷新任务，等待其完成
        if let existingTask = tokenRefreshTasks[characterId] {
            return try await existingTask.value
        }
        
        // 创建新的刷新任务
        let refreshTask = Task<EVEAuthToken, Error> {
            defer {
                tokenRefreshTasks[characterId] = nil
            }
            
            do {
                // 从 SecureStorage 获取 refresh token
                guard let refreshToken = try? SecureStorage.shared.loadToken(for: characterId) else {
                    throw NetworkError.authenticationError("No refresh token found")
                }
                
                // 刷新 token
                let newToken = try await EVELogin.shared.refreshToken(refreshToken: refreshToken, force: true)
                
                // 更新缓存
                let expirationDate = Date().addingTimeInterval(TimeInterval(newToken.expires_in))
                tokenCache[characterId] = CachedToken(token: newToken, expirationDate: expirationDate)
                
                // 保存新的refresh token
                try SecureStorage.shared.saveToken(newToken.refresh_token, for: characterId)
                
                Logger.info("TokenManager: Token刷新成功 - 角色ID: \(characterId)")
                return newToken
            } catch {
                // 如果刷新失败，清除所有相关缓存
                Logger.error("TokenManager: Token刷新失败 - 角色ID: \(characterId), 错误: \(error)")
                clearToken(for: characterId)
                
                // 通知EVELogin token已过期
                EVELogin.shared.markTokenExpired(characterId: characterId)
                
                throw error
            }
        }
        
        tokenRefreshTasks[characterId] = refreshTask
        return try await refreshTask.value
    }
    
    // 清除指定角色的token缓存
    func clearToken(for characterId: Int) {
        lock.lock()
        defer { lock.unlock() }
        
        tokenCache.removeValue(forKey: characterId)
        tokenRefreshTasks[characterId]?.cancel()
        tokenRefreshTasks.removeValue(forKey: characterId)
        
        // 同时清除 SecureStorage 中的 token
        try? SecureStorage.shared.deleteToken(for: characterId)
    }
    
    // 清除所有缓存
    func clearCache(for characterId: Int) {
        clearToken(for: characterId)
    }
    
    // 检查token是否有效
    func isTokenValid(for characterId: Int) -> Bool {
        guard let cachedToken = tokenCache[characterId] else {
            return false
        }
        return cachedToken.isValid
    }
    
    // 更新token缓存
    func updateTokenCache(characterId: Int, cachedToken: CachedToken) {
        lock.lock()
        defer { lock.unlock() }
        
        tokenCache[characterId] = cachedToken
    }
} 