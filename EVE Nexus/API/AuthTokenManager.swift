@preconcurrency import AppAuth
import Foundation

actor AuthTokenManager: NSObject {
    static let shared = AuthTokenManager()
    private var authStates: [Int: OIDAuthState] = [:]
    private var refreshTasks: [Int: Task<String, Error>] = [:]
    private var continuations: [Int: [CheckedContinuation<String, Error>]] = [:]
    
    private override init() {
        super.init()
    }
    
    // 获取有效的access token
    func getAccessToken(for characterId: Int) async throws -> String {
        // 如果已经有刷新任务在进行，等待其完成
        if let refreshTask = refreshTasks[characterId] {
            return try await refreshTask.value
        }
        
        let authState = try await getOrCreateAuthState(for: characterId)
        return try await withCheckedThrowingContinuation { continuation in
            authState.performAction { [weak self] accessToken, _, error in
                guard let self else { return }
                
                Task {
                    do {
                        if let error = error as? NSError,
                           error.domain == OIDOAuthTokenErrorDomain {
                            // Token 过期，尝试刷新
                            let token = try await self.handleTokenRefresh(for: characterId)
                            continuation.resume(returning: token)
                        } else if let error {
                            continuation.resume(throwing: error)
                        } else if let accessToken {
                            continuation.resume(returning: accessToken)
                        } else {
                            continuation.resume(throwing: NetworkError.invalidData)
                        }
                    } catch {
                        Logger.error("AuthTokenManager: Token获取失败 - 角色ID: \(characterId), 错误: \(error)")
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    // 提供一个方法用于重试失败的请求
    func retryWithFreshToken(for characterId: Int) async throws -> String {
        // 直接等待或触发刷新
        if let refreshTask = refreshTasks[characterId] {
            return try await refreshTask.value
        }
        return try await handleTokenRefresh(for: characterId)
    }
    
    private func handleTokenRefresh(for characterId: Int) async throws -> String {
        // 如果已经有刷新任务在进行，等待其完成
        if let existingTask = refreshTasks[characterId] {
            return try await existingTask.value
        }
        
        // 创建新的刷新任务
        let refreshTask = Task<String, Error> { [weak self] in
            guard let self = self else {
                throw NetworkError.invalidData
            }
            
            do {
                // 执行刷新
                let newAuthState = try await self.refreshAuthState(for: characterId)
                let token = try await self.getAccessTokenFromState(newAuthState)
                
                // 在主 actor 上清理任务
                await self.cleanupRefreshTask(for: characterId)
                return token
            } catch {
                // 在主 actor 上清理任务和通知失败
                await self.handleRefreshFailure(characterId: characterId, error: error)
                throw error
            }
        }
        
        refreshTasks[characterId] = refreshTask
        let token = try await refreshTask.value
        resumeAllContinuations(for: characterId, with: .success(token))
        return token
    }
    
    private func cleanupRefreshTask(for characterId: Int) {
        refreshTasks[characterId] = nil
    }
    
    private func handleRefreshFailure(characterId: Int, error: Error) {
        refreshTasks[characterId] = nil
        resumeAllContinuations(for: characterId, with: .failure(error))
    }
    
    private func resumeAllContinuations(for characterId: Int, with result: Result<String, Error>) {
        let waitingList = continuations[characterId] ?? []
        continuations[characterId] = nil
        
        for continuation in waitingList {
            switch result {
            case .success(let token):
                continuation.resume(returning: token)
            case .failure(let error):
                continuation.resume(throwing: error)
            }
        }
    }
    
    private func getAccessTokenFromState(_ authState: OIDAuthState) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            authState.performAction { accessToken, _, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let accessToken else {
                    continuation.resume(throwing: NetworkError.invalidData)
                    return
                }
                
                continuation.resume(returning: accessToken)
            }
        }
    }
    
    private func refreshAuthState(for characterId: Int) async throws -> OIDAuthState {
        guard let refreshToken = try? SecureStorage.shared.loadToken(for: characterId) else {
            throw NetworkError.authenticationError("No refresh token found")
        }
        
        let newAuthState = try await createAuthState(refreshToken: refreshToken)
        authStates[characterId] = newAuthState
        return newAuthState
    }
    
    private func getOrCreateAuthState(for characterId: Int) async throws -> OIDAuthState {
        if let existingState = authStates[characterId] {
            return existingState
        }
        
        guard let refreshToken = try? SecureStorage.shared.loadToken(for: characterId) else {
            Logger.error("AuthTokenManager: 无法从 SecureStorage 获取 refresh token - 角色ID: \(characterId)")
            throw NetworkError.authenticationError("No refresh token found")
        }
        
        let authState = try await createAuthState(refreshToken: refreshToken)
        authStates[characterId] = authState
        return authState
    }
    
    private func createAuthState(refreshToken: String) async throws -> OIDAuthState {
        let configuration = try await getOAuthConfiguration()
        let request = createTokenRequest(with: configuration, refreshToken: refreshToken)
        
        return try await withCheckedThrowingContinuation { continuation in
            OIDAuthorizationService.perform(request) { [weak self] response, error in
                Task { [weak self] in
                    guard let self = self else { return }
                    do {
                        let authState = try await self.handleTokenResponse(response, error: error, configuration: configuration)
                        continuation.resume(returning: authState)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    private func getOAuthConfiguration() async throws -> OIDServiceConfiguration {
        let issuer = URL(string: "https://login.eveonline.com")!
        return try await OIDAuthorizationService.discoverConfiguration(forIssuer: issuer)
    }
    
    private func createTokenRequest(with configuration: OIDServiceConfiguration, refreshToken: String) -> OIDTokenRequest {
        let redirectURI = URL(string: "eve-nexus://oauth/callback")!
        let clientId = EVELogin.shared.config?.clientId ?? ""
        
        return OIDTokenRequest(
            configuration: configuration,
            grantType: OIDGrantTypeRefreshToken,
            authorizationCode: nil,
            redirectURL: redirectURI,
            clientID: clientId,
            clientSecret: nil,
            scope: nil,
            refreshToken: refreshToken,
            codeVerifier: nil,
            additionalParameters: nil
        )
    }
    
    private func handleTokenResponse(_ response: OIDTokenResponse?, error: Error?, configuration: OIDServiceConfiguration) async throws -> OIDAuthState {
        if let error {
            Logger.error("AuthTokenManager: Token验证失败, 错误: \(error)")
            throw error
        }
        
        guard let response else {
            Logger.error("AuthTokenManager: Token响应无效")
            throw NetworkError.invalidData
        }
        
        let redirectURI = URL(string: "eve-nexus://oauth/callback")!
        let clientId = EVELogin.shared.config?.clientId ?? ""
        
        let authRequest = OIDAuthorizationRequest(
            configuration: configuration,
            clientId: clientId,
            scopes: nil,
            redirectURL: redirectURI,
            responseType: OIDResponseTypeCode,
            additionalParameters: nil
        )
        
        let authResponse = OIDAuthorizationResponse(
            request: authRequest,
            parameters: [
                "code": "refresh_token_flow" as NSString,
                "state": "refresh_token_flow" as NSString
            ]
        )
        
        let authState = OIDAuthState(authorizationResponse: authResponse, tokenResponse: response)
        authState.stateChangeDelegate = self
        
        Logger.info("AuthTokenManager: Token验证成功")
        return authState
    }
    
    func clearTokens(for characterId: Int) async {
        Logger.info("AuthTokenManager: 开始清除Token - 角色ID: \(characterId)")
        
        // 取消所有等待的请求
        resumeAllContinuations(for: characterId, with: .failure(NetworkError.authenticationError("Token cleared")))
        
        refreshTasks[characterId]?.cancel()
        refreshTasks[characterId] = nil
        
        if let authState = authStates.removeValue(forKey: characterId) {
            authState.stateChangeDelegate = nil
        }
        
        do {
            try SecureStorage.shared.deleteToken(for: characterId)
            Logger.info("AuthTokenManager: SecureStorage Token清除成功 - 角色ID: \(characterId)")
        } catch {
            Logger.error("AuthTokenManager: SecureStorage Token清除失败 - 角色ID: \(characterId), 错误: \(error)")
        }
    }
}

extension AuthTokenManager: OIDAuthStateChangeDelegate {
    nonisolated func didChange(_ state: OIDAuthState) {
        if let refreshToken = state.refreshToken {
            Task { @MainActor [weak self] in
                guard let self else { return }
                
                if let characterId = try? await self.findCharacterId(for: state) {
                    do {
                        try SecureStorage.shared.saveToken(refreshToken, for: characterId)
                        Logger.info("AuthTokenManager: Auth state 变化，新的 refresh token 已保存 - 角色ID: \(characterId)")
                    } catch {
                        Logger.error("AuthTokenManager: Auth state 变化，保存 refresh token 失败 - 角色ID: \(characterId), 错误: \(error)")
                    }
                }
            }
        }
    }
    
    private func findCharacterId(for state: OIDAuthState) async throws -> Int {
        guard let characterId = authStates.first(where: { $0.value === state })?.key else {
            throw NetworkError.invalidData
        }
        return characterId
    }
}

// 扩展 NetworkError 以支持 token 过期检查
extension NetworkError {
    var isTokenExpired: Bool {
        switch self {
        case .authenticationError:
            return true
        default:
            return false
        }
    }
}

// 示例用法：网络请求的包装器
extension URLSession {
    func dataRequest(for request: URLRequest, characterId: Int) async throws -> (Data, URLResponse) {
        do {
            // 首先获取 token
            let token = try await AuthTokenManager.shared.getAccessToken(for: characterId)
            var authenticatedRequest = request
            authenticatedRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            // 执行请求
            let (data, response) = try await URLSession.shared.data(for: authenticatedRequest)
            
            // 检查响应
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 401 {
                // Token 可能在请求过程中过期，尝试重试
                let newToken = try await AuthTokenManager.shared.retryWithFreshToken(for: characterId)
                authenticatedRequest.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                return try await URLSession.shared.data(for: authenticatedRequest)
            }
            
            return (data, response)
        } catch {
            // 如果是认证错误，尝试重试
            if case NetworkError.authenticationError = error {
                let newToken = try await AuthTokenManager.shared.retryWithFreshToken(for: characterId)
                var authenticatedRequest = request
                authenticatedRequest.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                return try await URLSession.shared.data(for: authenticatedRequest)
            }
            throw error
        }
    }
} 
