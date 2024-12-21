import SwiftUI
import SafariServices
import WebKit

struct AccountsView: View {
    @StateObject private var viewModel: EVELoginViewModel
    @State private var showingWebView = false
    @State private var isEditing = false
    @State private var characterToRemove: EVECharacterInfo? = nil
    @State private var forceUpdate: Bool = false
    @State private var isRefreshing = false
    @State private var refreshingCharacters: Set<Int> = []
    @Environment(\.dismiss) private var dismiss
    
    // 添加角色选择回调
    var onCharacterSelect: ((EVECharacterInfo, UIImage?) -> Void)?
    
    init(databaseManager: DatabaseManager = DatabaseManager(), onCharacterSelect: ((EVECharacterInfo, UIImage?) -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: EVELoginViewModel(databaseManager: databaseManager))
        self.onCharacterSelect = onCharacterSelect
    }
    
    // 格式化 ISK 显示
    private func formatISK(_ value: Double) -> String {
        let trillion = 1_000_000_000_000.0
        let billion = 1_000_000_000.0
        let million = 1_000_000.0
        let thousand = 1_000.0
        
        if value >= trillion {
            let formatted = value / trillion
            return String(format: "%.2fT", formatted)
        } else if value >= billion {
            let formatted = value / billion
            return String(format: "%.2fB", formatted)
        } else if value >= million {
            let formatted = value / million
            return String(format: "%.2fM", formatted)
        } else if value >= thousand {
            let formatted = value / thousand
            return String(format: "%.2fK", formatted)
        } else {
            return String(format: "%.2f", value)
        }
    }
    
    var body: some View {
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
                        Text(NSLocalizedString("Account_Add_Character", comment: ""))
                            .foregroundColor(.blue)
                        Spacer()
                    }
                }
            }
            
            // 已登录角色列表
            if !viewModel.characters.isEmpty {
                Section(header: Text(NSLocalizedString("Account_Logged_Characters", comment: ""))) {
                    ForEach(viewModel.characters, id: \.CharacterID) { character in
                        Button(action: {
                            if isEditing {
                                characterToRemove = character
                            } else {
                                onCharacterSelect?(character, viewModel.characterPortraits[character.CharacterID])
                                dismiss()
                            }
                        }) {
                            HStack {
                                if let portrait = viewModel.characterPortraits[character.CharacterID] {
                                    ZStack {
                                        Image(uiImage: portrait)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 64, height: 64)
                                            .clipShape(Circle())
                                        
                                        if refreshingCharacters.contains(character.CharacterID) {
                                            Circle()
                                                .fill(Color.black.opacity(0.6))
                                                .frame(width: 64, height: 64)
                                            
                                            ProgressView()
                                                .scaleEffect(0.8)
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
                                        
                                        if refreshingCharacters.contains(character.CharacterID) {
                                            Circle()
                                                .fill(Color.black.opacity(0.4))
                                                .frame(width: 64, height: 64)
                                            
                                            ProgressView()
                                                .scaleEffect(0.8)
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
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(character.CharacterName)
                                        .font(.headline)
                                        .frame(height: 20)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        if refreshingCharacters.contains(character.CharacterID) {
                                            // 位置信息占位
                                            HStack(spacing: 4) {
                                                Text("0.0")
                                                    .foregroundColor(.gray)
                                                    .redacted(reason: .placeholder)
                                                Text("Loading...")
                                                    .foregroundColor(.gray)
                                                    .redacted(reason: .placeholder)
                                            }
                                            .font(.caption)
                                            
                                            // 钱包信息占位
                                            Text("\(NSLocalizedString("Account_Wallet_value", comment: "")): 0.00 ISK")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                                .redacted(reason: .placeholder)
                                            
                                            // 技能点信息占位
                                            Text("\(NSLocalizedString("Account_Total_SP", comment: "")): 0.0M SP")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                                .redacted(reason: .placeholder)
                                        } else {
                                            // 位置信息
                                            if let location = character.location {
                                                HStack(spacing: 4) {
                                                    Text(formatSecurity(location.security))
                                                        .foregroundColor(getSecurityColor(location.security))
                                                    Text("\(location.systemName) / \(location.regionName)").lineLimit(1)
                                                    if let locationStatus = character.locationStatus?.description {
                                                        Text(locationStatus)
                                                            .foregroundColor(.secondary)
                                                            .lineLimit(1)
                                                    }
                                                }
                                                .font(.caption)
                                            } else {
                                                Text("Unknown Location")
                                                    .font(.caption)
                                                    .foregroundColor(.gray)
                                                    .lineLimit(1)
                                            }
                                            
                                            // 钱包信息
                                            if let balance = character.walletBalance {
                                                Text("\(NSLocalizedString("Account_Wallet_value", comment: "")): \(formatISK(balance)) ISK")
                                                    .font(.caption)
                                                    .foregroundColor(.gray)
                                                    .lineLimit(1)
                                            } else {
                                                Text("\(NSLocalizedString("Account_Wallet_value", comment: "")): -- ISK")
                                                    .font(.caption)
                                                    .foregroundColor(.gray)
                                                    .lineLimit(1)
                                            }
                                            
                                            // 技能点信息
                                            if let totalSP = character.totalSkillPoints {
                                                let spText = if let unallocatedSP = character.unallocatedSkillPoints, unallocatedSP > 0 {
                                                    "\(NSLocalizedString("Account_Total_SP", comment: "")): \(formatSkillPoints(totalSP)) SP (Free: \(formatSkillPoints(unallocatedSP)))"
                                                } else {
                                                    "\(NSLocalizedString("Account_Total_SP", comment: "")): \(formatSkillPoints(totalSP)) SP"
                                                }
                                                Text(spText)
                                                    .font(.caption)
                                                    .foregroundColor(.gray)
                                                    .lineLimit(1)
                                            } else {
                                                Text("\(NSLocalizedString("Account_Total_SP", comment: "")): -- SP")
                                                    .font(.caption)
                                                    .foregroundColor(.gray)
                                                    .lineLimit(1)
                                            }
                                            
                                            // 技能队列信息
                                            if let currentSkill = character.currentSkill {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    // 技能进度条
                                                    GeometryReader { geometry in
                                                        ZStack(alignment: .leading) {
                                                            // 背景
                                                            RoundedRectangle(cornerRadius: 2)
                                                                .fill(Color.gray.opacity(0.3))
                                                                .frame(height: 4)
                                                            
                                                            // 进度
                                                            RoundedRectangle(cornerRadius: 2)
                                                                .fill(currentSkill.remainingTime != nil ? Color.green : Color.gray)
                                                                .frame(width: geometry.size.width * currentSkill.progress, height: 4)
                                                        }
                                                    }
                                                    .frame(height: 4)
                                                    
                                                    // 技能信息
                                                    HStack {
                                                        HStack(spacing: 4) {
                                                            Image(systemName: currentSkill.remainingTime != nil ? "play.fill" : "pause.fill")
                                                                .font(.caption)
                                                                .foregroundColor(currentSkill.remainingTime != nil ? .green : .gray)
                                                            Text("\(currentSkill.name) \(currentSkill.level)")
                                                        }
                                                        .font(.caption)
                                                        .foregroundColor(.gray)
                                                        
                                                        Spacer()
                                                        
                                                        if let remainingTime = currentSkill.remainingTime {
                                                            Text(formatRemainingTime(remainingTime))
                                                                .font(.caption)
                                                                .foregroundColor(.gray)
                                                                .lineLimit(1)
                                                        } else {
                                                            Text("Pause")
                                                                .font(.caption)
                                                                .foregroundColor(.gray)
                                                                .lineLimit(1)
                                                        }
                                                    }
                                                }
                                            } else {
                                                // 没有技能在训练时显示的进度条
                                                GeometryReader { geometry in
                                                    ZStack(alignment: .leading) {
                                                        RoundedRectangle(cornerRadius: 2)
                                                            .fill(Color.gray.opacity(0.3))
                                                            .frame(height: 4)
                                                    }
                                                }
                                                .frame(height: 4)
                                                
                                                Text("-")
                                                    .font(.caption)
                                                    .foregroundColor(.gray)
                                            }
                                        }
                                    }
                                    .frame(height: 72) // 5行文本的固定高度 (18 * n)
                                }
                                .padding(.leading, 4)
                                
                                if isEditing {
                                    Spacer()
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
        .refreshable {
            // 刷新所有角色的ESI信息
            await refreshAllCharacters()
        }
        .navigationTitle(NSLocalizedString("Account_Management", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !viewModel.characters.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        isEditing.toggle()
                    }) {
                        Text(NSLocalizedString(isEditing ? "Main_Market_Done" : "Main_Market_Edit", comment: ""))
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
                Text(NSLocalizedString("Account_Cannot_Get_Auth_URL", comment: ""))
            }
        }
        .alert(NSLocalizedString("Account_Login_Failed", comment: ""), isPresented: Binding(
            get: { viewModel.showingError },
            set: { viewModel.showingError = $0 }
        )) {
            Button(NSLocalizedString("Common_OK", comment: ""), role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage)
        }
        .alert(NSLocalizedString("Account_Remove_Confirm_Title", comment: ""), isPresented: .init(
            get: { characterToRemove != nil },
            set: { if !$0 { characterToRemove = nil } }
        )) {
            Button(NSLocalizedString("Account_Remove_Confirm_Cancel", comment: ""), role: .cancel) {
                characterToRemove = nil
            }
            Button(NSLocalizedString("Account_Remove_Confirm_Remove", comment: ""), role: .destructive) {
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
            forceUpdate.toggle()
            // 重新加载角色列表以更新技能名称
            Task {
                await refreshAllCharacters()
            }
        }
        .id(forceUpdate) // 添加id以强制视图刷新
    }
    
    @MainActor
    private func refreshAllCharacters() async {
        // 先让刷新指示器完成动画
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
        
        isRefreshing = true
        
        // 获取所有保存的角色认证信息
        let characterAuths = EVELogin.shared.loadCharacters()
        
        // 添加一个帮助函数来处理 MainActor.run 的返回值
        @discardableResult
        @Sendable
        func updateUI<T>(_ operation: @MainActor () -> T) async -> T {
            await MainActor.run { operation() }
        }
        
        // 启动后台任务处理数据刷新
        Task {
            await withTaskGroup(of: Void.self) { group in
                for characterAuth in characterAuths {
                    group.addTask {
                        // 添加角色到刷新集合
                        await updateUI {
                            refreshingCharacters.insert(characterAuth.character.CharacterID)
                        }
                        
                        do {
                            // 步骤1: 获取新的访问令牌（串行，必须先执行）
                            let newToken = try await EVELogin.shared.refreshToken(
                                refreshToken: characterAuth.token.refresh_token,
                                force: true
                            )
                            Logger.info("""
                                角色Token已更新:
                                - 角色ID: \(characterAuth.character.CharacterID)
                                - 角色名: \(characterAuth.character.CharacterName)
                                - Token: \(newToken.access_token)
                                - 过期时间: \(newToken.expires_in)秒
                                """)
                            
                            // 并行执行所有更新任务
                            async let portraitTask: Void = {
                                if let portrait = try? await NetworkManager.shared.fetchCharacterPortrait(
                                    characterId: characterAuth.character.CharacterID,
                                    forceRefresh: true
                                ) {
                                    await updateUI {
                                        self.viewModel.characterPortraits[characterAuth.character.CharacterID] = portrait
                                    }
                                }
                            }()
                            
                            async let walletTask: Void = {
                                if let balance = try? await ESIDataManager.shared.getWalletBalance(
                                    characterId: characterAuth.character.CharacterID
                                ) {
                                    await updateUI {
                                        if let index = self.viewModel.characters.firstIndex(where: { $0.CharacterID == characterAuth.character.CharacterID }) {
                                            self.viewModel.characters[index].walletBalance = balance
                                        }
                                    }
                                }
                            }()
                            
                            async let skillsTask: Void = {
                                if let skillsInfo = try? await NetworkManager.shared.fetchCharacterSkills(
                                    characterId: characterAuth.character.CharacterID
                                ) {
                                    await updateUI {
                                        if let index = self.viewModel.characters.firstIndex(where: { $0.CharacterID == characterAuth.character.CharacterID }) {
                                            self.viewModel.characters[index].totalSkillPoints = skillsInfo.total_sp
                                            self.viewModel.characters[index].unallocatedSkillPoints = skillsInfo.unallocated_sp
                                        }
                                    }
                                }
                            }()
                            
                            async let locationTask: Void = {
                                do {
                                    let location = try await NetworkManager.shared.fetchCharacterLocation(
                                        characterId: characterAuth.character.CharacterID
                                    )
                                    
                                    // 获取位置详细信息
                                    let locationInfo = await NetworkManager.shared.getLocationInfo(
                                        solarSystemId: location.solar_system_id,
                                        databaseManager: self.viewModel.databaseManager
                                    )
                                    
                                    await updateUI {
                                        if let index = self.viewModel.characters.firstIndex(where: { $0.CharacterID == characterAuth.character.CharacterID }) {
                                            self.viewModel.characters[index].locationStatus = location.locationStatus
                                            if let locationInfo = locationInfo {
                                                self.viewModel.characters[index].location = locationInfo
                                            }
                                        }
                                    }
                                } catch {
                                    Logger.error("获取位置信息失败: \(error)")
                                }
                            }()
                            
                            async let skillQueueTask: Void = {
                                do {
                                    let queue = try await NetworkManager.shared.fetchSkillQueue(
                                        characterId: characterAuth.character.CharacterID
                                    )
                                    
                                    if let currentSkill = queue.first(where: { $0.isCurrentlyTraining }) {
                                        // 每次显示时重新获取技能名称，确保使用当前语言
                                        if let skillName = await NetworkManager.getSkillName(
                                            skillId: currentSkill.skill_id,
                                            databaseManager: self.viewModel.databaseManager
                                        ) {
                                            await updateUI {
                                                if let index = self.viewModel.characters.firstIndex(where: { $0.CharacterID == characterAuth.character.CharacterID }) {
                                                    self.viewModel.characters[index].currentSkill = EVECharacterInfo.CurrentSkillInfo(
                                                        skillId: currentSkill.skill_id,
                                                        name: skillName,
                                                        level: currentSkill.skillLevel,
                                                        progress: currentSkill.progress,
                                                        remainingTime: currentSkill.remainingTime
                                                    )
                                                }
                                            }
                                        }
                                    } else if let firstSkill = queue.first {
                                        // 如果没有正在训练的技能，但队列中有技能，说明是暂停状态
                                        // 同样每次显示时重新获取技能名称
                                        if let skillName = await NetworkManager.getSkillName(
                                            skillId: firstSkill.skill_id,
                                            databaseManager: self.viewModel.databaseManager
                                        ) {
                                            await updateUI {
                                                if let index = self.viewModel.characters.firstIndex(where: { $0.CharacterID == characterAuth.character.CharacterID }) {
                                                    self.viewModel.characters[index].currentSkill = EVECharacterInfo.CurrentSkillInfo(
                                                        skillId: firstSkill.skill_id,
                                                        name: skillName,
                                                        level: firstSkill.skillLevel,
                                                        progress: firstSkill.progress,
                                                        remainingTime: nil // 暂停状态
                                                    )
                                                }
                                            }
                                        }
                                    }
                                } catch {
                                    Logger.error("获取技能队列失败: \(error)")
                                }
                            }()
                            
                            // 等待所有任务完成
                            await _ = (portraitTask, walletTask, skillsTask, locationTask, skillQueueTask)
                            
                            // 保存最新的角色信息到数据库
                            await updateUI {
                                if let updatedCharacter = self.viewModel.characters.first(where: { $0.CharacterID == characterAuth.character.CharacterID }) {
                                    EVELogin.shared.saveAuthInfo(token: newToken, character: updatedCharacter)
                                }
                            }
                            
                            Logger.info("成功刷新角色信息 - \(characterAuth.character.CharacterName)")
                        } catch {
                            Logger.error("刷新角色信息失败 - \(characterAuth.character.CharacterName): \(error)")
                        }
                        
                        // 从刷新集合中移除角色
                        await updateRefreshingStatus(for: characterAuth.character.CharacterID)
                    }
                }
                
                // 等待所有角色的刷新任务完成
                await group.waitForAll()
            }
            
            // 所有刷新完成后更新登录状态
            await updateUI {
                self.isRefreshing = false
                self.viewModel.isLoggedIn = !self.viewModel.characters.isEmpty
            }
        }
        
        // 快速结束下拉刷新状态
        isRefreshing = false
    }
    
    @MainActor
    private func updateRefreshingStatus(for characterId: Int) {
        refreshingCharacters.remove(characterId)
    }
    
    @MainActor
    private func updatePortrait(characterId: Int, portrait: UIImage) {
        viewModel.characterPortraits[characterId] = portrait
    }
    
    // 格式化技能点显示
    private func formatSkillPoints(_ sp: Int) -> String {
        if sp >= 1_000_000 {
            return String(format: "%.1fM", Double(sp) / 1_000_000.0)
        } else if sp >= 1_000 {
            return String(format: "%.1fK", Double(sp) / 1_000.0)
        }
        return "\(sp)"
    }
    
    // 格式化剩余时间显示
    private func formatRemainingTime(_ seconds: TimeInterval) -> String {
        let days = Int(seconds) / 86400
        let hours = (Int(seconds) % 86400) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        
        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
} 
