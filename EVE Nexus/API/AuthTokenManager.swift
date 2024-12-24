@preconcurrency import AppAuth
import Foundation

actor AuthTokenManager: NSObject {
    static let shared = AuthTokenManager()
    private var authStates: [Int: OIDAuthState] = [:]
    private var refreshTasks: [Int: Task<String, Error>] = [:]
    
    private override init() {
        super.init()
    }
    
    func getAccessToken(for characterId: Int) async throws -> String {
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
                            continuation.resume(returning: try await self.handleTokenRefresh(for: characterId))
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
    
    func retryWithFreshToken(for characterId: Int) async throws -> String {
        if let refreshTask = refreshTasks[characterId] {
            return try await refreshTask.value
        }
        return try await handleTokenRefresh(for: characterId)
    }
    
    private func handleTokenRefresh(for characterId: Int) async throws -> String {
        if let existingTask = refreshTasks[characterId] {
            return try await existingTask.value
        }
        
        let refreshTask = Task<String, Error> { [weak self] in
            guard let self = self else { throw NetworkError.invalidData }
            
            let newAuthState = try await self.refreshAuthState(for: characterId)
            let token = try await self.getAccessTokenFromState(newAuthState)
            
            await self.cleanupRefreshTask(for: characterId)
            return token
        }
        
        refreshTasks[characterId] = refreshTask
        return try await refreshTask.value
    }
    
    private func cleanupRefreshTask(for characterId: Int) {
        refreshTasks[characterId] = nil
    }
    
    private func getAccessTokenFromState(_ authState: OIDAuthState) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            authState.performAction { accessToken, _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let accessToken = accessToken {
                    continuation.resume(returning: accessToken)
                } else {
                    continuation.resume(throwing: NetworkError.invalidData)
                }
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
        return try await refreshAuthState(for: characterId)
    }
    
    private func createAuthState(refreshToken: String) async throws -> OIDAuthState {
        let configuration = try await getOAuthConfiguration()
        let request = createTokenRequest(with: configuration, refreshToken: refreshToken)
        
        let (authState, _): (OIDAuthState, OIDTokenResponse) = try await withCheckedThrowingContinuation { continuation in
            OIDAuthorizationService.perform(request) { response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let response = response else {
                    continuation.resume(throwing: NetworkError.invalidData)
                    return
                }
                
                let authState = self.createAuthStateFromResponse(response, configuration: configuration)
                continuation.resume(returning: (authState, response))
            }
        }
        
        return authState
    }
    
    private func createAuthStateFromResponse(_ response: OIDTokenResponse, configuration: OIDServiceConfiguration) -> OIDAuthState {
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
        return authState
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
    
    func clearTokens(for characterId: Int) async {
        Logger.info("AuthTokenManager: 开始清除Token - 角色ID: \(characterId)")
        
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
                guard let self = self else { return }
                
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
