@preconcurrency import AppAuth
import Foundation

actor AuthTokenManager: NSObject {
    static let shared = AuthTokenManager()
    private var authStates: [Int: OIDAuthState] = [:]
    
    private override init() {
        super.init()
    }
    
    func getAccessToken(for characterId: Int) async throws -> String {
        let authState = try await getOrCreateAuthState(for: characterId)
        return try await withCheckedThrowingContinuation { continuation in
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
    
    private func getOrCreateAuthState(for characterId: Int) async throws -> OIDAuthState {
        // 如果存在有效的状态，直接返回
        if let existingState = authStates[characterId] {
            return existingState
        }
        
        // 从存储中恢复 refresh token
        guard let refreshToken = try? SecureStorage.shared.loadToken(for: characterId) else {
            throw NetworkError.authenticationError("No refresh token found")
        }
        
        // 获取配置
        let issuer = URL(string: "https://login.eveonline.com")!
        let configuration = try await OIDAuthorizationService.discoverConfiguration(forIssuer: issuer)
        let redirectURI = URL(string: "eveauthpanel://callback/")!
        let clientId = EVELogin.shared.config?.clientId ?? ""
        
        // 创建 token 请求
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
        let response: OIDTokenResponse = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<OIDTokenResponse, Error>) in
            OIDAuthorizationService.perform(request) { response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let response = response {
                    continuation.resume(returning: response)
                } else {
                    continuation.resume(throwing: NetworkError.invalidData)
                }
            }
        }
        
        // 创建 auth state
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
        
        // 保存有效的状态
        authStates[characterId] = authState
        return authState
    }
    
    func clearTokens(for characterId: Int) {
        if let authState = authStates.removeValue(forKey: characterId) {
            authState.stateChangeDelegate = nil
        }
        
        try? SecureStorage.shared.deleteToken(for: characterId)
    }
}

extension AuthTokenManager: OIDAuthStateChangeDelegate {
    nonisolated func didChange(_ state: OIDAuthState) {
        // 当 auth state 发生变化时保存新的 refresh token
        if let refreshToken = state.refreshToken {
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let characterId = await self.findCharacterId(for: state) {
                    try? SecureStorage.shared.saveToken(refreshToken, for: characterId)
                }
            }
        }
    }
    
    private func findCharacterId(for state: OIDAuthState) async -> Int? {
        return authStates.first(where: { $0.value === state })?.key
    }
}

// 网络请求的包装器
extension URLSession {
    func dataRequest(for request: URLRequest, characterId: Int) async throws -> (Data, URLResponse) {
        do {
            let token = try await AuthTokenManager.shared.getAccessToken(for: characterId)
            var authenticatedRequest = request
            authenticatedRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await URLSession.shared.data(for: authenticatedRequest)
            
            // 如果收到 401，AppAuth 会在下次请求时自动刷新 token
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 401 {
                // 重试一次
                let token = try await AuthTokenManager.shared.getAccessToken(for: characterId)
                authenticatedRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                return try await URLSession.shared.data(for: authenticatedRequest)
            }
            
            return (data, response)
        } catch {
            throw error
        }
    }
} 
