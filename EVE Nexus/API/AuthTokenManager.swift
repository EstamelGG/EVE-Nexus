@preconcurrency import AppAuth
import Foundation

// 添加 SecureStorage 类
class SecureStorage {
    static let shared = SecureStorage()

    private init() {}

    func saveToken(_ token: String, for characterId: Int) throws {
        Logger.info(
            "SecureStorage: 开始保存 refresh token 到 SecureStorage - 角色ID: \(characterId), token前缀: \(String(token.prefix(10)))..."
        )

        guard let tokenData = token.data(using: .utf8) else {
            Logger.error("SecureStorage: 无法将 token 转换为数据")
            throw KeychainError.unhandledError(status: errSecParam)
        }

        let query: [String: Any] = [
            String(kSecClass): kSecClassGenericPassword,
            String(kSecAttrAccount): "token_\(characterId)",
            String(kSecValueData): tokenData,
            String(kSecAttrAccessible): kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            // 如果已存在，则更新
            let updateQuery: [String: Any] = [
                String(kSecClass): kSecClassGenericPassword,
                String(kSecAttrAccount): "token_\(characterId)",
            ]
            let updateAttributes: [String: Any] = [
                String(kSecValueData): tokenData
            ]
            let updateStatus = SecItemUpdate(
                updateQuery as CFDictionary, updateAttributes as CFDictionary
            )
            if updateStatus != errSecSuccess {
                Logger.error(
                    "SecureStorage: 更新 refresh token 失败 - 角色ID: \(characterId), 错误码: \(updateStatus)"
                )
                throw KeychainError.unhandledError(status: updateStatus)
            }
            Logger.info("SecureStorage: 成功更新了 refresh token - 角色ID: \(characterId)")
        } else if status != errSecSuccess {
            Logger.error(
                "SecureStorage: 保存 refresh token 失败 - 角色ID: \(characterId), 错误码: \(status)")
            throw KeychainError.unhandledError(status: status)
        } else {
            Logger.info("SecureStorage: 成功保存新的 refresh token - 角色ID: \(characterId)")
        }
    }

    func loadToken(for characterId: Int) throws -> String? {
        Logger.info("SecureStorage: 开始尝试从 Keychain 加载 refresh token - 角色ID: \(characterId)")

        let query: [String: Any] = [
            String(kSecClass): kSecClassGenericPassword,
            String(kSecAttrAccount): "token_\(characterId)",
            String(kSecReturnData): true,
            String(kSecMatchLimit): kSecMatchLimitOne,
        ]

        Logger.info("SecureStorage: 查询参数 - account: token_\(characterId)")

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            Logger.error(
                "SecureStorage: 在 Keychain 中未找到 refresh token - 角色ID: \(characterId), 错误: 项目不存在")
            return nil
        } else if status != errSecSuccess {
            Logger.error(
                "SecureStorage: 从 Keychain 加载 refresh token 失败 - 角色ID: \(characterId), 错误码: \(status)"
            )
            throw KeychainError.unhandledError(status: status)
        }

        guard let data = result as? Data else {
            Logger.error(
                "SecureStorage: refresh token 数据格式错误 - 角色ID: \(characterId), 无法转换为 Data 类型")
            return nil
        }

        guard let token = String(data: data, encoding: .utf8) else {
            Logger.error(
                "SecureStorage: refresh token 数据格式错误 - 角色ID: \(characterId), 无法转换为 UTF-8 字符串")
            return nil
        }

        Logger.info(
            "SecureStorage: 成功从 Keychain 加载 refresh token - 角色ID: \(characterId), token前缀: \(String(token.prefix(10)))..."
        )
        return token
    }

    func deleteRefreshToken(for characterId: Int) throws {
        let query: [String: Any] = [
            String(kSecClass): kSecClassGenericPassword,
            String(kSecAttrAccount): "token_\(characterId)",
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess, status != errSecItemNotFound {
            throw KeychainError.unhandledError(status: status)
        }
    }

    // 列出所有有效的 refresh token
    func listValidRefreshTokens() -> [Int] {
        Logger.info("SecureStorage: 开始检查所有有效的 refresh token")

        let query: [String: Any] = [
            String(kSecClass): kSecClassGenericPassword,
            String(kSecReturnAttributes): true,
            String(kSecMatchLimit): kSecMatchLimitAll,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            Logger.info("SecureStorage: 未找到任何 refresh token")
            return []
        } else if status != errSecSuccess {
            Logger.error("SecureStorage: 查询 refresh token 失败，错误码: \(status)")
            return []
        }

        guard let items = result as? [[String: Any]] else {
            Logger.error("SecureStorage: 无法解析查询结果")
            return []
        }

        var validCharacterIds: [Int] = []

        for item in items {
            if let account = item[String(kSecAttrAccount)] as? String,
                account.hasPrefix("token_"),
                let characterIdStr = account.split(separator: "_").last,
                let characterId = Int(characterIdStr)
            {
                // 检查 token 是否有效
                if let token = try? loadToken(for: characterId), !token.isEmpty {
                    validCharacterIds.append(characterId)
                    Logger.info("SecureStorage: 找到有效的 refresh token - 角色ID: \(characterId)")
                }
            }
        }

        Logger.info("SecureStorage: 共找到 \(validCharacterIds.count) 个有效的 refresh token")
        return validCharacterIds
    }
}

enum KeychainError: Error {
    case unhandledError(status: OSStatus)
}

// OAuth认证相关的数据模型
struct EVEAuthToken: Codable {
    let access_token: String
    let expires_in: Int
    let token_type: String
    let refresh_token: String
}

actor AuthTokenManager: NSObject {
    static let shared = AuthTokenManager()
    private var authStates: [Int: OIDAuthState] = [:]
    private var currentAuthorizationFlow: OIDExternalUserAgentSession?
    private let redirectURI = EVEConfig.OAuth.redirectURI
    private var tokenRefreshTasks: [Int: Task<String, Error>] = [:]

    override private init() {
        super.init()
    }

    /// 验证 access token 是否有效
    private func accessTokenNotExpired(_ authState: OIDAuthState) -> Bool {
        guard let tokenResponse = authState.lastTokenResponse,
            let expirationDate = tokenResponse.accessTokenExpirationDate
        else {
            return false
        }

        // 提前5分钟认为token将过期
        let gracePeriod: TimeInterval = 5 * 60
        return Date().addingTimeInterval(gracePeriod) < expirationDate
    }

    /// 刷新 access token（使用 refresh token 获取新的 access token）
    private func refreshAccessToken(for characterId: Int) async throws -> String {
        Logger.info("开始刷新 access token 流程 - 角色ID: \(characterId)")

        // 如果已经有正在进行的刷新任务，等待其完成
        if let existingTask = tokenRefreshTasks[characterId] {
            Logger.info("等待现有的token刷新任务完成 - 角色ID: \(characterId)")
            return try await existingTask.value
        }

        // 创建新的刷新任务
        let task = Task<String, Error> {
            defer {
                tokenRefreshTasks[characterId] = nil
            }

            guard let authState = authStates[characterId] else {
                Logger.error("未找到认证状态 - 角色ID: \(characterId)")
                throw NetworkError.authenticationError("No auth state found")
            }

            Logger.info("开始执行 token 刷新 - 角色ID: \(characterId)")
            return try await withCheckedThrowingContinuation { continuation in
                authState.setNeedsTokenRefresh()  // 强制刷新
                authState.performAction { accessToken, _, error in
                    if let error = error {
                        Logger.error("刷新 token 失败: \(error) - 角色ID: \(characterId)")
                        continuation.resume(throwing: error)
                    } else if let accessToken = accessToken {
                        Logger.info("Token 已刷新 - 角色ID: \(characterId)")
                        continuation.resume(returning: accessToken)
                    } else {
                        Logger.error("刷新 token 失败: 无效数据 - 角色ID: \(characterId)")
                        continuation.resume(throwing: NetworkError.invalidData)
                    }
                }
            }
        }

        // 保存刷新任务
        tokenRefreshTasks[characterId] = task

        // 等待任务完成并返回结果
        return try await task.value
    }

    /// 获取授权URL配置（用于 OAuth 流程）
    private func getConfiguration() async throws -> OIDServiceConfiguration {
        return try await OIDAuthorizationService.discoverConfiguration(
            forIssuer: EVEConfig.OAuth.baseURL)
    }

    /// 初始授权流程（获取 access token 和 refresh token）
    func authorize(presenting viewController: UIViewController, scopes: [String]) async throws
        -> OIDAuthState
    {
        return try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                let configuration = OIDServiceConfiguration(
                    authorizationEndpoint: EVEConfig.OAuth.authorizationEndpoint,
                    tokenEndpoint: EVEConfig.OAuth.tokenEndpoint
                )

                let request = OIDAuthorizationRequest(
                    configuration: configuration,
                    clientId: EVEConfig.OAuth.clientId,
                    clientSecret: EVEConfig.OAuth.clientSecret,
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
        // 比较前后状态来确定流程的变化
        currentAuthorizationFlow = flow
        if currentAuthorizationFlow != nil {
            Logger.info("currentAuthorizationFlow != nil")
        }
    }

    /// 保存认证状态（包括 access token 和 refresh token）
    func saveAuthState(_ authState: OIDAuthState, for characterId: Int) {
        authState.stateChangeDelegate = self
        authStates[characterId] = authState

        if let refreshToken = authState.refreshToken {
            try? SecureStorage.shared.saveToken(refreshToken, for: characterId)
        }
    }

    /// 获取 access token（如果即将过期会自动刷新）
    func getAccessToken(for characterId: Int) async throws -> String {
        Logger.info("开始获取 access token - 角色ID: \(characterId)")
        let authState = try await getOrCreateAuthState(for: characterId)
        Logger.info(
            "获取到 authState: \(authState), 过期时间: \(String(describing: authState.lastTokenResponse?.accessTokenExpirationDate))"
        )

        // 检查状态是否有效，如果无效则强制刷新
        if !accessTokenNotExpired(authState) {
            Logger.info(
                "检测到token即将过期，当前过期时间: \(String(describing: authState.lastTokenResponse?.accessTokenExpirationDate))"
            )
            Logger.info("开始主动刷新 token - 角色ID: \(characterId)")
            return try await refreshAccessToken(for: characterId)
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
                    Logger.info("成功获取 access token - 角色ID: \(characterId)")
                    continuation.resume(returning: accessToken)
                } else {
                    Logger.error("获取 access token 失败: 无效数据")
                    continuation.resume(throwing: NetworkError.invalidData)
                }
            }
        }
    }

    /// 清除所有 token（包括 access token 和 refresh token）
    func clearAllTokens(for characterId: Int) {
        // 删除内存中的access token
        if let authState = authStates.removeValue(forKey: characterId) {
            authState.stateChangeDelegate = nil
        }
        // 删除Keychain中的refresh token
        try? SecureStorage.shared.deleteRefreshToken(for: characterId)
    }

    /// 处理 invalid_grant 错误
    private func handleInvalidGrantError(characterId: Int) {
        // 删除Keychain中的token
        try? SecureStorage.shared.deleteRefreshToken(for: characterId)
        Logger.info("AuthTokenManager: 已删除过期的refresh token - 角色ID: \(characterId)")
        // 更新角色的 refreshTokenExpired 状态
        EVELogin.shared.updateCharacterRefreshTokenExpiredStatus(
            characterId: characterId, expired: true)
    }

    /// 获取或创建认证状态（使用 refresh token 恢复认证状态）
    private func getOrCreateAuthState(for characterId: Int) async throws -> OIDAuthState {
        Logger.info("开始获取或创建认证状态 - 角色ID: \(characterId)")

        if let existingState = authStates[characterId] {
            Logger.info("找到现有的认证状态 - 角色ID: \(characterId)")
            return existingState
        }

        Logger.info("未找到现有认证状态，尝试从 Keychain 加载 refresh token - 角色ID: \(characterId)")
        guard let refreshToken = try? SecureStorage.shared.loadToken(for: characterId) else {
            Logger.error("未找到 refresh token - 角色ID: \(characterId)")
            throw NetworkError.authenticationError("No refresh token found")
        }

        let configuration = try await getConfiguration()
        let redirectURI = EVEConfig.OAuth.redirectURI
        let clientId = EVELogin.shared.config?.clientId ?? ""

        Logger.info("开始创建 token 刷新请求 - 角色ID: \(characterId)")
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

        do {
            Logger.info("开始执行 token 刷新请求 - 角色ID: \(characterId)")
            let response: OIDTokenResponse = try await withCheckedThrowingContinuation {
                continuation in
                OIDAuthorizationService.perform(request) { response, error in
                    if let error = error {
                        Logger.error("Token 刷新请求失败: \(error) - 角色ID: \(characterId)")
                        // 检查是否是invalid_grant错误
                        if let oauthError = error as NSError?,
                            oauthError.domain == "org.openid.appauth.oauth_token",
                            oauthError.code == -10,
                            let errorResponse = oauthError.userInfo["OIDOAuthErrorResponseErrorKey"]
                                as? [String: Any],
                            errorResponse["error"] as? String == "invalid_grant"
                        {
                            Logger.error("检测到 invalid_grant 错误，需要重新登录 - 角色ID: \(characterId)")
                            // 处理 invalid_grant 错误
                            self.handleInvalidGrantError(characterId: characterId)
                        }
                        continuation.resume(throwing: error)
                    } else if let response = response {
                        Logger.info("Token 刷新请求成功 - 角色ID: \(characterId)")
                        continuation.resume(returning: response)
                    } else {
                        Logger.error("Token 刷新请求返回空响应 - 角色ID: \(characterId)")
                        continuation.resume(throwing: NetworkError.invalidData)
                    }
                }
            }

            Logger.info("开始创建认证状态 - 角色ID: \(characterId)")
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

            let authState = OIDAuthState(
                authorizationResponse: authResponse, tokenResponse: response)
            authState.stateChangeDelegate = self

            authStates[characterId] = authState
            Logger.info("成功创建并保存认证状态 - 角色ID: \(characterId)")
            return authState
        } catch {
            Logger.error("创建认证状态失败: \(error) - 角色ID: \(characterId)")
            // 如果是invalid_grant错误，确保token被删除
            if let oauthError = error as NSError?,
                oauthError.domain == "org.openid.appauth.oauth_token",
                oauthError.code == -10,
                let errorResponse = oauthError.userInfo["OIDOAuthErrorResponseErrorKey"]
                    as? [String: Any],
                errorResponse["error"] as? String == "invalid_grant"
            {
                Logger.error("检测到 invalid_grant 错误，需要重新登录 - 角色ID: \(characterId)")
                // 处理 invalid_grant 错误
                handleInvalidGrantError(characterId: characterId)
            }
            throw error
        }
    }

    /// 创建并保存认证状态（包括 access token 和 refresh token）
    func createAndSaveAuthState(
        accessToken: String,
        refreshToken: String,
        expiresIn: Int,
        tokenType: String,
        characterId: Int
    ) async {
        let configuration = OIDServiceConfiguration(
            authorizationEndpoint: EVEConfig.OAuth.authorizationEndpoint,
            tokenEndpoint: EVEConfig.OAuth.tokenEndpoint
        )

        // 创建 mock 请求和响应
        let mockRequest = OIDAuthorizationRequest(
            configuration: configuration,
            clientId: EVEConfig.OAuth.clientId,
            clientSecret: EVEConfig.OAuth.clientSecret,
            scopes: EVELogin.shared.config?.scopes ?? [],
            redirectURL: EVEConfig.OAuth.redirectURI,
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
    /// 当认证状态改变时更新 refresh token
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
