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

// 导入NetworkError
extension EVELogin {
    typealias NetworkError = EVE_Nexus.NetworkError
}

class EVELogin {
    static let shared = EVELogin()
    
    private init() {}
    
    // EVE Online OAuth配置
    private struct EVEAuthConfig {
        static let clientId = "YOUR_CLIENT_ID" // 需要替换为实际的Client ID
        static let clientSecret = "YOUR_CLIENT_SECRET" // 需要替换为实际的Client Secret
        static let callbackScheme = "eve-nexus" // 自定义URL scheme
        static let callbackHost = "callback"
        static let scopes = [
            "publicData",
            "esi-skills.read_skills.v1",
            "esi-clones.read_clones.v1",
            "esi-mail.read_mail.v1",
            "esi-wallet.read_character_wallet.v1",
            "esi-assets.read_assets.v1",
            "esi-markets.read_character_orders.v1",
            "esi-contracts.read_character_contracts.v1"
        ].joined(separator: " ")
    }
    
    // 获取授权URL
    func getAuthorizationURL() -> URL? {
        var components = URLComponents(string: "https://login.eveonline.com/v2/oauth/authorize/")
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: "\(EVEAuthConfig.callbackScheme)://\(EVEAuthConfig.callbackHost)"),
            URLQueryItem(name: "client_id", value: EVEAuthConfig.clientId),
            URLQueryItem(name: "scope", value: EVEAuthConfig.scopes),
            URLQueryItem(name: "state", value: UUID().uuidString)
        ]
        return components?.url
    }
    
    // 处理授权回调
    func handleAuthCallback(url: URL) async throws -> EVEAuthToken {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw NetworkError.invalidURL
        }
        
        // 使用授权码获取访问令牌
        let tokenURL = URL(string: "https://login.eveonline.com/v2/oauth/token")!
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        
        // 设置Basic认证
        let authString = "\(EVEAuthConfig.clientId):\(EVEAuthConfig.clientSecret)"
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
        let verifyURL = URL(string: "https://login.eveonline.com/oauth/verify")!
        var request = URLRequest(url: verifyURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(EVECharacterInfo.self, from: data)
    }
    
    // 刷新访问令牌
    func refreshToken(_ refreshToken: String) async throws -> EVEAuthToken {
        let tokenURL = URL(string: "https://login.eveonline.com/v2/oauth/token")!
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        
        // 设置Basic认证
        let authString = "\(EVEAuthConfig.clientId):\(EVEAuthConfig.clientSecret)"
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
} 