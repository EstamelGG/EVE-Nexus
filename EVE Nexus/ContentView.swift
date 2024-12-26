import SwiftUI
import SafariServices
import WebKit
import Foundation

// 优化数据模型为值类型
struct TableRowNode: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let iconName: String
    let note: String?
    let destination: AnyView?
    
    init(title: String, iconName: String, note: String? = nil, destination: AnyView? = nil) {
        self.title = title
        self.iconName = iconName
        self.note = note
        self.destination = destination
    }
    
    static func == (lhs: TableRowNode, rhs: TableRowNode) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.iconName == rhs.iconName &&
        lhs.note == rhs.note
    }
}

struct TableNode: Identifiable, Equatable {
    let id = UUID()
    let title: String
    var rows: [TableRowNode]
    
    init(title: String, rows: [TableRowNode]) {
        self.title = title
        self.rows = rows
    }
    
    static func == (lhs: TableNode, rhs: TableNode) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.rows == rhs.rows
    }
}

// 优化 UTCTimeView
class UTCTimeViewModel: ObservableObject {
    @Published var currentTime = Date()
    private var timer: Timer?
    
    func startTimer() {
        // 停止现有的计时器（如果存在）
        stopTimer()
        
        // 创建新的计时器
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.currentTime = Date()
        }
    }
    
    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    deinit {
        stopTimer()
    }
}

struct UTCTimeView: View {
    @StateObject private var viewModel = UTCTimeViewModel()
    
    var body: some View {
        Text(formattedUTCTime)
            .font(.monospacedDigit(.caption)())
            .onAppear {
                viewModel.startTimer()
            }
            .onDisappear {
                viewModel.stopTimer()
            }
    }
    
    private var formattedUTCTime: String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter.string(from: viewModel.currentTime)
    }
}

// 优化 ServerStatusView
struct ServerStatusView: View {
    let status: ServerStatus?
    
    var body: some View {
        HStack(spacing: 4) {
            UTCTimeView()
            Text("-")
            if let status = status {
                if status.isOnline {
                    Text("Online")
                        .font(.caption.bold())
                        .foregroundColor(.green)
                    
                    let formattedPlayers = NumberFormatter.localizedString(
                        from: NSNumber(value: status.players),
                        number: .decimal
                    )
                    Text("(\(formattedPlayers) players)")
                        .font(.caption)
                } else {
                    Text("Offline")
                        .font(.caption.bold())
                        .foregroundColor(.red)
                }
            } else {
                Text("Checking Status...")
                    .font(.caption)
            }
        }
    }
}

// 修改LoginButtonView组件
struct LoginButtonView: View {
    let isLoggedIn: Bool
    let serverStatus: ServerStatus?
    let selectedCharacter: EVECharacterInfo?
    let characterPortrait: UIImage?
    let isRefreshing: Bool
    @State private var corporationInfo: CorporationInfo?
    @State private var corporationLogo: UIImage?
    @State private var allianceInfo: AllianceInfo?
    @State private var allianceLogo: UIImage?
    @State private var tokenExpired = false
    
    var body: some View {
        HStack {
            if let portrait = characterPortrait {
                ZStack {
                    Image(uiImage: portrait)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 64, height: 64)
                        .clipShape(Circle())
                    if isRefreshing {
                        Circle()
                            .fill(Color.black.opacity(0.6))
                            .frame(width: 64, height: 64)
                        
                        ProgressView()
                            .scaleEffect(0.8)
                    } else if tokenExpired {
                        // Token过期的灰色蒙版和感叹号
                        Circle()
                            .fill(Color.black.opacity(0.4))
                            .frame(width: 64, height: 64)
                        
                        ZStack {
                            // 红色边框三角形
                            Image(systemName: "triangle")
                                .font(.system(size: 32))
                                .foregroundColor(.red)
                            
                            // 红色感叹号
                            Image(systemName: "exclamationmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.red)
                        }
                    }
                }
                .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 3))
                .background(Circle().fill(Color.primary.opacity(0.05)))
                .shadow(color: Color.primary.opacity(0.2), radius: 8, x: 0, y: 4)
                .padding(4)
            } else {
                ZStack {
                    Image(systemName: "person.crop.circle")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 64, height: 64)
                        .foregroundColor(Color.primary.opacity(0.5))  // 降低不透明度使其更柔和
                        .clipShape(Circle())
                }
                .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 3))
                .background(Circle().fill(Color.primary.opacity(0.05)))
                .shadow(color: Color.primary.opacity(0.2), radius: 8, x: 0, y: 4)
                .padding(4)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                if let character = selectedCharacter {
                    Text(character.CharacterName)
                        .font(.headline)
                        .lineLimit(1)
                    
                    // 显示联盟信息
                    HStack(spacing: 4) {
                        if let alliance = allianceInfo, let logo = allianceLogo {
                            Image(uiImage: logo)
                                .resizable()
                                .frame(width: 16, height: 16)
                                .clipShape(Circle())
                            Text("[\(alliance.ticker)] \(alliance.name)")
                                .font(.caption)
                                .lineLimit(1)
                        } else {
                            Image(systemName: "square.dashed")
                                .resizable()
                                .frame(width: 16, height: 16)
                                .foregroundColor(.gray)
                            Text("[-] \(NSLocalizedString("No Alliance", comment: ""))")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .lineLimit(1)
                        }
                    }
                    
                    // 显示军团信息
                    HStack(spacing: 4) {
                        if let corporation = corporationInfo, let logo = corporationLogo {
                            Image(uiImage: logo)
                                .resizable()
                                .frame(width: 16, height: 16)
                                .clipShape(Circle())
                            Text("[\(corporation.ticker)] \(corporation.name)")
                                .font(.caption)
                                .lineLimit(1)
                        } else {
                            Image(systemName: "square.dashed")
                                .resizable()
                                .frame(width: 16, height: 16)
                                .foregroundColor(.gray)
                            Text("[-] \(NSLocalizedString("No Corporation", comment: ""))")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .lineLimit(1)
                        }
                    }
                } else if isLoggedIn {
                    Text(NSLocalizedString("Account_Management", comment: ""))
                        .font(.headline)
                        .lineLimit(1)
                } else {
                    Text(NSLocalizedString("Account_Add_Character", comment: ""))
                        .font(.headline)
                        .lineLimit(1)
                }
                ServerStatusView(status: serverStatus)
            }
            .frame(height: 72)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .padding(.vertical, 8)
        .task {
            await loadCharacterInfo()
            // 检查token状态
            if let character = selectedCharacter {
                if let auth = EVELogin.shared.getCharacterByID(character.CharacterID) {
                    tokenExpired = auth.character.tokenExpired
                }
            }
        }
    }
    
    private func loadCharacterInfo() async {
        guard let character = selectedCharacter else { return }
        
        do {
            // 获取角色公开信息
            let publicInfo = try await CharacterAPI.shared.fetchCharacterPublicInfo(characterId: character.CharacterID)
            
            // 获取联盟信息
            if let allianceId = publicInfo.alliance_id {
                async let allianceInfoTask = AllianceAPI.shared.fetchAllianceInfo(allianceId: allianceId)
                async let allianceLogoTask = AllianceAPI.shared.fetchAllianceLogo(allianceID: allianceId)
                
                do {
                    let (info, logo) = try await (allianceInfoTask, allianceLogoTask)
                    await MainActor.run {
                        self.allianceInfo = info
                        self.allianceLogo = logo
                        // 成功获取信息，重置token状态
                        self.tokenExpired = false
                    }
                } catch {
                    Logger.error("加载联盟信息失败: \(error)")
                    // 如果是token相关错误，标记token过期
                    if case NetworkError.tokenExpired = error {
                        await MainActor.run {
                            self.tokenExpired = true
                        }
                    }
                }
            } else {
                // 如果角色没有联盟，清除联盟信息
                await MainActor.run {
                    self.allianceInfo = nil
                    self.allianceLogo = nil
                }
                Logger.info("角色没有所属联盟")
            }
            
            // 获取军团信息
            async let corporationInfoTask = CorporationAPI.shared.fetchCorporationInfo(corporationId: publicInfo.corporation_id)
            async let corporationLogoTask = CorporationAPI.shared.fetchCorporationLogo(corporationId: publicInfo.corporation_id)
            
            do {
                let (info, logo) = try await (corporationInfoTask, corporationLogoTask)
                await MainActor.run {
                    self.corporationInfo = info
                    self.corporationLogo = logo
                }
            } catch {
                Logger.error("加载军团信息失败: \(error)")
                // 如果是token相关错误，标记token过期
                if case NetworkError.tokenExpired = error {
                    await MainActor.run {
                        self.tokenExpired = true
                    }
                }
            }
            
        } catch {
            Logger.error("加载角色公开信息失败: \(error)")
            // 如果是token相关错误，标记token过期
            if case NetworkError.tokenExpired = error {
                await MainActor.run {
                    self.tokenExpired = true
                }
            }
        }
    }
}

struct ContentView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var tables: [TableNode] = []
    @State private var isLoggedIn = false
    @State private var serverStatus: ServerStatus?
    @State private var isLoadingStatus = true
    @State private var lastStatusUpdateTime: Date?
    @State private var selectedCharacter: EVECharacterInfo?
    @State private var selectedCharacterPortrait: UIImage?
    @State private var isRefreshing = false
    @State private var tokenExpired = false
    @State private var corporationInfo: CorporationInfo?
    @State private var corporationLogo: UIImage?
    @State private var allianceInfo: AllianceInfo?
    @State private var allianceLogo: UIImage?
    // 添加任务标识符
    @State private var currentTaskId = UUID()
    
    // 添加 UserDefaults 存储的当前角色 ID
    @AppStorage("currentCharacterId") private var currentCharacterId: Int = 0
    
    // 添加主题设置
    @AppStorage("selectedTheme") private var selectedTheme: String = "system"
    @Environment(\.colorScheme) var systemColorScheme
    
    // 添加更新间隔常量
    private let statusUpdateInterval: TimeInterval = 300 // 5分钟 = 300秒
    
    // 添加预加载状态
    @State private var isDatabasePreloaded = false
    
    // 添加自动刷新的时间间隔常量
    private let characterInfoUpdateInterval: TimeInterval = 300 // 5分钟
    
    // 使用计算属性来确定当前的颜色方案
    private var currentColorScheme: ColorScheme? {
        switch selectedTheme {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            return nil
        }
    }
    
    // 自定初始化方法，确保 databaseManager 正确传递
    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
        
        // 预加载角色信息
        let currentCharacterId = UserDefaults.standard.integer(forKey: "currentCharacterId")
        if currentCharacterId != 0 {
            let characters = EVELogin.shared.loadCharacters()
            if let savedCharacter = characters.first(where: { $0.character.CharacterID == currentCharacterId }) {
                _selectedCharacter = State(initialValue: savedCharacter.character)
                _tokenExpired = State(initialValue: savedCharacter.character.tokenExpired)
                
                // 从缓存加载头像
                if let cachedPortraitData = UserDefaults.standard.data(forKey: "character_portrait_\(currentCharacterId)_128"),
                   let cachedPortrait = UIImage(data: cachedPortraitData) {
                    _selectedCharacterPortrait = State(initialValue: cachedPortrait)
                }
                
                // 从缓存加载军团信息
                if let corporationId = savedCharacter.character.corporationId,
                   let cachedCorpData = UserDefaults.standard.data(forKey: "corporation_info_\(corporationId)"),
                   let corpInfo = try? JSONDecoder().decode(CorporationInfo.self, from: cachedCorpData) {
                    _corporationInfo = State(initialValue: corpInfo)
                    
                    // 从缓存加载军团图标
                    if let cachedCorpLogoData = UserDefaults.standard.data(forKey: "corporation_logo_\(corporationId)_128"),
                       let corpLogo = UIImage(data: cachedCorpLogoData) {
                        _corporationLogo = State(initialValue: corpLogo)
                    }
                }
                
                // 从缓存加载联盟信息（如果有）
                if let allianceId = savedCharacter.character.allianceId {
                    if let cachedAllianceData = UserDefaults.standard.data(forKey: "alliance_info_\(allianceId)"),
                       let allianceInfo = try? JSONDecoder().decode(AllianceInfo.self, from: cachedAllianceData) {
                        _allianceInfo = State(initialValue: allianceInfo)
                    }
                    
                    // 从缓存加载联盟图标
                    if let cachedAllianceLogoData = UserDefaults.standard.data(forKey: "alliance_logo_\(allianceId)_128"),
                       let allianceLogo = UIImage(data: cachedAllianceLogoData) {
                        _allianceLogo = State(initialValue: allianceLogo)
                    }
                }
                
                _isLoggedIn = State(initialValue: true)
            }
        }
        
        _tables = State(initialValue: generateTables())
    }
    
    // 添加图标缓存
    private let cachedIcons: [String: Image] = [
        "charactersheet": Image("charactersheet"),
        "jumpclones": Image("jumpclones"),
        "skills": Image("skills"),
        "evemail": Image("evemail"),
        "calendar": Image("calendar"),
        "Folder": Image("Folder"),
        "lpstore": Image("lpstore"),
        "items": Image("items"),
        "market": Image("market"),
        "criminal": Image("criminal"),
        "terminate": Image("terminate"),
        "incursions": Image("incursions"),
        "sovereignty": Image("sovereignty"),
        "assets": Image("assets"),
        "marketdeliveries": Image("marketdeliveries"),
        "contracts": Image("contracts"),
        "journal": Image("journal"),
        "wallet": Image("wallet"),
        "industry": Image("industry"),
        "Settings": Image("Settings"),
        "info": Image("info")
    ]
    
    func getDestination(for row: TableRowNode) -> AnyView {
        if let destination = row.destination {
            return AnyView(destination)
        }
        return AnyView(Text("Details for \(row.title)"))
    }
    
    @ViewBuilder
    private func rowContent(_ row: TableRowNode) -> some View {
        HStack {
            // 用缓存的图标
            (cachedIcons[row.iconName] ?? Image(row.iconName))
                .resizable()
                .frame(width: 36, height: 36)
                .cornerRadius(6)
                .drawingGroup() // 使用 Metal 渲染
            
            VStack(alignment: .leading) {
                Text(row.title)
                    .fixedSize(horizontal: false, vertical: true)
                if let note = row.note, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .frame(height: 36)
    }

    
    // 添加重置角色信息的方法
    private func resetCharacterInfo() {
        if let character = selectedCharacter {
            Logger.info("重置角色信息显示 - 角色: \(character.CharacterName) (ID: \(character.CharacterID))")
        }
        
        // 重置所有角色相关信息
        selectedCharacter?.totalSkillPoints = nil
        selectedCharacter?.unallocatedSkillPoints = nil
        selectedCharacter?.walletBalance = nil
        selectedCharacter?.skillQueueLength = nil
        selectedCharacter?.currentSkill = nil
        selectedCharacter?.locationStatus = nil
        selectedCharacter?.location = nil
        
        // 重置军团和联盟信息
        corporationInfo = nil
        corporationLogo = nil
        allianceInfo = nil
        allianceLogo = nil
        
        // 重置状态标志
        isRefreshing = false
        tokenExpired = false
        
        Logger.info("角色信息显示已重置")
    }
    
    var body: some View {
        NavigationStack {
            List {
                // 登录按钮部分
                loginSection
                
                // 功能列表部分
                functionalSections
            }
            .listStyle(.insetGrouped)
            .refreshable {
                await refreshAllData(forceRefresh: true)
            }
            .navigationTitle(NSLocalizedString("Main_Title", comment: ""))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        // 记录当前登出的角色信息
                        if let character = selectedCharacter {
                            Logger.info("用户登出角色 - 角色: \(character.CharacterName) (ID: \(character.CharacterID))")
                        }
                        
                        // 清空 currentCharacterId
                        currentCharacterId = 0
                        
                        // 重置登录状态和选中角色
                        isLoggedIn = false
                        selectedCharacter = nil
                        selectedCharacterPortrait = nil
                        
                        // 刷新表格数据以显示默认值
                        withAnimation {
                            tables = generateTables()
                        }
                        
                        Logger.info("角色登出完成")
                    } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .resizable()
                            .frame(width: 24, height: 24)
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .task {
            await loadInitialData()
        }
        // 应用主题设置
        .preferredColorScheme(currentColorScheme)
        // 监听主题变化
        .onChange(of: selectedTheme) { oldValue, newValue in
            // 只更新表格数据，不强制刷新整个视图
            tables = generateTables()
        }
        // 监听语言变化
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("LanguageChanged"))) { _ in
            // 只更新必要的数据，不影响导航状态
            withAnimation(.easeInOut(duration: 0.3)) {
                tables = generateTables()
            }
            // 在后台静默刷新数据
            Task {
                await refreshAllData()
            }
        }
    }
    
    // 登录部分
    private var loginSection: some View {
        Section {
            NavigationLink {
                AccountsView(databaseManager: databaseManager) { character, portrait in
                    // 在选择新角色之前，先重置当前显示的信息
                    resetCharacterInfo()
                    
                    // 更新选中的角色和头像
                    selectedCharacter = character
                    selectedCharacterPortrait = portrait
                    currentCharacterId = character.CharacterID
                    
                    // 立即刷新表格显示，这样会显示 "-"
                    withAnimation {
                        tables = generateTables()
                    }
                    
                    // 保存选择
                    UserDefaults.standard.set(character.CharacterID, forKey: "selectedCharacterId")
                    
                    // 异步加载新数据
                    Task {
                        await refreshAllData()
                    }
                }
            } label: {
                LoginButtonView(
                    isLoggedIn: isLoggedIn,
                    serverStatus: serverStatus,
                    selectedCharacter: selectedCharacter,
                    characterPortrait: selectedCharacterPortrait,
                    isRefreshing: isRefreshing
                )
            }
        }
    }
    
    // 功能列表部分
    private var functionalSections: some View {
        ForEach(tables) { table in
            Section {
                tableContent(for: table)
            } header: {
                Text(table.title)
                    .fontWeight(.bold)
                    .font(.system(size: 18))
                    .foregroundColor(.primary)
            }
        }
    }
    
    // 表格内容
    private func tableContent(for table: TableNode) -> some View {
        ForEach(table.rows) { row in
            NavigationLink(destination: getDestination(for: row)) {
                rowContent(row)
            }
        }
    }
    
    // 添加 updateUI 辅助函数
    @discardableResult
    @Sendable
    private func updateUI<T>(_ operation: @MainActor () -> T) async -> T {
        await MainActor.run { operation() }
    }
    
    // 刷新所有数据
    private func refreshAllData(forceRefresh: Bool = false) async {
        // 生成新的任务ID
        let taskId = UUID()
        await updateUI {
            currentTaskId = taskId
        }
        
        // 先让刷新指示器完成动画
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
        
        Logger.info("开始刷新所有数据...")
        
        // 如果有选中的角色，只调用一次刷新
        if let character = selectedCharacter {
            Logger.info("开始刷新角色数据 - 角色: \(character.CharacterName) (ID: \(character.CharacterID))")
            
            do {
                // 创建一个临时的角色信息副本，用于累积更新
                var updatedCharacter = character
                
                // 获取角色公开信息和头像
                async let publicInfoTask = CharacterAPI.shared.fetchCharacterPublicInfo(characterId: character.CharacterID)
                async let portraitTask = CharacterAPI.shared.fetchCharacterPortrait(characterId: character.CharacterID)
                
                let (publicInfo, portrait) = try await (publicInfoTask, portraitTask)
                
                // 检查是否仍是当前任务
                guard await checkCurrentTask(taskId) else {
                    Logger.info("取消过期的角色数据刷新任务")
                    return
                }
                
                // 并行刷新军团和联盟信息
                async let corporationInfoTask = CorporationAPI.shared.fetchCorporationInfo(corporationId: publicInfo.corporation_id)
                async let corporationLogoTask = CorporationAPI.shared.fetchCorporationLogo(corporationId: publicInfo.corporation_id)
                
                var newCorpInfo: CorporationInfo?
                var newCorpLogo: UIImage?
                var newAllianceInfo: AllianceInfo?
                var newAllianceLogo: UIImage?
                
                if let allianceId = publicInfo.alliance_id {
                    async let allianceInfoTask = AllianceAPI.shared.fetchAllianceInfo(allianceId: allianceId)
                    async let allianceLogoTask = AllianceAPI.shared.fetchAllianceLogo(allianceID: allianceId)
                    
                    // 等待所有任务完成
                    let (corpInfo, corpLogo, allianceInfo, allianceLogo) = try await (corporationInfoTask, corporationLogoTask, allianceInfoTask, allianceLogoTask)
                    
                    // 再次检查是否仍是当前任务
                    guard await checkCurrentTask(taskId) else {
                        Logger.info("取消过期的联盟数据刷新任务")
                        return
                    }
                    
                    newCorpInfo = corpInfo
                    newCorpLogo = corpLogo
                    newAllianceInfo = allianceInfo
                    newAllianceLogo = allianceLogo
                } else {
                    // 等待军团相关任务完成
                    let (corpInfo, corpLogo) = try await (corporationInfoTask, corporationLogoTask)
                    
                    // 再次检查是否仍是当前任务
                    guard await checkCurrentTask(taskId) else {
                        Logger.info("取消过期的军团数据刷新任务")
                        return
                    }
                    
                    newCorpInfo = corpInfo
                    newCorpLogo = corpLogo
                }
                
                // 并行执行所有数据获取任务
                async let skillsTask = CharacterSkillsAPI.shared.fetchCharacterSkills(
                    characterId: character.CharacterID,
                    forceRefresh: forceRefresh
                )
                async let walletTask = CharacterWalletAPI.shared.getWalletBalance(
                    characterId: character.CharacterID
                )
                async let locationTask = CharacterLocationAPI.shared.fetchCharacterLocation(
                    characterId: character.CharacterID
                )
                async let queueTask = CharacterSkillsAPI.shared.fetchSkillQueue(
                    characterId: character.CharacterID
                )
                
                // 等待所有任务完成
                let (skills, balance, location, queue) = try await (
                    skillsTask,
                    walletTask,
                    locationTask,
                    queueTask
                )
                
                // 最终检查是否仍是当前任务
                guard await checkCurrentTask(taskId) else {
                    Logger.info("取消过期的角色状态刷新任务")
                    return
                }
                
                // 更新技能信息
                updatedCharacter.totalSkillPoints = skills.total_sp
                updatedCharacter.unallocatedSkillPoints = skills.unallocated_sp
                
                // 更新钱包余额
                updatedCharacter.walletBalance = balance
                
                // 更新位置信息
                updatedCharacter.locationStatus = location.locationStatus
                if let locationInfo = await getSolarSystemInfo(
                    solarSystemId: location.solar_system_id,
                    databaseManager: databaseManager
                ) {
                    updatedCharacter.location = locationInfo
                }
                
                // 更新技能队列
                updatedCharacter.skillQueueLength = queue.count
                if let currentSkill = queue.first(where: { $0.isCurrentlyTraining }),
                   let skillName = SkillTreeManager.shared.getSkillName(for: currentSkill.skill_id) {
                    updatedCharacter.currentSkill = EVECharacterInfo.CurrentSkillInfo(
                        skillId: currentSkill.skill_id,
                        name: skillName,
                        level: currentSkill.skillLevel,
                        progress: currentSkill.progress,
                        remainingTime: currentSkill.remainingTime
                    )
                } else if let firstSkill = queue.first,
                          let skillName = SkillTreeManager.shared.getSkillName(for: firstSkill.skill_id) {
                    updatedCharacter.currentSkill = EVECharacterInfo.CurrentSkillInfo(
                        skillId: firstSkill.skill_id,
                        name: skillName,
                        level: firstSkill.skillLevel,
                        progress: firstSkill.progress,
                        remainingTime: nil
                    )
                }
                
                // 一次性更新所有UI
                await updateUI {
                    selectedCharacter = updatedCharacter
                    selectedCharacterPortrait = portrait
                    corporationInfo = newCorpInfo
                    corporationLogo = newCorpLogo
                    allianceInfo = newAllianceInfo
                    allianceLogo = newAllianceLogo
                    tables = generateTables()
                }
                
            } catch {
                Logger.error("刷新角色数据失败: \(error)")
            }
        }
        
        // 刷新服务器状态
        do {
            let status = try await ServerStatusAPI.shared.fetchServerStatus()
            
            // 检查是否仍是当前任务
            guard await checkCurrentTask(taskId) else {
                Logger.info("取消过期的服务器状态刷新任务")
                return
            }
            
            await updateUI {
                withAnimation(.easeInOut(duration: 0.3)) {
                    serverStatus = status
                    lastStatusUpdateTime = Date()
                }
            }
        } catch {
            Logger.error("Failed to refresh server status: \(error)")
        }
        
        Logger.info("完成所有数据刷新")
    }
    
    // 添加检查当前任务的方法
    private func checkCurrentTask(_ taskId: UUID) async -> Bool {
        await MainActor.run { currentTaskId == taskId }
    }
    
    
    // 添加加载保存的角色信息的方法
    private func loadSavedCharacter() async {
        Logger.info("正在加载保存的角色信息...")
        Logger.info("当前保存的所选角色ID: \(currentCharacterId)")
        
        // 如果有保存的角色 ID，尝试加载该角色信息
        if currentCharacterId != 0 {
            let characters = EVELogin.shared.loadCharacters()
            if let savedCharacter = characters.first(where: { $0.character.CharacterID == currentCharacterId }) {
                selectedCharacter = savedCharacter.character
                Logger.info("""
                    成功加载保存的所选角色信息:
                    - 角色ID: \(savedCharacter.character.CharacterID)
                    - 角色名称: \(savedCharacter.character.CharacterName)
                    """)
                
                // 使用 API 的缓存机制加载数据
                do {
                    // 加载技能信息
                    if let skills = try? await CharacterSkillsAPI.shared.fetchCharacterSkills(
                        characterId: currentCharacterId
                    ) {
                        selectedCharacter?.totalSkillPoints = skills.total_sp
                        selectedCharacter?.unallocatedSkillPoints = skills.unallocated_sp
                        Logger.info("加载技能点信息成功")
                    }
                    
                    // 加载钱包余额
                    if let balance = try? await CharacterWalletAPI.shared.getWalletBalance(
                        characterId: currentCharacterId
                    ) {
                        selectedCharacter?.walletBalance = balance
                        Logger.info("加载钱包余额成功")
                    }
                    
                    // 加载技能队列
                    if let queue = try? await CharacterSkillsAPI.shared.fetchSkillQueue(
                        characterId: currentCharacterId
                    ) {
                        selectedCharacter?.skillQueueLength = queue.count
                        if let currentSkill = queue.first(where: { $0.isCurrentlyTraining }) {
                            if let skillName = SkillTreeManager.shared.getSkillName(for: currentSkill.skill_id) {
                                // 获取队列最后一个技能的完成时间
                                if let lastSkill = queue.last,
                                   let lastFinishTime = lastSkill.remainingTime {
                                    selectedCharacter?.queueFinishTime = lastFinishTime
                                }
                                
                                selectedCharacter?.currentSkill = EVECharacterInfo.CurrentSkillInfo(
                                    skillId: currentSkill.skill_id,
                                    name: skillName,
                                    level: currentSkill.skillLevel,
                                    progress: currentSkill.progress,
                                    remainingTime: currentSkill.remainingTime
                                )
                            }
                        }
                        Logger.info("加载技能队列成功 - \(savedCharacter.character.CharacterName) (ID: \(savedCharacter.character.CharacterID))")
                    }
                    
                    // 强制更新表格显示
                    tables = generateTables()
                }
                
                // 异步加载头像
                Task {
                    if let portrait = try? await CharacterAPI.shared.fetchCharacterPortrait(
                        characterId: currentCharacterId
                    ) {
                        await MainActor.run {
                            selectedCharacterPortrait = portrait
                        }
                    } else {
                        Logger.error("加载角色头像失败")
                    }
                }
            } else {
                // 如果找不到保存的角色，清除当前角色 ID
                Logger.warning("未找到保存的角色（ID: \(currentCharacterId)），清除当前角色ID")
                currentCharacterId = 0
            }
        } else {
            Logger.info("没有保存的角色ID")
        }
    }
    
    // 创建生成表格数据的私有方法
    private func generateTables() -> [TableNode] {
        var tables: [TableNode] = []
        
        // 如果有选中的角色，显示所有功能列表
        if currentCharacterId != 0 {
            // 格式化技能点显示
            let spText = if let character = selectedCharacter,
                           character.CharacterID == currentCharacterId,  // 确保是当前选中的角色
                           let totalSP = character.totalSkillPoints {
                NSLocalizedString("Main_Skills_Ponits", comment: "")
                    .replacingOccurrences(of: "$num", with: FormatUtil.format(Double(totalSP)))
            } else {
                NSLocalizedString("Main_Skills_Ponits", comment: "")
                    .replacingOccurrences(of: "$num", with: "--")
            }
            
            // 格式化技能队列显示
            let skillQueueText: String
            if let character = selectedCharacter,
               character.CharacterID == currentCharacterId {  // 确保是当前选中的角色
                if let _ = character.currentSkill,
                   let queueFinishTime = character.queueFinishTime {
                    // 正在训练状态
                    let remainingTime = queueFinishTime
                    let days = Int(remainingTime) / 86400
                    let hours = (Int(remainingTime) % 86400) / 3600
                    let minutes = (Int(remainingTime) % 3600) / 60
                    skillQueueText = NSLocalizedString("Main_Skills_Queue_Training", comment: "")
                        .replacingOccurrences(of: "$num", with: "\(character.skillQueueLength ?? 0)")
                        .replacingOccurrences(of: "$day", with: "\(days)")
                        .replacingOccurrences(of: "$hour", with: "\(hours)")
                        .replacingOccurrences(of: "$minutes", with: "\(minutes)")
                } else {
                    // 暂停状态
                    skillQueueText = NSLocalizedString("Main_Skills_Queue_Paused", comment: "")
                        .replacingOccurrences(of: "$num", with: "\(character.skillQueueLength ?? 0)")
                }
            } else {
                // 未选择角色
                skillQueueText = NSLocalizedString("Main_Skills_Queue_Empty", comment: "")
                    .replacingOccurrences(of: "$num", with: "0")
            }
            
            // 格式化钱包余额显示
            let iskText = if let character = selectedCharacter,
                           character.CharacterID == currentCharacterId,  // 确保是当前选中的角色
                           let balance = character.walletBalance {
                NSLocalizedString("Main_Wealth_ISK", comment: "")
                    .replacingOccurrences(of: "$num", with: FormatUtil.format(Double(balance)))
            } else {
                NSLocalizedString("Main_Wealth_ISK", comment: "")
                    .replacingOccurrences(of: "$num", with: "--")
            }
            
            // 添加角色相关功能列表
            tables.append(TableNode(
                title: NSLocalizedString("Main_Character", comment: ""),
                rows: [
                    TableRowNode(
                        title: NSLocalizedString("Main_Character_Sheet", comment: ""),
                        iconName: "charactersheet",
                        note: spText
                    ),
                    TableRowNode(
                        title: NSLocalizedString("Main_Jump_Clones", comment: ""),
                        iconName: "jumpclones",
                        note: NSLocalizedString("Main_Jump_Clones_Available", comment: "")
                    ),
                    TableRowNode(
                        title: NSLocalizedString("Main_Skills", comment: ""),
                        iconName: "skills",
                        note: skillQueueText
                    ),
                    TableRowNode(
                        title: NSLocalizedString("Main_EVE_Mail", comment: ""),
                        iconName: "evemail"
                    ),
                    TableRowNode(
                        title: NSLocalizedString("Main_Calendar", comment: ""),
                        iconName: "calendar"
                    ),
                    TableRowNode(
                        title: NSLocalizedString("Main_Wealth", comment: ""),
                        iconName: "Folder",
                        note: iskText
                    ),
                    TableRowNode(
                        title: NSLocalizedString("Main_Loyalty_Points", comment: ""),
                        iconName: "lpstore"
                    )
                ]
            ))
        }
        
        // 数据库列表（始终显示）
        tables.append(TableNode(
            title: NSLocalizedString("Main_Databases", comment: ""),
            rows: [
                TableRowNode(
                    title: NSLocalizedString("Main_Database", comment: ""),
                    iconName: "items",
                    destination: AnyView(DatabaseBrowserView(
                        databaseManager: databaseManager,
                        level: .categories
                    ))
                ),
                TableRowNode(
                    title: NSLocalizedString("Main_Market", comment: ""),
                    iconName: "market",
                    destination: AnyView(MarketBrowserView(databaseManager: databaseManager))
                ),
                TableRowNode(
                    title: "NPC",
                    iconName: "criminal",
                    destination: AnyView(NPCBrowserView(databaseManager: databaseManager))
                ),
                TableRowNode(
                    title: NSLocalizedString("Main_WH", comment: ""),
                    iconName: "terminate",
                    destination: AnyView(WormholeView(databaseManager: databaseManager))
                ),
                TableRowNode(
                    title: NSLocalizedString("Main_Incursions", comment: ""),
                    iconName: "incursions",
                    destination: AnyView(IncursionsView(databaseManager: databaseManager))
                ),
                TableRowNode(
                    title: NSLocalizedString("Main_Sovereignty", comment: ""),
                    iconName: "sovereignty",
                    destination: AnyView(SovereigntyView(databaseManager: databaseManager))
                )
            ]
        ))
        
        if currentCharacterId != 0 {
            // 添加商业相关功能列表
            tables.append(TableNode(
                title: NSLocalizedString("Main_Business", comment: ""),
                rows: [
                    TableRowNode(
                        title: NSLocalizedString("Main_Assets", comment: ""),
                        iconName: "assets",
                        destination: selectedCharacter.map { character in
                            AnyView(CharacterAssetsView(characterId: character.CharacterID))
                        }
                    ),
                    TableRowNode(
                        title: NSLocalizedString("Main_Market Orders", comment: ""),
                        iconName: "marketdeliveries"
                    ),
                    TableRowNode(
                        title: NSLocalizedString("Main_Contracts", comment: ""),
                        iconName: "contracts"
                    ),
                    TableRowNode(
                        title: NSLocalizedString("Main_Market Transactions", comment: ""),
                        iconName: "journal"
                    ),
                    TableRowNode(
                        title: NSLocalizedString("Main_Wallet Journal", comment: ""),
                        iconName: "wallet"
                    ),
                    TableRowNode(
                        title: NSLocalizedString("Main_Industry Jobs", comment: ""),
                        iconName: "industry"
                    )
                ]
            ))
        }
        
        // 其他设置列表（始终显示）
        tables.append(TableNode(
            title: NSLocalizedString("Main_Other", comment: ""),
            rows: [
                TableRowNode(
                    title: NSLocalizedString("Main_Setting", comment: ""),
                    iconName: "Settings",
                    destination: AnyView(SettingView(databaseManager: databaseManager))
                ),
                TableRowNode(
                    title: NSLocalizedString("Main_About", comment: ""),
                    iconName: "info",
                    destination: AnyView(AboutView())
                )
            ]
        ))
        
        return tables
    }
    
    // 添加加载初始数据的方法
    private func loadInitialData() async {
        // 生成新的任务ID
        let taskId = UUID()
        await updateUI {
            currentTaskId = taskId
        }
        
        // 1. 如果有已保存的角色ID，立即尝试加载头像（不等待其他信息）
        if currentCharacterId != 0 {
            // 尝试加载头像（优先使用缓存）
            if selectedCharacterPortrait == nil {
                if let portrait = try? await CharacterAPI.shared.fetchCharacterPortrait(
                    characterId: currentCharacterId,
                    forceRefresh: false
                ) {
                    // 检查是否仍是当前任务
                    guard await checkCurrentTask(taskId) else { return }
                    
                    await MainActor.run {
                        selectedCharacterPortrait = portrait
                    }
                }
            }
        }
        
        // 2. 加载保存的角色信息
        await loadSavedCharacter()
        
        // 3. 异步加载服务器状态
        do {
            let status = try await ServerStatusAPI.shared.fetchServerStatus()
            
            // 检查是否仍是当前任务
            guard await checkCurrentTask(taskId) else { return }
            
            await MainActor.run {
                serverStatus = status
                lastStatusUpdateTime = Date()
            }
        } catch {
            Logger.error("Failed to load server status: \(error)")
        }
        
        // 4. 如果有选中的角色，刷新其他数据
        if selectedCharacter != nil {
            // 如果头像加载失败，在这里重试一次
            if selectedCharacterPortrait == nil {
                if let portrait = try? await CharacterAPI.shared.fetchCharacterPortrait(
                    characterId: currentCharacterId,
                    forceRefresh: true  // 这次强制刷新
                ) {
                    // 检查是否仍是当前任务
                    guard await checkCurrentTask(taskId) else { return }
                    
                    await MainActor.run {
                        selectedCharacterPortrait = portrait
                    }
                }
            }
            
            await refreshAllData()
        }
    }
}
