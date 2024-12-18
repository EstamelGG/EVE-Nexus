import Foundation

// OAuth认证相关的数据模型
struct EVEAuthToken: Codable {
    let access_token: String
    let expires_in: Int
    let token_type: String
    let refresh_token: String
}

struct EVECharacterInfo: Codable {
    let CharacterID: Int
    let CharacterName: String
    let ExpiresOn: String
    let Scopes: String
    let TokenType: String
    let CharacterOwnerHash: String
}

// ESI配置模型
struct ESIConfig: Codable {
    let clientId: String
    let clientSecret: String
    let callbackScheme: String
    let callbackHost: String
    let urls: ESIUrls
    let scopes: [String]
    
    struct ESIUrls: Codable {
        let authorize: String
        let token: String
        let verify: String
    }
}

// 导入NetworkError
extension EVELogin {
    typealias NetworkError = EVE_Nexus.NetworkError
}

class EVELogin {
    static let shared = EVELogin()
    internal var config: ESIConfig?
    
    private init() {
        loadConfig()
    }
    
    private func loadConfig() {
        if let configURL = Bundle.main.url(forResource: "ESI_config", withExtension: "json"),
           let configData = try? Data(contentsOf: configURL) {
            do {
                config = try JSONDecoder().decode(ESIConfig.self, from: configData)
            } catch {
                print("Error loading ESI config: \(error)")
            }
        }
    }
    
    // 获取授权URL
    func getAuthorizationURL() -> URL? {
        guard let config = config else { return nil }
        
        var components = URLComponents(string: config.urls.authorize)
        
        // 构建回调 URL
        var callbackComponents = URLComponents()
        callbackComponents.scheme = config.callbackScheme
        callbackComponents.host = config.callbackHost
        callbackComponents.path = "/"
        
        guard let callbackURL = callbackComponents.url else {
            Logger.error("EVELogin: 无法构建回调 URL")
            return nil
        }
        
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: callbackURL.absoluteString),
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "scope", value: config.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: UUID().uuidString)
        ]
        return components?.url
    }
    
    // 处理授权回调
    func handleAuthCallback(url: URL) async throws -> EVEAuthToken {
        Logger.info("EVELogin: 开始处理授权回调: \(url.absoluteString)")
        
        guard let config = config else {
            Logger.error("EVELogin: 配置为空")
            throw NetworkError.invalidData
        }
        
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            Logger.error("EVELogin: 无法解析回调 URL")
            throw NetworkError.invalidURL
        }
        
        Logger.info("EVELogin: URL 组件: \(components)")
        
        guard let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            Logger.error("EVELogin: 无法从回调 URL 中获取授权码")
            if let error = components.queryItems?.first(where: { $0.name == "error" })?.value {
                Logger.error("EVELogin: EVE Online 返回错误: \(error)")
            }
            throw NetworkError.invalidURL
        }
        
        Logger.info("EVELogin: 获取到授权码: \(code.prefix(10))...")
        
        // 使用授权码获取访问令牌
        guard let tokenURL = URL(string: config.urls.token) else {
            Logger.error("EVELogin: 无效的令牌 URL")
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        
        // 设置Basic认证
        let authString = "\(config.clientId):\(config.clientSecret)"
        let authData = authString.data(using: .utf8)!.base64EncodedString()
        request.setValue("Basic \(authData)", forHTTPHeaderField: "Authorization")
        
        // 构建回调 URL
        var callbackComponents = URLComponents()
        callbackComponents.scheme = config.callbackScheme
        callbackComponents.host = config.callbackHost
        callbackComponents.path = "/"
        
        guard let callbackURL = callbackComponents.url else {
            Logger.error("EVELogin: 无法构建回调 URL")
            throw NetworkError.invalidURL
        }
        
        // 设置请求体
        let bodyParams = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": callbackURL.absoluteString
        ]
        
        Logger.info("EVELogin: 使用回调 URL: \(callbackURL.absoluteString)")
        
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let bodyString = bodyParams.map { key, value in
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(encodedKey)=\(encodedValue)"
        }.joined(separator: "&")
        
        Logger.info("EVELogin: 请求体: \(bodyString)")
        request.httpBody = bodyString.data(using: .utf8)
        
        Logger.info("EVELogin: 发送令牌请求")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                Logger.info("EVELogin: 收到响应，状态码: \(httpResponse.statusCode)")
                Logger.info("EVELogin: 响应头: \(httpResponse.allHeaderFields)")
                
                if httpResponse.statusCode != 200 {
                    let errorString = String(data: data, encoding: .utf8) ?? "未知错误"
                    Logger.error("EVELogin: 请求失败: \(errorString)")
                    throw NetworkError.invalidData
                }
            }
            
            let responseString = String(data: data, encoding: .utf8) ?? "无法解码响应数据"
            Logger.info("EVELogin: 收到响应数据: \(responseString)")
            
            let token = try JSONDecoder().decode(EVEAuthToken.self, from: data)
            Logger.info("EVELogin: 成功解析访问令牌")
            return token
        } catch let error as DecodingError {
            Logger.error("EVELogin: 解析令牌失败: \(error)")
            throw NetworkError.invalidData
        } catch {
            Logger.error("EVELogin: 网络请求失败: \(error)")
            throw NetworkError.invalidData
        }
    }
    
    // 获取角色信息
    func getCharacterInfo(token: String) async throws -> EVECharacterInfo {
        guard let config = config else {
            throw NetworkError.invalidData
        }
        
        guard let verifyURL = URL(string: config.urls.verify) else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: verifyURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(EVECharacterInfo.self, from: data)
    }
    
    // 刷新访问令牌
    func refreshToken(_ refreshToken: String) async throws -> EVEAuthToken {
        guard let config = config else {
            throw NetworkError.invalidData
        }
        
        guard let tokenURL = URL(string: config.urls.token) else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        
        // 设置Basic认证
        let authString = "\(config.clientId):\(config.clientSecret)"
        let authData = authString.data(using: .utf8)!.base64EncodedString()
        request.setValue("Basic \(authData)", forHTTPHeaderField: "Authorization")
        
        // 设置请求体
        let bodyParams = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ]
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(EVEAuthToken.self, from: data)
    }
    
    // 保存认证信息
    func saveAuthInfo(token: EVEAuthToken, character: EVECharacterInfo) {
        let defaults = UserDefaults.standard
        do {
            let tokenData = try JSONEncoder().encode(token)
            let characterData = try JSONEncoder().encode(character)
            defaults.set(tokenData, forKey: "EVEAuthToken")
            defaults.set(characterData, forKey: "EVECharacterInfo")
            defaults.set(Date().addingTimeInterval(TimeInterval(token.expires_in)), forKey: "TokenExpirationDate")
        } catch {
            print("Error saving auth info: \(error)")
        }
    }
    
    // 加载保存的认证信息
    func loadAuthInfo() -> (token: EVEAuthToken?, character: EVECharacterInfo?) {
        let defaults = UserDefaults.standard
        var token: EVEAuthToken?
        var character: EVECharacterInfo?
        
        if let tokenData = defaults.data(forKey: "EVEAuthToken"),
           let characterData = defaults.data(forKey: "EVECharacterInfo") {
            do {
                token = try JSONDecoder().decode(EVEAuthToken.self, from: tokenData)
                character = try JSONDecoder().decode(EVECharacterInfo.self, from: characterData)
            } catch {
                print("Error loading auth info: \(error)")
            }
        }
        
        return (token, character)
    }
    
    // 检查令牌是否过期
    func isTokenExpired() -> Bool {
        guard let expirationDate = UserDefaults.standard.object(forKey: "TokenExpirationDate") as? Date else {
            return true
        }
        return Date() >= expirationDate
    }
    
    // 清除认证信息
    func clearAuthInfo() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "EVEAuthToken")
        defaults.removeObject(forKey: "EVECharacterInfo")
        defaults.removeObject(forKey: "TokenExpirationDate")
    }
} 