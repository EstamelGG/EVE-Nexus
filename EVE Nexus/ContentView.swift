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

// 用于显示EVE Online登录页面的Safari视图
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    @Environment(\.presentationMode) var presentationMode
    @Binding var characterInfo: EVECharacterInfo?
    @Binding var isLoggedIn: Bool
    @Binding var showingError: Bool
    @Binding var errorMessage: String
    
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let controller = SFSafariViewController(url: url, configuration: config)
        controller.delegate = context.coordinator
        controller.dismissButtonStyle = .close
        return controller
    }
    
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
        // 不需要更新
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let parent: SafariView
        
        init(_ parent: SafariView) {
            self.parent = parent
        }
        
        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
        
        func safariViewController(_ controller: SFSafariViewController, didCompleteInitialLoad didLoadSuccessfully: Bool) {
            if !didLoadSuccessfully {
                Logger.error("SafariView: 加载失败")
            }
        }
    }
}

struct AccountsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var isLoggedIn: Bool
    @State var showingWebView = false
    @State var characterInfo: EVECharacterInfo?
    @State var showingError = false
    @State var errorMessage = ""
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    if let character = characterInfo {
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
                
                if characterInfo != nil {
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
                    SafariView(
                        url: url,
                        characterInfo: $characterInfo,
                        isLoggedIn: $isLoggedIn,
                        showingError: $showingError,
                        errorMessage: $errorMessage
                    )
                } else {
                    Text("无法获取授权URL")
                }
            }
            .alert("登录错误", isPresented: $showingError) {
                Button("确定", role: .cancel) { }
            } message: {
                Text(errorMessage)
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
                
                // 然后再获取钱包余额, 验证esi状态
//                do {
//                    let balance = try await ESIDataManager.shared.getWalletBalance(characterId: character.CharacterID)
//                    let formattedBalance = ESIDataManager.shared.formatISK(balance)
//                    Logger.info("获取到钱包余额: \(formattedBalance) ISK")
//                } catch {
//                    Logger.error("获取钱包余额失败: \(error)")
//                }
                
                // 更新UI状态
                await MainActor.run {
                    self.characterInfo = character
                    self.isLoggedIn = true
                    self.showingWebView = false
                }
            } catch {
                Logger.error("处理授权失败: \(error)")
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.showingError = true
                    self.showingWebView = false
                }
            }
        }
    }
    
    private func checkExistingAuth() {
        let authInfo = EVELogin.shared.loadAuthInfo()
        if let character = authInfo.character {
            Logger.info("加载已保存的角色信息 - 名称: \(character.CharacterName), ID: \(character.CharacterID)")
            characterInfo = character
            isLoggedIn = true
        }
    }
    
    private func logout() {
        EVELogin.shared.clearAuthInfo()
        characterInfo = nil
        isLoggedIn = false
    }
}

struct ContentView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var tables: [TableNode] = []
    @State private var isLoggedIn = false
    @State private var serverStatus: ServerStatus?
    @State private var isLoadingStatus = true
    @State private var currentTime = Date() // 添加当前时间状态
    @State private var showingAccountSheet = false // 添加sheet控制状态
    
    // 自定义初始化方法，确保 databaseManager 被正确传递
    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
        _tables = State(initialValue: [
            TableNode(
                title: NSLocalizedString("Main_Character", comment: ""),
                rows: [
                    TableRowNode(
                        title: NSLocalizedString("Main_Character Sheet", comment: ""),
                        iconName: "charactersheet",
                        note: NSLocalizedString("Main_Skills Ponits", comment: "")
                    ),
                    TableRowNode(
                        title: NSLocalizedString("Main_Jump Clones", comment: ""),
                        iconName: "jumpclones",
                        note: NSLocalizedString("Main_Jump Clones Available", comment: "")
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
        ])
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
                }
            }
            Spacer()
        }
        .frame(height: 36)
    }
    
    var serverStatusText: AttributedString {
        // 使用currentTime而不是Date()
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        let utcTime = formatter.string(from: currentTime)
        
        guard let status = serverStatus else {
            var attributed = AttributedString("\(utcTime) - Checking Status...")
            if let timeRange = attributed.range(of: utcTime) {
                attributed[timeRange].font = .monospacedDigit(.caption)()
            }
            return attributed
        }
        
        // 格式化玩家数，添加千分位
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        numberFormatter.groupingSeparator = ","
        let formattedPlayers = numberFormatter.string(from: NSNumber(value: status.players)) ?? "\(status.players)"
        
        var attributed = AttributedString("\(utcTime) - ")
        // 为时间部分设置等宽字体
        if let timeRange = attributed.range(of: utcTime) {
            attributed[timeRange].font = .monospacedDigit(.caption)()
        }
        
        if status.isOnline {
            var onlineText = AttributedString("Online")
            onlineText.font = .caption.bold()
            onlineText.foregroundColor = Color(red: 0, green: 0.5, blue: 0)
            attributed.append(onlineText)
            
            var playersText = AttributedString(" (\(formattedPlayers) players)")
            // 为玩家数设置等宽字体
            if let playersRange = playersText.range(of: formattedPlayers) {
                playersText[playersRange].font = .monospacedDigit(.caption)()
            }
            attributed.append(playersText)
        } else {
            var offlineText = AttributedString("Offline")
            offlineText.font = .caption.bold()
            offlineText.foregroundColor = .red
            attributed.append(offlineText)
        }
        return attributed
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
                                // 登录后显示联盟和军团信息
                                Text("联盟名称") // 这里替换为实际的联盟名称
                                    .font(.headline)
                                Text("军团名称") // 这里替换为实际的军团名称
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            } else {
                                // 未登录时显示登录提示
                                Text("Tap to Login")
                                    .font(.headline)
                                    .padding(.bottom, 4) // 增加一点底部间距
                            }
                            // 服务器状态始终显示在第三行
                            Text(serverStatusText)
                                .font(.caption)
                                .foregroundColor(.gray)
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
                // 强制刷新服务器状态
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
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            currentTime = Date()
        }
        .task {
            await updateServerStatus()
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
    
    // 添加初始化表格数据的方法
    private func initializeTables() {
        tables = [
            TableNode(
                title: NSLocalizedString("Main_Character", comment: ""),
                rows: [
                    TableRowNode(
                        title: NSLocalizedString("Main_Character Sheet", comment: ""),
                        iconName: "charactersheet",
                        note: NSLocalizedString("Main_Skills Ponits", comment: "")
                    ),
                    TableRowNode(
                        title: NSLocalizedString("Main_Jump Clones", comment: ""),
                        iconName: "jumpclones",
                        note: NSLocalizedString("Main_Jump Clones Available", comment: "")
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
