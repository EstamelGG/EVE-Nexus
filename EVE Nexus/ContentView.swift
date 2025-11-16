import Foundation
import SafariServices
import SwiftUI
import WebKit

// MARK: - PreferenceKey for frame tracking

struct AppendPreferenceKey<Value, ID>: PreferenceKey {
    static var defaultValue: [Value] { [] }
    static func reduce(value: inout [Value], nextValue: () -> [Value]) {
        value.append(contentsOf: nextValue())
    }
}

// MARK: - View extensions for frame tracking

extension View {
    func framePreference<ID>(in coordinateSpace: CoordinateSpace, _: ID.Type = ID.self)
        -> some View
    {
        background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: AppendPreferenceKey<CGRect, ID>.self,
                    value: [geometry.frame(in: coordinateSpace)]
                )
            })
    }

    func onFrameChange<ID>(_: ID.Type = ID.self, perform action: @escaping ([CGRect]) -> Void)
        -> some View
    {
        onPreferenceChange(AppendPreferenceKey<CGRect, ID>.self, perform: action)
    }
}

// 优化数据模型为值类型
struct TableRowNode: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let iconName: String
    let note: String?
    let destination: AnyView?

    static func == (lhs: TableRowNode, rhs: TableRowNode) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.iconName == rhs.iconName
            && lhs.note == rhs.note
    }
}

struct TableNode: Identifiable, Equatable {
    let id = UUID()
    let title: String
    var rows: [TableRowNode]

    static func == (lhs: TableNode, rhs: TableNode) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.rows == rhs.rows
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

        // 设置状态更新计时器（这会自动触发第一次刷新）
        resetStatusTimer()
    }

    private func getHourAndMinute(from date: Date) -> (hour: Int, minute: Int) {
        let calendar = Calendar.current
        let utc = TimeZone(identifier: "UTC")!
        let components = calendar.dateComponents(in: utc, from: date)
        return (components.hour ?? 0, components.minute ?? 0)
    }

    private func shouldImmediatelyRefresh(
        oldTime: (hour: Int, minute: Int), newTime: (hour: Int, minute: Int)
    ) -> Bool {
        // 11:00 AM UTC
        if newTime.hour == 11 && newTime.minute == 0 && (oldTime.hour != 11 || oldTime.minute != 0) {
            return true
        }
        return false
    }

    private func resetStatusTimer() {
        statusTimer?.invalidate()
        statusTimer = Timer.scheduledTimer(withTimeInterval: nextUpdateInterval, repeats: true) {
            [weak self] _ in
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

    private func refreshServerStatus(forceRefresh: Bool = false) async {
        do {
            let newStatus = try await ServerStatusAPI.shared.fetchServerStatus(
                forceRefresh: forceRefresh)
            await MainActor.run {
                self.status = newStatus

                // 如果在11:00-11:30之间且服务器已上线，重置计时器使用新的间隔
                let (hour, minute) = utcHourAndMinute
                if hour == 11, minute < 30, newStatus.isOnline {
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
                return Text(NSLocalizedString("Server_Status_Online", comment: ""))
                    .font(.caption.bold())
                    .foregroundColor(.green)
                    + Text(
                        String(
                            format: NSLocalizedString("Server_Status_Players", comment: ""),
                            formattedPlayers
                        )
                    )
                    .font(.caption)
            } else {
                return Text(NSLocalizedString("Server_Status_Offline", comment: ""))
                    .font(.caption.bold())
                    .foregroundColor(.red)
            }
        } else {
            return Text(NSLocalizedString("Server_Status_Checking", comment: ""))
                .font(.caption)
        }
    }
}

// MARK: - Refresh Token 更新时间视图

struct RefreshTokenUpdateTimeView: View {
    let characterId: Int
    @State private var lastUpdateTime: Date?

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.locale = Locale.current
        return formatter
    }

    var body: some View {
        HStack(spacing: 4) {
            Text("Refresh Token:")
                .font(.caption)
                .foregroundColor(.secondary)
            if let updateTime = lastUpdateTime {
                Text(dateFormatter.string(from: updateTime))
                    .font(.monospacedDigit(.caption)())
                    .foregroundColor(.secondary)
            } else {
                Text("Null")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            Task {
                lastUpdateTime = await AuthTokenManager.shared.getLastRefreshTokenUpdateTime(for: characterId)
            }
        }
    }
}

// MARK: - 自定义按钮样式

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - 导航栏头像组件

struct NavigationBarAvatarView: View {
    let characterPortrait: UIImage?
    let isRefreshTokenExpired: Bool
    let isRefreshing: Bool

    var body: some View {
        ZStack {
            if let portrait = characterPortrait {
                Image(uiImage: portrait)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())

                if isRefreshing {
                    Circle()
                        .fill(Color.black.opacity(0.6))
                        .frame(width: 32, height: 32)

                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(.white)
                } else if isRefreshTokenExpired {
                    // Token过期覆盖层（缩小版）
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.4))
                            .frame(width: 32, height: 32)

                        ZStack {
                            Image(systemName: "triangle")
                                .font(.system(size: 16))
                                .foregroundColor(.red)

                            Image(systemName: "exclamationmark")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundColor(.red)
                        }
                    }
                }
            } else {
                Image("default_char")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
            }
        }
        .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 1.5))
        .background(Circle().fill(Color.primary.opacity(0.05)))
        .shadow(color: Color.primary.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

// 修改LoginButtonView组件
struct LoginButtonView: View {
    let isLoggedIn: Bool
    let serverStatus: ServerStatus?
    let selectedCharacter: EVECharacterInfo?
    let characterPortrait: UIImage?
    let isRefreshing: Bool
    @State private var isRefreshTokenExpired = false
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
                    } else if isRefreshTokenExpired {
                        // 使用TokenExpiredOverlay组件
                        TokenExpiredOverlay()
                    }
                }
                .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 3))
                .background(Circle().fill(Color.primary.opacity(0.05)))
                .shadow(color: Color.primary.opacity(0.2), radius: 8, x: 0, y: 4)
                .padding(4)
            } else {
                ZStack {
                    Image("default_char")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 64, height: 64)
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

                    // 显示军团信息
                    HStack(spacing: 4) {
                        if let corporation = mainViewModel.corporationInfo,
                           let logo = mainViewModel.corporationLogo
                        {
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

                    // 显示联盟信息
                    HStack(spacing: 4) {
                        if let alliance = mainViewModel.allianceInfo,
                           let logo = mainViewModel.allianceLogo
                        {
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

                    // 显示势力信息
                    if let faction = mainViewModel.factionInfo,
                       let logo = mainViewModel.factionLogo
                    {
                        HStack(spacing: 4) {
                            Image(uiImage: logo)
                                .resizable()
                                .frame(width: 16, height: 16)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            Text(faction.name)
                                .font(.caption)
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
                    Logger.info("检查Token状态...")
                    isRefreshTokenExpired = auth.character.refreshTokenExpired
                    if isRefreshTokenExpired {
                        Logger.warning(
                            "角色 \(character.CharacterName) (\(character.CharacterID)) 的 Refresh Token 已过期，需要重新登录"
                        )
                    } else {
                        Logger.info(
                            "角色 \(character.CharacterName) (\(character.CharacterID)) 的 Refresh Token 状态正常"
                        )
                    }
                } else {
                    Logger.error(
                        "找不到角色 \(character.CharacterName) (\(character.CharacterID)) 的认证信息")
                    // 如果找不到认证信息，通知 ContentView 执行登出操作
                    NotificationCenter.default.post(
                        name: NSNotification.Name("CharacterLoggedOut"), object: nil
                    )
                }
            }
        }
    }
}

struct ContentView: View {
    private enum HeaderFrame {}

    @StateObject private var viewModel = MainViewModel()
    @ObservedObject var databaseManager: DatabaseManager
    @AppStorage("currentCharacterId") private var currentCharacterId: Int = 0
    @AppStorage("selectedTheme") private var selectedTheme: String = "system"
    @AppStorage("showCorporationAffairs") private var showCorporationAffairs: Bool = false
    @AppStorage("lastVersion") private var lastVersion: String = ""
    @AppStorage("enableLogging") private var enableLogging: Bool = false

    // 功能自定义相关状态
    @AppStorage("hiddenFeatures") private var hiddenFeaturesData: Data = .init()
    @State private var isCustomizeMode: Bool = false
    @State private var hiddenFeatures: Set<String> = []
    @Environment(\.colorScheme) var systemColorScheme
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var selectedItem: String? = nil
    @State private var showUpdateAlert = false
    @State private var shouldNavigateToUpdateLog = false
    @State private var isRefreshTokenExpired = false // 添加token过期状态
    @State private var navigationAvatarItemVisible = false // 改为使用滚动位置判断
    @State private var hasInitialLayout = false // 添加初始布局标记
    @StateObject private var sdeUpdateChecker = SDEUpdateChecker.shared // 观察SDE更新状态
    @State private var showingSDEUpdateSheet = false // 控制SDE更新sheet显示

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
                ScrollViewReader { _ in
                    List(selection: $selectedItem) {
                        // 登录部分
                        loginSection
                            .framePreference(in: .global, HeaderFrame.self)

                        // 角色功能部分
                        if currentCharacterId != 0 || isCustomizeMode {
                            characterSection

                            // 军团部分（仅在开启设置且已登录时显示）
                            if showCorporationAffairs || isCustomizeMode {
                                corporationSection
                            }
                        }

                        // 数据库部分(始终显示)
                        databaseSection

                        // 商业部分(登录后显示)
                        businessSection

                        // 战斗部分(登录后显示)
                        if currentCharacterId != 0 || isCustomizeMode {
                            KillBoardSection
                        }
                        // 装配部分(无需登录)
                        FittingSection
                        // 其他设置(始终显示)
                        otherSection
                    }
                    .listStyle(.insetGrouped)
                    .refreshable {
                        Logger.info("强制刷新基本数据")
                        await viewModel.refreshAllBasicData(forceRefresh: true)
                    }
                }
                .navigationTitle(NSLocalizedString("Main_Home", comment: ""))
                .task {
                    Logger.info("Sidebar appeared, refreshing data...")
                    await viewModel.refreshAllBasicData()
                    updateTokenStatus()
                }
                .toolbar {
                    toolbarContent
                }
                .navigationSplitViewColumnWidth(min: 300, ideal: geometry.size.width * 0.35)
                .onFrameChange(HeaderFrame.self) { frames in
                    // 确保初始布局完成后再开始检测滚动
                    if !hasInitialLayout {
                        hasInitialLayout = true
                        return
                    }

                    // 只有在初始布局完成后才更新头像可见性
                    let shouldShow = (frames.first?.minY ?? -100) < -35

                    // 使用动画来平滑切换状态
                    withAnimation(.easeInOut(duration: 0.25)) {
                        navigationAvatarItemVisible = shouldShow
                    }
                }
            } detail: {
                NavigationStack {
                    if selectedItem == nil {
                        Text(NSLocalizedString("Select_Item", comment: ""))
                            .foregroundColor(.gray)
                    } else {
                        // 记录用户访问的功能
                        let _ = logSelectedItem(selectedItem)

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
                                // 清除旧的技能数据，确保加载新角色的技能
                                Task {
                                    SharedSkillsManager.shared.clearSkillData()
                                    await viewModel.refreshAllBasicData()
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
                            if let character = viewModel.selectedCharacter {
                                CharacterCalendarView(
                                    characterId: character.CharacterID,
                                    databaseManager: databaseManager
                                )
                            }
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
                        case "attribute_compare":
                            AttributeCompareView(databaseManager: databaseManager)
                        case "npc":
                            NPCBrowserView(databaseManager: databaseManager)
                        case "npc_faction":
                            FactionBrowserView(
                                databaseManager: databaseManager,
                                characterId: currentCharacterId == 0 ? nil : currentCharacterId
                            )
                        case "agents":
                            AgentSearchView(databaseManager: databaseManager)
                        case "wormhole":
                            WormholeView(databaseManager: databaseManager)
                        case "incursions":
                            IncursionsView(databaseManager: databaseManager)
                        case "faction_war":
                            FactionWarView(databaseManager: databaseManager)
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
                                PersonalContractsView(character: character)
                            }
                        case "market_transactions":
                            if let character = viewModel.selectedCharacter {
                                WalletTransactionsView(
                                    characterId: character.CharacterID,
                                    databaseManager: databaseManager
                                )
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
                                MiningLedgerView(
                                    characterId: character.CharacterID,
                                    databaseManager: databaseManager
                                )
                            }
                        case "planetary":
                            if let character = viewModel.selectedCharacter {
                                CharacterPlanetaryView(characterId: character.CharacterID)
                            } else {
                                CharacterPlanetaryView(characterId: nil)
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
                        case "corporation_industry":
                            if let character = viewModel.selectedCharacter {
                                CorpIndustryView(characterId: character.CharacterID)
                            }
                        case "jump_navigation":
                            JumpNavigationView(databaseManager: databaseManager)
                        case "calculator":
                            CalculatorView()
                        case "star_map":
                            StarMapView(databaseManager: databaseManager)
                        case "fitting":
                            FittingMainView(
                                characterId: viewModel.selectedCharacter?.CharacterID,
                                databaseManager: databaseManager
                            )
                        case "settings":
                            SettingView(databaseManager: databaseManager)
                        case "about":
                            AboutView()
                        case "update_history":
                            UpdateLogListView()
                        default:
                            Text(NSLocalizedString("Select_Item", comment: ""))
                                .foregroundColor(.gray)
                        }
                    }
                }
                .onChange(of: shouldNavigateToUpdateLog) { _, newValue in
                    if newValue {
                        selectedItem = "update_history"
                        shouldNavigateToUpdateLog = false
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
                    // 清除技能数据
                    Task {
                        SharedSkillsManager.shared.clearSkillData()
                    }
                }
            }

            // 加载隐藏功能列表
            loadHiddenFeatures()

            // 检查应用版本更新
            checkAppVersionUpdate()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSNotification.Name("LanguageChanged"))
        ) { _ in
            // 语言变更时的处理
            Task {
                Logger.info("语言变更，刷新数据")
                await viewModel.refreshAllBasicData()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSNotification.Name("CharacterLoggedOut"))
        ) { _ in
            // 收到角色登出通知时执行登出操作
            currentCharacterId = 0
            viewModel.resetCharacterInfo()
            selectedItem = nil
            // 清除技能数据
            Task {
                SharedSkillsManager.shared.clearSkillData()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
        ) { _ in
            // App 从后台返回前台时刷新数据
            Logger.info("App entering foreground, refreshing data...")
            Task {
                await viewModel.refreshAllBasicData()
                updateTokenStatus()
            }
        }
        .onChange(of: viewModel.selectedCharacter) { _, _ in
            // 当选中的角色变化时，更新token状态
            updateTokenStatus()
        }
        .alert(
            NSLocalizedString("App_Updated_Title", comment: "App已更新"), isPresented: $showUpdateAlert
        ) {
            Button(NSLocalizedString("App_Updated_OK", comment: "好的"), role: .cancel) {
                // 只关闭弹窗
            }
            Button(NSLocalizedString("App_Updated_View_Changes", comment: "查看更新")) {
                shouldNavigateToUpdateLog = true
            }
        } message: {
            Text(NSLocalizedString("App_Updated_Message", comment: "应用已更新到新版本"))
        }
        .sheet(isPresented: $showingSDEUpdateSheet, onDismiss: {
            // 更新完成后重新检查更新状态
            Task { @MainActor in
                await SDEUpdateChecker.shared.checkForUpdates()
            }
        }) {
            SDEUpdateDetailView()
                .interactiveDismissDisabled()
        }
    }

    // MARK: - 辅助函数

    private func logSelectedItem(_ item: String?) {
        guard let item = item else { return }
        Logger.info("=== 用户访问功能: \(item) ===")
    }

    private func updateTokenStatus() {
        if let character = viewModel.selectedCharacter {
            if let auth = EVELogin.shared.getCharacterByID(character.CharacterID) {
                isRefreshTokenExpired = auth.character.refreshTokenExpired
            } else {
                isRefreshTokenExpired = false
            }
        } else {
            isRefreshTokenExpired = false
        }
    }

    // 功能自定义相关辅助函数
    private func loadHiddenFeatures() {
        do {
            if !hiddenFeaturesData.isEmpty {
                hiddenFeatures = try JSONDecoder().decode(
                    Set<String>.self, from: hiddenFeaturesData
                )
            }
        } catch {
            Logger.error("加载隐藏功能列表失败: \(error)")
            hiddenFeatures = []
        }
    }

    private func saveHiddenFeatures() {
        do {
            hiddenFeaturesData = try JSONEncoder().encode(hiddenFeatures)
        } catch {
            Logger.error("保存隐藏功能列表失败: \(error)")
        }
    }

    private func isFeatureHidden(_ featureId: String) -> Bool {
        return hiddenFeatures.contains(featureId)
    }

    private func toggleFeatureVisibility(_ featureId: String) {
        if hiddenFeatures.contains(featureId) {
            hiddenFeatures.remove(featureId)
        } else {
            hiddenFeatures.insert(featureId)
        }
        saveHiddenFeatures()
    }

    // 检查section是否有可见的功能
    private func hasVisibleFeatures(in features: [String]) -> Bool {
        if isCustomizeMode {
            return true // 自定义模式下总是显示section
        }

        // 检查是否有任何功能未被隐藏且满足登录要求
        return features.contains { featureId in
            let participatesInHiding = shouldParticipateInHiding(featureId)
            let isHidden = participatesInHiding && isFeatureHidden(featureId)
            return !isHidden && isFeatureAvailableForCurrentUser(featureId)
        }
    }

    // 功能配置结构
    struct FeatureConfig {
        let id: String
        let requiresLogin: Bool
        let section: String
    }

    // 所有功能的配置
    private let featureConfigs: [FeatureConfig] = [
        // 角色功能
        FeatureConfig(id: "character_sheet", requiresLogin: true, section: "character"),
        FeatureConfig(id: "character_clones", requiresLogin: true, section: "character"),
        FeatureConfig(id: "character_skills", requiresLogin: true, section: "character"),
        FeatureConfig(id: "character_mail", requiresLogin: true, section: "character"),
        FeatureConfig(id: "calendar", requiresLogin: true, section: "character"),
        FeatureConfig(id: "character_wealth", requiresLogin: true, section: "character"),
        FeatureConfig(id: "character_lp", requiresLogin: true, section: "character"),
        FeatureConfig(id: "searcher", requiresLogin: true, section: "character"),

        // 军团功能
        FeatureConfig(id: "corporation_wallet", requiresLogin: true, section: "corporation"),
        FeatureConfig(id: "corporation_members", requiresLogin: true, section: "corporation"),
        FeatureConfig(id: "corporation_moon", requiresLogin: true, section: "corporation"),
        FeatureConfig(id: "corporation_structures", requiresLogin: true, section: "corporation"),
        FeatureConfig(id: "corporation_industry", requiresLogin: true, section: "corporation"),

        // 数据库功能
        FeatureConfig(id: "database", requiresLogin: false, section: "database"),
        FeatureConfig(id: "market", requiresLogin: false, section: "database"),
        FeatureConfig(id: "vip_market_item", requiresLogin: false, section: "database"),
        FeatureConfig(id: "attribute_compare", requiresLogin: false, section: "database"),
        FeatureConfig(id: "npc", requiresLogin: false, section: "database"),
        FeatureConfig(id: "npc_faction", requiresLogin: false, section: "database"),
        FeatureConfig(id: "agents", requiresLogin: false, section: "database"),
        FeatureConfig(id: "star_map", requiresLogin: false, section: "database"),
        FeatureConfig(id: "wormhole", requiresLogin: false, section: "database"),
        FeatureConfig(id: "incursions", requiresLogin: false, section: "database"),
        FeatureConfig(id: "faction_war", requiresLogin: false, section: "database"),
        FeatureConfig(id: "sovereignty", requiresLogin: false, section: "database"),
        FeatureConfig(id: "language_map", requiresLogin: false, section: "database"),
        FeatureConfig(id: "jump_navigation", requiresLogin: false, section: "database"),
        FeatureConfig(id: "calculator", requiresLogin: false, section: "database"),

        // 商业功能
        FeatureConfig(id: "assets", requiresLogin: true, section: "business"),
        FeatureConfig(id: "market_orders", requiresLogin: true, section: "business"),
        FeatureConfig(id: "contracts", requiresLogin: true, section: "business"),
        FeatureConfig(id: "market_transactions", requiresLogin: true, section: "business"),
        FeatureConfig(id: "wallet_journal", requiresLogin: true, section: "business"),
        FeatureConfig(id: "industry_jobs", requiresLogin: true, section: "business"),
        FeatureConfig(id: "mining_ledger", requiresLogin: true, section: "business"),
        FeatureConfig(id: "planetary", requiresLogin: false, section: "business"),

        // 战斗功能
        FeatureConfig(id: "killboard", requiresLogin: true, section: "battle"),

        // 装配功能
        FeatureConfig(id: "fitting", requiresLogin: false, section: "fitting"),

        // 其他功能
        FeatureConfig(id: "settings", requiresLogin: false, section: "other"),
        FeatureConfig(id: "update_history", requiresLogin: false, section: "other"),
        FeatureConfig(id: "about", requiresLogin: false, section: "other"),
    ]

    // 获取指定section的所有功能ID
    private func getFeatureIds(for section: String) -> [String] {
        return
            featureConfigs
                .filter { $0.section == section }
                .map { $0.id }
    }

    // 检查功能是否对当前用户可用
    private func isFeatureAvailableForCurrentUser(_ featureId: String) -> Bool {
        guard let config = featureConfigs.first(where: { $0.id == featureId }) else {
            return true // 如果找不到配置，默认可用
        }

        if config.requiresLogin {
            return currentCharacterId != 0
        }

        return true
    }

    // 检查功能是否应该参与隐藏机制（other section中的功能不参与隐藏）
    private func shouldParticipateInHiding(_ featureId: String) -> Bool {
        guard let config = featureConfigs.first(where: { $0.id == featureId }) else {
            return true
        }

        // other section中的功能不参与隐藏
        return config.section != "other"
    }

    // 检查功能是否应该在编辑模式下显示选择圆圈（other section中的功能不显示选择圆圈）
    private func shouldShowSelectionCircle(_ featureId: String) -> Bool {
        guard let config = featureConfigs.first(where: { $0.id == featureId }) else {
            return true
        }

        // other section中的功能不显示选择圆圈
        return config.section != "other"
    }

    // 创建可自定义的NavigationLink（带有默认的listRowInsets）
    @ViewBuilder
    private func customizableNavigationLink(
        value: String,
        title: String,
        icon: String,
        note: String? = nil,
        noteView: AnyView? = nil
    ) -> some View {
        let participatesInHiding = shouldParticipateInHiding(value)
        let isHidden = participatesInHiding && isFeatureHidden(value)
        let showSelectionCircle = shouldShowSelectionCircle(value)

        let contentView = HStack {
            Image(icon)
                .resizable()
                .frame(width: 36, height: 36)
                .cornerRadius(6)
                .drawingGroup()
                .opacity(isCustomizeMode && isHidden ? 0.4 : 1.0)

            VStack(alignment: .leading) {
                Text(title)
                    .fixedSize(horizontal: false, vertical: true)
                if let noteView = noteView {
                    noteView
                } else if let note = note, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(1)
                }
            }
            Spacer()

            // 在自定义模式下显示选择圆环（仅对显示选择圆圈的功能显示）
            if isCustomizeMode && showSelectionCircle {
                Image(systemName: !isFeatureHidden(value) ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(!isFeatureHidden(value) ? .blue : .gray)
            }
        }

        if isCustomizeMode {
            // 编辑模式下，所有功能都变成不可点击的状态
            contentView
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                .contentShape(Rectangle())
                .onTapGesture {
                    // 只有参与隐藏且显示选择圆圈的功能才能响应点击
                    if participatesInHiding && showSelectionCircle {
                        toggleFeatureVisibility(value)
                    }
                }
        } else {
            NavigationLink(value: value) {
                contentView
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            .isHidden(isHidden)
        }
    }

    private func checkAppVersionUpdate() {
        let currentVersion = AppConfiguration.Version.fullVersion

        // 如果lastVersion为空，说明是首次安装，记录版本号但不显示更新提示
        if lastVersion.isEmpty {
            lastVersion = currentVersion
            Logger.info("首次安装应用，记录当前版本: \(currentVersion)")
        }
        // 如果版本不同，显示更新提示
        else if lastVersion != currentVersion {
            Logger.info("检测到应用版本更新: \(lastVersion) -> \(currentVersion)")
            showUpdateAlert = true
            // 立即更新存储的版本号，确保提示只显示一次
            lastVersion = currentVersion
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
            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
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
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                ServerStatusView(mainViewModel: viewModel)

                // 在调试模式下显示 refresh token 更新时间
                if enableLogging && currentCharacterId != 0 {
                    RefreshTokenUpdateTimeView(characterId: currentCharacterId)
                }
            }
        }
    }

    private var characterSection: some View {
        Section {
            customizableNavigationLink(
                value: "character_sheet",
                title: NSLocalizedString("Main_Character_Sheet", comment: ""),
                icon: "charactersheet",
                note: viewModel.characterStats.skillPoints
            )
            .isHidden(currentCharacterId == 0 && !isCustomizeMode)

            customizableNavigationLink(
                value: "character_clones",
                title: NSLocalizedString("Main_Jump_Clones", comment: ""),
                icon: "jumpclones",
                noteView: AnyView(CloneCountdownView(targetDate: viewModel.cloneCooldownEndDate))
            )
            .isHidden(currentCharacterId == 0 && !isCustomizeMode)

            customizableNavigationLink(
                value: "character_skills",
                title: NSLocalizedString("Main_Skills", comment: ""),
                icon: "skills",
                noteView: AnyView(
                    SkillQueueCountdownView(
                        queueEndDate: viewModel.skillQueueEndDate,
                        skillCount: viewModel.skillQueueCount
                    ))
            )
            .isHidden(currentCharacterId == 0 && !isCustomizeMode)

            customizableNavigationLink(
                value: "character_mail",
                title: NSLocalizedString("Main_EVE_Mail", comment: ""),
                icon: "evemail"
            )
            .isHidden(currentCharacterId == 0 && !isCustomizeMode)

            customizableNavigationLink(
                value: "calendar",
                title: NSLocalizedString("Main_Calendar", comment: ""),
                icon: "calendar"
            )
            .isHidden(currentCharacterId == 0 && !isCustomizeMode)

            customizableNavigationLink(
                value: "character_wealth",
                title: NSLocalizedString("Main_Wealth", comment: ""),
                icon: "Folder",
                note: viewModel.characterStats.walletBalance
            )
            .isHidden(currentCharacterId == 0 && !isCustomizeMode)

            customizableNavigationLink(
                value: "character_lp",
                title: NSLocalizedString("Main_Loyalty_Points", comment: ""),
                icon: "lpstore"
            )
            .isHidden(currentCharacterId == 0 && !isCustomizeMode)

            customizableNavigationLink(
                value: "searcher",
                title: NSLocalizedString("Main_Contact_Search", comment: ""),
                icon: "peopleandplaces"
            )
            .isHidden(currentCharacterId == 0 && !isCustomizeMode)
        } header: {
            Text(NSLocalizedString("Main_Character", comment: ""))
                .fontWeight(.semibold)
                .font(.system(size: 18))
                .foregroundColor(.primary)
                .textCase(nil)
        }
        .isHidden(!hasVisibleFeatures(in: getFeatureIds(for: "character")))
    }

    private var corporationSection: some View {
        Section {
            customizableNavigationLink(
                value: "corporation_wallet",
                title: NSLocalizedString("Main_Corporation_wallet", comment: ""),
                icon: "wallet"
            )
            .isHidden(currentCharacterId == 0 && !isCustomizeMode)

            customizableNavigationLink(
                value: "corporation_members",
                title: NSLocalizedString("Main_Corporation_Members", comment: ""),
                icon: "corporation"
            )
            .isHidden(currentCharacterId == 0 && !isCustomizeMode)

            customizableNavigationLink(
                value: "corporation_moon",
                title: NSLocalizedString("Main_Corporation_Moon_Mining", comment: ""),
                icon: "satellite"
            )
            .isHidden(currentCharacterId == 0 && !isCustomizeMode)

            customizableNavigationLink(
                value: "corporation_structures",
                title: NSLocalizedString("Main_Corporation_Structures", comment: ""),
                icon: "Structurebrowser"
            )
            .isHidden(currentCharacterId == 0 && !isCustomizeMode)

            customizableNavigationLink(
                value: "corporation_industry",
                title: NSLocalizedString("Main_Corporation_Industry", comment: ""),
                icon: "industry"
            )
            .isHidden(currentCharacterId == 0 && !isCustomizeMode)
        } header: {
            Text(NSLocalizedString("Main_Corporation", comment: ""))
                .fontWeight(.semibold)
                .font(.system(size: 18))
                .foregroundColor(.primary)
                .textCase(nil)
        }
        .isHidden(!hasVisibleFeatures(in: getFeatureIds(for: "corporation")))
    }

    private var databaseSection: some View {
        Section {
            customizableNavigationLink(
                value: "database",
                title: NSLocalizedString("Main_Database", comment: ""),
                icon: "items"
            )

            customizableNavigationLink(
                value: "market",
                title: NSLocalizedString("Main_Market", comment: ""),
                icon: "market"
            )

            customizableNavigationLink(
                value: "vip_market_item",
                title: NSLocalizedString("Main_Market_Watch_List", comment: ""),
                icon: "searchmarket"
            )

            customizableNavigationLink(
                value: "attribute_compare",
                title: NSLocalizedString("Main_Attribute_Compare", comment: "属性对比器"),
                icon: "comparetool"
            )

            customizableNavigationLink(
                value: "npc",
                title: NSLocalizedString("Main_NPC_entity", comment: ""),
                icon: "criminal"
            )

            customizableNavigationLink(
                value: "npc_faction",
                title: NSLocalizedString("Main_NPC_Faction", comment: ""),
                icon: "concord"
            )

            customizableNavigationLink(
                value: "agents",
                title: NSLocalizedString("Main_Agents", comment: ""),
                icon: "agentfinder"
            )

            customizableNavigationLink(
                value: "star_map",
                title: NSLocalizedString("Main_Star_Map", comment: "星图"),
                icon: "map"
            )

            customizableNavigationLink(
                value: "wormhole",
                title: NSLocalizedString("Main_WH", comment: ""),
                icon: "terminate"
            )

            customizableNavigationLink(
                value: "incursions",
                title: NSLocalizedString("Main_Incursions", comment: ""),
                icon: "incursions"
            )

            customizableNavigationLink(
                value: "faction_war",
                title: NSLocalizedString("Main_Section_Frontlines", comment: ""),
                icon: "factionalwarfare"
            )

            customizableNavigationLink(
                value: "sovereignty",
                title: NSLocalizedString("Main_Sovereignty", comment: ""),
                icon: "sovereignty"
            )

            customizableNavigationLink(
                value: "language_map",
                title: NSLocalizedString("Main_Language_Map", comment: ""),
                icon: "browser"
            )

            customizableNavigationLink(
                value: "jump_navigation",
                title: NSLocalizedString("Main_Jump_Navigation", comment: ""),
                icon: "capitalnavigation"
            )

            customizableNavigationLink(
                value: "calculator",
                title: NSLocalizedString("Calculator_Title", comment: "计算器"),
                icon: "calculator"
            )
        } header: {
            Text(NSLocalizedString("Main_Databases", comment: ""))
                .fontWeight(.semibold)
                .font(.system(size: 18))
                .foregroundColor(.primary)
                .textCase(nil)
        }
        .isHidden(!hasVisibleFeatures(in: getFeatureIds(for: "database")))
    }

    private var businessSection: some View {
        Section {
            customizableNavigationLink(
                value: "assets",
                title: NSLocalizedString("Main_Assets", comment: ""),
                icon: "assets"
            )
            .isHidden(currentCharacterId == 0 && !isCustomizeMode)

            customizableNavigationLink(
                value: "market_orders",
                title: NSLocalizedString("Main_Market_Orders", comment: ""),
                icon: "marketdeliveries"
            )
            .isHidden(currentCharacterId == 0 && !isCustomizeMode)

            customizableNavigationLink(
                value: "contracts",
                title: NSLocalizedString("Main_Contracts", comment: ""),
                icon: "contracts"
            )
            .isHidden(currentCharacterId == 0 && !isCustomizeMode)

            customizableNavigationLink(
                value: "market_transactions",
                title: NSLocalizedString("Main_Market_Transactions", comment: ""),
                icon: "journal"
            )
            .isHidden(currentCharacterId == 0 && !isCustomizeMode)

            customizableNavigationLink(
                value: "wallet_journal",
                title: NSLocalizedString("Main_Wallet_Journal", comment: ""),
                icon: "wallet"
            )
            .isHidden(currentCharacterId == 0 && !isCustomizeMode)

            customizableNavigationLink(
                value: "industry_jobs",
                title: NSLocalizedString("Main_Industry_Jobs", comment: ""),
                icon: "industry"
            )
            .isHidden(currentCharacterId == 0 && !isCustomizeMode)

            customizableNavigationLink(
                value: "mining_ledger",
                title: NSLocalizedString("Main_Mining_Ledger", comment: ""),
                icon: "miningledger"
            )
            .isHidden(currentCharacterId == 0 && !isCustomizeMode)

            customizableNavigationLink(
                value: "planetary",
                title: NSLocalizedString("Main_Planetary", comment: ""),
                icon: "planets"
            )
        } header: {
            Text(NSLocalizedString("Main_Business", comment: ""))
                .fontWeight(.semibold)
                .font(.system(size: 18))
                .foregroundColor(.primary)
                .textCase(nil)
        }
        .isHidden(!hasVisibleFeatures(in: getFeatureIds(for: "business")))
    }

    private var KillBoardSection: some View {
        Section {
            customizableNavigationLink(
                value: "killboard",
                title: NSLocalizedString("Main_Killboard", comment: ""),
                icon: "killreport",
                note: NSLocalizedString("KillMail_Data_Source", comment: "")
            )
            .isHidden(currentCharacterId == 0 && !isCustomizeMode)
        } header: {
            Text(NSLocalizedString("Main_Battle", comment: ""))
                .fontWeight(.semibold)
                .font(.system(size: 18))
                .foregroundColor(.primary)
                .textCase(nil)
        }
        .isHidden(!hasVisibleFeatures(in: getFeatureIds(for: "battle")))
    }

    private var FittingSection: some View {
        Section {
            customizableNavigationLink(
                value: "fitting",
                title: NSLocalizedString("Main_Fitting_Simulation", comment: ""),
                icon: "fitting"
            )
        } header: {
            Text(NSLocalizedString("Main_Fitting", comment: ""))
                .fontWeight(.semibold)
                .font(.system(size: 18))
                .foregroundColor(.primary)
                .textCase(nil)
        }
        .isHidden(!hasVisibleFeatures(in: getFeatureIds(for: "fitting")))
    }

    private var otherSection: some View {
        Section {
            customizableNavigationLink(
                value: "settings",
                title: NSLocalizedString("Main_Setting", comment: ""),
                icon: "Settings"
            )

            customizableNavigationLink(
                value: "update_history",
                title: NSLocalizedString("Main_Update_History", comment: "更新历史"),
                icon: "log"
            )

            customizableNavigationLink(
                value: "about",
                title: NSLocalizedString("Main_About", comment: ""),
                icon: "info"
            )
        } header: {
            Text(NSLocalizedString("Main_Other", comment: ""))
                .fontWeight(.semibold)
                .font(.system(size: 18))
                .foregroundColor(.primary)
                .textCase(nil)
        } footer: {
            VStack(spacing: 8) {
                // 主要的切换按钮
                HStack {
                    Spacer()
                    if isCustomizeMode {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                isCustomizeMode = false
                            }
                        }) {
                            Text(NSLocalizedString("Features_Exit_Customize", comment: ""))
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    } else {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                isCustomizeMode.toggle()
                            }
                        }) {
                            let hiddenCount = hiddenFeatures.count
                            if hiddenCount > 0 {
                                Text(
                                    String(
                                        format: NSLocalizedString(
                                            "Features_Too_Many_With_Count", comment: ""
                                        ),
                                        hiddenCount
                                    )
                                )
                                .font(.caption)
                                .foregroundColor(.blue)
                            } else {
                                Text(NSLocalizedString("Features_Too_Many", comment: ""))
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    Spacer()
                }

                if isCustomizeMode {
                    // 恢复默认按钮
                    HStack {
                        Spacer()
                        Button(action: {
                            // 恢复默认 - 清空所有隐藏功能
                            hiddenFeatures.removeAll()
                            saveHiddenFeatures()
                        }) {
                            Text(NSLocalizedString("Features_Restore_Default", comment: ""))
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        Spacer()
                    }

                    // 自定义模式下的说明
                    Text(NSLocalizedString("Features_Customize_Mode", comment: ""))
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .padding(.top, 8)
        }
        .isHidden(!hasVisibleFeatures(in: getFeatureIds(for: "other")))
    }

    // MARK: - Toolbar Content

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // 在导航栏左侧显示人物头像（仅当滚动且已登录时）
        ToolbarItem(placement: .navigationBarLeading) {
            if currentCharacterId != 0, viewModel.selectedCharacter != nil,
               navigationAvatarItemVisible
            {
                Button(action: {
                    // 跳转到人物选择页面
                    selectedItem = "accounts"
                }) {
                    NavigationBarAvatarView(
                        characterPortrait: viewModel.characterPortrait,
                        isRefreshTokenExpired: isRefreshTokenExpired,
                        isRefreshing: viewModel.isRefreshing
                    )
                }
                .buttonStyle(ScaleButtonStyle())
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.8)),
                        removal: .opacity.combined(with: .scale(scale: 0.8))
                    ))
            }
        }

        // SDE更新下载按钮（仅当有更新时显示，在登出按钮左边）
        ToolbarItem(placement: .navigationBarTrailing) {
            if sdeUpdateChecker.updateStatus == .hasUpdate {
                Button(action: {
                    showingSDEUpdateSheet = true
                }) {
                    HStack(spacing: 4) {
                        Text(NSLocalizedString("Main_SDE_Update_Available", comment: ""))
                            .font(.caption)
                            .foregroundColor(.green)
                        Image(systemName: "arrow.down.circle.fill")
                            .resizable()
                            .frame(width: 20, height: 20)
                            .foregroundColor(.green)
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.8)),
                    removal: .opacity.combined(with: .scale(scale: 0.8))
                ))
                .animation(.easeInOut(duration: 0.3), value: sdeUpdateChecker.updateStatus)
            }
        }

        // 登出按钮或退出自定义模式按钮
        ToolbarItem(placement: .navigationBarTrailing) {
            if isCustomizeMode {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isCustomizeMode = false
                    }
                }) {
                    Text(NSLocalizedString("Features_Exit_Customize", comment: ""))
                        .foregroundColor(.blue)
                }
            } else if currentCharacterId != 0 {
                logoutButton
            }
        }
    }

    private var logoutButton: some View {
        Button {
            currentCharacterId = 0
            viewModel.resetCharacterInfo()
            // 清除技能数据
            Task {
                SharedSkillsManager.shared.clearSkillData()
            }
        } label: {
            Image(systemName: "rectangle.portrait.and.arrow.right")
                .resizable()
                .frame(width: 28, height: 24)
                .foregroundColor(.red)
        }
    }

    // MARK: - 通用组件

    struct RowView: View {
        let title: String
        let icon: String
        var note: String?
        var noteView: AnyView? = nil

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
                    if let noteView = noteView {
                        noteView
                    } else if let note = note, !note.isEmpty {
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

// MARK: - 克隆倒计时组件

struct CloneCountdownView: View {
    let targetDate: Date?

    var body: some View {
        if let date = targetDate {
            TimelineView(.periodic(from: Date(), by: 1.0)) { timeline in
                let now = timeline.date
                let remainingTime = date.timeIntervalSince(now)

                if remainingTime <= 0 {
                    Text(NSLocalizedString("Main_Jump_Clones_Ready", comment: ""))
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(1)
                } else {
                    // 转换为小时、分钟和秒
                    let hours = Int(remainingTime) / 3600
                    let minutes = (Int(remainingTime) % 3600) / 60
                    let seconds = Int(remainingTime) % 60

                    if hours > 0 {
                        if minutes > 0 {
                            Text(
                                String(
                                    format: NSLocalizedString(
                                        "Main_Jump_Clones_Cooldown_Hours_Minutes_Seconds",
                                        comment: "下次跳跃: %dh %dm %ds"
                                    ), hours, minutes, seconds
                                )
                            )
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(1)
                        } else {
                            Text(
                                String(
                                    format: NSLocalizedString(
                                        "Main_Jump_Clones_Cooldown_Hours_Seconds",
                                        comment: "下次跳跃: %dh %ds"
                                    ), hours, seconds
                                )
                            )
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(1)
                        }
                    } else if minutes > 0 {
                        Text(
                            String(
                                format: NSLocalizedString(
                                    "Main_Jump_Clones_Cooldown_Minutes_Seconds",
                                    comment: "下次跳跃: %dm %ds"
                                ), minutes, seconds
                            )
                        )
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(1)
                    } else {
                        Text(
                            String(
                                format: NSLocalizedString(
                                    "Main_Jump_Clones_Cooldown_Seconds", comment: "下次跳跃: %ds"
                                ), seconds
                            )
                        )
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(1)
                    }
                }
            }
        } else {
            Text(NSLocalizedString("Main_Jump_Clones_Ready", comment: ""))
                .font(.system(size: 12))
                .foregroundColor(.gray)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(1)
        }
    }
}

// MARK: - 技能队列倒计时组件

struct SkillQueueCountdownView: View {
    let queueEndDate: Date?
    let skillCount: Int

    var body: some View {
        if let endDate = queueEndDate, skillCount > 0 {
            TimelineView(.periodic(from: Date(), by: 1.0)) { timeline in
                let now = timeline.date
                let remainingTime = endDate.timeIntervalSince(now)

                if remainingTime <= 0 {
                    // 队列已完成
                    Text(NSLocalizedString("Main_Skills_Queue_Complete", comment: "完成"))
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(1)
                } else {
                    // 转换为天、小时、分钟和秒
                    let days = Int(remainingTime) / 86400
                    let hours = (Int(remainingTime) % 86400) / 3600
                    let minutes = (Int(remainingTime) % 3600) / 60
                    let seconds = Int(remainingTime) % 60

                    if days > 0 {
                        Text(
                            String(
                                format: NSLocalizedString(
                                    "Main_Skills_Queue_Training_Days",
                                    comment: "训练中 - %d个技能 - %dd %dh %dm"
                                ), skillCount, days, hours, minutes
                            )
                        )
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(1)
                    } else if hours > 0 {
                        Text(
                            String(
                                format: NSLocalizedString(
                                    "Main_Skills_Queue_Training_Hours",
                                    comment: "训练中 - %d个技能 - %dh %dm %ds"
                                ), skillCount, hours, minutes, seconds
                            )
                        )
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(1)
                    } else {
                        Text(
                            String(
                                format: NSLocalizedString(
                                    "Main_Skills_Queue_Training_Minutes",
                                    comment: "训练中 - %d个技能 - %dm %ds"
                                ), skillCount, minutes, seconds
                            )
                        )
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(1)
                    }
                }
            }
        } else if skillCount > 0 {
            // 有技能但暂停中
            Text(
                String(
                    format: NSLocalizedString("Main_Skills_Queue_Paused", comment: "暂停中 - %d个技能"),
                    skillCount
                )
            )
            .font(.system(size: 12))
            .foregroundColor(.gray)
            .fixedSize(horizontal: false, vertical: true)
            .lineLimit(1)
        } else {
            // 空队列
            Text(NSLocalizedString("Main_Skills_Queue_Empty", comment: "技能队列为空"))
                .font(.system(size: 12))
                .foregroundColor(.gray)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(1)
        }
    }
}
