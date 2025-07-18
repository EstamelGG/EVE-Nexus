@preconcurrency import AppAuth
import BackgroundTasks
import Foundation
import Security
import SwiftUI

// 导入技能队列数据模型
// typealias SkillQueueItem = EVE_Nexus.SkillQueueItem

struct EVECharacterInfo: Codable {
    let CharacterID: Int
    let CharacterName: String
    let ExpiresOn: String
    let Scopes: String
    let TokenType: String
    let CharacterOwnerHash: String
    var corporationId: Int?
    var allianceId: Int?
    var factionId: Int?
    var refreshTokenExpired: Bool = false

    // 动态属性
    var totalSkillPoints: Int?
    var unallocatedSkillPoints: Int?
    var walletBalance: Double?
    var skillQueueLength: Int?
    var currentSkill: CurrentSkillInfo?
    var locationStatus: CharacterLocation.LocationStatus?
    var location: SolarSystemInfo?
    var queueFinishTime: TimeInterval?  // 添加队列总剩余时间属性

    // 为JWT令牌解析添加的初始化方法
    init(
        CharacterID: Int, CharacterName: String, ExpiresOn: String, Scopes: String,
        TokenType: String, CharacterOwnerHash: String
    ) {
        self.CharacterID = CharacterID
        self.CharacterName = CharacterName
        self.ExpiresOn = ExpiresOn
        self.Scopes = Scopes
        self.TokenType = TokenType
        self.CharacterOwnerHash = CharacterOwnerHash
        self.refreshTokenExpired = false
    }

    // 内部类型定义
    struct CurrentSkillInfo: Codable {
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
        case refreshTokenExpired
        case corporationId
        case allianceId
        case factionId
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
        unallocatedSkillPoints = try container.decodeIfPresent(
            Int.self, forKey: .unallocatedSkillPoints
        )
        walletBalance = try container.decodeIfPresent(Double.self, forKey: .walletBalance)
        location = try container.decodeIfPresent(SolarSystemInfo.self, forKey: .location)
        locationStatus = try container.decodeIfPresent(
            CharacterLocation.LocationStatus.self, forKey: .locationStatus
        )
        currentSkill = try container.decodeIfPresent(CurrentSkillInfo.self, forKey: .currentSkill)
        refreshTokenExpired =
            try container.decodeIfPresent(Bool.self, forKey: .refreshTokenExpired) ?? false
        corporationId = try container.decodeIfPresent(Int.self, forKey: .corporationId)
        allianceId = try container.decodeIfPresent(Int.self, forKey: .allianceId)
        factionId = try container.decodeIfPresent(Int.self, forKey: .factionId)
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
        try container.encode(refreshTokenExpired, forKey: .refreshTokenExpired)
        try container.encodeIfPresent(corporationId, forKey: .corporationId)
        try container.encodeIfPresent(allianceId, forKey: .allianceId)
        try container.encodeIfPresent(factionId, forKey: .factionId)
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
    //    let clientSecret: String
    //    let callbackUrl: String
    var urls: ESIUrls
    var scopes: [String]

    struct ESIUrls: Codable {
        //        let authorize: String
        //        let token: String
        // 添加JWT元数据端点
        let jwksMetadata: String?

        enum CodingKeys: String, CodingKey {
            case jwksMetadata
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            jwksMetadata = try container.decodeIfPresent(String.self, forKey: .jwksMetadata)
        }

        init(jwksMetadata: String? = nil) {
            self.jwksMetadata = jwksMetadata
        }
    }
}

// 添加角色管理相关的数据结构
struct CharacterAuth: Codable {
    var character: EVECharacterInfo
    let addedDate: Date
    let lastTokenUpdateTime: Date
}

// 添加用户管理的 ViewModel
@MainActor
class EVELoginViewModel: ObservableObject {
    @Published var characterInfo: EVECharacterInfo?
    // @Published var isLoggedIn: Bool = false
    @Published var showingError: Bool = false
    @Published var errorMessage: String = ""
    @Published var characters: [EVECharacterInfo] = []
    @Published var characterPortraits: [Int: UIImage] = [:]
    let databaseManager: DatabaseManager

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
                if let index = characters.firstIndex(where: {
                    $0.CharacterID == updatedCharacter.CharacterID
                }) {
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
            Logger.error("[EVELogin]加载角色头像失败: \(error)")
        }
    }

    func loadCharacters() {
        Task { @MainActor in
            let allCharacters = EVELogin.shared.loadCharacters()
            characters = allCharacters.map { $0.character }
            // isLoggedIn = !characters.isEmpty

            Task {
                for character in characters {
                    await loadCharacterPortrait(characterId: character.CharacterID)
                }
            }
        }
    }

    // 处理授权回调
    func handleCallback(url _: URL) {
        Task { @MainActor in
            do {
                guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                    let viewController = scene.windows.first?.rootViewController
                else {
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
                // isLoggedIn = true
                loadCharacters()

                // 4. 加载新角色的头像
                await loadCharacterPortrait(characterId: character.CharacterID)
            } catch {
                errorMessage = error.localizedDescription
                showingError = false
                Logger.error("[EVELogin]登录失败: \(error)")
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
        //        if characters.isEmpty {
        //            isLoggedIn = false
        //        }
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
    var config: ESIConfig?
    private var session: URLSession!
    private let charactersKey = "EVECharacters"
    private let characterOrderKey = "EVECharacterOrder"
    private let databaseManager: DatabaseManager

    private static let defaultConfig = ESIConfig(
        clientId: EVEConfig.OAuth.clientId,
        //        clientSecret: EVEConfig.OAuth.clientSecret,
        //        callbackUrl: EVEConfig.OAuth.redirectURI.absoluteString,
        urls: ESIConfig.ESIUrls(
            //            authorize: EVEConfig.OAuth.authorizationEndpoint.absoluteString,
            //            token: EVEConfig.OAuth.tokenEndpoint.absoluteString,
            jwksMetadata: EVEConfig.OAuth.jwksMetadataEndpoint.absoluteString
        ),
        scopes: []  // 将在 loadConfig 中填充
    )

    private init() {
        session = URLSession.shared
        databaseManager = DatabaseManager()
        loadConfig()
    }

    // 主处理函数 - 基本认证
    func processLogin(authState: OIDAuthState) async throws -> EVECharacterInfo {
        Logger.info("[EVELogin]开始处理登录流程...")

        // 1. 获取角色信息
        let character = try await getCharacterInfo(
            token: authState.lastTokenResponse?.accessToken ?? "",
            forceRefresh: true
        )
        Logger.info(
            "[EVELogin]成功获取角色信息 - 名称: \(character.CharacterName), ID: \(character.CharacterID)")

        // 2. 保存认证状态
        await AuthTokenManager.shared.saveAuthState(authState, for: character.CharacterID)

        // 3. 保存角色信息
        try await saveCharacterInfo(character)

        // 4. 加载详细信息
        let updatedCharacter = try await loadDetailedInfo(character: character)

        return updatedCharacter
    }

    // 保存角色信息
    func saveCharacterInfo(_ character: EVECharacterInfo) async throws {
        Logger.info(
            "[EVELogin]开始保存角色信息 - 角色: \(character.CharacterName) (\(character.CharacterID))")

        var characters = loadCharacters()
        var isNewCharacter = false

        // 检查是否已存在该角色
        if let index = characters.firstIndex(where: {
            $0.character.CharacterID == character.CharacterID
        }) {
            // 保持原有的 addedDate
            let originalAddedDate = characters[index].addedDate
            characters[index] = CharacterAuth(
                character: character,
                addedDate: originalAddedDate,
                lastTokenUpdateTime: Date()
            )
            Logger.info("[EVELogin]更新现有角色信息")
        } else {
            characters.append(
                CharacterAuth(
                    character: character,
                    addedDate: Date(),
                    lastTokenUpdateTime: Date()
                ))
            isNewCharacter = true
            Logger.info("[EVELogin]添加新角色信息")
        }

        // 保存到 UserDefaults
        if let encodedData = try? JSONEncoder().encode(characters) {
            Logger.info("[EVELogin]正在缓存个人信息数据, key: \(charactersKey), 数据大小: \(encodedData.count) bytes")
            UserDefaults.standard.set(encodedData, forKey: charactersKey)
        }

        // 如果是新角色，更新角色顺序
        if isNewCharacter {
            // 获取现有的角色顺序
            var characterOrder =
                UserDefaults.standard.array(forKey: characterOrderKey) as? [Int] ?? []
            // 将新角色添加到顺序列表末尾
            characterOrder.append(character.CharacterID)
            // 保存更新后的顺序
            Logger.info(
                "[EVELogin]正在缓存角色顺序数据, key: \(characterOrderKey), 数据大小: \(characterOrder.count) bytes")
            UserDefaults.standard.set(characterOrder, forKey: characterOrderKey)
        }
    }

    // 加载详细信息
    private func loadDetailedInfo(character: EVECharacterInfo) async throws -> EVECharacterInfo {
        // 获取角色详细信息
        let (skills, balance, location, skillQueue) = try await fetchCharacterDetails(
            characterId: character.CharacterID)

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
            let skillName = SkillTreeManager.shared.getSkillName(for: trainingSkill.skill_id)
        {
            updatedCharacter.currentSkill = EVECharacterInfo.CurrentSkillInfo(
                skillId: trainingSkill.skill_id,
                name: skillName,
                level: trainingSkill.skillLevel,
                progress: trainingSkill.progress,
                remainingTime: trainingSkill.remainingTime
            )

            if let lastSkill = skillQueue.last,
                let finishTime = lastSkill.remainingTime
            {
                updatedCharacter.queueFinishTime = finishTime
            }
        }

        // 保存更新后的信息
        try await saveCharacterInfo(updatedCharacter)

        Logger.info("[EVELogin]详细信息加载完成")
        return updatedCharacter
    }

    // 获取角色信息
    private func getCharacterInfo(token: String, forceRefresh: Bool) async throws
        -> EVECharacterInfo
    {
        // 解析JWT令牌
        if let characterInfo = JWTTokenValidator.shared.parseToken(token) {
            Logger.info("[EVELogin]从JWT令牌成功解析角色信息 - 角色名: \(characterInfo.CharacterName)")

            // 获取角色的公开信息以更新军团和联盟ID
            let publicInfo = try await CharacterAPI.shared.fetchCharacterPublicInfo(
                characterId: characterInfo.CharacterID,
                forceRefresh: forceRefresh
            )

            var updatedCharacterInfo = characterInfo
            updatedCharacterInfo.corporationId = publicInfo.corporation_id
            updatedCharacterInfo.allianceId = publicInfo.alliance_id
            updatedCharacterInfo.factionId = publicInfo.faction_id

            return updatedCharacterInfo
        }

        // 如果JWT解析失败
        Logger.error("[EVELogin]无法解析JWT令牌，请确保使用的是v2版本的OAuth端点")
        throw NetworkError.authenticationError("[EVELogin]无法解析JWT令牌，请确保使用的是v2版本的OAuth端点")
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
                let characterDict = Dictionary(
                    uniqueKeysWithValues: characters.map { ($0.character.CharacterID, $0) })

                // 按保存的顺序重新排列角色
                characters = savedOrder.compactMap { characterDict[$0] }

                // 添加可能存在的新角色（不在已保存顺序中的角色）
                let savedCharacterIds = Set(savedOrder)
                let unsortedCharacters = characters.filter {
                    !savedCharacterIds.contains($0.character.CharacterID)
                }
                characters.append(contentsOf: unsortedCharacters)
            }

            return characters
        } catch {
            Logger.error("[EVELogin]加载角色信息失败: \(error)")
            return []
        }
    }

    // 移除角色
    func removeCharacter(characterId: Int) {
        Logger.info("[EVELogin]开始移除角色 (ID: \(characterId))")

        // 1. 从 UserDefaults 中移除角色信息
        var characters = loadCharacters()
        characters.removeAll { $0.character.CharacterID == characterId }

        if let encodedData = try? JSONEncoder().encode(characters) {
            Logger.info("[EVELogin]正在更新角色列表缓存, key: \(charactersKey)")
            UserDefaults.standard.set(encodedData, forKey: charactersKey)
        }

        // 2. 从角色顺序列表中移除
        var characterOrder = UserDefaults.standard.array(forKey: characterOrderKey) as? [Int] ?? []
        characterOrder.removeAll { $0 == characterId }
        Logger.info("[EVELogin]正在更新角色顺序缓存, key: \(characterOrderKey)")
        UserDefaults.standard.set(characterOrder, forKey: characterOrderKey)

        // 3. 清除 AuthTokenManager 中的缓存
        Task {
            await AuthTokenManager.shared.clearAllTokens(for: characterId)
        }

        // 4. 清理 CharacterDatabase 中的相关数据
        Task {
            do {
                try await CharacterDatabaseManager.shared.deleteCharacterData(
                    characterId: characterId)
                Logger.info("[EVELogin]已清理角色 \(characterId) 在数据库中的所有数据")
            } catch {
                Logger.error("[EVELogin]清理角色 \(characterId) 的数据库数据失败: \(error)")
            }
        }

        UserDefaults.standard.synchronize()
        Logger.info("[EVELogin]角色移除完成 (ID: \(characterId))")
    }

    // 保存角色顺序
    func saveCharacterOrder(_ characterIds: [Int]) {
        // 使用 OrderedSet 去除重复的角色ID，保持原有顺序
        var uniqueCharacterIds: [Int] = []
        var seenCharacterIds = Set<Int>()

        for characterId in characterIds {
            if !seenCharacterIds.contains(characterId) {
                uniqueCharacterIds.append(characterId)
                seenCharacterIds.insert(characterId)
            } else {
                Logger.warning("[EVELogin]发现重复的角色ID在顺序列表中，已忽略: \(characterId)")
            }
        }

        Logger.info(
            "[EVELogin]正在缓存角色顺序数据, key: \(characterOrderKey), 数据大小: \(uniqueCharacterIds.count) bytes")
        UserDefaults.standard.set(uniqueCharacterIds, forKey: characterOrderKey)
        UserDefaults.standard.synchronize()
    }

    // 获取指定ID的角色
    func getCharacterByID(_ characterId: Int) -> CharacterAuth? {
        return loadCharacters().first { $0.character.CharacterID == characterId }
    }

    // 获取角色详细信息
    private func fetchCharacterDetails(characterId: Int) async throws -> (
        skills: CharacterSkillsResponse, balance: Double, location: CharacterLocation,
        skillQueue: [SkillQueueItem]
    ) {
        Logger.info("[EVELogin]EVELogin: 开始获取角色详细信息...")

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
            let (skillsResult, balanceResult, locationResult, queueResult) = try await (
                skills, balance, location, skillQueue
            )
            Logger.info("[EVELogin]成功获取所有角色详细信息")
            return (skillsResult, balanceResult, locationResult, queueResult)
        } catch {
            Logger.error("[EVELogin]获取角色详细信息失败: \(error)")
            throw error
        }
    }

    private func loadConfig() {
        // 初始化基本配置
        var configWithScopes = EVELogin.defaultConfig
        configWithScopes.scopes = []

        // 更新jwksMetadata配置
        configWithScopes.urls = ESIConfig.ESIUrls(
            jwksMetadata: EVEConfig.OAuth.jwksMetadataEndpoint.absoluteString
        )

        config = configWithScopes

        // 异步加载 scopes
        Task {
            let scopes = await ScopeManager.shared.getLatestScopes()
            await MainActor.run {
                self.config?.scopes = scopes
            }
        }
    }

    // 更新角色的 refreshTokenExpired 状态
    func updateCharacterRefreshTokenExpiredStatus(characterId: Int, expired: Bool) {
        var characters = loadCharacters()
        if let index = characters.firstIndex(where: { $0.character.CharacterID == characterId }) {
            var updatedCharacter = characters[index].character
            if updatedCharacter.refreshTokenExpired != expired {
                Logger.info(
                    "[EVELogin]将人物 \(characterId) 的 refresh token 过期状态从 \(updatedCharacter.refreshTokenExpired) 改为 \(expired)"
                )
                updatedCharacter.refreshTokenExpired = expired
                characters[index] = CharacterAuth(
                    character: updatedCharacter, addedDate: characters[index].addedDate,
                    lastTokenUpdateTime: Date())

                // 保存更新后的角色信息
                if let encodedData = try? JSONEncoder().encode(characters) {
                    UserDefaults.standard.set(encodedData, forKey: charactersKey)
                }

                // 发送通知以更新UI
                NotificationCenter.default.post(
                    name: Notification.Name("CharacterDetailsUpdated"),
                    object: nil,
                    userInfo: ["character": updatedCharacter]
                )
            } else {
                Logger.info(
                    "[EVELogin]人物 \(characterId) 的 refresh token 过期状态为 \(updatedCharacter.refreshTokenExpired), 无需更改"
                )
            }
        }
    }

    // 保存认证信息
    func saveAuthInfo(token: EVEAuthToken, character: EVECharacterInfo) async throws {
        Logger.info(
            "[EVELogin]开始保存认证信息 - 角色: \(character.CharacterName) (\(character.CharacterID))")

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

        // 3. 重置refreshTokenExpired状态
        updateCharacterRefreshTokenExpiredStatus(characterId: character.CharacterID, expired: false)

        Logger.info("[EVELogin]EVELogin: 认证状态已保存")
    }

    // 添加 getScopes 方法到类内部
    func getScopes() async -> [String] {
        let scopes = await ScopeManager.shared.getLatestScopes()
        // 更新配置中的 scopes
        await MainActor.run {
            self.config?.scopes = scopes
        }
        return scopes
    }

    func resetRefreshTokenExpired(characterId: Int) {
        // 不再需要手动管理 token 状态，由 AuthTokenManager 处理
        Task {
            do {
                _ = try await AuthTokenManager.shared.getAccessToken(for: characterId)
                // 明确将refreshTokenExpired设置为false
                updateCharacterRefreshTokenExpiredStatus(characterId: characterId, expired: false)
                Logger.info("[EVELogin]EVELogin: 已重置角色 \(characterId) 的 token 状态")
            } catch {
                Logger.error("[EVELogin]重置角色 \(characterId) 的 token 状态失败: \(error)")
            }
        }
    }
}

// 添加 ScopeManager 类
class ScopeManager {
    static let shared = ScopeManager()
    private let latestScopesFileName = "latest_scopes.json"
    private let hardcodedScopesFileName = "scopes.json"

    private init() {}

    // 获取文档目录路径
    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // 获取最新 scopes 文件路径
    private var latestScopesPath: URL {
        documentsDirectory.appendingPathComponent(latestScopesFileName)
    }

    // 从本地文件加载 scopes
    private func loadScopesFromFile(_ url: URL) -> [String]? {
        do {
            let data = try Data(contentsOf: url)
            let scopesDict = try JSONDecoder().decode([String: [String]].self, from: data)
            Logger.info("[EVELogin]从文件加载 scopes 成功: \(url)")
            return Array(Set(scopesDict.values.flatMap { $0 }))
        } catch {
            Logger.error("[EVELogin]从文件加载 scopes 失败: \(error)")
            return nil
        }
    }

    // 保存 scopes 到本地文件
    private func saveScopesToFile(_ scopes: [String]) {
        do {
            // 对 scopes 数组进行排序
            let sortedScopes = scopes.sorted()
            let scopesDict = ["scopes": sortedScopes]
            let data = try JSONEncoder().encode(scopesDict)
            try data.write(to: latestScopesPath)
            Logger.info("[EVELogin]成功保存 scopes 到本地文件，共 \(sortedScopes.count) 个权限")
        } catch {
            Logger.error("[EVELogin]保存 scopes 到本地文件失败: \(error)")
        }
    }

    // 从 swagger.json 获取最新的 scopes
    func fetchLatestScopes() async throws -> [String] {
        guard let url = URL(string: "https://esi.evetech.net/latest/swagger.json") else {
            throw NetworkError.invalidURL
        }

        // 使用NetworkManager实现超时重试机制
        let data = try await NetworkManager.shared.fetchData(
            from: url,
            method: "GET",
            headers: ["Accept": "application/json"],
            noRetryKeywords: nil,
            timeouts: [2, 5, 5]
        )

        let swagger = try JSONDecoder().decode(SwaggerResponse.self, from: data)

        // 从 securityDefinitions.evesso.scopes 中提取所有的 scope keys
        let allScopes = swagger.securityDefinitions.evesso.scopes.keys.map { String($0) }
        
        // 获取不允许的 scopes 并过滤
        let notAllowedScopes = getNotAllowedScopes()
        let filteredScopes = allScopes.filter { !notAllowedScopes.contains($0) }

        // 保存过滤后的 scopes 到本地文件
        saveScopesToFile(filteredScopes)

        Logger.info("[EVELogin]成功从网络获取最新scopes，原始: \(allScopes.count)，过滤后: \(filteredScopes.count)")

        return filteredScopes
    }
    
    // 获取不允许的 scopes 集合
    private func getNotAllowedScopes() -> Set<String> {
        guard let scopesURL = Bundle.main.url(forResource: hardcodedScopesFileName, withExtension: nil),
              let data = try? Data(contentsOf: scopesURL),
              let scopesDict = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            return Set()
        }
        return Set(scopesDict["notAllowedScopes"] ?? [])
    }

    // 获取 scopes
    func getLatestScopes(forceRefresh: Bool = false) async -> [String] {
        // 检查是否需要刷新
        var shouldRefresh = forceRefresh

        if !shouldRefresh && FileManager.default.fileExists(atPath: latestScopesPath.path) {
            do {
                let attributes = try FileManager.default.attributesOfItem(
                    atPath: latestScopesPath.path)
                if let modificationDate = attributes[.modificationDate] as? Date {
                    let timeInterval = Date().timeIntervalSince(modificationDate)
                    let days = Int(timeInterval) / (24 * 3600)
                    let remainingDays = 7 - days
                    shouldRefresh = timeInterval >= 7 * 24 * 3600

                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                    let lastUpdateStr = dateFormatter.string(from: modificationDate)

                    Logger.info(
                        """
                        [EVELogin]Scopes 文件状态:
                        - 最后更新时间: \(lastUpdateStr)
                        - 已过去天数: \(days) 天
                        - 剩余有效期: \(remainingDays) 天
                        - 是否需要刷新: \(shouldRefresh ? "是" : "否")
                        """)
                }
            } catch {
                Logger.error("[EVELogin]检查 latest_scopes.json 文件属性失败: \(error)")
                shouldRefresh = true
            }
        } else if !shouldRefresh {
            Logger.info("[EVELogin]latest_scopes.json 文件不存在，需要创建")
            shouldRefresh = true
        }

        // 如果需要刷新，尝试从网络获取
        if shouldRefresh {
            do {
                Logger.info("[EVELogin]尝试从网络获取最新 scopes")
                return try await fetchLatestScopes()
            } catch {
                Logger.error("[EVELogin]从网络获取 scopes 失败: \(error)，尝试使用本地文件")
            }
        }

        // 尝试从本地文件加载
        if let scopes = loadScopesFromFile(latestScopesPath) {
            Logger.info("[EVELogin]从本地文件加载 scopes 成功")
            // 对从本地文件加载的 scopes 也应用过滤
            let notAllowedScopes = getNotAllowedScopes()
            let filteredScopes = scopes.filter { !notAllowedScopes.contains($0) }
            if notAllowedScopes.count > 0 && scopes.count != filteredScopes.count {
                Logger.info("[EVELogin]对本地 scopes 应用过滤，原始: \(scopes.count)，过滤后: \(filteredScopes.count)")
            }
            return filteredScopes
        }

        // 如果本地文件加载失败，使用硬编码的 scopes
        Logger.info("[EVELogin]从本地文件加载失败，使用硬编码的 scopes")
        return loadHardcodedScopes() ?? []
    }

    // 从硬编码的 scopes.json 加载，并过滤掉不允许的 scopes
    private func loadHardcodedScopes() -> [String]? {
        guard let scopesURL = Bundle.main.url(forResource: hardcodedScopesFileName, withExtension: nil) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: scopesURL)
            let scopesDict = try JSONDecoder().decode([String: [String]].self, from: data)
            let allScopes = scopesDict["scopes"] ?? []
            let notAllowedScopes = Set(scopesDict["notAllowedScopes"] ?? [])
            
            let filteredScopes = allScopes.filter { !notAllowedScopes.contains($0) }
            
            if notAllowedScopes.count > 0 {
                Logger.info("[EVELogin]从硬编码文件加载 scopes 成功，原始: \(allScopes.count)，过滤后: \(filteredScopes.count)")
            } else {
                Logger.info("[EVELogin]从硬编码文件加载 scopes 成功，共 \(filteredScopes.count) 个权限")
            }
            
            return filteredScopes
        } catch {
            Logger.error("[EVELogin]从硬编码文件加载 scopes 失败: \(error)")
            return nil
        }
    }
}

// 添加 SwaggerResponse 结构体
private struct SwaggerResponse: Codable {
    let securityDefinitions: SecurityDefinitions

    struct SecurityDefinitions: Codable {
        let evesso: EveSSO

        struct EveSSO: Codable {
            let scopes: [String: String]
        }
    }
}
