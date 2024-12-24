@preconcurrency import AppAuth
import Foundation

actor AuthTokenManager: NSObject {
    static let shared = AuthTokenManager()
    private var authStates: [Int: OIDAuthState] = [:]
    private var currentAuthorizationFlow: OIDExternalUserAgentSession?
    private let redirectURI = URL(string: "eveauthpanel://callback/")!
    
    private override init() {
        super.init()
    }
    
    // 获取授权URL配置
    private func getConfiguration() async throws -> OIDServiceConfiguration {
        let issuer = URL(string: "https://login.eveonline.com")!
        return try await OIDAuthorizationService.discoverConfiguration(forIssuer: issuer)
    }
    
    // 初始授权流程
    func authorize(presenting viewController: UIViewController, scopes: [String]) async throws -> OIDAuthState {
        return try await withCheckedThrowingContinuation { continuation in
            // 确保在主线程上执行 UI 操作
            DispatchQueue.main.async {
                guard let authorizationEndpoint = URL(string: "https://login.eveonline.com/v2/oauth/authorize/"),
                      let tokenEndpoint = URL(string: "https://login.eveonline.com/v2/oauth/token") else {
                    continuation.resume(throwing: NetworkError.invalidURL)
                    return
                }
                
                let configuration = OIDServiceConfiguration(
                    authorizationEndpoint: authorizationEndpoint,
                    tokenEndpoint: tokenEndpoint
                )
                
                let request = OIDAuthorizationRequest(
                    configuration: configuration,
                    clientId: "7339147833b44ad3815c7ef0957950c2",
                    clientSecret: "cgEH3hswersReqCFUyzRmsvb7C7wBAPYVq2IM2Of",
                    scopes: scopes,
                    redirectURL: self.redirectURI,
                    responseType: OIDResponseTypeCode,
                    additionalParameters: nil
                )
                
                // 在主线程上执行授权请求
                self.currentAuthorizationFlow = OIDAuthState.authState(byPresenting: request, presenting: viewController) { authState, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    guard let authState = authState else {
                        return
                    }
                    
                    continuation.resume(returning: authState)
                }
            }
        }
    }
    
    // 保存认证状态
    func saveAuthState(_ authState: OIDAuthState, for characterId: Int) {
        authState.stateChangeDelegate = self
        authStates[characterId] = authState
        
        // 保存 refresh token
        if let refreshToken = authState.refreshToken {
            try? SecureStorage.shared.saveToken(refreshToken, for: characterId)
        }
    }
    
    // 获取访问令牌
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
        let configuration = try await getConfiguration()
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
        let response: OIDTokenResponse = try await withCheckedThrowingContinuation { continuation in
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
    
    // 获取授权URL
    func getAuthorizationURL() -> URL? {
        let configuration = OIDServiceConfiguration(
            authorizationEndpoint: URL(string: "https://login.eveonline.com/v2/oauth/authorize/")!,
            tokenEndpoint: URL(string: "https://login.eveonline.com/v2/oauth/token")!
        )
        
        let request = OIDAuthorizationRequest(
            configuration: configuration,
            clientId: "7339147833b44ad3815c7ef0957950c2",
            clientSecret: "cgEH3hswersReqCFUyzRmsvb7C7wBAPYVq2IM2Of",
            scopes: EVELogin.shared.config?.scopes ?? [],
            redirectURL: URL(string: "eveauthpanel://callback/")!,
            responseType: OIDResponseTypeCode,
            additionalParameters: nil
        )
        
        return request.authorizationRequestURL()
    }
    
    // 创建并保存认证状态
    func createAndSaveAuthState(
        accessToken: String,
        refreshToken: String,
        expiresIn: Int,
        tokenType: String,
        characterId: Int
    ) async {
        let configuration = OIDServiceConfiguration(
            authorizationEndpoint: URL(string: "https://login.eveonline.com/v2/oauth/authorize/")!,
            tokenEndpoint: URL(string: "https://login.eveonline.com/v2/oauth/token")!
        )
        
        // 创建 mock 请求和响应
        let mockRequest = OIDAuthorizationRequest(
            configuration: configuration,
            clientId: "7339147833b44ad3815c7ef0957950c2",
            clientSecret: "cgEH3hswersReqCFUyzRmsvb7C7wBAPYVq2IM2Of",
            scopes: EVELogin.shared.config?.scopes ?? [],
            redirectURL: URL(string: "eveauthpanel://callback/")!,
            responseType: OIDResponseTypeCode,
            additionalParameters: nil
        )
        
        let mockResponse = OIDAuthorizationResponse(
            request: mockRequest,
            parameters: [
                "code": "mock_code" as NSString,
                "state": (mockRequest.state ?? "") as NSString
            ]
        )
        
        // 创建 token 响应
        let tokenRequest = OIDTokenRequest(
            configuration: configuration,
            grantType: OIDGrantTypeAuthorizationCode,
            authorizationCode: "mock_code",
            redirectURL: mockRequest.redirectURL,
            clientID: mockRequest.clientID,
            clientSecret: mockRequest.clientSecret,
            scope: mockRequest.scope,
            refreshToken: refreshToken,
            codeVerifier: nil,
            additionalParameters: nil
        )
        
        let tokenResponse = OIDTokenResponse(
            request: tokenRequest,
            parameters: [
                "access_token": accessToken as NSString,
                "refresh_token": refreshToken as NSString,
                "expires_in": String(expiresIn) as NSString,
                "token_type": tokenType as NSString
            ]
        )
        
        // 创建认证状态
        let authState = OIDAuthState(
            authorizationResponse: mockResponse,
            tokenResponse: tokenResponse
        )
        
        // 保存认证状态
        saveAuthState(authState, for: characterId)
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
