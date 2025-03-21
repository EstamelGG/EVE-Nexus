@preconcurrency import AppAuth
import Foundation

actor AuthTokenManager: NSObject {
    static let shared = AuthTokenManager()
    private var authStates: [Int: OIDAuthState] = [:]
    private var currentAuthorizationFlow: OIDExternalUserAgentSession?
    private let redirectURI = URL(string: "eveauthpanel://callback/")!
    private var refreshingTokens: [Int: Task<String, Error>] = [:]

    override private init() {
        super.init()
    }

    // 验证认证状态是否有效
    private func validateAuthState(_ authState: OIDAuthState) -> Bool {
        guard let tokenResponse = authState.lastTokenResponse,
            let expirationDate = tokenResponse.accessTokenExpirationDate
        else {
            return false
        }

        // 提前5分钟认为token将过期
        let gracePeriod: TimeInterval = 5 * 60
        return Date().addingTimeInterval(gracePeriod) < expirationDate
    }

    // 显式刷新token
    private func refreshToken(for characterId: Int) async throws -> String {
        // 如果已经有正在进行的刷新任务，等待其完成
        if let existingTask = refreshingTokens[characterId] {
            Logger.info("等待现有的token刷新任务完成 - 角色ID: \(characterId)")
            return try await existingTask.value
        }

        // 创建新的刷新任务
        let task = Task<String, Error> {
            defer {
                refreshingTokens[characterId] = nil
            }

            guard let authState = authStates[characterId] else {
                throw NetworkError.authenticationError("No auth state found")
            }

            return try await withCheckedThrowingContinuation { continuation in
                authState.setNeedsTokenRefresh()  // 强制刷新
                authState.performAction { accessToken, _, error in
                    if let error = error {
                        Logger.error("刷新 token 失败: \(error)")
                        continuation.resume(throwing: error)
                    } else if let accessToken = accessToken {
                        Logger.info("Token 已刷新 - 角色ID: \(characterId)")
                        continuation.resume(returning: accessToken)
                    } else {
                        Logger.error("刷新 token 失败: 无效数据")
                        continuation.resume(throwing: NetworkError.invalidData)
                    }
                }
            }
        }

        // 保存刷新任务
        refreshingTokens[characterId] = task

        // 等待任务完成并返回结果
        return try await task.value
    }

    // 获取授权URL配置
    private func getConfiguration() async throws -> OIDServiceConfiguration {
        let issuer = URL(string: "https://login.eveonline.com")!
        return try await OIDAuthorizationService.discoverConfiguration(forIssuer: issuer)
    }

    // 初始授权流程
    func authorize(presenting viewController: UIViewController, scopes: [String]) async throws
        -> OIDAuthState
    {
        return try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                guard
                    let authorizationEndpoint = URL(
                        string: "https://login.eveonline.com/v2/oauth/authorize/"),
                    let tokenEndpoint = URL(string: "https://login.eveonline.com/v2/oauth/token")
                else {
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

                let authFlow = OIDAuthState.authState(
                    byPresenting: request, presenting: viewController
                ) { [] authState, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }

                    guard let authState = authState else {
                        return
                    }

                    continuation.resume(returning: authState)
                }

                Task {
                    await self.setCurrentAuthorizationFlow(authFlow)
                }
            }
        }
    }

    private func setCurrentAuthorizationFlow(_ flow: OIDExternalUserAgentSession?) {
        currentAuthorizationFlow = flow
    }

    func saveAuthState(_ authState: OIDAuthState, for characterId: Int) {
        authState.stateChangeDelegate = self
        authStates[characterId] = authState

        if let refreshToken = authState.refreshToken {
            try? SecureStorage.shared.saveToken(refreshToken, for: characterId)
        }
    }

    func getAccessToken(for characterId: Int) async throws -> String {
        let authState = try await getOrCreateAuthState(for: characterId)

        // 检查状态是否有效，如果无效则强制刷新
        if !validateAuthState(authState) {
            Logger.info("检测到token即将过期，主动刷新 - 角色ID: \(characterId)")
            return try await refreshToken(for: characterId)
        }

        return try await withCheckedThrowingContinuation { continuation in
            authState.performAction { accessToken, _, error in
                if let error = error {
                    Logger.error("获取 access token 失败: \(error)")
                    continuation.resume(throwing: error)
                } else if let accessToken = accessToken {
                    if let lastToken = authState.lastTokenResponse?.accessToken,
                        lastToken != accessToken
                    {
                        Logger.info("Token 已自动刷新 - 角色ID: \(characterId)")
                    }
                    continuation.resume(returning: accessToken)
                } else {
                    Logger.error("获取 access token 失败: 无效数据")
                    continuation.resume(throwing: NetworkError.invalidData)
                }
            }
        }
    }

    private func getOrCreateAuthState(for characterId: Int) async throws -> OIDAuthState {
        if let existingState = authStates[characterId] {
            return existingState
        }

        guard let refreshToken = try? SecureStorage.shared.loadToken(for: characterId) else {
            throw NetworkError.authenticationError("No refresh token found")
        }

        let configuration = try await getConfiguration()
        let redirectURI = URL(string: "eveauthpanel://callback/")!
        let clientId = EVELogin.shared.config?.clientId ?? ""

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
                "state": "refresh_token_flow" as NSString,
            ]
        )

        let authState = OIDAuthState(authorizationResponse: authResponse, tokenResponse: response)
        authState.stateChangeDelegate = self

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
                "state": (mockRequest.state ?? "") as NSString,
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
                "token_type": tokenType as NSString,
            ]
        )

        // 创建认证状态
        let authState = OIDAuthState(
            authorizationResponse: mockResponse,
            tokenResponse: tokenResponse
        )

        // 保存认证状态
        Logger.info("将登陆结果保存到 SecureStorage")
        saveAuthState(authState, for: characterId)
    }
}

extension AuthTokenManager: OIDAuthStateChangeDelegate {
    nonisolated func didChange(_ state: OIDAuthState) {
        Logger.info("登录状态改变，尝试刷新 refresh token")
        if let refreshToken = state.refreshToken {
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let characterId = await self.findCharacterId(for: state) {
                    Logger.info("登录状态改变，保存新的 refresh token")
                    try? SecureStorage.shared.saveToken(refreshToken, for: characterId)
                }
            }
        }
    }

    private func findCharacterId(for state: OIDAuthState) async -> Int? {
        return authStates.first(where: { $0.value === state })?.key
    }
}
