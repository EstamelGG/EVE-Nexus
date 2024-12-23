import Foundation

@MainActor
class TokenManager {
    static let shared = TokenManager()
    private var tokenCache: [Int: CachedToken] = [:]
    private let lock = NSLock()
    private var tokenRefreshTasks: [Int: Task<EVEAuthToken, Error>] = [:]
    private var refreshTimers: [Int: Task<Void, Never>] = [:]
    
    private init() {}
    
    struct CachedToken {
        let token: EVEAuthToken
        let expirationDate: Date
        
        var isValid: Bool {
            return Date() < expirationDate
        }
    }
    
    // 添加定时刷新机制
    private func scheduleTokenRefresh(for characterId: Int, token: EVEAuthToken) {
        // 取消现有的定时器
        refreshTimers[characterId]?.cancel()
        
        // 创建新的定时器
        let refreshTask = Task {
            // 提前5分钟刷新
            let refreshInterval = TimeInterval(token.expires_in) - 300
            try? await Task.sleep(nanoseconds: UInt64(refreshInterval * 1_000_000_000))
            if !Task.isCancelled {
                do {
                    _ = try await getToken(for: characterId)
                    Logger.info("TokenManager: 定时刷新token成功 - 角色ID: \(characterId)")
                } catch {
                    Logger.error("TokenManager: 定时刷新token失败 - 角色ID: \(characterId), 错误: \(error)")
                }
            }
        }
        
        refreshTimers[characterId] = refreshTask
    }
    
    // 获取有效的token
    func getToken(for characterId: Int) async throws -> EVEAuthToken {
        // 检查缓存
        if let cachedToken = tokenCache[characterId], cachedToken.isValid {
            // 验证token的合法性
            if try await validateToken(cachedToken.token) {
                return cachedToken.token
            } else {
                // 如果token不合法，清除缓存并重新获取
                clearToken(for: characterId)
            }
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
                if let refreshToken = try? SecureStorage.shared.loadToken(for: characterId) {
                    // 使用现有的 refresh token
                    return try await refreshTokenWithRetry(refreshToken: refreshToken, characterId: characterId)
                }
                
                // 如果 SecureStorage 中没有找到，尝试从 UserDefaults 恢复
                Logger.info("TokenManager: 尝试从 UserDefaults 恢复 refresh token - 角色ID: \(characterId)")
                if let characters = try? JSONDecoder().decode([CharacterAuth].self, from: UserDefaults.standard.data(forKey: "EVECharacters") ?? Data()),
                   let character = characters.first(where: { $0.character.CharacterID == characterId }) {
                    
                    // 找到了角色信息，尝试恢复 refresh token
                    do {
                        try SecureStorage.shared.saveToken(character.token.refresh_token, for: characterId)
                        Logger.info("TokenManager: 成功从 UserDefaults 恢复 refresh token - 角色ID: \(characterId)")
                        return try await refreshTokenWithRetry(refreshToken: character.token.refresh_token, characterId: characterId)
                    } catch {
                        Logger.error("TokenManager: 恢复 refresh token 失败 - 角色ID: \(characterId), 错误: \(error)")
                    }
                }
                
                // 如果恢复失败，抛出错误
                throw NetworkError.authenticationError("No refresh token found")
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
        if let newToken = try? await refreshTask.value {
            // 设置定时刷新
            scheduleTokenRefresh(for: characterId, token: newToken)
            return newToken
        }
        
        throw NetworkError.tokenExpired
    }
    
    // 添加带重试的 token 刷新方法
    private func refreshTokenWithRetry(refreshToken: String, characterId: Int) async throws -> EVEAuthToken {
        var retryCount = 0
        var lastError: Error? = nil
        
        while retryCount < 3 {
            do {
                // 刷新 token
                let newToken = try await EVELogin.shared.refreshToken(refreshToken: refreshToken, force: true)
                Logger.info("TokenManager: Token已刷新 - 角色ID: \(characterId)")
                
                // 验证新token的合法性
                guard try await validateToken(newToken) else {
                    throw NetworkError.invalidToken("Invalid token format or signature")
                }
                
                // 更新缓存
                let expirationDate = Date().addingTimeInterval(TimeInterval(newToken.expires_in))
                tokenCache[characterId] = CachedToken(token: newToken, expirationDate: expirationDate)
                
                // 保存新的refresh token
                try SecureStorage.shared.saveToken(newToken.refresh_token, for: characterId)
                
                return newToken
            } catch {
                lastError = error
                retryCount += 1
                if retryCount < 3 {
                    // 等待一秒后重试
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    Logger.info("TokenManager: 重试刷新 token (第\(retryCount)次) - 角色ID: \(characterId)")
                }
            }
        }
        
        throw lastError ?? NetworkError.tokenExpired
    }
    
    // 验证token的合法性
    private func validateToken(_ token: EVEAuthToken) async throws -> Bool {
        let tokenPrefix = String(token.access_token.prefix(32))
        
        do {
            // 使用JWTValidator验证token
            guard let config = EVELogin.shared.config else {
                Logger.error("TokenManager: Token验证失败 - Token前缀: \(tokenPrefix), 错误: 配置未初始化")
                throw NetworkError.invalidData
            }
            
            let isValid = try await JWTValidator.validate(token.access_token, config: config)
            if isValid {
                Logger.info("TokenManager: Token验证成功 - Token前缀: \(tokenPrefix)")
            } else {
                Logger.warning("TokenManager: Token验证未通过 - Token前缀: \(tokenPrefix)")
            }
            return isValid
        } catch {
            Logger.error("TokenManager: Token验证失败 - Token前缀: \(tokenPrefix), 错误: \(error)")
            return false
        }
    }
    
    // 清除指定角色的token缓存
    func clearToken(for characterId: Int) {
        Logger.info("TokenManager: 开始清除Token - 角色ID: \(characterId)")
        
        lock.lock()
        defer { lock.unlock() }
        
        // 记录被清除的token信息
        if let cachedToken = tokenCache[characterId] {
            let tokenPrefix = String(cachedToken.token.access_token.prefix(32))
            Logger.info("TokenManager: 清除缓存Token - 角色ID: \(characterId), Token前缀: \(tokenPrefix)")
        }
        
        tokenCache.removeValue(forKey: characterId)
        tokenRefreshTasks[characterId]?.cancel()
        tokenRefreshTasks.removeValue(forKey: characterId)
        refreshTimers[characterId]?.cancel()
        refreshTimers.removeValue(forKey: characterId)
        
        // 同时清除 SecureStorage 中的 token
        do {
            try SecureStorage.shared.deleteToken(for: characterId)
            Logger.info("TokenManager: SecureStorage Token清除成功 - 角色ID: \(characterId)")
        } catch {
            Logger.error("TokenManager: SecureStorage Token清除失败 - 角色ID: \(characterId), 错误: \(error)")
        }
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
