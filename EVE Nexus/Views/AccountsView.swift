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
                            if refreshingCharacters.contains(character.CharacterID) {
                                ProgressView()
                                    .frame(width: 64, height: 64)
                            } else if let portrait = viewModel.characterPortraits[character.CharacterID] {
                                Image(uiImage: portrait)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 64, height: 64)
                                    .clipShape(Circle())
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
                                Image(systemName: "person.crop.circle.fill")
                                    .resizable()
                                    .frame(width: 64, height: 64)
                                    .foregroundColor(.gray)
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
                            
                            VStack(alignment: .leading) {
                                Text(character.CharacterName)
                                    .font(.headline)
                                if refreshingCharacters.contains(character.CharacterID) {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .frame(height: 15)
                                } else {
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
                                        .foregroundColor(.gray)
                                    }
                                    if let balance = character.walletBalance {
                                        Text("\(NSLocalizedString("Account_Wallet_value", comment: "")): \(formatISK(balance)) ISK")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                    if let totalSP = character.totalSkillPoints {
                                        let spText = if let unallocatedSP = character.unallocatedSkillPoints, unallocatedSP > 0 {
                                            "\(NSLocalizedString("Account_Total_SP", comment: "")): \(formatSkillPoints(totalSP)) SP (Free: \(formatSkillPoints(unallocatedSP)))"
                                        } else {
                                            "\(NSLocalizedString("Account_Total_SP", comment: "")): \(formatSkillPoints(totalSP)) SP"
                                        }
                                        Text(spText)
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                }
                            }
                            .padding(.leading, 8)
                            
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
                        .padding(.vertical, 8)
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
        defer { isRefreshing = false }
        
        // 获取所有保存的角色认证信息
        let characterAuths = EVELogin.shared.loadCharacters()
        
        // 创建所有刷新任务
        await withTaskGroup(of: Void.self) { group in
            for characterAuth in characterAuths {
                group.addTask {
                    // 添加角色到刷新集合
                    let _ = await MainActor.run {
                        self.refreshingCharacters.insert(characterAuth.character.CharacterID)
                    }
                    
                    do {
                        // 使用刷新令牌获取新的访问令牌
                        let newToken = try await EVELogin.shared.refreshToken(refreshToken: characterAuth.token.refresh_token)
                        
                        // 打印完整的访问令牌
                        Logger.info("角色 \(characterAuth.character.CharacterName) 的访问令牌: \(newToken.access_token)")
                        
                        // 使用新的访问令牌获取最新的角色信息
                        let updatedCharacter = try await EVELogin.shared.getCharacterInfo(token: newToken.access_token)
                        
                        // 获取角色技能信息
                        let skillsInfo = try await NetworkManager.shared.fetchCharacterSkills(
                            characterId: characterAuth.character.CharacterID,
                            token: newToken.access_token
                        )
                        
                        // 获取钱包余额
                        let balance = try await ESIDataManager.shared.getWalletBalance(
                            characterId: characterAuth.character.CharacterID,
                            token: newToken.access_token
                        )
                        
                        // 获取位置信息
                        let location = try await NetworkManager.shared.fetchCharacterLocation(
                            characterId: characterAuth.character.CharacterID,
                            token: newToken.access_token
                        )
                        
                        // 获取位置详细信息
                        let locationInfo = await NetworkManager.shared.getLocationInfo(
                            solarSystemId: location.solar_system_id,
                            databaseManager: viewModel.databaseManager
                        )
                        
                        // 更新角色信息
                        var characterWithInfo = updatedCharacter
                        characterWithInfo.totalSkillPoints = skillsInfo.total_sp
                        characterWithInfo.unallocatedSkillPoints = skillsInfo.unallocated_sp
                        characterWithInfo.walletBalance = balance
                        characterWithInfo.locationStatus = location.locationStatus
                        
                        // 更新位置信息
                        if let locationInfo = locationInfo {
                            characterWithInfo.location = locationInfo
                        }
                        
                        // 保存更新后的认证信息
                        EVELogin.shared.saveAuthInfo(token: newToken, character: characterWithInfo)
                        Logger.info("Refreshed token: \(newToken)")
                        
                        // 强制从网络重新加载头像
                        if let portrait = try? await NetworkManager.shared.fetchCharacterPortrait(
                            characterId: characterAuth.character.CharacterID,
                            forceRefresh: true
                        ) {
                            // 更新头像
                            let _ = await MainActor.run {
                                self.viewModel.characterPortraits[characterAuth.character.CharacterID] = portrait
                            }
                        }
                        
                        Logger.info("成功刷新角色信息 - \(updatedCharacter.CharacterName)")
                    } catch {
                        Logger.error("刷新角色信息失败 - \(characterAuth.character.CharacterName): \(error)")
                    }
                    
                    // 从刷新集合中移除已完成的角色
                    let _ = await MainActor.run {
                        self.refreshingCharacters.remove(characterAuth.character.CharacterID)
                    }
                }
            }
        }
        
        // 更新角色列表
        viewModel.characters = EVELogin.shared.getAllCharacters()
        viewModel.isLoggedIn = !viewModel.characters.isEmpty
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
