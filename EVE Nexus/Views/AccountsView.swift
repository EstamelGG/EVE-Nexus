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
        .alert(NSLocalizedString("Account_Login_Failed", comment: ""), isPresented: $viewModel.showingError) {
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
    
    private func refreshAllCharacters() async {
        isRefreshing = true
        defer { isRefreshing = false }
        
        for character in viewModel.characters {
            do {
                // 获取新的访问令牌
                let token = try await EVELogin.shared.getValidToken()
                // 获取最新的角色信息
                let updatedCharacter = try await EVELogin.shared.getCharacterInfo(token: token)
                // 更新角色信息
                EVELogin.shared.saveAuthInfo(token: EVEAuthToken(
                    access_token: token,
                    expires_in: 1200, // 20分钟
                    token_type: "Bearer",
                    refresh_token: token
                ), character: updatedCharacter)
                
                // 重新加载头像
                await viewModel.loadCharacterPortrait(characterId: character.CharacterID)
            } catch {
                Logger.error("刷新角色信息失败 - \(character.CharacterName): \(error)")
            }
        }
        
        // 重新加载所有角色信息
        viewModel.loadCharacters()
    }
} 