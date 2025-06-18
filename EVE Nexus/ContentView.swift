import Foundation
import SafariServices
import SwiftUI
import WebKit

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
            return 60  // 1分钟
        }
        // 11:00-11:30 AM UTC
        else if hour == 11 && minute < 30 {
            // 如果服务器已经在线，切换到2分钟间隔
            if let status = status, status.isOnline {
                return 120  // 2分钟
            }
            return 60  // 1分钟
        }
        // 11:30 AM UTC 之后
        else if hour == 11 && minute >= 30 {
            return 120  // 2分钟
        }
        // 11:00 AM UTC 之前
        else {
            return 1200  // 20分钟
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
        if newTime.hour == 11 && newTime.minute == 0 && (oldTime.hour != 11 || oldTime.minute != 0)
        {
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
                return Text(NSLocalizedString("Server_Status_Online", comment: ""))
                    .font(.caption.bold())
                    .foregroundColor(.green)
                + Text(
                    String(
                        format: NSLocalizedString("Server_Status_Players", comment: ""),
                        formattedPlayers)
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
                    businessSection

                    // 战斗部分(登录后显示)
                    if currentCharacterId != 0 {
                        KillBoardSection
                    }
                    // 装配部分(无需登录)
                    FittingSection
                    // 其他设置(始终显示)
                    otherSection
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    await viewModel.refreshAllData(forceRefresh: true)
                }
                .navigationTitle(NSLocalizedString("Main_Home", comment: ""))
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
                            Text("Calendar View")  // 待实现
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
                                PersonalContractsView(characterId: character.CharacterID)
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
                        case "jump_navigation":
                            JumpNavigationView(databaseManager: databaseManager)
                        case "fitting":
                            FittingMainView(
                                characterId: viewModel.selectedCharacter?.CharacterID,
                                databaseManager: databaseManager)
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
        .onReceive(
            NotificationCenter.default.publisher(for: NSNotification.Name("LanguageChanged"))
        ) { _ in
            // 语言变更时的处理
            Task {
                await viewModel.refreshAllData()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSNotification.Name("CharacterLoggedOut"))
        ) { _ in
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
        } footer: {
            ServerStatusView(mainViewModel: viewModel)
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
                    noteView: AnyView(CloneCountdownView(targetDate: viewModel.cloneCooldownEndDate))
                )
            }

            NavigationLink(value: "character_skills") {
                RowView(
                    title: NSLocalizedString("Main_Skills", comment: ""),
                    icon: "skills",
                    noteView: AnyView(SkillQueueCountdownView(queueEndDate: viewModel.skillQueueEndDate, skillCount: viewModel.skillQueueCount))
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
                    title: NSLocalizedString("Main_Contact_Search", comment: ""),
                    icon: "peopleandplaces"
                )
            }
        } header: {
            Text(NSLocalizedString("Main_Character", comment: ""))
                .fontWeight(.semibold)
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
                .fontWeight(.semibold)
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

            NavigationLink(value: "attribute_compare") {
                RowView(
                    title: NSLocalizedString("Main_Attribute_Compare", comment: "属性对比器"),
                    icon: "comparetool"
                )
            }

            NavigationLink(value: "npc") {
                RowView(
                    title: "NPC",
                    icon: "criminal"
                )
            }

            NavigationLink(value: "agents") {
                RowView(
                    title: NSLocalizedString("Main_Agents", comment: ""),
                    icon: "agentfinder"
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

            NavigationLink(value: "faction_war") {
                RowView(
                    title: NSLocalizedString("Main_Section_Frontlines", comment: ""),
                    icon: "factionalwarfare"
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

            NavigationLink(value: "jump_navigation") {
                RowView(
                    title: NSLocalizedString("Main_Jump_Navigation", comment: ""),
                    icon: "capitalnavigation"
                )
            }
        } header: {
            Text(NSLocalizedString("Main_Databases", comment: ""))
                .fontWeight(.semibold)
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
            }.isHidden(currentCharacterId == 0)

            NavigationLink(value: "market_orders") {
                RowView(
                    title: NSLocalizedString("Main_Market_Orders", comment: ""),
                    icon: "marketdeliveries"
                )
            }.isHidden(currentCharacterId == 0)

            NavigationLink(value: "contracts") {
                RowView(
                    title: NSLocalizedString("Main_Contracts", comment: ""),
                    icon: "contracts"
                )
            }.isHidden(currentCharacterId == 0)

            NavigationLink(value: "market_transactions") {
                RowView(
                    title: NSLocalizedString("Main_Market_Transactions", comment: ""),
                    icon: "journal"
                )
            }.isHidden(currentCharacterId == 0)

            NavigationLink(value: "wallet_journal") {
                RowView(
                    title: NSLocalizedString("Main_Wallet_Journal", comment: ""),
                    icon: "wallet"
                )
            }.isHidden(currentCharacterId == 0)

            NavigationLink(value: "industry_jobs") {
                RowView(
                    title: NSLocalizedString("Main_Industry_Jobs", comment: ""),
                    icon: "industry"
                )
            }.isHidden(currentCharacterId == 0)

            NavigationLink(value: "mining_ledger") {
                RowView(
                    title: NSLocalizedString("Main_Mining_Ledger", comment: ""),
                    icon: "miningledger"
                )
            }.isHidden(currentCharacterId == 0)

            NavigationLink(value: "planetary") {
                RowView(
                    title: NSLocalizedString("Main_Planetary", comment: ""),
                    icon: "planets"
                )
            }
        } header: {
            Text(NSLocalizedString("Main_Business", comment: ""))
                .fontWeight(.semibold)
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
                .fontWeight(.semibold)
                .font(.system(size: 18))
                .foregroundColor(.primary)
                .textCase(nil)
        }
    }
    private var FittingSection: some View {
        Section {
            NavigationLink(value: "fitting") {
                RowView(
                    title: NSLocalizedString("Main_Fitting_Simulation", comment: ""),
                    icon: "fitting"
                )
            }
        } header: {
            Text(NSLocalizedString("Main_Fitting", comment: ""))
                .fontWeight(.semibold)
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
                .fontWeight(.semibold)
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
        var noteView: AnyView? = nil
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
                            Text(String(
                                format: NSLocalizedString(
                                    "Main_Jump_Clones_Cooldown_Hours_Minutes_Seconds", comment: "下次跳跃: %dh %dm %ds"
                                ), hours, minutes, seconds
                            ))
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(1)
                        } else {
                            Text(String(
                                format: NSLocalizedString(
                                    "Main_Jump_Clones_Cooldown_Hours_Seconds", comment: "下次跳跃: %dh %ds"
                                ), hours, seconds
                            ))
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(1)
                        }
                    } else if minutes > 0 {
                        Text(String(
                            format: NSLocalizedString(
                                "Main_Jump_Clones_Cooldown_Minutes_Seconds", comment: "下次跳跃: %dm %ds"
                            ), minutes, seconds
                        ))
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(1)
                    } else {
                        Text(String(
                            format: NSLocalizedString(
                                "Main_Jump_Clones_Cooldown_Seconds", comment: "下次跳跃: %ds"
                            ), seconds
                        ))
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
                        Text(String(
                            format: NSLocalizedString(
                                "Main_Skills_Queue_Training_Days", comment: "训练中 - %d个技能 - %dd %dh %dm"
                            ), skillCount, days, hours, minutes
                        ))
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(1)
                    } else if hours > 0 {
                        Text(String(
                            format: NSLocalizedString(
                                "Main_Skills_Queue_Training_Hours", comment: "训练中 - %d个技能 - %dh %dm %ds"
                            ), skillCount, hours, minutes, seconds
                        ))
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(1)
                    } else {
                        Text(String(
                            format: NSLocalizedString(
                                "Main_Skills_Queue_Training_Minutes", comment: "训练中 - %d个技能 - %dm %ds"
                            ), skillCount, minutes, seconds
                        ))
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(1)
                    }
                }
            }
        } else if skillCount > 0 {
            // 有技能但暂停中
            Text(String(
                format: NSLocalizedString("Main_Skills_Queue_Paused", comment: "暂停中 - %d个技能"),
                skillCount
            ))
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
