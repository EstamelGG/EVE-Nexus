@preconcurrency import AppAuth
import Foundation

actor AuthTokenManager: NSObject {
    static let shared = AuthTokenManager()
    private var authStates: [Int: OIDAuthState] = [:]
    
    private override init() {
        super.init()
    }
    
    // 获取有效的access token
    func getAccessToken(for characterId: Int) async throws -> String {
        let authState = try await getOrCreateAuthState(for: characterId)
        return try await withCheckedThrowingContinuation { continuation in
            authState.performAction { accessToken, _, error in
                if let error = error {
                    Logger.error("AuthTokenManager: Token获取失败 - 角色ID: \(characterId), 错误: \(error)")
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let accessToken = accessToken else {
                    Logger.error("AuthTokenManager: Token无效 - 角色ID: \(characterId)")
                    continuation.resume(throwing: NetworkError.invalidData)
                    return
                }
                
                Logger.info("AuthTokenManager: 成功获取 access token - 角色ID: \(characterId)")
                continuation.resume(returning: accessToken)
            }
        }
    }
    
    private func getOrCreateAuthState(for characterId: Int) async throws -> OIDAuthState {
        // 检查现有的 auth state
        if let existingState = authStates[characterId] {
            return existingState
        }
        
        // 如果没有，从 SecureStorage 恢复
        guard let refreshToken = try? SecureStorage.shared.loadToken(for: characterId) else {
            Logger.error("AuthTokenManager: 无法从 SecureStorage 获取 refresh token - 角色ID: \(characterId)")
            throw NetworkError.authenticationError("No refresh token found")
        }
        
        // 创建新的 auth state
        let authState = try await createAuthState(characterId: characterId, refreshToken: refreshToken)
        authStates[characterId] = authState
        return authState
    }
    
    private func createAuthState(characterId: Int, refreshToken: String) async throws -> OIDAuthState {
        // 创建 OAuth 配置
        let issuer = URL(string: "https://login.eveonline.com")!
        let redirectURI = URL(string: "eve-nexus://oauth/callback")!
        let clientId = EVELogin.shared.config?.clientId ?? ""
        
        let configuration = try await OIDAuthorizationService.discoverConfiguration(forIssuer: issuer)
        
        // 创建 token request
        let request = OIDTokenRequest(
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
        
        // 执行 token 请求
        return try await withCheckedThrowingContinuation { continuation in
            OIDAuthorizationService.perform(request) { response, error in
                if let error = error {
                    Logger.error("AuthTokenManager: Token验证失败 - 角色ID: \(characterId), 错误: \(error)")
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let response = response else {
                    Logger.error("AuthTokenManager: Token响应无效 - 角色ID: \(characterId)")
                    continuation.resume(throwing: NetworkError.invalidData)
                    return
                }
                
                // 创建模拟的授权请求和响应
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
                
                // 创建 auth state
                let authState = OIDAuthState(authorizationResponse: authResponse, tokenResponse: response)
                authState.stateChangeDelegate = self
                
                Logger.info("AuthTokenManager: Token验证成功 - 角色ID: \(characterId)")
                continuation.resume(returning: authState)
            }
        }
    }
    
    func clearTokens(for characterId: Int) async {
        Logger.info("AuthTokenManager: 开始清除Token - 角色ID: \(characterId)")
        
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
        // 当 auth state 发生变化时（比如 token 刷新）会调用此方法
        if let refreshToken = state.refreshToken {
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                // 通过 auth state 的 lastTokenResponse 找到对应的 characterId
                if let characterId = await self.findCharacterId(for: state) {
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
    
    private func findCharacterId(for state: OIDAuthState) async -> Int? {
        return authStates.first(where: { $0.value === state })?.key
    }
} 