import SwiftUI
import SafariServices
import WebKit

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

struct AccountsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = SafariViewModel()
    @Binding var isLoggedIn: Bool
    @State private var showingWebView = false
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    if let character = viewModel.characterInfo {
                        VStack(alignment: .leading) {
                            Text(character.CharacterName)
                                .font(.headline)
                            Text("Character ID: \(character.CharacterID)")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    } else {
                        Button(action: {
                            if EVELogin.shared.getAuthorizationURL() != nil {
                                showingWebView = true
                            } else {
                                Logger.error("获取授权URL失败")
                            }
                        }) {
                            Text("Log In with EVE Online")
                                .foregroundColor(.blue)
                                .frame(maxWidth: .infinity)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
            }
            .navigationTitle("Accounts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.blue)
                    }
                }
                
                if viewModel.characterInfo != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("登出") {
                            logout()
                        }
                    }
                }
            }
            .sheet(isPresented: $showingWebView) {
            } content: {
                if let url = EVELogin.shared.getAuthorizationURL() {
                    SafariView(url: url)
                        .environmentObject(viewModel)
                } else {
                    Text("无法获取授权URL")
                }
            }
            .alert("登录错误", isPresented: $viewModel.showingError) {
                Button("确定", role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage)
            }
            .onAppear {
                checkExistingAuth()
            }
            .onOpenURL { url in
                handleCallback(url: url)
            }
        }
    }
    
    private func handleCallback(url: URL) {
        Task {
            do {
                let token = try await EVELogin.shared.handleAuthCallback(url: url)
                let character = try await EVELogin.shared.getCharacterInfo(token: token.access_token)
                
                Logger.info("成功获取角色信息 - 名称: \(character.CharacterName), ID: \(character.CharacterID)")
                
                // 先保存认证信息
                EVELogin.shared.saveAuthInfo(token: token, character: character)
                
                // 更新UI状态
                await MainActor.run {
                    viewModel.handleLoginSuccess(character: character)
                    isLoggedIn = true
                    showingWebView = false
                }
            } catch {
                Logger.error("处理授权失败: \(error)")
                await MainActor.run {
                    viewModel.handleLoginError(error)
                    showingWebView = false
                }
            }
        }
    }
    
    private func checkExistingAuth() {
        let authInfo = EVELogin.shared.loadAuthInfo()
        if let character = authInfo.character {
            Logger.info("加载已保存的角色信息 - 名称: \(character.CharacterName), ID: \(character.CharacterID)")
            viewModel.handleLoginSuccess(character: character)
            isLoggedIn = true
        }
    }
    
    private func logout() {
        EVELogin.shared.clearAuthInfo()
        viewModel.characterInfo = nil
        isLoggedIn = false
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
    @Published var serverStatus: ServerStatus?
    @Published var isLoadingStatus = true
    private var updateTask: Task<Void, Never>?
    
    func startUpdating() {
        // 取消之前的任务（如果存在）
        updateTask?.cancel()
        
        // 创建新的更新任务
        updateTask = Task {
            while !Task.isCancelled {
                await updateServerStatus()
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000) // 60秒更新一次
            }
        }
    }
    
    func stopUpdating() {
        updateTask?.cancel()
        updateTask = nil
    }
    
    private func updateServerStatus() async {
        do {
            let status = try await NetworkManager.shared.fetchServerStatus()
            await MainActor.run {
                self.serverStatus = status
                self.isLoadingStatus = false
            }
        } catch {
            Logger.error("Failed to fetch server status: \(error)")
            await MainActor.run {
                self.isLoadingStatus = false
            }
        }
    }
}

struct ServerStatusView: View {
    @StateObject private var viewModel = ServerStatusViewModel()
    let status: ServerStatus?
    
    var body: some View {
        HStack(spacing: 4) {
            UTCTimeView()
            Text("-")
            if let status = status {
                if status.isOnline {
                    Text("Online")
                        .font(.caption.bold())
                        .foregroundColor(Color(red: 0, green: 0.5, blue: 0))
                    
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
        .onAppear {
            viewModel.startUpdating()
        }
        .onDisappear {
            viewModel.stopUpdating()
        }
    }
}

struct ContentView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var tables: [TableNode] = []
    @State private var isLoggedIn = false
    @State private var serverStatus: ServerStatus?
    @State private var isLoadingStatus = true
    @State private var showingAccountSheet = false
    
    // 添加预加载状态
    @State private var isDatabasePreloaded = false
    
    // 自定义初始化方法，确保 databaseManager 被正确传递
    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
        _tables = State(initialValue: generateTables())
    }
    
    // 使用 @AppStorage 来读取存储的主题设置
    @AppStorage("selectedTheme") private var selectedTheme: String = "system" // 默认为系统模式
    
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
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 15) {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .frame(width: 50, height: 50)
                            .foregroundColor(.gray)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            if isLoggedIn {
                                Text("联盟名称")
                                    .font(.headline)
                                    .lineLimit(1)
                                Text("军团名称")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                            } else {
                                Text("Tap to Login")
                                    .font(.headline)
                                    .padding(.bottom, 4)
                            }
                            ServerStatusView(status: serverStatus)
                        }
                        Spacer()
                    }
                    .onTapGesture {
                        showingAccountSheet = true
                    }
                }
                
                // 原有的表格内容
                ForEach(tables) { table in
                    Section(header: Text(table.title)
                        .fontWeight(.bold)
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                    ) {
                        ForEach(table.rows) { row in
                            NavigationLink(destination: getDestination(for: row)) {
                                rowContent(row)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable {
                do {
                    serverStatus = try await NetworkManager.shared.fetchServerStatus()
                } catch {
                    Logger.error("Failed to refresh server status: \(error)")
                }
            }
            .navigationTitle(NSLocalizedString("Main_Title", comment: ""))
            .sheet(isPresented: $showingAccountSheet) {
                AccountsView(isLoggedIn: $isLoggedIn)
            }
        }
        .preferredColorScheme(selectedTheme == "light" ? .light : (selectedTheme == "dark" ? .dark : nil))
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("LanguageChanged"))) { _ in
            initializeTables()
        }
        .task {
            // 合并所有异步任务
            async let statusTask: Void = updateServerStatus()
            async let preloadTask: Void = preloadDatabaseIfNeeded()
            _ = await (statusTask, preloadTask)
        }
    }
    
    private func updateServerStatus() async {
        do {
            serverStatus = try await NetworkManager.shared.fetchServerStatus()
        } catch {
            Logger.error("Failed to fetch server status: \(error)")
        }
        isLoadingStatus = false
        
        // 每60秒更新一次服务器状态
        try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
        if !Task.isCancelled {
            await updateServerStatus()
        }
    }
    
    // 预加载数据库内容
    private func preloadDatabaseIfNeeded() async {
        print("=== Debug: Checking preload condition ===")
        print("isDatabasePreloaded: \(isDatabasePreloaded)")
        
        guard !isDatabasePreloaded else {
            print("=== Debug: Database already preloaded, skipping ===")
            return
        }
        
        print("=== Debug: Starting database content preload... ===")
        
        // 预加载
        let (published, unpublished) = databaseManager.loadCategories()
        print("=== Debug: Loaded categories - Published: \(published.count), Unpublished: \(unpublished.count) ===")
        let res = databaseManager.loadAttributeUnits()
        print("=== Debug: Loaded \(res.count) AttributeUnits ===")
        
        // 预加载分类图标
        for category in published + unpublished {
            _ = IconManager.shared.loadUIImage(for: category.iconFileNew)
        }
        print("=== Debug: Preloaded \(published.count + unpublished.count) category icons ===")
        
        await MainActor.run {
            isDatabasePreloaded = true
            print("=== Debug: Database preload completed successfully ===")
        }
    }
    
    // 添加初始化表格数据的方法
    private func initializeTables() {
        tables = generateTables()
    }
    
    // 创建生成表格数据的私有方法
    private func generateTables() -> [TableNode] {
        return [
            TableNode(
                title: NSLocalizedString("Main_Character", comment: ""),
                rows: [
                    TableRowNode(
                        title: NSLocalizedString("Main_Character_Sheet", comment: ""),
                        iconName: "charactersheet",
                        note: NSLocalizedString("Main_Skills Ponits", comment: "")
                    ),
                    TableRowNode(
                        title: NSLocalizedString("Main_Jump_Clones", comment: ""),
                        iconName: "jumpclones",
                        note: NSLocalizedString("Main_Jump_Clones_Available", comment: "")
                    ),
                    TableRowNode(
                        title: NSLocalizedString("Main_Skills", comment: ""),
                        iconName: "skills",
                        note: NSLocalizedString("Main_Skills Queue", comment: "")
                    ),
                    TableRowNode(
                        title: NSLocalizedString("Main_EVE Mail", comment: ""),
                        iconName: "evemail"
                    ),
                    TableRowNode(
                        title: NSLocalizedString("Main_Calendar", comment: ""),
                        iconName: "calendar"
                    ),
                    TableRowNode(
                        title: NSLocalizedString("Main_Wealth", comment: ""),
                        iconName: "Folder",
                        note: NSLocalizedString("Main_Wealth ISK", comment: "")
                    ),
                    TableRowNode(
                        title: NSLocalizedString("Main_Loyalty Points", comment: ""),
                        iconName: "lpstore"
                    )
                ]
            ),
            TableNode(
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
            ),
            TableNode(
                title: NSLocalizedString("Main_Business", comment: ""),
                rows: [
                    TableRowNode(
                        title: NSLocalizedString("Main_Assets", comment: ""),
                        iconName: "assets"
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
            ),
            TableNode(
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
            )
        ]
    }
}

#Preview {
    ContentView(databaseManager: DatabaseManager()) // 确保传递数据库管理器
}
