import Foundation
import BackgroundTasks
import SwiftUI
import Security

// 添加 SecureStorage 类
class SecureStorage {
    static let shared = SecureStorage()
    
    private init() {}
    
    func saveToken(_ token: String, for characterId: Int) throws {
        Logger.info("SecureStorage: 开始保存 refresh token 到 SecureStorage - 角色ID: \(characterId), token前缀: \(String(token.prefix(10)))...")
        
        guard let tokenData = token.data(using: .utf8) else {
            Logger.error("SecureStorage: 无法将 token 转换为数据")
            throw KeychainError.unhandledError(status: errSecParam)
        }
        
        let query: [String: Any] = [
            String(kSecClass): kSecClassGenericPassword,
            String(kSecAttrAccount): "token_\(characterId)",
            String(kSecValueData): tokenData,
            String(kSecAttrAccessible): kSecAttrAccessibleAfterFirstUnlock
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            // 如果已存在，则更新
            let updateQuery: [String: Any] = [
                String(kSecClass): kSecClassGenericPassword,
                String(kSecAttrAccount): "token_\(characterId)"
            ]
            let updateAttributes: [String: Any] = [
                String(kSecValueData): tokenData
            ]
            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)
            if updateStatus != errSecSuccess {
                Logger.error("SecureStorage: 更新 refresh token 失败 - 角色ID: \(characterId), 错误码: \(updateStatus)")
                throw KeychainError.unhandledError(status: updateStatus)
            }
            Logger.info("SecureStorage: 更新已存在的 refresh token - 角色ID: \(characterId)")
        } else if status != errSecSuccess {
            Logger.error("SecureStorage: 保存 refresh token 失败 - 角色ID: \(characterId), 错误码: \(status)")
            throw KeychainError.unhandledError(status: status)
        } else {
            Logger.info("SecureStorage: 成功保存新的 refresh token - 角色ID: \(characterId)")
        }
    }
    
    func loadToken(for characterId: Int) throws -> String? {
        Logger.info("SecureStorage: 开始尝试从 Keychain 加载 token - 角色ID: \(characterId)")
        
        let query: [String: Any] = [
            String(kSecClass): kSecClassGenericPassword,
            String(kSecAttrAccount): "token_\(characterId)",
            String(kSecReturnData): true,
            String(kSecMatchLimit): kSecMatchLimitOne
        ]
        
        Logger.info("SecureStorage: 查询参数 - account: token_\(characterId)")
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecItemNotFound {
            Logger.error("SecureStorage: 在 Keychain 中未找到 token - 角色ID: \(characterId), 错误: 项目不存在")
            return nil
        } else if status != errSecSuccess {
            Logger.error("SecureStorage: 从 Keychain 加载 token 失败 - 角色ID: \(characterId), 错误码: \(status)")
            throw KeychainError.unhandledError(status: status)
        }
        
        guard let data = result as? Data else {
            Logger.error("SecureStorage: token 数据格式错误 - 角色ID: \(characterId), 无法转换为 Data 类型")
            return nil
        }
        
        guard let token = String(data: data, encoding: .utf8) else {
            Logger.error("SecureStorage: token 数据格式错误 - 角色ID: \(characterId), 无法转换为 UTF-8 字符串")
            return nil
        }
        
        Logger.info("SecureStorage: 成功从 Keychain 加载 token - 角色ID: \(characterId), token前缀: \(String(token.prefix(10)))...")
        return token
    }
    
    func deleteToken(for characterId: Int) throws {
        let query: [String: Any] = [
            String(kSecClass): kSecClassGenericPassword,
            String(kSecAttrAccount): "token_\(characterId)"
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.unhandledError(status: status)
        }
    }
    
    // 列出所有有效的 token
    func listValidTokens() -> [Int] {
        Logger.info("SecureStorage: 开始检查所有有效的 token")
        
        let query: [String: Any] = [
            String(kSecClass): kSecClassGenericPassword,
            String(kSecReturnAttributes): true,
            String(kSecMatchLimit): kSecMatchLimitAll
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecItemNotFound {
            Logger.info("SecureStorage: 未找到任何 token")
            return []
        } else if status != errSecSuccess {
            Logger.error("SecureStorage: 查询 token 失败，错误码: \(status)")
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
               let characterId = Int(characterIdStr) {
                // 检查 token 是否有效
                if let token = try? loadToken(for: characterId), !token.isEmpty {
                    validCharacterIds.append(characterId)
                    Logger.info("SecureStorage: 找到有效的 token - 角色ID: \(characterId)")
                }
            }
        }
        
        Logger.info("SecureStorage: 共找到 \(validCharacterIds.count) 个有效的 token")
        return validCharacterIds
    }
}

enum KeychainError: Error {
    case unhandledError(status: OSStatus)
}

// 添加 JWT 相关结构
struct EVEJWTPayload: Codable {
    let scp: [String]
    let jti: String
    let kid: String
    let sub: String
    let azp: String
    let tenant: String
    let tier: String
    let region: String
    let aud: [String]
    let name: String
    let owner: String
    let exp: Int
    let iat: Int
    let iss: String
}

// 添加 String 扩展用于处理 base64url 解码
extension String {
    func base64URLDecoded() -> Data? {
        // 将 base64url 转换为标准 base64
        let base64 = self
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        // 计算需要添加的填充数量
        let paddingLength = base64.count % 4
        let padding = paddingLength > 0 ? String(repeating: "=", count: 4 - paddingLength) : ""
        
        // 使用原生方法进行 base64 解码
        return Data(base64Encoded: base64 + padding, options: .ignoreUnknownCharacters)
    }
}

struct JWTValidator {
    static func validate(_ token: String, config: ESIConfig) async throws -> Bool {
        // 解码 JWT
        let segments = token.components(separatedBy: ".")
        guard segments.count == 3,
              let payloadData = segments[1].base64URLDecoded(),
              let payload = try? JSONDecoder().decode(EVEJWTPayload.self, from: payloadData) else {
            throw NetworkError.invalidToken("Invalid JWT format")
        }
        
        // 验证 issuer
        guard payload.iss == "login.eveonline.com" || 
              payload.iss == "https://login.eveonline.com" else {
            throw NetworkError.invalidToken("Invalid issuer")
        }
        
        // 验证过期时间
        let currentTimestamp = Int(Date().timeIntervalSince1970)
        guard payload.exp > currentTimestamp else {
            throw NetworkError.tokenExpired
        }
        
        // 验证 audience
        guard payload.aud.contains(config.clientId) && 
              payload.aud.contains("EVE Online") else {
            throw NetworkError.invalidToken("Invalid audience")
        }
        
        return true
    }
}

// 导入技能队列数据模型
// typealias SkillQueueItem = EVE_Nexus.SkillQueueItem

// OAuth认证相关的数据模型
struct EVEAuthToken: Codable {
    let access_token: String
    let expires_in: Int
    let token_type: String
    let refresh_token: String
}

struct EVECharacterInfo: Codable {
    public let CharacterID: Int
    public let CharacterName: String
    public let ExpiresOn: String
    public let Scopes: String
    public let TokenType: String
    public let CharacterOwnerHash: String
    public var corporationId: Int?
    public var allianceId: Int?
    public var tokenExpired: Bool = false
    
    // 动态属性
    public var totalSkillPoints: Int?
    public var unallocatedSkillPoints: Int?
    public var walletBalance: Double?
    public var skillQueueLength: Int?
    public var currentSkill: CurrentSkillInfo?
    public var locationStatus: CharacterLocation.LocationStatus?
    public var location: SolarSystemInfo?
    public var queueFinishTime: TimeInterval?  // 添加队列总剩余时间属性
    
    // 内部类型定义
    public struct CurrentSkillInfo: Codable {
        let skillId: Int
        let name: String
        let level: String
        let progress: Double
        let remainingTime: TimeInterval?
    }
    
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
        case currentSkill
        case tokenExpired
        case corporationId
        case allianceId
        case skillQueueLength
        case queueFinishTime
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
        locationStatus = try container.decodeIfPresent(CharacterLocation.LocationStatus.self, forKey: .locationStatus)
        currentSkill = try container.decodeIfPresent(CurrentSkillInfo.self, forKey: .currentSkill)
        tokenExpired = try container.decodeIfPresent(Bool.self, forKey: .tokenExpired) ?? false
        corporationId = try container.decodeIfPresent(Int.self, forKey: .corporationId)
        allianceId = try container.decodeIfPresent(Int.self, forKey: .allianceId)
        skillQueueLength = try container.decodeIfPresent(Int.self, forKey: .skillQueueLength)
        queueFinishTime = try container.decodeIfPresent(TimeInterval.self, forKey: .queueFinishTime)
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
        try container.encodeIfPresent(currentSkill, forKey: .currentSkill)
        try container.encode(tokenExpired, forKey: .tokenExpired)
        try container.encodeIfPresent(corporationId, forKey: .corporationId)
        try container.encodeIfPresent(allianceId, forKey: .allianceId)
        try container.encodeIfPresent(skillQueueLength, forKey: .skillQueueLength)
        try container.encodeIfPresent(queueFinishTime, forKey: .queueFinishTime)
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
    var character: EVECharacterInfo
    let addedDate: Date
    let lastTokenUpdateTime: Date
    
    // 检查是否需要更新令牌
    func shouldUpdateToken(minimumInterval: TimeInterval = 300) -> Bool {
        return Date().timeIntervalSince(lastTokenUpdateTime) >= minimumInterval
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
        // 添加通知观察者
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCharacterDetailsUpdate(_:)),
            name: Notification.Name("CharacterDetailsUpdated"),
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleCharacterDetailsUpdate(_ notification: Notification) {
        Task { @MainActor in
            if let updatedCharacter = notification.userInfo?["character"] as? EVECharacterInfo {
                // 更新角色列表
                if let index = characters.firstIndex(where: { $0.CharacterID == updatedCharacter.CharacterID }) {
                    characters[index] = updatedCharacter
                }
                // 如果是当前选中的角色，也更新characterInfo
                if characterInfo?.CharacterID == updatedCharacter.CharacterID {
                    characterInfo = updatedCharacter
                }
            }
        }
    }
    
    func loadCharacterPortrait(characterId: Int, forceRefresh: Bool = false) async {
        do {
            // 如果不是强制刷新且已有缓存的头像，直接返回
            if !forceRefresh && characterPortraits[characterId] != nil {
                return
            }
            
            // 从网络加载新的头像
            let portrait = try await CharacterAPI.shared.fetchCharacterPortrait(
                characterId: characterId,
                forceRefresh: forceRefresh
            )
            
            await MainActor.run {
                characterPortraits[characterId] = portrait
            }
        } catch {
            Logger.error("加载角色头像失败: \(error)")
        }
    }
    
    func loadCharacters() {
        Task { @MainActor in
            let allCharacters = EVELogin.shared.loadCharacters()
            characters = allCharacters.map { $0.character }
            isLoggedIn = !characters.isEmpty
            
            // 分别启动三个独立的任务
            // 1. 加载头像
            Task {
                for character in characters {
                    await loadCharacterPortrait(characterId: character.CharacterID)
                }
            }
        }
    }
    
    func handleCallback(url: URL) async {
        do {
            let character = try await EVELogin.shared.processLogin(url: url)
            handleLoginSuccess(character: character)
        } catch {
            handleLoginError(error)
        }
    }
    
    func handleLoginSuccess(character: EVECharacterInfo) {
        characterInfo = character
        isLoggedIn = true
        // 重置token状态
        EVELogin.shared.resetTokenExpired(characterId: character.CharacterID)
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
}

class EVELogin {
    static let shared = EVELogin()
    internal var config: ESIConfig?
    private var session: URLSession!
    private let charactersKey = "EVECharacters"
    private let databaseManager: DatabaseManager
    
    private init() {
        session = URLSession.shared
        databaseManager = DatabaseManager()
        loadConfig()
    }
    
    // 步骤1：处理授权回调，获取token
    private func processAuthCallback(url: URL) async throws -> (token: EVEAuthToken, character: EVECharacterInfo) {
        Logger.info("EVELogin: 开始处理授权回调...")
        let token = try await handleAuthCallback(url: url)
        Logger.info("EVELogin: 成功获取token")
        
        let character = try await getCharacterInfo(token: token.access_token)
        Logger.info("EVELogin: 成功获取角色信息 - 名称: \(character.CharacterName), ID: \(character.CharacterID)")
        
        return (token, character)
    }
    
    // 步骤2：保存基本认证信息
    private func saveInitialAuth(token: EVEAuthToken, character: EVECharacterInfo) {
        Logger.info("EVELogin: 开始保存初始认证信息...")
        saveAuthInfo(token: token, character: character)
        UserDefaults.standard.synchronize()
        Logger.info("EVELogin: 初始认证信息保存完成")
    }
    
    // 步骤3：获取角色详细信息
    private func fetchCharacterDetails(characterId: Int) async throws -> (skills: CharacterSkillsResponse, balance: Double, location: CharacterLocation, skillQueue: [SkillQueueItem]) {
        Logger.info("EVELogin: 开始获取角色详细信息...")
        
        let skills = try await CharacterSkillsAPI.shared.fetchCharacterSkills(
            characterId: characterId
        )
        Logger.info("EVELogin: 成功获取技能信息")
        
        let balance = try await CharacterWalletAPI.shared.getWalletBalance(
            characterId: characterId
        )
        Logger.info("EVELogin: 成功获取钱包余额")
        
        let location = try await CharacterLocationAPI.shared.fetchCharacterLocation(
            characterId: characterId
        )
        Logger.info("EVELogin: 成功获取位置信息")
        
        let skillQueue = try await CharacterSkillsAPI.shared.fetchSkillQueue(
            characterId: characterId
        )
        Logger.info("EVELogin: 成功获取技能队列信息")
        
        return (skills, balance, location, skillQueue)
    }
    
    // 步骤4：更新角色信息
    private func updateCharacterInfo(
        character: EVECharacterInfo,
        skills: CharacterSkillsResponse,
        balance: Double,
        location: CharacterLocation,
        locationInfo: SolarSystemInfo?,
        skillQueue: [SkillQueueItem]
    ) async -> EVECharacterInfo {
        Logger.info("EVELogin: 开始更新角色信息...")
        var updatedCharacter = character
        updatedCharacter.totalSkillPoints = skills.total_sp
        updatedCharacter.unallocatedSkillPoints = skills.unallocated_sp
        updatedCharacter.walletBalance = balance
        updatedCharacter.locationStatus = location.locationStatus
        
        if let locationInfo = locationInfo {
            updatedCharacter.location = locationInfo
        }
        
        // 更新当前技能信息
        if let currentSkill = skillQueue.first(where: { $0.isCurrentlyTraining }) {
            if let skillName = SkillTreeManager.shared.getSkillName(for: currentSkill.skill_id) {
                updatedCharacter.currentSkill = EVECharacterInfo.CurrentSkillInfo(
                    skillId: currentSkill.skill_id,
                    name: skillName,
                    level: currentSkill.skillLevel,
                    progress: currentSkill.progress,
                    remainingTime: currentSkill.remainingTime
                )
            }
        } else if let firstSkill = skillQueue.first {
            if let skillName = SkillTreeManager.shared.getSkillName(for: firstSkill.skill_id) {
                updatedCharacter.currentSkill = EVECharacterInfo.CurrentSkillInfo(
                    skillId: firstSkill.skill_id,
                    name: skillName,
                    level: firstSkill.skillLevel,
                    progress: firstSkill.progress,
                    remainingTime: nil
                )
            }
        }
        
        // 更新当前技能信息
        if let currentSkill = updatedCharacter.currentSkill,
           let skillName = SkillTreeManager.shared.getSkillName(for: currentSkill.skillId) {
            updatedCharacter.currentSkill = EVECharacterInfo.CurrentSkillInfo(
                skillId: currentSkill.skillId,
                name: skillName,
                level: currentSkill.level,
                progress: currentSkill.progress,
                remainingTime: currentSkill.remainingTime
            )
        }
        
        Logger.info("EVELogin: 角色信息更新完成")
        return updatedCharacter
    }
    
    // 主处理函数 - 第一阶段：基本认证
    func processLogin(url: URL) async throws -> EVECharacterInfo {
        do {
            // 步骤1：处理授权回调，获取token和基本角色信息
            let (token, character) = try await processAuthCallback(url: url)
            
            // 步骤2：保存初始认证信息
            saveInitialAuth(token: token, character: character)
            
            // 验证保存是否成功
            guard getCharacterByID(character.CharacterID) != nil else {
                Logger.error("EVELogin: 初始认证信息保存失败")
                throw NetworkError.invalidData
            }
            Logger.info("EVELogin: 验证初始认证信息保存成功")
            
            // 启动后台任务加载详细信息
            Task {
                do {
                    let updatedCharacter = try await loadDetailedInfo(token: token, character: character)
                    NotificationCenter.default.post(
                        name: Notification.Name("CharacterDetailsUpdated"),
                        object: nil,
                        userInfo: ["character": updatedCharacter]
                    )
                } catch {
                    Logger.error("EVELogin: 加载详细信息失败: \(error)")
                }
            }
            
            // 立即返回基本角色信息，让浏览器可以关闭
            return character
            
        } catch {
            Logger.error("EVELogin: 处理授权失败: \(error)")
            throw error
        }
    }
    
    // 第二阶段：加载详细信息
    private func loadDetailedInfo(token: EVEAuthToken, character: EVECharacterInfo) async throws -> EVECharacterInfo {
        // 步骤3：获取角色详细信息
        let (skills, balance, location, skillQueue) = try await fetchCharacterDetails(characterId: character.CharacterID)
        
        // 获取位置详细信息
        let locationInfo = await getSolarSystemInfo(
            solarSystemId: location.solar_system_id,
            databaseManager: databaseManager
        )
        
        // 步骤4：更新角色信息
        let updatedCharacter = await updateCharacterInfo(
            character: character,
            skills: skills,
            balance: balance,
            location: location,
            locationInfo: locationInfo,
            skillQueue: skillQueue
        )
        
        // 步骤5：保存更新后的信息
        Logger.info("EVELogin: 保存更新后的角色信息...")
        saveAuthInfo(token: token, character: updatedCharacter)
        UserDefaults.standard.synchronize()
        
        // 步骤6：验证最终保存
        guard getCharacterByID(character.CharacterID) != nil else {
            Logger.error("EVELogin: 最终角色信息保存失败")
            throw NetworkError.invalidData
        }
        Logger.info("EVELogin: 最终角色信息保存成功")
        
        Logger.info("EVELogin: 详细信息加载完成")
        return updatedCharacter
    }
    
    // 执行后台刷新
    func performBackgroundRefresh() async throws {
        guard let token = loadAuthInfo().token,
              let character = loadAuthInfo().character else {
            Logger.info("EVELogin: 无需执行后台刷新，未找到令牌或角色信息")
            return
        }
        
        do {
            let newToken = try await refreshToken(characterId: character.CharacterID, refreshToken: token.refresh_token)
            saveAuthInfo(token: newToken, character: character)
            Logger.info("EVELogin: 后台刷新令牌成功")
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
                
                // 合并所有限
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
            Logger.error("EVELogin: 配置为空，无法获得授权URL")
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
            Logger.error("EVELogin: 配置为空，无法处理授权回调")
            throw EVE_Nexus.NetworkError.invalidData
        }
        
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            Logger.error("EVELogin: 无法从URL获取授权码")
            throw EVE_Nexus.NetworkError.invalidURL
        }
        
        Logger.info("EVELogin: 成功获取授权码: \(String(code.prefix(10)))...")
        
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
        
        Logger.info("EVELogin: 准备发送token请求，redirect_uri: \(config.callbackUrl)")
        
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        do {
            let (data, response) = try await session.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                Logger.info("EVELogin: Token请求响应状态码: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode != 200 {
                    if let errorString = String(data: data, encoding: .utf8) {
                        Logger.error("EVELogin: Token请求失败，错误信息: \(errorString)")
                    }
                }
            }
            
            let token = try JSONDecoder().decode(EVEAuthToken.self, from: data)
            Logger.info("EVELogin: 成功获取token，access_token长度: \(token.access_token.count)")
            return token
        } catch {
            Logger.error("EVELogin: Token请求失败: \(error)")
            throw error
        }
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
        var characterInfo = try JSONDecoder().decode(EVECharacterInfo.self, from: data)
        
        // 获取角色的公开信息以更新军团和联盟ID
        let publicInfo = try await CharacterAPI.shared.fetchCharacterPublicInfo(characterId: characterInfo.CharacterID)
        characterInfo.corporationId = publicInfo.corporation_id
        characterInfo.allianceId = publicInfo.alliance_id
        
        return characterInfo
    }
    
    // 保存认证信息
    func saveAuthInfo(token: EVEAuthToken, character: EVECharacterInfo) {
        Logger.info("EVELogin: 开始保存认证信息 - 角色: \(character.CharacterName) (\(character.CharacterID))")
        Logger.info("EVELogin: Access Token 前缀: \(String(token.access_token.prefix(10)))...")
        Logger.info("EVELogin: Refresh Token 前缀: \(String(token.refresh_token.prefix(10)))...")
        
        let defaults = UserDefaults.standard
        let characterAuth = CharacterAuth(
            character: character,
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
                    addedDate: originalAddedDate,
                    lastTokenUpdateTime: Date()
                )
                Logger.info("EVELogin: 更新现有角色信息")
            } else {
                characters.append(characterAuth)
                Logger.info("EVELogin: 添加新角色信息")
            }
            
            // 保存到 UserDefaults（只包含角色信息）
            let encodedData = try JSONEncoder().encode(characters)
            defaults.set(encodedData, forKey: charactersKey)
            Logger.info("EVELogin: 角色信息已保存到 UserDefaults")
            
            // 保存 refresh token 到 SecureStorage
            try SecureStorage.shared.saveToken(token.refresh_token, for: character.CharacterID)
            
            // 更新 TokenManager 的缓存
            Task {
                let tokenCache = TokenManager.CachedToken(
                    token: token,  // 使用完整的 token
                    expirationDate: Date().addingTimeInterval(TimeInterval(token.expires_in))
                )
                await TokenManager.shared.updateTokenCache(characterId: character.CharacterID, cachedToken: tokenCache)
                Logger.info("EVELogin: TokenManager 缓存已更新")
            }
            
            // 强制同步到磁盘
            defaults.synchronize()
            
            Logger.info("EVELogin: 保存角色认证信息完成 - \(character.CharacterName) (\(character.CharacterID))")
        } catch {
            Logger.error("EVELogin: 保存角色认证信息失败: \(error)")
        }
    }
    
    // 加载保存的认证信息
    func loadAuthInfo() -> (token: EVEAuthToken?, character: EVECharacterInfo?) {
        let characters = loadCharacters()
        guard let lastCharacter = characters.last else {
            return (token: nil, character: nil)
        }
        
        // 从 SecureStorage 获取 token
        var token: EVEAuthToken?
        if let refreshToken = try? SecureStorage.shared.loadToken(for: lastCharacter.character.CharacterID) {
            // 创建一个临时的 token 对象
            token = EVEAuthToken(
                access_token: "",  // access token 会在需要时刷新
                expires_in: 0,     // 过期时间会在刷新时更新
                token_type: "Bearer",
                refresh_token: refreshToken
            )
        }
        
        return (token: token, character: lastCharacter.character)
    }
    
    // 加载所有角色信息
    func loadCharacters() -> [CharacterAuth] {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: charactersKey) else {
            return []
        }
        
        do {
            var characters = try JSONDecoder().decode([CharacterAuth].self, from: data)
            
            // 新从当前语言的数据库中获取技能名称
            for i in 0..<characters.count {
                if let currentSkill = characters[i].character.currentSkill,
                   let skillName = SkillTreeManager.shared.getSkillName(for: currentSkill.skillId) {
                    // 更新技能名称，保持其他信息不变
                    characters[i].character.currentSkill = EVECharacterInfo.CurrentSkillInfo(
                        skillId: currentSkill.skillId,
                        name: skillName,
                        level: currentSkill.level,
                        progress: currentSkill.progress,
                        remainingTime: currentSkill.remainingTime
                    )
                }
            }
            
            return characters
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
            
            // 清除 SecureStorage 中的 token
            try SecureStorage.shared.deleteToken(for: characterId)
            Logger.info("EVELogin: 已从 SecureStorage 中移除角色 token")
            
            // 清除 TokenManager 中的缓存
            Task {
                await TokenManager.shared.clearToken(for: characterId)
                Logger.info("EVELogin: 已清除 TokenManager 缓存")
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
        defaults.synchronize()
        Logger.info("EVELogin: 清除所有认证信息")
    }
    
    // 刷新令牌
    func refreshToken(characterId: Int, refreshToken: String? = nil, force: Bool = false) async throws -> EVEAuthToken {
        // 如果不是强制刷新，检查上次更新时间
        if !force {
            if let characters = try? JSONDecoder().decode([CharacterAuth].self, from: UserDefaults.standard.data(forKey: charactersKey) ?? Data()),
               let character = characters.first(where: { $0.character.CharacterID == characterId }),
               !character.shouldUpdateToken() {
                // 如果距离上次更新时间不足5分钟，尝试从 SecureStorage 获取 token
                if let storedToken = try? SecureStorage.shared.loadToken(for: characterId) {
                    // 创建一个临时的 token 对象
                    return EVEAuthToken(
                        access_token: "",  // access token 会在需要时刷新
                        expires_in: 0,     // 过期时间会在刷新时更新
                        token_type: "Bearer",
                        refresh_token: storedToken
                    )
                }
            }
        }
        
        // 执行令牌刷新
        guard let config = config else {
            throw NetworkError.invalidData
        }
        
        Logger.info("EVELogin: 开始刷新令牌 - 角色ID: \(characterId)")
        
        // 从 SecureStorage 获取 refresh token
        let storedRefreshToken: String
        if let providedToken = refreshToken, !providedToken.isEmpty {
            Logger.info("EVELogin: 使用提供的 refresh token")
            storedRefreshToken = providedToken
        } else {
            Logger.info("EVELogin: 提供的 token 为空或无效，尝试从 SecureStorage 获取 refresh token")
            guard let token = try? SecureStorage.shared.loadToken(for: characterId) else {
                Logger.error("EVELogin: 无法从 SecureStorage 获取 refresh token - 角色ID: \(characterId)")
                throw NetworkError.authenticationError("No refresh token found")
            }
            storedRefreshToken = token
            Logger.info("EVELogin: 成功从 SecureStorage 获取 refresh token")
        }
        
        // 检查最终使用的 token 是否有效
        guard !storedRefreshToken.isEmpty else {
            Logger.error("EVELogin: refresh token 为空 - 角色ID: \(characterId)")
            throw NetworkError.authenticationError("Empty refresh token")
        }
        
        Logger.info("EVELogin: 使用的 refresh token 前缀: \(String(storedRefreshToken.prefix(10)))...")
        
        var request = URLRequest(url: URL(string: config.urls.token)!)
        request.httpMethod = "POST"
        
        // 设置请求头
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("login.eveonline.com", forHTTPHeaderField: "Host")
        
        // 构建请求体参数
        let bodyParams = [
            "grant_type": "refresh_token",
            "refresh_token": storedRefreshToken,
            "client_id": config.clientId
        ]
        
        let bodyString = bodyParams
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)
        
        // 打印请求信息（注意不要打印完整的敏感信息）
        Logger.info("EVELogin: 刷新令牌请求 URL: \(config.urls.token)")
        Logger.info("EVELogin: 请求体: grant_type=refresh_token&refresh_token=\(String(storedRefreshToken.prefix(10)))...&client_id=\(config.clientId)")
        
        let (data, response) = try await session.data(for: request)
        
        // 记录响应状态码和响应体
        if let httpResponse = response as? HTTPURLResponse {
            Logger.info("EVELogin: 刷新令牌响应状态码: \(httpResponse.statusCode)")
            
            // 如果状态码不是 200，记录详细错误信息
            if httpResponse.statusCode != 200 {
                if let responseString = String(data: data, encoding: .utf8) {
                    Logger.error("EVELogin: 刷新令牌失败 - 角色ID: \(characterId), 响应体: \(responseString)")
                    Logger.error("EVELogin: 请求头: \(httpResponse.allHeaderFields)")
                }
                throw NetworkError.invalidResponse
            }
        }
        
        do {
            let newToken = try JSONDecoder().decode(EVEAuthToken.self, from: data)
            Logger.info("EVELogin: 成功获取新的 token - 角色ID: \(characterId)")
            return newToken
        } catch {
            // 如果是解码错误，记录原始数据
            if let decodingError = error as? DecodingError {
                Logger.error("EVELogin: 令牌解码失败 - 角色ID: \(characterId), 错误: \(decodingError)")
                if let responseString = String(data: data, encoding: .utf8) {
                    Logger.error("EVELogin: 无法解码的响应数据: \(responseString)")
                }
            }
            throw error
        }
    }
    
    // 获取有效的访问令牌
    func getValidToken() async throws -> String {
        let authInfo = loadAuthInfo()
        guard let character = authInfo.character else {
            throw NetworkError.unauthed
        }
        
        do {
            // 使用TokenManager获取有效的token
            let token = try await TokenManager.shared.getToken(for: character.CharacterID)
            return token.access_token
        } catch {
            Logger.error("EVELogin: 获取有效token失败: \(error)")
            if case NetworkError.tokenExpired = error {
                // 标记token已过期
                markTokenExpired(characterId: character.CharacterID)
            }
            throw error
        }
    }
    
    // ESI数据缓存结构
    struct ESICachedData<T: Codable>: Codable {
        let data: T
        let timestamp: Date
    }
    
    // 通用的ESI数据获取方法
    func fetchAndCacheESIData<T: Codable>(
        characterId: Int,
        dataType: String,
        fetchData: @escaping () async throws -> T
    ) async throws -> T {
        do {
            let data = try await fetchData()
            Logger.info("EVELogin: 成功获取\(dataType)数据 - 角色ID: \(characterId)")
            return data
        } catch {
            Logger.error("EVELogin: 获取\(dataType)数据失败 - 角色ID: \(characterId), 错误: \(error)")
            if case NetworkError.tokenExpired = error {
                markTokenExpired(characterId: characterId)
            }
            throw error
        }
    }
    
    // 根据ID获取角色信息
    func getCharacterByID(_ characterId: Int) -> CharacterAuth? {
        let characters = loadCharacters()
        return characters.first { $0.character.CharacterID == characterId }
    }
    
    // 在 EVELogin 类中添加更新 token 状态的方法
    func markTokenExpired(characterId: Int) {
        var characters = loadCharacters()
        if let index = characters.firstIndex(where: { $0.character.CharacterID == characterId }) {
            var updatedCharacter = characters[index].character
            updatedCharacter.tokenExpired = true
            characters[index] = CharacterAuth(
                character: updatedCharacter,
                addedDate: characters[index].addedDate,
                lastTokenUpdateTime: characters[index].lastTokenUpdateTime
            )
            
            do {
                let encodedData = try JSONEncoder().encode(characters)
                UserDefaults.standard.set(encodedData, forKey: charactersKey)
                UserDefaults.standard.synchronize()
                Logger.info("已将角色 \(characterId) 标记为 token 过期")
                
                // 发送通知
                NotificationCenter.default.post(
                    name: Notification.Name("CharacterTokenStatusChanged"),
                    object: nil,
                    userInfo: [
                        "characterId": characterId,
                        "tokenExpired": true
                    ]
                )
            } catch {
                Logger.error("保存角色 token 状态失败: \(error)")
            }
        }
    }
    
    func resetTokenExpired(characterId: Int) {
        var characters = loadCharacters()
        if let index = characters.firstIndex(where: { $0.character.CharacterID == characterId }) {
            var updatedCharacter = characters[index].character
            updatedCharacter.tokenExpired = false
            characters[index] = CharacterAuth(
                character: updatedCharacter,
                addedDate: characters[index].addedDate,
                lastTokenUpdateTime: characters[index].lastTokenUpdateTime
            )
            
            do {
                let encodedData = try JSONEncoder().encode(characters)
                UserDefaults.standard.set(encodedData, forKey: charactersKey)
                UserDefaults.standard.synchronize()
                Logger.info("已重置角色 \(characterId) 的 token 状态")
                
                // 发送通知
                NotificationCenter.default.post(
                    name: Notification.Name("CharacterTokenStatusChanged"),
                    object: nil,
                    userInfo: [
                        "characterId": characterId,
                        "tokenExpired": false
                    ]
                )
            } catch {
                Logger.error("重置角色 token 状态失败: \(error)")
            }
        }
    }
    
    // 检查和清理无效的角色
    func validateCharacters() {
        Logger.info("EVELogin: 开始验证角色信息")
        
        // 获取所有有效的 token
        let validCharacterIds = SecureStorage.shared.listValidTokens()
        Logger.info("EVELogin: 找到 \(validCharacterIds.count) 个有效的 token")
        
        // 获取当前保存的所有角色
        var characters = loadCharacters()
        Logger.info("EVELogin: 当前保存了 \(characters.count) 个角色")
        
        // 移除没有有效 token 的角色
        characters.removeAll { character in
            let hasValidToken = validCharacterIds.contains(character.character.CharacterID)
            if !hasValidToken {
                Logger.info("EVELogin: 移除无效 token 的角色 - \(character.character.CharacterName) (\(character.character.CharacterID))")
            }
            return !hasValidToken
        }
        
        // 保存更新后的角色列表
        do {
            let encodedData = try JSONEncoder().encode(characters)
            UserDefaults.standard.set(encodedData, forKey: charactersKey)
            UserDefaults.standard.synchronize()
            Logger.info("EVELogin: 成功更新角色列表，保留 \(characters.count) 个有效角色")
        } catch {
            Logger.error("EVELogin: 保存更新后的角色列表失败: \(error)")
        }
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
