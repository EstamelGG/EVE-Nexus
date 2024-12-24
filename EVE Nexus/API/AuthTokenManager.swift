@preconcurrency import AppAuth
import Foundation

actor AuthTokenManager: NSObject {
    static let shared = AuthTokenManager()
    private var authStates: [Int: OIDAuthState] = [:]
    private var refreshTasks: [Int: Task<Void, Never>] = [:]
    private var continuations: [Int: [CheckedContinuation<String, Error>]] = [:]
    
    private override init() {
        super.init()
    }
    
    // 获取有效的access token
    func getAccessToken(for characterId: Int) async throws -> String {
        let authState = try await getOrCreateAuthState(for: characterId)
        
        return try await withCheckedThrowingContinuation { continuation in
            authState.performAction { [weak self] accessToken, _, error in
                guard let self else { return }
                
                Task {
                    do {
                        if let error = error as? NSError,
                           error.domain == OIDOAuthTokenErrorDomain {
                            // Token 过期，尝试刷新
                            try await self.handleTokenRefresh(for: characterId, continuation: continuation)
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
    
    private func handleTokenRefresh(for characterId: Int, continuation: CheckedContinuation<String, Error>) async throws {
        // 将当前请求添加到等待队列
        var waitingList = continuations[characterId] ?? []
        waitingList.append(continuation)
        continuations[characterId] = waitingList
        
        // 如果已经有刷新任务在进行，直接返回
        guard refreshTasks[characterId] == nil else {
            return
        }
        
        // 创建刷新任务
        let refreshTask = Task<Void, Never> { [weak self] in
            guard let self = self else { return }
            do {
                // 执行刷新
                let newAuthState = try await self.refreshAuthState(for: characterId)
                let newToken = try await self.getAccessTokenFromState(newAuthState)
                
                // 通知所有等待的请求
                await self.resumeAllContinuations(for: characterId, with: .success(newToken))
            } catch {
                // 通知所有等待的请求失败
                await self.resumeAllContinuations(for: characterId, with: .failure(error))
            }
        }
        
        refreshTasks[characterId] = refreshTask
    }
    
    private func resumeAllContinuations(for characterId: Int, with result: Result<String, Error>) {
        let waitingList = continuations[characterId] ?? []
        continuations[characterId] = nil
        refreshTasks[characterId] = nil
        
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
                
                if let characterId = await findCharacterId(for: state) {
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
