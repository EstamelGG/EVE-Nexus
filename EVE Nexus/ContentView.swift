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
    @StateObject private var viewModel = EVELoginViewModel()
    @State private var showingWebView = false
    @State private var isEditing = false
    @State private var characterToRemove: EVECharacterInfo? = nil
    
    var body: some View {
        NavigationView {
            List {
                // 添加新角色按钮
                Section {
                    Button(action: {
                        if EVELogin.shared.getAuthorizationURL() != nil {
                            showingWebView = true
                        } else {
                            Logger.error("获取授权URL失败")
                        }
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.blue)
                            Text("Account_Add_Character")
                                .foregroundColor(.blue)
                            Spacer()
                        }
                    }
                }
                
                // 已登录角色列表
                if !viewModel.characters.isEmpty {
                    Section(header: Text("Account_Logged_Characters")) {
                        ForEach(viewModel.characters, id: \.CharacterID) { character in
                            HStack {
                                if let portrait = viewModel.characterPortraits[character.CharacterID] {
                                    Image(uiImage: portrait)
                                        .resizable()
                                        .frame(width: 40, height: 40)
                                        .clipShape(Circle())
                                } else {
                                    Image(systemName: "person.crop.circle.fill")
                                        .resizable()
                                        .frame(width: 40, height: 40)
                                        .foregroundColor(.gray)
                                }
                                
                                VStack(alignment: .leading) {
                                    Text(character.CharacterName)
                                        .font(.headline)
                                    Text("\(NSLocalizedString("Account_Character_ID", comment: "")): \(character.CharacterID)")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                
                                if isEditing {
                                    Spacer()
                                    Button(action: {
                                        characterToRemove = character
                                    }) {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Account_Management")
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
                
                if !viewModel.characters.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            isEditing.toggle()
                        }) {
                            Text(isEditing ? "Main_Market_Done" : "Main_Market_Edit")
                                .foregroundColor(.blue)
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
                    Text("Account_Cannot_Get_Auth_URL")
                }
            }
            .alert("Account_Login_Failed", isPresented: $viewModel.showingError) {
                Button("Common_OK", role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage)
            }
            .alert("Account_Remove_Confirm_Title", isPresented: .init(
                get: { characterToRemove != nil },
                set: { if !$0 { characterToRemove = nil } }
            )) {
                Button("Account_Remove_Confirm_Cancel", role: .cancel) {
                    characterToRemove = nil
                }
                Button("Account_Remove_Confirm_Remove", role: .destructive) {
                    if let character = characterToRemove {
                        viewModel.removeCharacter(character)
                        characterToRemove = nil
                    }
                }
            } message: {
                if let character = characterToRemove {
                    Text(character.CharacterName)
                }
            }
            .onAppear {
                viewModel.loadCharacters()
            }
            .onOpenURL { url in
                Task {
                    await viewModel.handleCallback(url: url)
                    showingWebView = false
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("LanguageChanged"))) { _ in
                // 强制视图刷新
                viewModel.objectWillChange.send()
            }
        }
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

// 添加登录按钮组件
struct LoginButtonView: View {
    let isLoggedIn: Bool
    let serverStatus: ServerStatus?
    let action: () -> Void
    @State private var forceUpdate: Bool = false
    
    var body: some View {
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
                    Text(NSLocalizedString("Account_Add_Character", comment: ""))
                        .font(.headline)
                        .padding(.bottom, 4)
                }
                ServerStatusView(status: serverStatus)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
                .font(.system(size: 14))
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .id(forceUpdate) // 强制视图刷新
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("LanguageChanged"))) { _ in
            forceUpdate.toggle()
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
    @State private var forceViewUpdate: Bool = false // 添加强制更新标志
    
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
                    LoginButtonView(
                        isLoggedIn: isLoggedIn,
                        serverStatus: serverStatus,
                        action: { showingAccountSheet = true }
                    )
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
                AccountsView()
            }
        }
        .preferredColorScheme(selectedTheme == "light" ? .light : (selectedTheme == "dark" ? .dark : nil))
        .id(forceViewUpdate) // 添加id以强制视图刷新
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("LanguageChanged"))) { _ in
            // 强制整个视图重新加载
            forceViewUpdate.toggle()
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
