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
    
    init(databaseManager: DatabaseManager = DatabaseManager()) {
        _viewModel = StateObject(wrappedValue: EVELoginViewModel(databaseManager: databaseManager))
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
                                                Text("\(location.systemName) / \(location.regionName)")
                                                if let locationStatus = character.locationStatus?.description {
                                                    Text(locationStatus)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                            .font(.caption)
                                        } else {
                                            Text("Unknown Location")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                        }
                                        
                                        // 钱包信息
                                        if let balance = character.walletBalance {
                                            Text("\(NSLocalizedString("Account_Wallet_value", comment: "")): \(formatISK(balance)) ISK")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                        } else {
                                            Text("\(NSLocalizedString("Account_Wallet_value", comment: "")): -- ISK")
                                                .font(.caption)
                                                .foregroundColor(.gray)
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
                                        } else {
                                            Text("\(NSLocalizedString("Account_Total_SP", comment: "")): -- SP")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                        }
                                    }
                                }
                                .frame(height: 54) // 3行文本的固定高度 (18 * 3)
                            }
                            .padding(.leading, 4)
                            
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
                        //.frame(height: 64)
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
                            self.refreshingCharacters.insert(characterAuth.character.CharacterID)
                        }
                        
                        do {
                            // 步骤1: 获取新的访问令牌（串行，必须先执行）
                            let newToken = try await EVELogin.shared.refreshToken(refreshToken: characterAuth.token.refresh_token)
                            Logger.info("角色 \(characterAuth.character.CharacterName) 的访问令牌: \(newToken.access_token)")
                            
                            // 步骤2: 获取基础角色信息（串行，依赖token）
                            let characterWithInfo = try await EVELogin.shared.getCharacterInfo(token: newToken.access_token)
                            
                            // 保存基础信息并更新UI
                            await updateUI {
                                // 更新基础信息到viewModel中对应的角色
                                if let index = self.viewModel.characters.firstIndex(where: { $0.CharacterID == characterAuth.character.CharacterID }) {
                                    self.viewModel.characters[index] = characterWithInfo
                                }
                            }
                            
                            // 并行执行所有更新任务
                            let portraitTask = Task<Void, Never> {
                                if let portrait = try? await NetworkManager.shared.fetchCharacterPortrait(
                                    characterId: characterAuth.character.CharacterID,
                                    forceRefresh: true
                                ) {
                                    await updateUI {
                                        self.viewModel.characterPortraits[characterAuth.character.CharacterID] = portrait
                                    }
                                }
                            }
                            
                            let walletTask = Task<Void, Never> {
                                if let balance = try? await ESIDataManager.shared.getWalletBalance(
                                    characterId: characterAuth.character.CharacterID
                                ) {
                                    await updateUI {
                                        if let index = self.viewModel.characters.firstIndex(where: { $0.CharacterID == characterAuth.character.CharacterID }) {
                                            self.viewModel.characters[index].walletBalance = balance
                                        }
                                    }
                                }
                            }
                            
                            let skillsTask = Task<Void, Never> {
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
                            }
                            
                            let locationTask = Task<Void, Never> {
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
                            }
                            
                            // 等待所有任务完成
                            try? await withThrowingTaskGroup(of: Void.self) { group in
                                group.addTask { await portraitTask.value }
                                group.addTask { await walletTask.value }
                                group.addTask { await skillsTask.value }
                                group.addTask { await locationTask.value }
                                try await group.waitForAll()
                            }
                            
                            // 保存最新的角色信息到数据库
                            await updateUI {
                                if let updatedCharacter = self.viewModel.characters.first(where: { $0.CharacterID == characterAuth.character.CharacterID }) {
                                    EVELogin.shared.saveAuthInfo(token: newToken, character: updatedCharacter)
                                }
                            }
                            
                            Logger.info("成功刷新角色信息 - \(characterWithInfo.CharacterName)")
                        } catch {
                            Logger.error("刷新角色信息失败 - \(characterAuth.character.CharacterName): \(error)")
                        }
                        
                        // 从刷新集合中移除已完成的角色
                        await updateUI {
                            self.refreshingCharacters.remove(characterAuth.character.CharacterID)
                        }
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
} 
