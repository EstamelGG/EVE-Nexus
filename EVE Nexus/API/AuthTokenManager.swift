@preconcurrency import AppAuth
import Foundation

/// 添加 SecureStorage 类
class SecureStorage {
    static let shared = SecureStorage()

    private init() {}

    func saveToken(_ token: String, for characterId: Int) throws {
        Logger.info(
            "SecureStorage: 开始保存 refresh token 到 SecureStorage - 角色ID: \(characterId), token前缀: \(String(token.prefix(4)))......"
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
                String(kSecValueData): tokenData,
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
            // 保存更新时间戳
            saveTokenUpdateTimestamp(for: characterId)
        } else if status != errSecSuccess {
            Logger.error(
                "SecureStorage: 保存 refresh token 失败 - 角色ID: \(characterId), 错误码: \(status)"
            )
            throw KeychainError.unhandledError(status: status)
        } else {
            Logger.info("SecureStorage: 成功保存新的 refresh token - 角色ID: \(characterId)")
            // 保存更新时间戳
            saveTokenUpdateTimestamp(for: characterId)
        }
    }

    /// 保存 refresh token 更新时间戳到 Keychain
    private func saveTokenUpdateTimestamp(for characterId: Int) {
        let timestamp = Date().timeIntervalSince1970
        let timestampString = String(timestamp)

        guard let timestampData = timestampString.data(using: .utf8) else {
            Logger.error("SecureStorage: 无法将时间戳转换为数据 - 角色ID: \(characterId)")
            return
        }

        let query: [String: Any] = [
            String(kSecClass): kSecClassGenericPassword,
            String(kSecAttrAccount): "token_timestamp_\(characterId)",
            String(kSecValueData): timestampData,
            String(kSecAttrAccessible): kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            // 如果已存在，则更新
            let updateQuery: [String: Any] = [
                String(kSecClass): kSecClassGenericPassword,
                String(kSecAttrAccount): "token_timestamp_\(characterId)",
            ]
            let updateAttributes: [String: Any] = [
                String(kSecValueData): timestampData,
            ]
            let updateStatus = SecItemUpdate(
                updateQuery as CFDictionary, updateAttributes as CFDictionary
            )
            if updateStatus != errSecSuccess {
                Logger.error(
                    "SecureStorage: 更新时间戳失败 - 角色ID: \(characterId), 错误码: \(updateStatus)"
                )
            } else {
                Logger.info("SecureStorage: 成功更新时间戳 - 角色ID: \(characterId), 时间戳: \(timestampString)")
            }
        } else if status != errSecSuccess {
            Logger.error(
                "SecureStorage: 保存时间戳失败 - 角色ID: \(characterId), 错误码: \(status)"
            )
        } else {
            Logger.info("SecureStorage: 成功保存时间戳 - 角色ID: \(characterId), 时间戳: \(timestampString)")
        }
    }

    func loadToken(for characterId: Int) throws -> String? {
        // Logger.info("SecureStorage: 开始尝试从 Keychain 加载 refresh token - 角色ID: \(characterId)")

        let query: [String: Any] = [
            String(kSecClass): kSecClassGenericPassword,
            String(kSecAttrAccount): "token_\(characterId)",
            String(kSecReturnData): true,
            String(kSecMatchLimit): kSecMatchLimitOne,
        ]

        // Logger.info("SecureStorage: 查询参数 - account: token_\(characterId)")

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            Logger.error(
                "SecureStorage: 在 Keychain 中未找到 refresh token - 角色ID: \(characterId), 错误: 项目不存在"
            )
            return nil
        } else if status != errSecSuccess {
            Logger.error(
                "SecureStorage: 从 Keychain 加载 refresh token 失败 - 角色ID: \(characterId), 错误码: \(status)"
            )
            throw KeychainError.unhandledError(status: status)
        }

        guard let data = result as? Data else {
            Logger.error(
                "SecureStorage: refresh token 数据格式错误 - 角色ID: \(characterId), 无法转换为 Data 类型"
            )
            return nil
        }

        guard let token = String(data: data, encoding: .utf8) else {
            Logger.error(
                "SecureStorage: refresh token 数据格式错误 - 角色ID: \(characterId), 无法转换为 UTF-8 字符串"
            )
            return nil
        }

//        Logger.info(
//            "SecureStorage: 成功从 Keychain 加载 refresh token - 角色ID: \(characterId), token前缀: \(String(token.prefix(10)))..."
//        )
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

        // 同时删除时间戳
        deleteTokenUpdateTimestamp(for: characterId)
    }

    /// 删除 refresh token 更新时间戳
    private func deleteTokenUpdateTimestamp(for characterId: Int) {
        let query: [String: Any] = [
            String(kSecClass): kSecClassGenericPassword,
            String(kSecAttrAccount): "token_timestamp_\(characterId)",
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess, status != errSecItemNotFound {
            Logger.error(
                "SecureStorage: 删除时间戳失败 - 角色ID: \(characterId), 错误码: \(status)"
            )
        }
    }

    /// 列出所有有效的 refresh token
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
                    // Logger.info("SecureStorage: 找到有效的 refresh token - 角色ID: \(characterId)")
                }
            }
        }

        Logger.success("SecureStorage: 共找到 \(validCharacterIds.count) 个不为空的 refresh token")
        return validCharacterIds
    }
}

enum KeychainError: Error {
    case unhandledError(status: OSStatus)
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

    /// 验证 access token 是否有效（提前 5 分钟视为将过期）
    private func accessTokenNotExpired(_ authState: OIDAuthState) -> Bool {
        guard let tokenResponse = authState.lastTokenResponse else {
            return false
        }

        let gracePeriod: TimeInterval = 5 * 60
        let cutoff = Date().addingTimeInterval(gracePeriod)

        // ESI v2：access_token 本身是 JWT，解码成功则以 JWT exp 为准
        if let accessToken = tokenResponse.accessToken,
           let expiresAt = JWTTokenValidator.shared.expirationDate(of: accessToken)
        {
            return cutoff < expiresAt
        }

        if let idToken = tokenResponse.idToken,
           let expiresAt = JWTTokenValidator.shared.expirationDate(of: idToken)
        {
            return cutoff < expiresAt
        }

        guard let expirationDate = tokenResponse.accessTokenExpirationDate else {
            return false
        }
        return cutoff < expirationDate
    }

    /// 刷新 access token（使用 refresh token 获取新的 access token）
    private func refreshAccessToken(for characterId: Int) async throws -> String {
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

            Logger.info("开始执行 access token 刷新 - 角色ID: \(characterId)")
            return try await withCheckedThrowingContinuation { continuation in
                authState.setNeedsTokenRefresh() // 强制刷新
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

        do {
            return try await task.value
        } catch {
            if isInvalidGrantError(error) {
                Logger.error("检测到 invalid_grant 错误，需要重新登录 - 角色ID: \(characterId)")
                handleInvalidGrantError(characterId: characterId)
                throw NetworkError.refreshTokenExpired
            }
            throw error
        }
    }

    /// 获取授权URL配置（用于 OAuth 流程）
    private func getConfiguration() async throws -> OIDServiceConfiguration {
        return try await OIDAuthorizationService.discoverConfiguration(
            forIssuer: EVEConfig.OAuth.baseURL
        )
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
                    clientSecret: nil,
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
                        continuation.resume(
                            throwing: NetworkError.authenticationError("OAuth returned empty auth state")
                        )
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

    /// 读取内存中缓存的 access token（不触发刷新，仅供调试查看）
    func getCachedAccessToken(for characterId: Int) -> String? {
        guard let authState = authStates[characterId],
              let tokenResponse = authState.lastTokenResponse,
              let token = tokenResponse.accessToken
        else {
            return nil
        }
        return token
    }

    /// 获取 access token（如果即将过期会自动刷新）
    /// 成功后自动重置 refreshTokenExpired 状态
    /// 如果 token 已标记为过期，直接抛出错误，避免无效的网络请求
    func getAccessToken(for characterId: Int) async throws -> String {
        // 提前检查：如果 token 已标记为过期，直接抛出错误
        if let auth = EVELogin.shared.getCharacterByID(characterId),
           auth.character.refreshTokenExpired
        {
            Logger.info("Token 已标记为过期，跳过请求 - 角色ID: \(characterId)")
            throw NetworkError.refreshTokenExpired
        }

        let authState = try await getOrCreateAuthState(for: characterId)
        Logger.info(
            "获取到 access token 过期时间: \(String(describing: authState.lastTokenResponse?.accessTokenExpirationDate))"
        )

        let accessToken: String
        // 检查是否有有效的access token
        if let tokenResponse = authState.lastTokenResponse,
           let token = tokenResponse.accessToken,
           accessTokenNotExpired(authState)
        {
            Logger.info("找到有效的 access token，直接返回 - 角色ID: \(characterId)")
            accessToken = token
        } else {
            // 如果没有有效token则刷新
            Logger.info(
                "检测到 access token 即将过期或已经过期，当前过期时间: \(String(describing: authState.lastTokenResponse?.accessTokenExpirationDate))"
            )
            Logger.info("开始主动刷新 access token - 角色ID: \(characterId)")
            accessToken = try await refreshAccessToken(for: characterId)
        }

        // token 获取/刷新成功，重置过期状态（仅当当前标记为过期时才更新，避免不必要的写入）
        resetExpiredStatusIfNeeded(characterId: characterId)
        return accessToken
    }

    /// 如果当前角色被标记为 refreshTokenExpired，重置为 false
    private func resetExpiredStatusIfNeeded(characterId: Int) {
        if let auth = EVELogin.shared.getCharacterByID(characterId),
           auth.character.refreshTokenExpired
        {
            Logger.info("Token 有效，重置过期状态 - 角色ID: \(characterId)")
            EVELogin.shared.updateCharacterRefreshTokenExpiredStatus(
                characterId: characterId, expired: false
            )
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

    private func isInvalidGrantError(_ error: Error) -> Bool {
        let oauthError = error as NSError
        guard oauthError.domain == "org.openid.appauth.oauth_token",
              oauthError.code == -10,
              let errorResponse = oauthError.userInfo["OIDOAuthErrorResponseErrorKey"]
              as? [String: Any]
        else {
            return false
        }
        return errorResponse["error"] as? String == "invalid_grant"
    }

    /// 处理 invalid_grant 错误：清内存状态、Keychain，并标记角色需重新登录
    private func handleInvalidGrantError(characterId: Int) {
        if let authState = authStates.removeValue(forKey: characterId) {
            authState.stateChangeDelegate = nil
        }
        tokenRefreshTasks[characterId]?.cancel()
        tokenRefreshTasks[characterId] = nil
        try? SecureStorage.shared.deleteRefreshToken(for: characterId)
        Logger.info("AuthTokenManager: 已删除过期的refresh token - 角色ID: \(characterId)")
        EVELogin.shared.updateCharacterRefreshTokenExpiredStatus(
            characterId: characterId, expired: true
        )
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
                        continuation.resume(throwing: error)
                    } else if let response = response {
                        Logger.success("Token 刷新请求成功 - 角色ID: \(characterId)")
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
                authorizationResponse: authResponse, tokenResponse: response
            )
            authState.stateChangeDelegate = self

            authStates[characterId] = authState
            Logger.success("成功创建并保存认证状态 - 角色ID: \(characterId)")
            return authState
        } catch {
            Logger.error("创建认证状态失败: \(error) - 角色ID: \(characterId)")
            if isInvalidGrantError(error) {
                Logger.error("检测到 invalid_grant 错误，需要重新登录 - 角色ID: \(characterId)")
                handleInvalidGrantError(characterId: characterId)
                throw NetworkError.refreshTokenExpired
            }
            throw error
        }
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
