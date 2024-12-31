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
        .task {
            // 初始加载
            if let character = selectedCharacter {
                do {
                    // 加载军团信息和图标
                    async let corporationInfoTask = CorporationAPI.shared.fetchCorporationInfo(corporationId: character.corporationId ?? 0)
                    async let corporationLogoTask = CorporationAPI.shared.fetchCorporationLogo(corporationId: character.corporationId ?? 0)
                    
                    let (corpInfo, corpLogo) = try await (corporationInfoTask, corporationLogoTask)
                    
                    corporationInfo = corpInfo
                    corporationLogo = corpLogo
                    
                    // 如果有联盟,加载联盟信息和图标
                    if let allianceId = character.allianceId {
                        async let allianceInfoTask = AllianceAPI.shared.fetchAllianceInfo(allianceId: allianceId)
                        async let allianceLogoTask = AllianceAPI.shared.fetchAllianceLogo(allianceID: allianceId)
                        
                        let (alliInfo, alliLogo) = try await (allianceInfoTask, allianceLogoTask)
                        
                        allianceInfo = alliInfo
                        allianceLogo = alliLogo
                    }
                } catch {
                    Logger.error("加载角色信息失败: \(error)")
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
    @Environment(\.colorScheme) var systemColorScheme
    
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
        NavigationStack {
            List {
                // 登录部分
                loginSection
                
                // 角色功能部分
        if currentCharacterId != 0 {
                    characterSection
                }
                
                // 数据库部分(始终显示)
                databaseSection
                
                // 商业部分(登录后显示)
                if currentCharacterId != 0 {
                    businessSection
                }
                
                // 其他设置(始终显示)
                otherSection
            }
            .listStyle(.insetGrouped)
            .refreshable {
                await viewModel.refreshAllData(forceRefresh: true)
            }
            .navigationTitle(NSLocalizedString("Main_Title", comment: ""))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    logoutButton
                }
            }
        }
        .preferredColorScheme(currentColorScheme)
        .task {
            await viewModel.refreshAllData()
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
    }
    
    // MARK: - 视图组件
    private var loginSection: some View {
        Section {
            NavigationLink {
                AccountsView(
                    databaseManager: databaseManager,
                    mainViewModel: viewModel
                ) { character, portrait in
                    viewModel.resetCharacterInfo()
                    viewModel.selectedCharacter = character
                    viewModel.characterPortrait = portrait
                    currentCharacterId = character.CharacterID
                    Task {
                        await viewModel.refreshAllData()
                    }
                }
            } label: {
                LoginButtonView(
                    isLoggedIn: currentCharacterId != 0,
                    serverStatus: viewModel.serverStatus,
                    selectedCharacter: viewModel.selectedCharacter,
                    characterPortrait: viewModel.characterPortrait,
                    isRefreshing: viewModel.isRefreshing
                )
            }
        }
    }
    
    private var characterSection: some View {
        Section(NSLocalizedString("Main_Character", comment: "")) {
            NavigationLink {
                if let character = viewModel.selectedCharacter {
                    CharacterSheetView(
                        character: character,
                        characterPortrait: viewModel.characterPortrait
                    )
                }
            } label: {
                RowView(
                    title: NSLocalizedString("Main_Character_Sheet", comment: ""),
                    icon: "charactersheet",
                    note: viewModel.characterStats.skillPoints
                )
            }
            
            NavigationLink {
                if let character = viewModel.selectedCharacter {
                    CharacterClonesView(character: character)
                }
            } label: {
                RowView(
                    title: NSLocalizedString("Main_Jump_Clones", comment: ""),
                    icon: "jumpclones",
                    note: viewModel.cloneJumpStatus
                )
            }
            
            NavigationLink {
                Text("Skills View") // 待实现
            } label: {
                RowView(
                    title: NSLocalizedString("Main_Skills", comment: ""),
                    icon: "skills",
                    note: viewModel.characterStats.queueStatus
                )
            }
            
            NavigationLink {
                Text("EVE Mail View") // 待实现
            } label: {
                RowView(
                    title: NSLocalizedString("Main_EVE_Mail", comment: ""),
                    icon: "evemail"
                )
            }
            
            NavigationLink {
                Text("Calendar View") // 待实现
            } label: {
                RowView(
                    title: NSLocalizedString("Main_Calendar", comment: ""),
                    icon: "calendar"
                )
            }
            
            NavigationLink {
                Text("Wealth View") // 待实现
            } label: {
                RowView(
                    title: NSLocalizedString("Main_Wealth", comment: ""),
                    icon: "Folder",
                    note: viewModel.characterStats.walletBalance
                )
            }
            
            NavigationLink {
                Text("Loyalty Points View") // 待实现
            } label: {
                RowView(
                    title: NSLocalizedString("Main_Loyalty_Points", comment: ""),
                    icon: "lpstore"
                )
            }
        }
    }
    
    private var databaseSection: some View {
        Section(NSLocalizedString("Main_Databases", comment: "")) {
            NavigationLink {
                DatabaseBrowserView(
                    databaseManager: databaseManager,
                    level: .categories
                )
            } label: {
                RowView(
                    title: NSLocalizedString("Main_Database", comment: ""),
                    icon: "items"
                )
            }
            
            NavigationLink {
                MarketBrowserView(databaseManager: databaseManager)
            } label: {
                RowView(
                    title: NSLocalizedString("Main_Market", comment: ""),
                    icon: "market"
                )
            }
            
            NavigationLink {
                NPCBrowserView(databaseManager: databaseManager)
            } label: {
                RowView(
                    title: "NPC",
                    icon: "criminal"
                )
            }
            
            NavigationLink {
                WormholeView(databaseManager: databaseManager)
            } label: {
                RowView(
                    title: NSLocalizedString("Main_WH", comment: ""),
                    icon: "terminate"
                )
            }
            
            NavigationLink {
                IncursionsView(databaseManager: databaseManager)
            } label: {
                RowView(
                    title: NSLocalizedString("Main_Incursions", comment: ""),
                    icon: "incursions"
                )
            }
            
            NavigationLink {
                SovereigntyView(databaseManager: databaseManager)
            } label: {
                RowView(
                    title: NSLocalizedString("Main_Sovereignty", comment: ""),
                    icon: "sovereignty"
                )
            }
        }
    }
    
    private var businessSection: some View {
        Section(NSLocalizedString("Main_Business", comment: "")) {
            NavigationLink {
                if let character = viewModel.selectedCharacter {
                    CharacterAssetsView(characterId: character.CharacterID)
                }
            } label: {
                RowView(
                    title: NSLocalizedString("Main_Assets", comment: ""),
                    icon: "assets"
                )
            }
            
            NavigationLink {
                if let character = viewModel.selectedCharacter {
                    CharacterOrdersView(characterId: Int64(character.CharacterID))
                }
            } label: {
                RowView(
                    title: NSLocalizedString("Main_Market_Orders", comment: ""),
                    icon: "marketdeliveries"
                )
            }
            
            NavigationLink {
                if let character = viewModel.selectedCharacter {
                    PersonalContractsView(characterId: character.CharacterID)
                }
            } label: {
                RowView(
                    title: NSLocalizedString("Main_Contracts", comment: ""),
                    icon: "contracts"
                )
            }
            
            NavigationLink {
                if let character = viewModel.selectedCharacter {
                    WalletTransactionsView(characterId: character.CharacterID, databaseManager: databaseManager)
                }
            } label: {
                RowView(
                    title: NSLocalizedString("Main_Market_Transactions", comment: ""),
                    icon: "journal"
                )
            }
            
            NavigationLink {
                if let character = viewModel.selectedCharacter {
                    WalletJournalView(characterId: character.CharacterID)
                }
            } label: {
                RowView(
                    title: NSLocalizedString("Main_Wallet_Journal", comment: ""),
                    icon: "wallet"
                )
            }
            
            NavigationLink {
                if let character = viewModel.selectedCharacter {
                    CharacterIndustryView(characterId: character.CharacterID)
                }
            } label: {
                RowView(
                    title: NSLocalizedString("Main_Industry_Jobs", comment: ""),
                    icon: "industry"
                )
            }
            
            NavigationLink {
                if let character = viewModel.selectedCharacter {
                    MiningLedgerView(characterId: character.CharacterID, databaseManager: databaseManager)
                }
            } label: {
                RowView(
                    title: NSLocalizedString("Main_Mining_Ledger", comment: ""),
                    icon: "miningledger"
                )
            }
        }
    }
    
    private var otherSection: some View {
        Section(NSLocalizedString("Main_Other", comment: "")) {
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
        }
    }
    
    private var logoutButton: some View {
        Button {
            currentCharacterId = 0
            viewModel.resetCharacterInfo()
        } label: {
            Image(systemName: "rectangle.portrait.and.arrow.right")
                .resizable()
                .frame(width: 24, height: 24)
                .foregroundColor(.red)
        }
    }
    
    // MARK: - 通用组件
    struct RowView: View {
        let title: String
        let icon: String
        var note: String?
        
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
            .frame(height: 36)
        }
    }
}
