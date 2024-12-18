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
    let callbackUrl: String
    let urls: ESIUrls
    var scopes: [String]
    
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
    private var session: URLSession!
    
    private init() {
        session = URLSession.shared
        loadConfig()
    }
    
    private func loadConfig() {
        // 从 scopes.json 加载所有权限
        var allScopes: [String] = []
        if let scopesURL = Bundle.main.url(forResource: "scopes", withExtension: "json") {
            do {
                let scopesData = try Data(contentsOf: scopesURL)
                let scopesDict = try JSONDecoder().decode([String: [String]].self, from: scopesData)
                
                // 合并所有权限
                var scopesSet = Set<String>()
                for scopeArray in scopesDict.values {
                    scopesSet.formUnion(scopeArray)
                }
                allScopes = Array(scopesSet)
                Logger.info("EVELogin: 成功加载权限: \(allScopes)")
            } catch {
                Logger.error("EVELogin: 加载权限配置失败: \(error)")
                return
            }
        }
        
        // 使用默认配置并设置所有权限
        var configWithScopes = EVELogin.defaultConfig
        configWithScopes.scopes = allScopes
        self.config = configWithScopes
    }
    
    // 获取授权URL
    func getAuthorizationURL() -> URL? {
        guard let config = config else { 
            Logger.error("EVELogin: 配置为空，无法获取授权URL")
            return nil 
        }
        
        guard var components = URLComponents(string: config.urls.authorize) else {
            Logger.error("EVELogin: 无效的授权URL")
            return nil
        }
        
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: config.callbackUrl),
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "scope", value: config.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: UUID().uuidString)
        ]
        
        return components.url
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
        
        var request = URLRequest(url: URL(string: config.urls.token)!)
        request.httpMethod = "POST"
        
        let authString = "\(config.clientId):\(config.clientSecret)"
        let authData = authString.data(using: .utf8)!.base64EncodedString()
        request.setValue("Basic \(authData)", forHTTPHeaderField: "Authorization")
        
        let bodyParams = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": config.callbackUrl
        ]
        
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode(EVEAuthToken.self, from: data)
    }
    
    // 获取角色信息
    func getCharacterInfo(token: String) async throws -> EVECharacterInfo {
        guard let config = config,
              let verifyURL = URL(string: config.urls.verify) else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: verifyURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode(EVECharacterInfo.self, from: data)
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
            Logger.error("EVELogin: 保存认证信息失败: \(error)")
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
                Logger.error("EVELogin: 加载认证信息失败: \(error)")
            }
        }
        
        return (token, character)
    }
    
    // 清除认证信息
    func clearAuthInfo() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "EVEAuthToken")
        defaults.removeObject(forKey: "EVECharacterInfo")
        defaults.removeObject(forKey: "TokenExpirationDate")
        Logger.info("EVELogin: 认证信息已清除")
    }
}

// 在 EVELogin 类中添加私有静态配置
private extension EVELogin {
    static let defaultConfig = ESIConfig(
        clientId: "7339147833b44ad3815c7ef0957950c2",
        clientSecret: "cgEH3hswersReqCFUyzRmsvb7C7wBAPYVq2IM2Of",
        callbackUrl: "eveauthpanel://callback/",
        urls: ESIConfig.ESIUrls(
            authorize: "https://login.eveonline.com/v2/oauth/authorize/",
            token: "https://login.eveonline.com/v2/oauth/token",
            verify: "https://login.eveonline.com/oauth/verify"
        ),
        scopes: []  // 将在 loadConfig 中填充
    )
} 
