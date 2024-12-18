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
    private var config: ESIConfig?
    
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
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: "\(config.callbackScheme)://\(config.callbackHost)"),
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "scope", value: config.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: UUID().uuidString)
        ]
        return components?.url
    }
    
    // 处理授权回调
    func handleAuthCallback(url: URL) async throws -> EVEAuthToken {
        guard let config = config else {
            throw NetworkError.invalidData
        }
        
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw NetworkError.invalidURL
        }
        
        // 使用授权码获取访问令牌
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
            "grant_type": "authorization_code",
            "code": code
        ]
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(EVEAuthToken.self, from: data)
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