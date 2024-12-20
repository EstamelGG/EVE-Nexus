import SwiftUI
import SafariServices
import WebKit

struct AccountsView: View {
    @StateObject private var viewModel = EVELoginViewModel()
    @State private var showingWebView = false
    @State private var isEditing = false
    @State private var characterToRemove: EVECharacterInfo? = nil
    @State private var forceUpdate: Bool = false
    @State private var isRefreshing = false
    @State private var refreshingCharacters: Set<Int> = []
    
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
                                    .frame(width: 64, height: 64)
                                    .clipShape(Circle())
                            } else {
                                Image(systemName: "person.crop.circle.fill")
                                    .resizable()
                                    .frame(width: 64, height: 64)
                                    .foregroundColor(.gray)
                            }
                            
                            VStack(alignment: .leading) {
                                Text(character.CharacterName)
                                    .font(.headline)
                                Text("\(NSLocalizedString("Account_Character_ID", comment: "")): \(character.CharacterID)")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                if let totalSP = character.totalSkillPoints {
                                    Text("\(NSLocalizedString("Account_Total_SP", comment: "")): \(formatSkillPoints(totalSP))")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                if let unallocatedSP = character.unallocatedSkillPoints, unallocatedSP > 0 {
                                    Text("\(NSLocalizedString("Account_Unallocated_SP", comment: "")): \(formatSkillPoints(unallocatedSP))")
                                        .font(.caption)
                                        .foregroundColor(.blue)
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
        isRefreshing = true
        defer { isRefreshing = false }
        
        // 获取所有保存的角色认证信息
        let characterAuths = EVELogin.shared.loadCharacters()
        
        // 添加所有角色到刷新集合
        refreshingCharacters = Set(characterAuths.map { $0.character.CharacterID })
        
        // 创建所有刷新任务
        await withTaskGroup(of: Void.self) { group in
            for characterAuth in characterAuths {
                group.addTask {
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
                        
                        // 更新角色的技能点信息
                        var characterWithSkills = updatedCharacter
                        characterWithSkills.totalSkillPoints = skillsInfo.total_sp
                        characterWithSkills.unallocatedSkillPoints = skillsInfo.unallocated_sp
                        
                        // 保存更新后的认证信息
                        EVELogin.shared.saveAuthInfo(token: newToken, character: characterWithSkills)
                        
                        // 强制从网络重新加载头像
                        if let portrait = try? await NetworkManager.shared.fetchCharacterPortrait(
                            characterId: characterAuth.character.CharacterID,
                            forceRefresh: true
                        ) {
                            // 更新头像
                            await updatePortrait(characterId: characterAuth.character.CharacterID, portrait: portrait)
                        }
                        
                        // 从刷新集合中移除已完成的角色
                        await updateRefreshingStatus(for: characterAuth.character.CharacterID)
                        
                        Logger.info("成功刷新角色信息 - \(updatedCharacter.CharacterName)")
                    } catch {
                        Logger.error("刷新角色信息失败 - \(characterAuth.character.CharacterName): \(error)")
                        // 如果刷新失败，也要从刷新集合中移除
                        await updateRefreshingStatus(for: characterAuth.character.CharacterID)
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