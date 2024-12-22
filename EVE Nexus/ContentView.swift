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
    
    // 添加联盟和军团信息的状态
    @State private var allianceInfo: NetworkManager.AllianceInfo?
    @State private var corporationInfo: NetworkManager.CorporationInfo?
    @State private var allianceLogo: UIImage?
    @State private var corporationLogo: UIImage?
    @State private var tokenExpired: Bool = false
    
    var body: some View {
        HStack(spacing: 15) {
            if let portrait = characterPortrait {
                ZStack {
                    Image(uiImage: portrait)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 64, height: 64)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 2))
                    
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
                .overlay(
                    Circle()
                        .stroke(Color.primary.opacity(0.2), lineWidth: 3)
                )
                .background(
                    Circle()
                        .fill(Color.primary.opacity(0.05))
                )
                .shadow(color: Color.primary.opacity(0.2), radius: 8, x: 0, y: 4)
                .padding(4)
            } else {
                ZStack {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .frame(width: 64, height: 64)
                        .foregroundColor(.gray)
                        
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
                .overlay(
                    Circle()
                        .stroke(Color.primary.opacity(0.2), lineWidth: 3)
                )
                .background(
                    Circle()
                        .fill(Color.primary.opacity(0.05))
                )
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
                        .padding(.bottom, 4)
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
            let publicInfo = try await NetworkManager.shared.fetchCharacterPublicInfo(characterId: character.CharacterID)
            
            // 获取联盟信息
            if let allianceId = publicInfo.alliance_id {
                async let allianceInfoTask = NetworkManager.shared.fetchAllianceInfo(allianceId: allianceId)
                async let allianceLogoTask = NetworkManager.shared.fetchAllianceLogo(allianceID: allianceId)
                
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
            async let corporationInfoTask = NetworkManager.shared.fetchCorporationInfo(corporationId: publicInfo.corporation_id)
            async let corporationLogoTask = NetworkManager.shared.fetchCorporationLogo(corporationId: publicInfo.corporation_id)
            
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
    @State private var forceViewUpdate: Bool = false
    @State private var lastStatusUpdateTime: Date?
    @State private var selectedCharacter: EVECharacterInfo?
    @State private var selectedCharacterPortrait: UIImage?
    @State private var isRefreshing = false
    
    // 添加 UserDefaults 存储的当前角色 ID
    @AppStorage("currentCharacterId") private var currentCharacterId: Int = 0
    
    // 添加更新间隔常量
    private let statusUpdateInterval: TimeInterval = 300 // 5分钟 = 300秒
    
    // 添加预加载状态
    @State private var isDatabasePreloaded = false
    
    // 添加自动刷新的时间间隔常量
    private let characterInfoUpdateInterval: TimeInterval = 300 // 5分钟
    
    // 自定义初始化方法，确保 databaseManager 被正确传递
    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
        _tables = State(initialValue: generateTables())
    }
    
    // 使用 @AppStorage 来读取存储的主题设置
    @AppStorage("selectedTheme") private var selectedTheme: String = "system" // 默认采用系统模式
    
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
    
    // 添加刷新角色信息的方法
    private func refreshCharacterInfo() async {
        guard let character = selectedCharacter else { return }
        
        do {
            // 获取技能信息
            if let skills = try? await NetworkManager.shared.fetchCharacterSkills(
                characterId: character.CharacterID
            ) {
                await MainActor.run {
                    selectedCharacter?.totalSkillPoints = skills.total_sp
                    selectedCharacter?.unallocatedSkillPoints = skills.unallocated_sp
                    // 强制更新表格显示
                    tables = generateTables()
                }
            }
            
            // 获取钱包余额
            if let balance = try? await EVELogin.shared.getCharacterWallet(
                characterId: character.CharacterID
            ) {
                await MainActor.run {
                    selectedCharacter?.walletBalance = balance
                    // 强制更新表格显示
                    tables = generateTables()
                }
            }
            
            // 获取技能队列
            if let queue = try? await NetworkManager.shared.fetchSkillQueue(
                characterId: character.CharacterID
            ) {
                await MainActor.run {
                    // 更新当前技能信息
                    if let currentSkill = queue.first(where: { $0.isCurrentlyTraining }) {
                        if let skillName = NetworkManager.getSkillName(
                            skillId: currentSkill.skill_id,
                            databaseManager: databaseManager
                        ) {
                            selectedCharacter?.currentSkill = EVECharacterInfo.CurrentSkillInfo(
                                skillId: currentSkill.skill_id,
                                name: skillName,
                                level: currentSkill.skillLevel,
                                progress: currentSkill.progress,
                                remainingTime: currentSkill.remainingTime
                            )
                        }
                    } else if let firstSkill = queue.first {
                        if let skillName = NetworkManager.getSkillName(
                            skillId: firstSkill.skill_id,
                            databaseManager: databaseManager
                        ) {
                            selectedCharacter?.currentSkill = EVECharacterInfo.CurrentSkillInfo(
                                skillId: firstSkill.skill_id,
                                name: skillName,
                                level: firstSkill.skillLevel,
                                progress: firstSkill.progress,
                                remainingTime: nil
                            )
                        }
                    }
                    // 强制更新表格显示
                    tables = generateTables()
                }
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                // 登录按钮
                Section {
                    NavigationLink {
                        AccountsView(databaseManager: databaseManager) { character, portrait in
                            selectedCharacter = character
                            selectedCharacterPortrait = portrait
                            // 保存当前选中的角色 ID
                            currentCharacterId = character.CharacterID
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
                isRefreshing = true
                // 刷新服务器状态
                do {
                    serverStatus = try await NetworkManager.shared.fetchServerStatus()
                    lastStatusUpdateTime = Date()
                } catch {
                    Logger.error("Failed to refresh server status: \(error)")
                }
                
                // 如果有选中的角色，刷新角色信息
                if let character = selectedCharacter {
                    do {
                        // 强制刷新角色公开信息
                        let publicInfo = try await NetworkManager.shared.fetchCharacterPublicInfo(
                            characterId: character.CharacterID,
                            forceRefresh: true
                        )
                        
                        // 强制刷新角色头像
                        if let portrait = try? await NetworkManager.shared.fetchCharacterPortrait(
                            characterId: character.CharacterID,
                            forceRefresh: true
                        ) {
                            await MainActor.run {
                                selectedCharacterPortrait = portrait
                                Logger.info("成功刷新角色头像")
                            }
                        }
                        
                        // 获取联盟信息
                        if let allianceId = publicInfo.alliance_id {
                            async let allianceInfoTask = NetworkManager.shared.fetchAllianceInfo(
                                allianceId: allianceId,
                                forceRefresh: true
                            )
                            async let allianceLogoTask = NetworkManager.shared.fetchAllianceLogo(
                                allianceID: allianceId
                            )
                            
                            do {
                                let (_, _) = try await (allianceInfoTask, allianceLogoTask)
                                Logger.info("成功刷新联盟信息和图标")
                            } catch {
                                Logger.error("刷新联盟信息失败: \(error)")
                            }
                        }
                        
                        // 获取军团信息
                        do {
                            async let corporationInfoTask = NetworkManager.shared.fetchCorporationInfo(
                                corporationId: publicInfo.corporation_id,
                                forceRefresh: true
                            )
                            async let corporationLogoTask = NetworkManager.shared.fetchCorporationLogo(
                                corporationId: publicInfo.corporation_id
                            )
                            
                            let (_, _) = try await (corporationInfoTask, corporationLogoTask)
                            Logger.info("成功刷新军团信息和图标")
                        } catch {
                            Logger.error("刷新军团信息失败: \(error)")
                        }
                        
                        Logger.info("成功完成所有信息刷新")
                    } catch {
                        Logger.error("刷新角色信息失败: \(error)")
                    }
                }
                isRefreshing = false
            }
            .navigationTitle(NSLocalizedString("Main_Title", comment: ""))
            .toolbar {
                if selectedCharacter != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            selectedCharacter = nil
                            selectedCharacterPortrait = nil
                            // 清除当前角色 ID
                            currentCharacterId = 0
                        }) {
                            Text(NSLocalizedString("Account_Logout", comment: ""))
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .onAppear {
                // 检查选中的角色是否还存在，并加载保存的角色信息
                loadSavedCharacter()
                
                // 如果有选中的角色，开始自动刷新任务
                if selectedCharacter != nil {
                    Task {
                        while !Task.isCancelled {
                            await refreshCharacterInfo()
                            try? await Task.sleep(nanoseconds: UInt64(characterInfoUpdateInterval) * 1_000_000_000)
                        }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CharacterRemoved"))) { notification in
                if let removedCharacterId = notification.userInfo?["characterId"] as? Int {
                    if selectedCharacter?.CharacterID == removedCharacterId {
                        selectedCharacter = nil
                        selectedCharacterPortrait = nil
                        // 如果删除的是当前角色，清除当前角色 ID
                        if currentCharacterId == removedCharacterId {
                            currentCharacterId = 0
                        }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CharacterTokenStatusChanged"))) { notification in
                if let characterId = notification.userInfo?["characterId"] as? Int,
                   let tokenExpired = notification.userInfo?["tokenExpired"] as? Bool,
                   characterId == selectedCharacter?.CharacterID {
                    // 如果是当前选中的角色，更新其状态
                    var updatedCharacter = selectedCharacter
                    updatedCharacter?.tokenExpired = tokenExpired
                    selectedCharacter = updatedCharacter
                }
            }
        }
        .preferredColorScheme(selectedTheme == "light" ? .light : (selectedTheme == "dark" ? .dark : nil))
        .id(forceViewUpdate)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("LanguageChanged"))) { _ in
            forceViewUpdate.toggle()
            initializeTables()
        }
        .task {
            async let statusTask: Void = updateServerStatus()
            async let preloadTask: Void = preloadDatabaseIfNeeded()
            _ = await (statusTask, preloadTask)
        }
    }
    
    private func updateServerStatus() async {
        // 检查是否需要更新
        if let lastUpdate = lastStatusUpdateTime,
           Date().timeIntervalSince(lastUpdate) < statusUpdateInterval {
            Logger.info("Server status was updated less than 5 minutes ago, skipping update")
            isLoadingStatus = false
            return
        }
        
        do {
            serverStatus = try await NetworkManager.shared.fetchServerStatus()
            await MainActor.run {
                lastStatusUpdateTime = Date()
            }
        } catch {
            Logger.error("Failed to fetch server status: \(error)")
        }
        isLoadingStatus = false
        
        // 等待5分钟后再次更新
        try? await Task.sleep(nanoseconds: UInt64(statusUpdateInterval) * 1_000_000_000)
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
        // 格式化技能点显示
        let spText = if let character = selectedCharacter,
                       let totalSP = character.totalSkillPoints {
            NSLocalizedString("Main_Skills_Ponits", comment: "")
                .replacingOccurrences(of: "$num", with: NumberFormatUtil.format(Double(totalSP)))
        } else {
            NSLocalizedString("Main_Skills_Ponits", comment: "")
                .replacingOccurrences(of: "$num", with: "--")
        }
        
        // 格式化技能队列显示
        let skillQueueText: String
        if let character = selectedCharacter,
           let currentSkill = character.currentSkill {
            if let remainingTime = currentSkill.remainingTime {
                let days = Int(remainingTime) / 86400
                let hours = (Int(remainingTime) % 86400) / 3600
                let minutes = (Int(remainingTime) % 3600) / 60
                skillQueueText = NSLocalizedString("Main_Skills_Queue", comment: "")
                    .replacingOccurrences(of: "$num", with: "1")
                    .replacingOccurrences(of: "$day", with: "\(days)")
                    .replacingOccurrences(of: "$hour", with: "\(hours)")
                    .replacingOccurrences(of: "$minutes", with: "\(minutes)")
            } else {
                skillQueueText = NSLocalizedString("Main_Skills_Queue", comment: "")
                    .replacingOccurrences(of: "$num", with: "1")
                    .replacingOccurrences(of: "$day", with: "0")
                    .replacingOccurrences(of: "$hour", with: "0")
                    .replacingOccurrences(of: "$minutes", with: "0")
            }
        } else {
            skillQueueText = NSLocalizedString("Main_Skills_Queue", comment: "")
                .replacingOccurrences(of: "$num", with: "0")
                .replacingOccurrences(of: "$day", with: "0")
                .replacingOccurrences(of: "$hour", with: "0")
                .replacingOccurrences(of: "$minutes", with: "0")
        }
        
        // 格式化钱包余额显示
        let iskText = if let character = selectedCharacter,
                       let balance = character.walletBalance {
            NSLocalizedString("Main_Wealth_ISK", comment: "")
                .replacingOccurrences(of: "$num", with: NumberFormatUtil.format(Double(balance)))
        } else {
            NSLocalizedString("Main_Wealth_ISK", comment: "")
                .replacingOccurrences(of: "$num", with: "--")
        }
        
        return [
            TableNode(
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
    
    // 添加格式化技能点的辅助方法
    private func formatSkillPoints(_ sp: Int) -> String {
        if sp >= 1_000_000 {
            return String(format: "%.1fM", Double(sp) / 1_000_000.0)
        } else if sp >= 1_000 {
            return String(format: "%.1fK", Double(sp) / 1_000.0)
        }
        return "\(sp)"
    }
    
    // 添加格式化 ISK 的辅助方法
    private func formatISK(_ isk: Double) -> String {
        if isk >= 1_000_000_000 {
            return String(format: "%.1fB", isk / 1_000_000_000.0)
        } else if isk >= 1_000_000 {
            return String(format: "%.1fM", isk / 1_000_000.0)
        } else if isk >= 1_000 {
            return String(format: "%.1fK", isk / 1_000.0)
        }
        return String(format: "%.0f", isk)
    }
    
    // 添加加载保存的角色信息的方法
    private func loadSavedCharacter() {
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
                
                // 异步加载头像
                Task {
                    if let portrait = try? await NetworkManager.shared.fetchCharacterPortrait(
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
}

#Preview {
    ContentView(databaseManager: DatabaseManager()) // 确保传递数据库管理器
}
