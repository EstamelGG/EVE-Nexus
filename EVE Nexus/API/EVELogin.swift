@preconcurrency import AppAuth
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
            Logger.info("SecureStorage: 成功更新了 refresh token - 角色ID: \(characterId)")
        } else if status != errSecSuccess {
            Logger.error("SecureStorage: 保存 refresh token 失败 - 角色ID: \(characterId), 错误码: \(status)")
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
            String(kSecMatchLimit): kSecMatchLimitOne
        ]
        
        Logger.info("SecureStorage: 查询参数 - account: token_\(characterId)")
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecItemNotFound {
            Logger.error("SecureStorage: 在 Keychain 中未找到 refresh token - 角色ID: \(characterId), 错误: 项目不存在")
            return nil
        } else if status != errSecSuccess {
            Logger.error("SecureStorage: 从 Keychain 加载 refresh token 失败 - 角色ID: \(characterId), 错误码: \(status)")
            throw KeychainError.unhandledError(status: status)
        }
        
        guard let data = result as? Data else {
            Logger.error("SecureStorage: refresh token 数据格式错误 - 角色ID: \(characterId), 无法转换为 Data 类型")
            return nil
        }
        
        guard let token = String(data: data, encoding: .utf8) else {
            Logger.error("SecureStorage: refresh token 数据格式错误 - 角色ID: \(characterId), 无法转换为 UTF-8 字符串")
            return nil
        }
        
        Logger.info("SecureStorage: 成功从 Keychain 加载 refresh token - 角色ID: \(characterId), token前缀: \(String(token.prefix(10)))...")
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
        Logger.info("SecureStorage: 开始检查所有有效的 refresh token")
        
        let query: [String: Any] = [
            String(kSecClass): kSecClassGenericPassword,
            String(kSecReturnAttributes): true,
            String(kSecMatchLimit): kSecMatchLimitAll
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
               let characterId = Int(characterIdStr) {
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

// 添加Equatable协议支持
extension EVECharacterInfo: Equatable {
    static func == (lhs: EVECharacterInfo, rhs: EVECharacterInfo) -> Bool {
        return lhs.CharacterID == rhs.CharacterID
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
    @Published var characterPortraits: [Int: UIImage] = [:]
    let databaseManager: DatabaseManager
    private let databaseQueue = DispatchQueue(label: "com.eve.nexus.database", qos: .userInitiated)
    
    init(databaseManager: DatabaseManager = DatabaseManager()) {
        self.databaseManager = databaseManager
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
                if let index = characters.firstIndex(where: { $0.CharacterID == updatedCharacter.CharacterID }) {
                    characters[index] = updatedCharacter
                }
                if characterInfo?.CharacterID == updatedCharacter.CharacterID {
                    characterInfo = updatedCharacter
                }
            }
        }
    }
    
    func loadCharacterPortrait(characterId: Int, forceRefresh: Bool = false) async {
        do {
            if !forceRefresh && characterPortraits[characterId] != nil {
                return
            }
            
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
            
            Task {
                for character in characters {
                    await loadCharacterPortrait(characterId: character.CharacterID)
                }
            }
        }
    }
    
    // 处理授权回调
    func handleCallback(url: URL) {
        Task { @MainActor in
            do {
                guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                      let viewController = scene.windows.first?.rootViewController else {
                    return
                }
                
                // 1. 使用 AuthTokenManager 处理授权回调
                // 由于我们已经在 @MainActor 上下文中，不需要额外的主线程包装
                let authState = try await AuthTokenManager.shared.authorize(
                    presenting: viewController,
                    scopes: EVELogin.shared.config?.scopes ?? []
                )
                
                // 2. 处理登录流程
                let character = try await EVELogin.shared.processLogin(authState: authState)
                
                // 3. 更新 UI（已在 MainActor 上下文中）
                characterInfo = character
                isLoggedIn = true
                loadCharacters()
                
                // 4. 加载新角色的头像
                await loadCharacterPortrait(characterId: character.CharacterID)
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
                Logger.error("登录失败: \(error)")
            }
        }
    }
    
    // 移除角色
    func removeCharacter(_ character: EVECharacterInfo) {
        EVELogin.shared.removeCharacter(characterId: character.CharacterID)
        characterPortraits.removeValue(forKey: character.CharacterID)
        loadCharacters()
        
        // 如果移除的是当前选中的角色，清除选中状态
        if characterInfo?.CharacterID == character.CharacterID {
            characterInfo = nil
        }
        
        // 如果没有角色了，更新登录状态
        if characters.isEmpty {
            isLoggedIn = false
        }
    }
    
    // 更新角色顺序
    func moveCharacter(from source: IndexSet, to destination: Int) {
        characters.move(fromOffsets: source, toOffset: destination)
        let characterIds = characters.map { $0.CharacterID }
        EVELogin.shared.saveCharacterOrder(characterIds)
    }
}

class EVELogin {
    static let shared = EVELogin()
    internal var config: ESIConfig?
    private var session: URLSession!
    private let charactersKey = "EVECharacters"
    private let characterOrderKey = "EVECharacterOrder"
    private let databaseManager: DatabaseManager
    
    private init() {
        session = URLSession.shared
        databaseManager = DatabaseManager()
        loadConfig()
    }
    
    // 主处理函数 - 基本认证
    func processLogin(authState: OIDAuthState) async throws -> EVECharacterInfo {
        Logger.info("EVELogin: 开始处理登录流程...")
        
        // 1. 获取角色信息
        let character = try await getCharacterInfo(token: authState.lastTokenResponse?.accessToken ?? "")
        Logger.info("EVELogin: 成功获取角色信息 - 名称: \(character.CharacterName), ID: \(character.CharacterID)")
        
        // 2. 保存认证状态
        await AuthTokenManager.shared.saveAuthState(authState, for: character.CharacterID)
        
        // 3. 保存角色信息
        try await saveCharacterInfo(character)
        
        // 4. 加载详细信息
        let updatedCharacter = try await loadDetailedInfo(character: character)
        
        return updatedCharacter
    }
    
    // 保存角色信息
    private func saveCharacterInfo(_ character: EVECharacterInfo) async throws {
        Logger.info("EVELogin: 开始保存角色信息 - 角色: \(character.CharacterName) (\(character.CharacterID))")
        
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
            characters.append(CharacterAuth(
                character: character,
                addedDate: Date(),
                lastTokenUpdateTime: Date()
            ))
            Logger.info("EVELogin: 添加新角色信息")
        }
        
        // 保存到 UserDefaults
        if let encodedData = try? JSONEncoder().encode(characters) {
            Logger.info("正在缓存个人信息数据, key: \(charactersKey), 数据大小: \(encodedData.count) bytes")
            UserDefaults.standard.set(encodedData, forKey: charactersKey)
        }
    }
    
    // 加载详细信息
    private func loadDetailedInfo(character: EVECharacterInfo) async throws -> EVECharacterInfo {
        // 获取角色详细信息
        let (skills, balance, location, skillQueue) = try await fetchCharacterDetails(characterId: character.CharacterID)
        
        // 获取位置详细信息
        let locationInfo = await getSolarSystemInfo(
            solarSystemId: location.solar_system_id,
            databaseManager: databaseManager
        )
        
        // 更新角色信息
        var updatedCharacter = character
        updatedCharacter.totalSkillPoints = skills.total_sp
        updatedCharacter.unallocatedSkillPoints = skills.unallocated_sp
        updatedCharacter.walletBalance = balance
        updatedCharacter.location = locationInfo
        updatedCharacter.locationStatus = location.locationStatus
        updatedCharacter.skillQueueLength = skillQueue.count
        
        // 更新技能队列信息
        if let trainingSkill = skillQueue.first(where: { $0.isCurrentlyTraining }),
           let skillName = SkillTreeManager.shared.getSkillName(for: trainingSkill.skill_id) {
            updatedCharacter.currentSkill = EVECharacterInfo.CurrentSkillInfo(
                skillId: trainingSkill.skill_id,
                name: skillName,
                level: trainingSkill.skillLevel,
                progress: trainingSkill.progress,
                remainingTime: trainingSkill.remainingTime
            )
            
            if let lastSkill = skillQueue.last,
               let finishTime = lastSkill.remainingTime {
                updatedCharacter.queueFinishTime = finishTime
            }
        }
        
        // 保存更新后的信息
        try await saveCharacterInfo(updatedCharacter)
        
        Logger.info("EVELogin: 详细信息加载完成")
        return updatedCharacter
    }
    
    // 执行后台刷新
    func performBackgroundRefresh() async throws {
        Logger.info("EVELogin: 开始执行后台刷新...")
        
        // 获取所有角色
        let characters = loadCharacters()
        guard !characters.isEmpty else {
            Logger.info("EVELogin: 无需执行后台刷新，未找到角色信息")
            return
        }
        
        // 为每个角色刷新令牌和信息
        for character in characters {
            do {
                // 1. 刷新令牌
                _ = try await AuthTokenManager.shared.getAccessToken(for: character.character.CharacterID)
                Logger.info("EVELogin: 成功刷新角色 \(character.character.CharacterName) 的令牌")
                
                // 2. 更新角色信息
                let updatedCharacter = try await loadDetailedInfo(character: character.character)
                
                // 3. 发送通知
                NotificationCenter.default.post(
                    name: Notification.Name("CharacterDetailsUpdated"),
                    object: nil,
                    userInfo: ["character": updatedCharacter]
                )
                
                Logger.info("EVELogin: 成功更新角色 \(character.character.CharacterName) 的信息")
            } catch {
                Logger.error("EVELogin: 更新角色 \(character.character.CharacterName) 失败: \(error)")
                // 继续处理下一个角色
                continue
            }
        }
        
        Logger.info("EVELogin: 后台刷新完成")
    }
    
    // 获取角色信息
    private func getCharacterInfo(token: String) async throws -> EVECharacterInfo {
        guard let config = config,
              let verifyURL = URL(string: config.urls.verify) else {
            throw NetworkError.invalidURL
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
    
    // 加载保存的角色列表
    func loadCharacters() -> [CharacterAuth] {
        guard let data = UserDefaults.standard.data(forKey: charactersKey) else {
            return []
        }
        
        do {
            var characters = try JSONDecoder().decode([CharacterAuth].self, from: data)
            
            // 获取保存的顺序
            if let savedOrder = UserDefaults.standard.array(forKey: characterOrderKey) as? [Int] {
                // 创建一个字典，用于快速查找角色
                let characterDict = Dictionary(uniqueKeysWithValues: characters.map { ($0.character.CharacterID, $0) })
                
                // 按保存的顺序重新排列角色
                characters = savedOrder.compactMap { characterDict[$0] }
                
                // 添加可能存在的新角色（不在已保存顺序中的角色）
                let savedCharacterIds = Set(savedOrder)
                let unsortedCharacters = characters.filter { !savedCharacterIds.contains($0.character.CharacterID) }
                characters.append(contentsOf: unsortedCharacters)
            }
            
            return characters
        } catch {
            Logger.error("EVELogin: 加载角色信息失败: \(error)")
            return []
        }
    }
    
    // 移除角色
    func removeCharacter(characterId: Int) {
        // 从 UserDefaults 中移除角色信息
        var characters = loadCharacters()
        characters.removeAll { $0.character.CharacterID == characterId }
        
        if let encodedData = try? JSONEncoder().encode(characters) {
            Logger.info("正在缓存个人信息数据, key: \(charactersKey), 数据大小: \(encodedData.count) bytes")
            UserDefaults.standard.set(encodedData, forKey: charactersKey)
        }
        
        // 清除 AuthTokenManager 中的缓存
        Task {
            await AuthTokenManager.shared.clearTokens(for: characterId)
        }
        
        UserDefaults.standard.synchronize()
    }
    
    // 保存角色顺序
    func saveCharacterOrder(_ characterIds: [Int]) {
        Logger.info("正在缓存角色顺序数据, key: \(charactersKey), 数据大小: \(characterIds.count) bytes")
        UserDefaults.standard.set(characterIds, forKey: characterOrderKey)
        UserDefaults.standard.synchronize()
    }
    
    // 获取指定ID的角色
    func getCharacterByID(_ characterId: Int) -> CharacterAuth? {
        return loadCharacters().first { $0.character.CharacterID == characterId }
    }
    
    // 获取角色详细信息
    private func fetchCharacterDetails(characterId: Int) async throws -> (skills: CharacterSkillsResponse, balance: Double, location: CharacterLocation, skillQueue: [SkillQueueItem]) {
        Logger.info("EVELogin: 开始获取角色详细信息...")
        
        async let skills = CharacterSkillsAPI.shared.fetchCharacterSkills(
            characterId: characterId
        )
        
        async let balance = CharacterWalletAPI.shared.getWalletBalance(
            characterId: characterId
        )
        
        async let location = CharacterLocationAPI.shared.fetchCharacterLocation(
            characterId: characterId
        )
        
        async let skillQueue = CharacterSkillsAPI.shared.fetchSkillQueue(
            characterId: characterId
        )
        
        do {
            let (skillsResult, balanceResult, locationResult, queueResult) = try await (skills, balance, location, skillQueue)
            Logger.info("EVELogin: 成功获取所有角色详细信息")
            return (skillsResult, balanceResult, locationResult, queueResult)
        } catch {
            Logger.error("EVELogin: 获取角色详细信息失败: \(error)")
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
                allScopes = Array(Set(scopesDict.values.flatMap { $0 }))
                Logger.info("EVELogin: 成功加载权限: \(allScopes)")
            } catch {
                Logger.error("EVELogin: 加载权限配置失败: \(error)")
                return
            }
        }
        
        var configWithScopes = EVELogin.defaultConfig
        configWithScopes.scopes = allScopes
        self.config = configWithScopes
    }

    
    // 重置token状态
    func resetTokenExpired(characterId: Int) {
        // 不再需要手动管理 token 状态，由 AuthTokenManager 处理
        Task {
            do {
                _ = try await AuthTokenManager.shared.getAccessToken(for: characterId)
                Logger.info("EVELogin: 已重置角色 \(characterId) 的 token 状态")
            } catch {
                Logger.error("EVELogin: 重置角色 \(characterId) 的 token 状态失败: \(error)")
            }
        }
    }
    
    // 保存认证信息
    func saveAuthInfo(token: EVEAuthToken, character: EVECharacterInfo) async throws {
        Logger.info("EVELogin: 开始保存认证信息 - 角色: \(character.CharacterName) (\(character.CharacterID))")
        
        // 1. 保存角色信息
        try await saveCharacterInfo(character)
        
        // 2. 创建并保存 OIDAuthState
        await AuthTokenManager.shared.createAndSaveAuthState(
            accessToken: token.access_token,
            refreshToken: token.refresh_token,
            expiresIn: token.expires_in,
            tokenType: token.token_type,
            characterId: character.CharacterID
        )
        
        Logger.info("EVELogin: 认证状态已保存")
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
