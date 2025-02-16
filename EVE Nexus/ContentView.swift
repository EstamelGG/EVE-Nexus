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
class ServerStatusViewModel: ObservableObject {
    @Published var status: ServerStatus?
    @Published var currentTime = Date()
    private var timer: Timer?
    private var statusTimer: Timer?
    
    // 获取UTC时间的小时和分钟
    private var utcHourAndMinute: (hour: Int, minute: Int) {
        let calendar = Calendar.current
        let utc = TimeZone(identifier: "UTC")!
        let components = calendar.dateComponents(in: utc, from: currentTime)
        return (components.hour ?? 0, components.minute ?? 0)
    }
    
    // 计算下一次更新的时间间隔
    private var nextUpdateInterval: TimeInterval {
        let (hour, minute) = utcHourAndMinute
        
        // 11:00 AM UTC
        if hour == 11 && minute == 0 {
            return 60 // 1分钟
        }
        // 11:00-11:30 AM UTC
        else if hour == 11 && minute < 30 {
            // 如果服务器已经在线，切换到2分钟间隔
            if let status = status, status.isOnline {
                return 120 // 2分钟
            }
            return 60 // 1分钟
        }
        // 11:30 AM UTC 之后
        else if hour == 11 && minute >= 30 {
            return 120 // 2分钟
        }
        // 11:00 AM UTC 之前
        else {
            return 1200 // 20分钟
        }
    }
    
    func startTimers() {
        // 停止现有的计时器
        stopTimers()
        
        // 创建时间更新计时器（每秒更新）
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let oldTime = self.currentTime
            self.currentTime = Date()
            
            // 检查是否跨越了整点或半点
            let oldHourMinute = self.getHourAndMinute(from: oldTime)
            let newHourMinute = self.getHourAndMinute(from: self.currentTime)
            
            // 在特定时间点立即刷新
            if self.shouldImmediatelyRefresh(oldTime: oldHourMinute, newTime: newHourMinute) {
                Task {
                    await self.refreshServerStatus()
                }
                // 重新设置状态更新计时器
                self.resetStatusTimer()
            }
        }
        
        // 立即开始第一次刷新
        Task {
            await refreshServerStatus()
        }
        
        // 设置状态更新计时器
        resetStatusTimer()
    }
    
    private func getHourAndMinute(from date: Date) -> (hour: Int, minute: Int) {
        let calendar = Calendar.current
        let utc = TimeZone(identifier: "UTC")!
        let components = calendar.dateComponents(in: utc, from: date)
        return (components.hour ?? 0, components.minute ?? 0)
    }
    
    private func shouldImmediatelyRefresh(oldTime: (hour: Int, minute: Int), newTime: (hour: Int, minute: Int)) -> Bool {
        // 11:00 AM UTC
        if newTime.hour == 11 && newTime.minute == 0 && 
           (oldTime.hour != 11 || oldTime.minute != 0) {
            return true
        }
        return false
    }
    
    private func resetStatusTimer() {
        statusTimer?.invalidate()
        statusTimer = Timer.scheduledTimer(withTimeInterval: nextUpdateInterval, repeats: true) { [weak self] _ in
            Task {
                await self?.refreshServerStatus()
            }
        }
    }
    
    func stopTimers() {
        timer?.invalidate()
        timer = nil
        statusTimer?.invalidate()
        statusTimer = nil
    }
    
    // 强制刷新方法，供下拉刷新使用
    func forceRefresh() async {
        await refreshServerStatus(forceRefresh: true)
    }
    
    private func refreshServerStatus(forceRefresh: Bool = false) async {
        do {
            let newStatus = try await ServerStatusAPI.shared.fetchServerStatus(forceRefresh: forceRefresh)
            await MainActor.run {
                self.status = newStatus
                
                // 如果在11:00-11:30之间且服务器已上线，重置计时器使用新的间隔
                let (hour, minute) = utcHourAndMinute
                if hour == 11 && minute < 30 && newStatus.isOnline {
                    resetStatusTimer()
                }
            }
        } catch {
            Logger.error("刷新服务器状态失败: \(error)")
        }
    }
    
    deinit {
        stopTimers()
    }
}

struct ServerStatusView: View {
    @StateObject private var viewModel = ServerStatusViewModel()
    @ObservedObject var mainViewModel: MainViewModel
    
    var body: some View {
        HStack(spacing: 4) {
            Text(formattedUTCTime)
                .font(.monospacedDigit(.caption)())
            Text("-")
                .font(.caption)
            statusText
        }
        .onAppear {
            viewModel.startTimers()
        }
        .onDisappear {
            viewModel.stopTimers()
        }
    }
    
    private var formattedUTCTime: String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter.string(from: viewModel.currentTime)
    }
    
    private var statusText: Text {
        if let status = mainViewModel.serverStatus {
            if status.isOnline {
                let formattedPlayers = NumberFormatter.localizedString(
                    from: NSNumber(value: status.players),
                    number: .decimal
                )
                return Text("Online")
                    .font(.caption.bold())
                    .foregroundColor(.green) +
                Text(" (\(formattedPlayers) players)")
                    .font(.caption)
            } else {
                return Text("Offline")
                    .font(.caption.bold())
                    .foregroundColor(.red)
            }
        } else {
            return Text("Checking Status...")
                .font(.caption)
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
    @ObservedObject var mainViewModel: MainViewModel
    
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
                                .clipShape(RoundedRectangle(cornerRadius: 4))
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
                                .clipShape(RoundedRectangle(cornerRadius: 4))
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
                ServerStatusView(mainViewModel: mainViewModel)
            }
            .frame(height: 72)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .padding(.vertical, 8)
        .task {
            // 检查token状态
            if let character = selectedCharacter {
                if let auth = EVELogin.shared.getCharacterByID(character.CharacterID) {
                    tokenExpired = auth.character.tokenExpired
                    await loadCharacterInfo()
                } else {
                    // 如果找不到认证信息，通知 ContentView 执行登出操作
                    NotificationCenter.default.post(name: NSNotification.Name("CharacterLoggedOut"), object: nil)
                }
            }
        }
        .onChange(of: selectedCharacter) { oldValue, newValue in
            // 清除旧的图标和信息
            corporationInfo = nil
            corporationLogo = nil
            allianceInfo = nil
            allianceLogo = nil
            
            // 如果有新的角色,加载新的图标
            if let character = newValue {
                Task {
                    do {
                        // 加载军团信息和图标
                        async let corporationInfoTask = CorporationAPI.shared.fetchCorporationInfo(corporationId: character.corporationId ?? 0)
                        async let corporationLogoTask = CorporationAPI.shared.fetchCorporationLogo(corporationId: character.corporationId ?? 0)
                        
                        let (corpInfo, corpLogo) = try await (corporationInfoTask, corporationLogoTask)
                        
                        await MainActor.run {
                            corporationInfo = corpInfo
                            corporationLogo = corpLogo
                        }
                        
                        // 如果有联盟,加载联盟信息和图标
                        if let allianceId = character.allianceId {
                            async let allianceInfoTask = AllianceAPI.shared.fetchAllianceInfo(allianceId: allianceId)
                            async let allianceLogoTask = AllianceAPI.shared.fetchAllianceLogo(allianceID: allianceId)
                            
                            let (alliInfo, alliLogo) = try await (allianceInfoTask, allianceLogoTask)
                            
                            await MainActor.run {
                                allianceInfo = alliInfo
                                allianceLogo = alliLogo
                            }
                        }
                    } catch {
                        Logger.error("加载角色信息失败: \(error)")
                    }
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
                    }
                } catch {
                    Logger.error("获取联盟信息失败: \(error)")
                }
            }
            
            // 获取军团信息
            let corporationId = publicInfo.corporation_id
            async let corpInfoTask = CorporationAPI.shared.fetchCorporationInfo(corporationId: corporationId)
            async let corpLogoTask = CorporationAPI.shared.fetchCorporationLogo(corporationId: corporationId)
            
            do {
                let (info, logo) = try await (corpInfoTask, corpLogoTask)
                await MainActor.run {
                    self.corporationInfo = info
                    self.corporationLogo = logo
                }
            } catch {
                Logger.error("获取军团信息失败: \(error)")
            }
            
        } catch {
            Logger.error("获取角色信息失败: \(error)")
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = MainViewModel()
    @ObservedObject var databaseManager: DatabaseManager
    @AppStorage("currentCharacterId") private var currentCharacterId: Int = 0
    @AppStorage("selectedTheme") private var selectedTheme: String = "system"
    @AppStorage("showCorporationAffairs") private var showCorporationAffairs: Bool = false
    @Environment(\.colorScheme) var systemColorScheme
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var selectedItem: String? = nil
    
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
    
    var body: some View {
        GeometryReader { geometry in
            NavigationSplitView(columnVisibility: $columnVisibility) {
                List(selection: $selectedItem) {
                    // 登录部分
                    loginSection
                    
                    // 角色功能部分
                    if currentCharacterId != 0 {
                        characterSection
                        
                        // 军团部分（仅在开启设置且已登录时显示）
                        if showCorporationAffairs {
                            corporationSection
                        }
                    }
                    
                    // 数据库部分(始终显示)
                    databaseSection
                    
                    // 商业部分(登录后显示)
                    if currentCharacterId != 0 {
                        businessSection
                        KillBoardSection
                    }
                    
                    // 其他设置(始终显示)
                    otherSection
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    await viewModel.refreshAllData(forceRefresh: true)
                }
                .navigationTitle("Home")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        logoutButton
                    }
                }
                .navigationSplitViewColumnWidth(min: 300, ideal: geometry.size.width * 0.35)
            } detail: {
                NavigationStack {
                    if selectedItem == nil {
                        Text(NSLocalizedString("Select_Item", comment: ""))
                            .foregroundColor(.gray)
                    } else {
                        switch selectedItem {
                        case "accounts":
                            AccountsView(
                                databaseManager: databaseManager,
                                mainViewModel: viewModel,
                                selectedItem: $selectedItem
                            ) { character, portrait in
                                viewModel.resetCharacterInfo()
                                viewModel.selectedCharacter = character
                                viewModel.characterPortrait = portrait
                                currentCharacterId = character.CharacterID
                                Task {
                                    await viewModel.refreshAllData()
                                }
                            }
                        case "character_sheet":
                            if let character = viewModel.selectedCharacter {
                                CharacterSheetView(
                                    character: character,
                                    characterPortrait: viewModel.characterPortrait
                                )
                            }
                        case "character_clones":
                            if let character = viewModel.selectedCharacter {
                                CharacterClonesView(character: character)
                            }
                        case "character_skills":
                            if let character = viewModel.selectedCharacter {
                                CharacterSkillsView(
                                    characterId: character.CharacterID,
                                    databaseManager: databaseManager
                                )
                            }
                        case "character_mail":
                            if let character = viewModel.selectedCharacter {
                                CharacterMailView(characterId: character.CharacterID)
                            }
                        case "calendar":
                            Text("Calendar View") // 待实现
                        case "character_wealth":
                            if let character = viewModel.selectedCharacter {
                                CharacterWealthView(characterId: character.CharacterID)
                            }
                        case "character_lp":
                            if let character = viewModel.selectedCharacter {
                                CharacterLoyaltyPointsView(characterId: character.CharacterID)
                            }
                        case "searcher":
                            if let character = viewModel.selectedCharacter {
                                SearcherView(character: character)
                            }
                        case "database":
                            DatabaseBrowserView(
                                databaseManager: databaseManager,
                                level: .categories
                            )
                        case "market":
                            MarketBrowserView(databaseManager: databaseManager)
                        case "vip_market_item":
                            MarketQuickbarView(databaseManager: databaseManager)
                        case "npc":
                            NPCBrowserView(databaseManager: databaseManager)
                        case "wormhole":
                            WormholeView(databaseManager: databaseManager)
                        case "incursions":
                            IncursionsView(databaseManager: databaseManager)
                        case "sovereignty":
                            SovereigntyView(databaseManager: databaseManager)
                        case "language_map":
                            LanguageMapView()
                        case "assets":
                            if let character = viewModel.selectedCharacter {
                                CharacterAssetsView(characterId: character.CharacterID)
                            }
                        case "market_orders":
                            if let character = viewModel.selectedCharacter {
                                CharacterOrdersView(characterId: Int64(character.CharacterID))
                            }
                        case "contracts":
                            if let character = viewModel.selectedCharacter {
                                PersonalContractsView(characterId: character.CharacterID)
                            }
                        case "market_transactions":
                            if let character = viewModel.selectedCharacter {
                                WalletTransactionsView(characterId: character.CharacterID, databaseManager: databaseManager)
                            }
                        case "wallet_journal":
                            if let character = viewModel.selectedCharacter {
                                WalletJournalView(characterId: character.CharacterID)
                            }
                        case "industry_jobs":
                            if let character = viewModel.selectedCharacter {
                                CharacterIndustryView(characterId: character.CharacterID)
                            }
                        case "mining_ledger":
                            if let character = viewModel.selectedCharacter {
                                MiningLedgerView(characterId: character.CharacterID, databaseManager: databaseManager)
                            }
                        case "planetary":
                            if let character = viewModel.selectedCharacter {
                                CharacterPlanetaryView(characterId: character.CharacterID)
                            }
                        case "corporation_wallet":
                            if let character = viewModel.selectedCharacter {
                                CorpWalletView(characterId: character.CharacterID)
                            }
                            
                        case "corporation_moon":
                            if let character = viewModel.selectedCharacter {
                                CorpMoonMiningView(characterId: character.CharacterID)
                            }
                            
                        case "corporation_structures":
                            if let character = viewModel.selectedCharacter {
                                CorpStructureView(characterId: character.CharacterID)
                            }
                        case "killboard":
                            if let character = viewModel.selectedCharacter {
                                // KillMailListView(characterId: character.CharacterID)
                                BRKillMailView(characterId: character.CharacterID)
                            }
                        case "corporation_members":
                            if let character = viewModel.selectedCharacter {
                                CorpMemberListView(characterId: character.CharacterID)
                            }
                        default:
                            Text(NSLocalizedString("Select_Item", comment: ""))
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .preferredColorScheme(currentColorScheme)
        .onAppear {
            // 检查当前选择的角色是否在已登录列表中
            Logger.debug("Check current character: \(currentCharacterId)")
            if currentCharacterId != 0 {
                let auth = EVELogin.shared.getCharacterByID(currentCharacterId)
                if auth == nil {
                    // 如果找不到认证信息，说明角色已退出
                    currentCharacterId = 0
                    viewModel.resetCharacterInfo()
                }
            }
        }
        .onChange(of: selectedTheme) { _, _ in
            // 主题变更时的处理
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("LanguageChanged"))) { _ in
            // 语言变更时的处理
            Task {
                await viewModel.refreshAllData()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CharacterLoggedOut"))) { _ in
            // 收到角色登出通知时执行登出操作
            currentCharacterId = 0
            viewModel.resetCharacterInfo()
            selectedItem = nil
        }
        .task {
            await viewModel.refreshAllData()
        }
    }
    
    // MARK: - 视图组件
    private var loginSection: some View {
        Section {
            NavigationLink(value: "accounts") {
                LoginButtonView(
                    isLoggedIn: currentCharacterId != 0,
                    serverStatus: viewModel.serverStatus,
                    selectedCharacter: viewModel.selectedCharacter,
                    characterPortrait: viewModel.characterPortrait,
                    isRefreshing: viewModel.isRefreshing,
                    mainViewModel: viewModel
                )
            }
            .onDisappear {
                // 从人物管理页面返回时检查
                if currentCharacterId != 0 {
                    let auth = EVELogin.shared.getCharacterByID(currentCharacterId)
                    if auth == nil {
                        // 如果找不到认证信息，说明角色已退出
                        currentCharacterId = 0
                        viewModel.resetCharacterInfo()
                    }
                }
            }
        }
    }
    
    private var characterSection: some View {
        Section {
            NavigationLink(value: "character_sheet") {
                RowView(
                    title: NSLocalizedString("Main_Character_Sheet", comment: ""),
                    icon: "charactersheet",
                    note: viewModel.characterStats.skillPoints
                )
            }
            
            NavigationLink(value: "character_clones") {
                RowView(
                    title: NSLocalizedString("Main_Jump_Clones", comment: ""),
                    icon: "jumpclones",
                    note: viewModel.cloneJumpStatus
                )
            }
            
            NavigationLink(value: "character_skills") {
                RowView(
                    title: NSLocalizedString("Main_Skills", comment: ""),
                    icon: "skills",
                    note: viewModel.characterStats.queueStatus
                )
            }
            
            NavigationLink(value: "character_mail") {
                RowView(
                    title: NSLocalizedString("Main_EVE_Mail", comment: ""),
                    icon: "evemail"
                )
            }
            
            NavigationLink(value: "calendar") {
                RowView(
                    title: NSLocalizedString("Main_Calendar", comment: ""),
                    icon: "calendar"
                )
            }
            .isHidden(true)
            
            NavigationLink(value: "character_wealth") {
                RowView(
                    title: NSLocalizedString("Main_Wealth", comment: ""),
                    icon: "Folder",
                    note: viewModel.characterStats.walletBalance
                )
            }
            
            NavigationLink(value: "character_lp") {
                RowView(
                    title: NSLocalizedString("Main_Loyalty_Points", comment: ""),
                    icon: "lpstore"
                )
            }
            
            NavigationLink(value: "searcher") {
                RowView(
                    title: NSLocalizedString("Main_Search", comment: ""),
                    icon: "peopleandplaces"
                )
            }
        } header: {
            Text(NSLocalizedString("Main_Character", comment: ""))
                .fontWeight(.bold)
                .font(.system(size: 18))
                .foregroundColor(.primary)
                .textCase(nil)
        }
    }
    
    private var corporationSection: some View {
        Section {
            NavigationLink(value: "corporation_wallet") {
                RowView(
                    title: NSLocalizedString("Main_Corporation_wallet", comment: ""),
                    icon: "wallet"
                )
            }

            NavigationLink(value: "corporation_members") {
                RowView(
                    title: NSLocalizedString("Main_Corporation_Members", comment: ""),
                    icon: "corporation"
                )
            }

            NavigationLink(value: "corporation_moon") {
                RowView(
                    title: NSLocalizedString("Main_Corporation_Moon_Mining", comment: ""),
                    icon: "satellite"
                )
            }

            NavigationLink(value: "corporation_structures") {
                RowView(
                    title: NSLocalizedString("Main_Corporation_Structures", comment: ""),
                    icon: "Structurebrowser"
                )
            }

            // NavigationLink(value: "corporation_members") {
            //     RowView(
            //         title: NSLocalizedString("Main_Corporation_Members", comment: ""),
            //         icon: "corporation"
            //     )
            // }
            
            // NavigationLink(value: "corporation_contracts") {
            //     RowView(
            //         title: NSLocalizedString("Main_Corporation_Contracts", comment: ""),
            //         icon: "contracts"
            //     )
            // }
            
            // NavigationLink(value: "corporation_market_orders") {
            //     RowView(
            //         title: NSLocalizedString("Main_Corporation_Market_Orders", comment: ""),
            //         icon: "marketdeliveries"
            //     )
            // }
            
            // NavigationLink(value: "corporation_industry") {
            //     RowView(
            //         title: NSLocalizedString("Main_Corporation_Industry", comment: ""),
            //         icon: "industry"
            //     )
            // }
        } header: {
            Text(NSLocalizedString("Main_Corporation", comment: ""))
                .fontWeight(.bold)
                .font(.system(size: 18))
                .foregroundColor(.primary)
                .textCase(nil)
        }
    }
    
    private var databaseSection: some View {
        Section {
            NavigationLink(value: "database") {
                RowView(
                    title: NSLocalizedString("Main_Database", comment: ""),
                    icon: "items"
                )
            }
            
            NavigationLink(value: "market") {
                RowView(
                    title: NSLocalizedString("Main_Market", comment: ""),
                    icon: "market"
                )
            }
            
            NavigationLink(value: "vip_market_item") {
                RowView(
                    title: NSLocalizedString("Main_Market_Watch_List", comment: ""),
                    icon: "searchmarket"
                )
            }
            
            NavigationLink(value: "npc") {
                RowView(
                    title: "NPC",
                    icon: "criminal"
                )
            }
            
            NavigationLink(value: "wormhole") {
                RowView(
                    title: NSLocalizedString("Main_WH", comment: ""),
                    icon: "terminate"
                )
            }
            
            NavigationLink(value: "incursions") {
                RowView(
                    title: NSLocalizedString("Main_Incursions", comment: ""),
                    icon: "incursions"
                )
            }
            
            NavigationLink(value: "sovereignty") {
                RowView(
                    title: NSLocalizedString("Main_Sovereignty", comment: ""),
                    icon: "sovereignty"
                )
            }
            
            NavigationLink(value: "language_map") {
                RowView(
                    title: NSLocalizedString("Main_Language_Map", comment: ""),
                    icon: "browser"
                )
            }
        } header: {
            Text(NSLocalizedString("Main_Databases", comment: ""))
                .fontWeight(.bold)
                .font(.system(size: 18))
                .foregroundColor(.primary)
                .textCase(nil)
        }
    }
    
    private var businessSection: some View {
        Section {
            NavigationLink(value: "assets") {
                RowView(
                    title: NSLocalizedString("Main_Assets", comment: ""),
                    icon: "assets"
                )
            }
            
            NavigationLink(value: "market_orders") {
                RowView(
                    title: NSLocalizedString("Main_Market_Orders", comment: ""),
                    icon: "marketdeliveries"
                )
            }
            
            NavigationLink(value: "contracts") {
                RowView(
                    title: NSLocalizedString("Main_Contracts", comment: ""),
                    icon: "contracts"
                )
            }
            
            NavigationLink(value: "market_transactions") {
                RowView(
                    title: NSLocalizedString("Main_Market_Transactions", comment: ""),
                    icon: "journal"
                )
            }
            
            NavigationLink(value: "wallet_journal") {
                RowView(
                    title: NSLocalizedString("Main_Wallet_Journal", comment: ""),
                    icon: "wallet"
                )
            }
            
            NavigationLink(value: "industry_jobs") {
                RowView(
                    title: NSLocalizedString("Main_Industry_Jobs", comment: ""),
                    icon: "industry"
                )
            }
            
            NavigationLink(value: "mining_ledger") {
                RowView(
                    title: NSLocalizedString("Main_Mining_Ledger", comment: ""),
                    icon: "miningledger"
                )
            }
            
            NavigationLink(value: "planetary") {
                RowView(
                    title: NSLocalizedString("Main_Planetary", comment: ""),
                    icon: "planets"
                )
            }
        } header: {
            Text(NSLocalizedString("Main_Business", comment: ""))
                .fontWeight(.bold)
                .font(.system(size: 18))
                .foregroundColor(.primary)
                .textCase(nil)
        }
    }
    
    private var KillBoardSection: some View {
        Section {
            NavigationLink(value: "killboard") {
                RowView(
                    title: NSLocalizedString("Main_Killboard", comment: ""),
                    icon: "killreport",
                    note: NSLocalizedString("KillMail_Data_Source", comment: "")
                )
            }
        } header: {
            Text(NSLocalizedString("Main_Battle", comment: ""))
                .fontWeight(.bold)
                .font(.system(size: 18))
                .foregroundColor(.primary)
                .textCase(nil)
        }
    }
    
    private var otherSection: some View {
        Section {
            NavigationLink {
                SettingView(databaseManager: databaseManager)
            } label: {
                RowView(
                    title: NSLocalizedString("Main_Setting", comment: ""),
                    icon: "Settings"
                )
            }
            
            NavigationLink {
                AboutView()
            } label: {
                RowView(
                    title: NSLocalizedString("Main_About", comment: ""),
                    icon: "info"
                )
            }
        } header: {
            Text(NSLocalizedString("Main_Other", comment: ""))
                .fontWeight(.bold)
                .font(.system(size: 18))
                .foregroundColor(.primary)
                .textCase(nil)
        }
    }
    
    private var logoutButton: some View {
        Button {
            if currentCharacterId != 0 {
                currentCharacterId = 0
                viewModel.resetCharacterInfo()
            }
        } label: {
            if currentCharacterId != 0 {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .resizable()
                    .frame(width: 28, height: 24)
                    .foregroundColor(.red)
            } else {
                EmptyView()
            }
        }
    }
    
    // MARK: - 通用组件
    struct RowView: View {
        let title: String
        let icon: String
        var note: String?
        var isVisible: Bool = true
        
        var body: some View {
            HStack {
                Image(icon)
                    .resizable()
                    .frame(width: 36, height: 36)
                    .cornerRadius(6)
                    .drawingGroup()
                
                VStack(alignment: .leading) {
                    Text(title)
                        .fixedSize(horizontal: false, vertical: true)
                    if let note = note, !note.isEmpty {
                        Text(note)
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
        }
    }
}

extension View {
    @ViewBuilder
    func isHidden(_ hidden: Bool) -> some View {
        if !hidden {
            self
        }
    }
}
