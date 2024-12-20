import Foundation
import BackgroundTasks
import SwiftUI

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

// 添加角色管理相关的数据结构
struct CharacterAuth: Codable {
    let character: EVECharacterInfo
    let token: EVEAuthToken
    let addedDate: Date
}

// 添加用户管理的 ViewModel
@MainActor
class EVELoginViewModel: ObservableObject {
    @Published var characterInfo: EVECharacterInfo?
    @Published var isLoggedIn: Bool = false
    @Published var showingError: Bool = false
    @Published var errorMessage: String = ""
    @Published var characters: [EVECharacterInfo] = []
    @Published var characterPortraits: [Int: UIImage] = [:] // 添加头像存储
    
    func loadCharacterPortrait(characterId: Int, forceRefresh: Bool = false) async {
        do {
            // 如果不是强制刷新且已有缓存的头像，直接返回
            if !forceRefresh && characterPortraits[characterId] != nil {
                return
            }
            
            // 从网络加载新的头像
            let portrait = try await NetworkManager.shared.fetchCharacterPortrait(
                characterId: characterId,
                forceRefresh: forceRefresh
            )
            characterPortraits[characterId] = portrait
        } catch {
            Logger.error("加载角色头像失败: \(error)")
        }
    }
    
    func loadCharacters() {
        characters = EVELogin.shared.getAllCharacters()
        isLoggedIn = !characters.isEmpty
        
        // 异步加载所有角色的头像，但不强制刷新
        Task {
            for character in characters {
                await loadCharacterPortrait(characterId: character.CharacterID)
            }
        }
    }
    
    func handleLoginSuccess(character: EVECharacterInfo) {
        characterInfo = character
        isLoggedIn = true
        loadCharacters()
    }
    
    func handleLoginError(_ error: Error) {
        errorMessage = error.localizedDescription
        showingError = true
    }
    
    func removeCharacter(_ character: EVECharacterInfo) {
        EVELogin.shared.removeCharacter(characterId: character.CharacterID)
        characterPortraits.removeValue(forKey: character.CharacterID) // 移除头像缓存
        loadCharacters()
    }
    
    func handleCallback(url: URL) async {
        do {
            let token = try await EVELogin.shared.handleAuthCallback(url: url)
            let character = try await EVELogin.shared.getCharacterInfo(token: token.access_token)
            
            Logger.info("成功获取角色信息 - 名称: \(character.CharacterName), ID: \(character.CharacterID)")
            
            // 保存认证信息
            EVELogin.shared.saveAuthInfo(token: token, character: character)
            
            // 更新UI状态
            handleLoginSuccess(character: character)
        } catch {
            Logger.error("处理授权失败: \(error)")
            handleLoginError(error)
        }
    }
}

class EVELogin {
    static let shared = EVELogin()
    internal var config: ESIConfig?
    private var session: URLSession!
    private let charactersKey = "EVECharacters"
    
    private init() {
        session = URLSession.shared
        loadConfig()
    }
    
    // 执行后台刷新
    func performBackgroundRefresh() async throws {
        guard let token = loadAuthInfo().token else {
            Logger.info("EVELogin: 无需执行后台刷新，未找到令牌")
            return
        }
        
        do {
            let newToken = try await refreshToken(refreshToken: token.refresh_token)
            if let character = loadAuthInfo().character {
                saveAuthInfo(token: newToken, character: character)
                Logger.info("EVELogin: 后台刷新令牌成功")
            }
        } catch {
            Logger.error("EVELogin: 后台刷新令牌失败: \(error)")
            throw error
        }
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
        let characterAuth = CharacterAuth(
            character: character,
            token: token,
            addedDate: Date()
        )
        
        do {
            var characters = loadCharacters()
            // 检查是否已存在该角色
            if let index = characters.firstIndex(where: { $0.character.CharacterID == character.CharacterID }) {
                characters[index] = characterAuth
            } else {
                characters.append(characterAuth)
            }
            
            let encodedData = try JSONEncoder().encode(characters)
            defaults.set(encodedData, forKey: charactersKey)
            defaults.set(Date().addingTimeInterval(TimeInterval(token.expires_in)), forKey: "TokenExpirationDate")
            
            Logger.info("EVELogin: 保存角色认证信息成功 - \(character.CharacterName)")
        } catch {
            Logger.error("EVELogin: 保存角色认证信息失败: \(error)")
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
        defaults.removeObject(forKey: charactersKey)
        defaults.removeObject(forKey: "TokenExpirationDate")
        Logger.info("EVELogin: 清除所有认证信息")
    }
    
    // 添加令牌刷新功能
    // 检查令牌是否有效
    func isTokenValid() -> Bool {
        guard let expirationDate = UserDefaults.standard.object(forKey: "TokenExpirationDate") as? Date else {
            return false
        }
        // 提前5分钟认为令牌过期，以防止边界情况
        return expirationDate.timeIntervalSinceNow > 300
    }
    
    // 刷新令牌
    func refreshToken(refreshToken: String) async throws -> EVEAuthToken {
        guard let config = config else {
            throw NetworkError.invalidData
        }
        
        var request = URLRequest(url: URL(string: config.urls.token)!)
        request.httpMethod = "POST"
        
        let authString = "\(config.clientId):\(config.clientSecret)"
        let authData = authString.data(using: .utf8)!.base64EncodedString()
        request.setValue("Basic \(authData)", forHTTPHeaderField: "Authorization")
        
        let bodyParams = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ]
        
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode(EVEAuthToken.self, from: data)
    }
    
    // 获取有效的访问令牌
    func getValidToken() async throws -> String {
        let authInfo = loadAuthInfo()
        
        if !isTokenValid(), let token = authInfo.token {
            Logger.info("EVELogin: 令牌已过期，尝试刷新")
            do {
                // 令牌过期，尝试刷新
                let newToken = try await refreshToken(refreshToken: token.refresh_token)
                if let character = authInfo.character {
                    saveAuthInfo(token: newToken, character: character)
                    Logger.info("EVELogin: 令牌刷新成功")
                }
                return newToken.access_token
            } catch {
                // 如果刷新失败，可能是刷新令牌已过期
                Logger.error("EVELogin: 刷新令牌失败，可能已过期: \(error)")
                // 清除过期的认证信息
                clearAuthInfo()
                throw NetworkError.tokenExpired
            }
        } else if let token = authInfo.token {
            Logger.info("EVELogin: 使用现有有效令牌")
            // 令牌有效，直接返回
            return token.access_token
        }
        
        Logger.error("EVELogin: 无法获取有效令牌")
        throw NetworkError.invalidData
    }
    
    // 加载所有角色信息
    func loadCharacters() -> [CharacterAuth] {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: charactersKey) else {
            return []
        }
        
        do {
            return try JSONDecoder().decode([CharacterAuth].self, from: data)
        } catch {
            Logger.error("EVELogin: 加载角色信息失败: \(error)")
            return []
        }
    }
    
    // 移除指定角色
    func removeCharacter(characterId: Int) {
        var characters = loadCharacters()
        characters.removeAll { $0.character.CharacterID == characterId }
        
        do {
            let encodedData = try JSONEncoder().encode(characters)
            UserDefaults.standard.set(encodedData, forKey: charactersKey)
            Logger.info("EVELogin: 移除角色成功 - ID: \(characterId)")
        } catch {
            Logger.error("EVELogin: 移除角色失败: \(error)")
        }
    }
    
    // 获取所有角色信息
    func getAllCharacters() -> [EVECharacterInfo] {
        return loadCharacters().map { $0.character }
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
