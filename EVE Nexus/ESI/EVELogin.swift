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
    var totalSkillPoints: Int?
    var unallocatedSkillPoints: Int?
    var walletBalance: Double?
    var location: SolarSystemInfo?
    var locationStatus: NetworkManager.CharacterLocation.LocationStatus?
    
    enum CodingKeys: String, CodingKey {
        case CharacterID
        case CharacterName
        case ExpiresOn
        case Scopes
        case TokenType
        case CharacterOwnerHash
        case totalSkillPoints
        case unallocatedSkillPoints
        case walletBalance
        case location
        case locationStatus
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        CharacterID = try container.decode(Int.self, forKey: .CharacterID)
        CharacterName = try container.decode(String.self, forKey: .CharacterName)
        ExpiresOn = try container.decode(String.self, forKey: .ExpiresOn)
        Scopes = try container.decode(String.self, forKey: .Scopes)
        TokenType = try container.decode(String.self, forKey: .TokenType)
        CharacterOwnerHash = try container.decode(String.self, forKey: .CharacterOwnerHash)
        totalSkillPoints = try container.decodeIfPresent(Int.self, forKey: .totalSkillPoints)
        unallocatedSkillPoints = try container.decodeIfPresent(Int.self, forKey: .unallocatedSkillPoints)
        walletBalance = try container.decodeIfPresent(Double.self, forKey: .walletBalance)
        location = try container.decodeIfPresent(SolarSystemInfo.self, forKey: .location)
        locationStatus = try container.decodeIfPresent(NetworkManager.CharacterLocation.LocationStatus.self, forKey: .locationStatus)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(CharacterID, forKey: .CharacterID)
        try container.encode(CharacterName, forKey: .CharacterName)
        try container.encode(ExpiresOn, forKey: .ExpiresOn)
        try container.encode(Scopes, forKey: .Scopes)
        try container.encode(TokenType, forKey: .TokenType)
        try container.encode(CharacterOwnerHash, forKey: .CharacterOwnerHash)
        try container.encodeIfPresent(totalSkillPoints, forKey: .totalSkillPoints)
        try container.encodeIfPresent(unallocatedSkillPoints, forKey: .unallocatedSkillPoints)
        try container.encodeIfPresent(walletBalance, forKey: .walletBalance)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encodeIfPresent(locationStatus, forKey: .locationStatus)
    }
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

// 添加角色管理相关的数据结构
struct CharacterAuth: Codable {
    let character: EVECharacterInfo
    let token: EVEAuthToken
    let addedDate: Date
    let lastTokenUpdateTime: Date
    
    // 检查是否需要更新令牌
    func shouldUpdateToken(minimumInterval: TimeInterval = 300) -> Bool {
        return Date().timeIntervalSince(lastTokenUpdateTime) >= minimumInterval
    }
    
    // 自定义初始化方法
    init(character: EVECharacterInfo, token: EVEAuthToken, addedDate: Date, lastTokenUpdateTime: Date) {
        self.character = character
        self.token = token
        self.addedDate = addedDate
        self.lastTokenUpdateTime = lastTokenUpdateTime
    }
    
    private enum CodingKeys: String, CodingKey {
        case character
        case token
        case addedDate
        case lastTokenUpdateTime
    }
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
    let databaseManager: DatabaseManager
    private let databaseQueue = DispatchQueue(label: "com.eve.nexus.database", qos: .userInitiated)
    
    init(databaseManager: DatabaseManager = DatabaseManager()) {
        self.databaseManager = databaseManager
    }
    
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
        
        // 分别启动三个独立的任务
        // 1. 加载头像
        Task {
            for character in characters {
                await loadCharacterPortrait(characterId: character.CharacterID)
            }
        }
        
        // 2. 加载技能点、钱包和位置信息
        Task {
            for character in characters {
                do {
                    if let characterAuth = EVELogin.shared.loadCharacters().first(where: { $0.character.CharacterID == character.CharacterID }) {
                        // 使用串行队列执行数据库操作
                        let locationInfo = await withCheckedContinuation { continuation in
                            Task {
                                if let location = try? await NetworkManager.shared.fetchCharacterLocation(
                                    characterId: character.CharacterID
                                ) {
                                    let info = await NetworkManager.shared.getLocationInfo(
                                        solarSystemId: location.solar_system_id,
                                        databaseManager: self.databaseManager
                                    )
                                    continuation.resume(returning: info)
                                } else {
                                    continuation.resume(returning: nil)
                                }
                            }
                        }
                        
                        // 更新角色信息
                        var updatedCharacter = character
                        
                        // 获取技能点信息
                        let skillsInfo = try await NetworkManager.shared.fetchCharacterSkills(
                            characterId: character.CharacterID
                        )
                        
                        // 获取钱包余额
                        let balance = try await ESIDataManager.shared.getWalletBalance(
                            characterId: character.CharacterID
                        )
                        
                        // 更新位置信息
                        if let locationInfo = locationInfo {
                            updatedCharacter.location = locationInfo
                        }
                        
                        // 保存更新后的信息
                        EVELogin.shared.saveAuthInfo(token: characterAuth.token, character: updatedCharacter)
                    }
                }
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
            
            // 获取技能点信息
            let skillsInfo = try await NetworkManager.shared.fetchCharacterSkills(
                characterId: character.CharacterID
            )
            
            // 获取钱包余额
            let balance = try await ESIDataManager.shared.getWalletBalance(
                characterId: character.CharacterID
            )
            
            // 获取位置信息
            let location = try await NetworkManager.shared.fetchCharacterLocation(
                characterId: character.CharacterID
            )
            
            // 获取位置详细信息
            let locationInfo = await NetworkManager.shared.getLocationInfo(
                solarSystemId: location.solar_system_id,
                databaseManager: databaseManager
            )
            
            // 更新角色信息
            var updatedCharacter = character
            updatedCharacter.totalSkillPoints = skillsInfo.total_sp
            updatedCharacter.unallocatedSkillPoints = skillsInfo.unallocated_sp
            updatedCharacter.walletBalance = balance
            updatedCharacter.locationStatus = location.locationStatus
            
            // 更新位置信息
            if let locationInfo = locationInfo {
                updatedCharacter.location = locationInfo
            }
            
            // 保存认证信息
            EVELogin.shared.saveAuthInfo(token: token, character: updatedCharacter)
            
            // 更新UI状态
            handleLoginSuccess(character: updatedCharacter)
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
            throw EVE_Nexus.NetworkError.invalidData
        }
        
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw EVE_Nexus.NetworkError.invalidURL
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
            throw EVE_Nexus.NetworkError.invalidURL
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
            addedDate: Date(),
            lastTokenUpdateTime: Date()
        )
        
        do {
            var characters = loadCharacters()
            // 检查是否已存在该角色
            if let index = characters.firstIndex(where: { $0.character.CharacterID == character.CharacterID }) {
                // 保持原有的 addedDate
                let originalAddedDate = characters[index].addedDate
                characters[index] = CharacterAuth(
                    character: character,
                    token: token,
                    addedDate: originalAddedDate,
                    lastTokenUpdateTime: Date()
                )
            } else {
                characters.append(characterAuth)
            }
            
            // 保存到 UserDefaults
            let encodedData = try JSONEncoder().encode(characters)
            defaults.set(encodedData, forKey: charactersKey)
            defaults.set(Date().addingTimeInterval(TimeInterval(token.expires_in)), forKey: "TokenExpirationDate")
            
            Logger.info("EVELogin: 保存角色认证信息成功 - \(character.CharacterName) - \(character.CharacterID)")
        } catch {
            Logger.error("EVELogin: 保存角色认证信息失��: \(error)")
        }
    }
    
    // 加载保存的认证信息
    func loadAuthInfo() -> (token: EVEAuthToken?, character: EVECharacterInfo?) {
        let _ = UserDefaults.standard
        var token: EVEAuthToken?
        var character: EVECharacterInfo?
        
        // 安全地加载角色数据
        let characters = loadCharacters()
        if let lastCharacter = characters.last {
            token = lastCharacter.token
            character = lastCharacter.character
        }
        
        return (token: token, character: character)
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
            Logger.error("EVELogin: 加载角色信息失败，正在尝试恢复: \(error)")
            // 尝试逐个解码角色信息
            if let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                var validCharacters: [CharacterAuth] = []
                
                for characterData in array {
                    do {
                        let jsonData = try JSONSerialization.data(withJSONObject: characterData)
                        let character = try JSONDecoder().decode(CharacterAuth.self, from: jsonData)
                        validCharacters.append(character)
                    } catch {
                        Logger.error("EVELogin: 跳过损坏的角色数据: \(error)")
                        continue
                    }
                }
                
                // 保存有效的角色数据
                if !validCharacters.isEmpty {
                    do {
                        let encodedData = try JSONEncoder().encode(validCharacters)
                        defaults.set(encodedData, forKey: charactersKey)
                        Logger.info("EVELogin: 成功恢复 \(validCharacters.count) 个角色数据")
                        return validCharacters
                    } catch {
                        Logger.error("EVELogin: 保存恢复的角色数据失败: \(error)")
                    }
                }
            }
            
            // 如果恢复失败，清除损坏的数据
            Logger.info("EVELogin: 清除损坏的角色数据")
            defaults.removeObject(forKey: charactersKey)
            return []
        }
    }
    
    // 移除指定角色
    func removeCharacter(characterId: Int) {
        let defaults = UserDefaults.standard
        
        // 从 UserDefaults 中移除角色信息
        var characters = loadCharacters()
        characters.removeAll { $0.character.CharacterID == characterId }
        
        do {
            let encodedData = try JSONEncoder().encode(characters)
            defaults.set(encodedData, forKey: charactersKey)
            Logger.info("EVELogin: 已从 UserDefaults 中移除角色 \(characterId)")
            
            // 移除该角色的所有缓存数据
            let keysToRemove = [
                "wallet_\(characterId)",      // 钱包缓存
                "skills_\(characterId)",      // 技能缓存
                "location_\(characterId)",    // 位置缓存
                // 可以根据需要添加更多缓存键
            ]
            
            for key in keysToRemove {
                defaults.removeObject(forKey: key)
                Logger.info("EVELogin: 已移除缓存数据: \(key)")
            }
            
            // 如果没有其他角色了，清除通用的认证信息
            if characters.isEmpty {
                defaults.removeObject(forKey: "TokenExpirationDate")
                Logger.info("EVELogin: 已清除令牌过期时间")
            }
            
            // 同步 UserDefaults 确保数据立即保存
            defaults.synchronize()
            
        } catch {
            Logger.error("EVELogin: 移除角色信息失败: \(error)")
        }
    }
    
    // 获取所有角色信息
    func getAllCharacters() -> [EVECharacterInfo] {
        let characters = loadCharacters()
        return characters.map { $0.character }
    }
    
    // 清除认证信息
    func clearAuthInfo() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: charactersKey)
        defaults.removeObject(forKey: "TokenExpirationDate")
        Logger.info("EVELogin: 清除所有认证信息")
    }
    
    // 检查令牌是否有效
    func isTokenValid() -> Bool {
        guard let expirationDate = UserDefaults.standard.object(forKey: "TokenExpirationDate") as? Date else {
            return false
        }
        // 提前5分钟认为令牌过期，以防止边界情况
        return expirationDate.timeIntervalSinceNow > 300
    }
    
    // 刷新令牌
    func refreshToken(refreshToken: String, force: Bool = false) async throws -> EVEAuthToken {
        // 如果不是强制刷新，检查上次更新时间
        if !force {
            if let characters = try? JSONDecoder().decode([CharacterAuth].self, from: UserDefaults.standard.data(forKey: charactersKey) ?? Data()),
               let character = characters.first(where: { $0.token.refresh_token == refreshToken }),
               !character.shouldUpdateToken() {
                // 如果距离上次更新时间不足5分钟，直接返回当前令牌
                Logger.info("EVELogin: 跳过\(character.character.CharacterName) 令牌刷新，距离上次更新时间不足5分钟")
                return character.token
            }
        }
        
        // 执行令牌刷新
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
            Logger.info("EVELogin: 使��现有有效令牌")
            // 令牌有效，直接返回
            return token.access_token
        }
        
        Logger.error("EVELogin: 无法获取有效令牌")
        throw NetworkError.invalidData
    }
    
    // ESI数据缓存结构
    struct ESICachedData<T: Codable>: Codable {
        let data: T
        let timestamp: Date
    }
    
    // 通用的ESI数据获取和缓存方法
    func fetchAndCacheESIData<T: Codable>(
        characterId: Int,
        dataType: String,
        cacheKey: String,
        cacheDuration: TimeInterval = 3600,
        forceRefresh: Bool = false,
        fetchData: @escaping (String) async throws -> T
    ) async throws -> T {
        let defaults = UserDefaults.standard
        
        // 1. 安全地尝试从UserDefaults获取缓存数据
        if !forceRefresh,
           let cachedData = defaults.data(forKey: cacheKey) {
            do {
                let cached = try JSONDecoder().decode(ESICachedData<T>.self, from: cachedData)
                if cached.timestamp.addingTimeInterval(cacheDuration) > Date() {
                    Logger.info("EVELogin: 从UserDefaults获取\(dataType)缓存数据 - 角色ID: \(characterId)")
                    return cached.data
                }
            } catch {
                Logger.error("EVELogin: UserDefaults中的\(dataType)缓存数据损坏，将被删除: \(error)")
                defaults.removeObject(forKey: cacheKey)
            }
        }
        
        // 2. 从ESI接口获取新数据
        guard let token = loadAuthInfo().token else {
            throw NetworkError.unauthed
        }
        
        let data = try await fetchData(token.access_token)
        
        // 3. 安全地保存数据到缓存
        let cachedData = ESICachedData(data: data, timestamp: Date())
        let encoder = JSONEncoder()
        
        do {
            let encodedData = try encoder.encode(cachedData)
            defaults.set(encodedData, forKey: cacheKey)
            Logger.info("EVELogin: 已更新\(dataType)数据缓存 - 角色ID: \(characterId)")
        } catch {
            Logger.error("EVELogin: 保存\(dataType)数据缓存失败: \(error)")
        }
        
        return data
    }
    
    // 获取钱包余额的包装方法
    func getCharacterWallet(characterId: Int, forceRefresh: Bool = false) async throws -> Double {
        return try await fetchAndCacheESIData(
            characterId: characterId,
            dataType: "wallet",
            cacheKey: "wallet_\(characterId)",
            cacheDuration: 300, // 钱包数据缓存5分钟
            forceRefresh: forceRefresh
        ) { _ in
            try await ESIDataManager.shared.getWalletBalance(
                characterId: characterId
            )
        }
    }
    
    // 获取技能信息的包装方法
    func getCharacterSkills(characterId: Int, forceRefresh: Bool = false) async throws -> CharacterSkillsResponse {
        return try await fetchAndCacheESIData(
            characterId: characterId,
            dataType: "skills",
            cacheKey: "skills_\(characterId)",
            cacheDuration: 3600, // 技能数据缓存1小时
            forceRefresh: forceRefresh
        ) { _ in
            try await NetworkManager.shared.fetchCharacterSkills(
                characterId: characterId
            )
        }
    }
    
    // 获取位置信息的包装方法
    func getCharacterLocation(characterId: Int, forceRefresh: Bool = false) async throws -> NetworkManager.CharacterLocation {
        return try await fetchAndCacheESIData(
            characterId: characterId,
            dataType: "location",
            cacheKey: "location_\(characterId)",
            cacheDuration: 60, // 位置数据缓存1分钟
            forceRefresh: forceRefresh
        ) { _ in
            try await NetworkManager.shared.fetchCharacterLocation(
                characterId: characterId
            )
        }
    }
    
    // 根据ID获取角色信息
    func getCharacterByID(_ characterId: Int) -> CharacterAuth? {
        let characters = loadCharacters()
        return characters.first { $0.character.CharacterID == characterId }
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
