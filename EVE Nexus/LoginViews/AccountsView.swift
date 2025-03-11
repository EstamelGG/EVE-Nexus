import SafariServices
import SwiftUI
import WebKit

struct AccountsView: View {
    @StateObject private var viewModel: EVELoginViewModel
    let mainViewModel: MainViewModel
    @State private var showingWebView = false
    @State private var isEditing = false
    @State private var characterToRemove: EVECharacterInfo? = nil
    @State private var forceUpdate: Bool = false
    @State private var isRefreshing = false
    @State private var refreshingCharacters: Set<Int> = []
    @State private var expiredTokenCharacters: Set<Int> = []
    @State private var isLoggingIn = false
    @State private var isRefreshingScopes = false
    @Binding var selectedItem: String?
    @State private var successMessage: String = ""
    @State private var showingSuccess: Bool = false

    // 添加角色选择回调
    var onCharacterSelect: ((EVECharacterInfo, UIImage?) -> Void)?

    init(
        databaseManager: DatabaseManager = DatabaseManager(),
        mainViewModel: MainViewModel,
        selectedItem: Binding<String?>,
        onCharacterSelect: ((EVECharacterInfo, UIImage?) -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: EVELoginViewModel(databaseManager: databaseManager))
        self.mainViewModel = mainViewModel
        _selectedItem = selectedItem
        self.onCharacterSelect = onCharacterSelect
    }

    var body: some View {
        List {
            // 添加新角色按钮
            Section {
                Button(action: {
                    Task { @MainActor in
                        // 设置登录状态为true
                        isLoggingIn = true
                        
                        // 检查并更新scopes（如果需要）
                        await checkAndUpdateScopesIfNeeded()

                        guard
                            let scene = UIApplication.shared.connectedScenes.first
                                as? UIWindowScene,
                            let viewController = scene.windows.first?.rootViewController
                        else {
                            isLoggingIn = false  // 确保在失败时重置状态
                            return
                        }

                        do {
                            // 尝试使用当前配置的 scopes 进行登录
                            let authState = try await AuthTokenManager.shared.authorize(
                                presenting: viewController,
                                scopes: EVELogin.shared.config?.scopes ?? []
                            )

                            // 获取角色信息
                            let character = try await EVELogin.shared.processLogin(
                                authState: authState
                            )

                            // 获取并保存角色公开信息到数据库
                            let publicInfo = try await CharacterAPI.shared.fetchCharacterPublicInfo(
                                characterId: character.CharacterID,
                                forceRefresh: true
                            )
                            Logger.info("成功获取并保存角色公开信息 - 角色: \(publicInfo.name)")

                            // UI 更新已经在 MainActor 上下文中
                            viewModel.characterInfo = character
                            viewModel.isLoggedIn = true
                            viewModel.loadCharacters()

                            // 加载新角色的头像
                            await viewModel.loadCharacterPortrait(
                                characterId: character.CharacterID)

                            // 加载技能队列信息
                            await updateCharacterSkillQueue(character: character)

                            // 保存更新后的角色信息到UserDefaults
                            if let index = await MainActor.run(body: {
                                self.viewModel.characters.firstIndex(where: {
                                    $0.CharacterID == character.CharacterID
                                })
                            }) {
                                let updatedCharacter = await MainActor.run {
                                    self.viewModel.characters[index]
                                }
                                do {
                                    // 获取 access token
                                    let accessToken = try await AuthTokenManager.shared
                                        .getAccessToken(for: updatedCharacter.CharacterID)
                                    // 创建 EVEAuthToken 对象
                                    let token = try EVEAuthToken(
                                        access_token: accessToken,
                                        expires_in: 1200,  // 20分钟过期
                                        token_type: "Bearer",
                                        refresh_token: SecureStorage.shared.loadToken(
                                            for: updatedCharacter.CharacterID) ?? ""
                                    )
                                    // 保存认证信息
                                    try await EVELogin.shared.saveAuthInfo(
                                        token: token,
                                        character: updatedCharacter
                                    )
                                    Logger.info("已保存更新后的角色信息 - \(updatedCharacter.CharacterName)")

                                    // 立即刷新该角色的所有数据
                                    await refreshCharacterData(updatedCharacter)
                                } catch {
                                    Logger.error("保存认证信息失败: \(error)")
                                }
                            }

                            Logger.info(
                                "成功刷新角色信息(\(character.CharacterID)) - \(character.CharacterName)")
                        } catch {
                            // 检查是否是 scope 无效错误
                            if error.localizedDescription.lowercased().contains("invalid_scope") {
                                Logger.info("检测到无效权限，尝试重新获取最新的 scopes")
                                // 强制刷新获取最新的 scopes
                                let scopes = await ScopeManager.shared.getScopes(forceRefresh: true)

                                do {
                                    // 使用新的 scopes 重试登录
                                    let authState = try await AuthTokenManager.shared.authorize(
                                        presenting: viewController,
                                        scopes: scopes
                                    )

                                    // 获取角色信息
                                    let character = try await EVELogin.shared.processLogin(
                                        authState: authState
                                    )

                                    // 获取并保存角色公开信息到数据库
                                    let publicInfo = try await CharacterAPI.shared
                                        .fetchCharacterPublicInfo(
                                            characterId: character.CharacterID,
                                            forceRefresh: true
                                        )
                                    Logger.info("成功获取并保存角色公开信息 - 角色: \(publicInfo.name)")

                                    // UI 更新已经在 MainActor 上下文中
                                    viewModel.characterInfo = character
                                    viewModel.isLoggedIn = true
                                    viewModel.loadCharacters()

                                    // 加载新角色的头像
                                    await viewModel.loadCharacterPortrait(
                                        characterId: character.CharacterID)

                                    // 加载技能队列信息
                                    await updateCharacterSkillQueue(character: character)

                                    // 保存更新后的角色信息到UserDefaults
                                    if let index = await MainActor.run(body: {
                                        self.viewModel.characters.firstIndex(where: {
                                            $0.CharacterID == character.CharacterID
                                        })
                                    }) {
                                        let updatedCharacter = await MainActor.run {
                                            self.viewModel.characters[index]
                                        }
                                        do {
                                            // 获取 access token
                                            let accessToken = try await AuthTokenManager.shared
                                                .getAccessToken(for: updatedCharacter.CharacterID)
                                            // 创建 EVEAuthToken 对象
                                            let token = try EVEAuthToken(
                                                access_token: accessToken,
                                                expires_in: 1200,  // 20分钟过期
                                                token_type: "Bearer",
                                                refresh_token: SecureStorage.shared.loadToken(
                                                    for: updatedCharacter.CharacterID) ?? ""
                                            )
                                            // 保存认证信息
                                            try await EVELogin.shared.saveAuthInfo(
                                                token: token,
                                                character: updatedCharacter
                                            )
                                            Logger.info(
                                                "已保存更新后的角色信息 - \(updatedCharacter.CharacterName)")

                                            // 立即刷新该角色的所有数据
                                            await refreshCharacterData(updatedCharacter)
                                        } catch {
                                            Logger.error("保存认证信息失败: \(error)")
                                        }
                                    }

                                    Logger.info(
                                        "成功刷新角色信息(\(character.CharacterID)) - \(character.CharacterName)"
                                    )
                                } catch {
                                    viewModel.errorMessage =
                                        "登录失败，请稍后重试：\(error.localizedDescription)"
                                    viewModel.showingError = true
                                    Logger.error("使用更新后的权限登录仍然失败: \(error)")
                                }
                            } else {
                                viewModel.errorMessage = error.localizedDescription
                                viewModel.showingError = true
                                Logger.error("登录失败: \(error)")
                            }
                        }

                        // 确保在最后重置登录状态
                        isLoggingIn = false
                    }
                }) {
                    HStack {
                        if isLoggingIn {
                            ProgressView()
                                .scaleEffect(0.8)
                                .padding(.trailing, 5)
                        } else {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.blue)
                        }
                        Text(
                            NSLocalizedString(
                                isLoggingIn ? "Account_Logging_In" : "Account_Add_Character",
                                comment: ""
                            )
                        )
                        .foregroundColor(isEditing ? .primary : .blue)
                        Spacer()
                    }
                }
                .disabled(isLoggingIn)
            } footer: {
                HStack {
                    Text(NSLocalizedString("Scopes_refresh_hint", comment: ""))
                    Button(action: {
                        // 添加刷新状态指示
                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                        impactFeedback.impactOccurred()
                        
                        // 设置刷新状态
                        isRefreshingScopes = true
                        
                        Task {
                            // 强制刷新 scopes
                            Logger.info("手动强制刷新 scopes")
                            let _ = await ScopeManager.shared.getScopes(forceRefresh: true)
                            
                            // 更新 EVELogin 中的 scopes 配置
                            let scopes = await EVELogin.shared.getScopes()
                            Logger.info("成功刷新 scopes，获取到 \(scopes.count) 个权限")
                            
                            // 显示成功提示
                            await MainActor.run {
                                isRefreshingScopes = false  // 重置刷新状态
                                successMessage = "成功刷新 scopes，获取到 \(scopes.count) 个权限"
                                showingSuccess = true
                            }
                        }
                    }) {
                        HStack {
                            if isRefreshingScopes {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .padding(.trailing, 2)
                            }
                            Text("scopes")
                                .foregroundColor(.blue)
                        }
                    }
                    .disabled(isRefreshingScopes)
                    Text(".")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 4)
            }

            // 已登录角色列表
            if !viewModel.characters.isEmpty {
                Section(
                    header: Text(
                        "\(NSLocalizedString("Account_Logged_Characters", comment: "")) (\(viewModel.characters.count))"
                    )
                ) {
                    if isEditing {
                        ForEach(viewModel.characters, id: \.CharacterID) { character in
                            Button(action: {
                                characterToRemove = character
                            }) {
                                CharacterRowView(
                                    character: character,
                                    portrait: viewModel.characterPortraits[character.CharacterID],
                                    isRefreshing: refreshingCharacters.contains(
                                        character.CharacterID),
                                    isEditing: isEditing,
                                    tokenExpired: expiredTokenCharacters.contains(
                                        character.CharacterID),
                                    formatISK: FormatUtil.formatISK,
                                    formatSkillPoints: formatSkillPoints,
                                    formatRemainingTime: formatRemainingTime
                                )
                            }
                            .foregroundColor(.primary)
                        }
                        .onMove { from, to in
                            viewModel.moveCharacter(from: from, to: to)
                        }
                    } else {
                        ForEach(viewModel.characters, id: \.CharacterID) { character in
                            Button {
                                // 复用已加载的数据
                                let portrait = viewModel.characterPortraits[character.CharacterID]
                                // 保存当前角色的最新状态到 EVELogin
                                Task {
                                    do {
                                        // 获取 access token
                                        let accessToken = try await AuthTokenManager.shared
                                            .getAccessToken(for: character.CharacterID)
                                        // 创建 EVEAuthToken 对象
                                        let token = try EVEAuthToken(
                                            access_token: accessToken,
                                            expires_in: 1200,  // 20分钟过期
                                            token_type: "Bearer",
                                            refresh_token: SecureStorage.shared.loadToken(
                                                for: character.CharacterID) ?? ""
                                        )
                                        // 保存认证信息
                                        try await EVELogin.shared.saveAuthInfo(
                                            token: token,
                                            character: character
                                        )
                                    } catch {
                                        Logger.error("保存认证信息失败: \(error)")
                                    }
                                }
                                onCharacterSelect?(character, portrait)
                                selectedItem = nil
                            } label: {
                                CharacterRowView(
                                    character: character,
                                    portrait: viewModel.characterPortraits[character.CharacterID],
                                    isRefreshing: refreshingCharacters.contains(
                                        character.CharacterID),
                                    isEditing: isEditing,
                                    tokenExpired: expiredTokenCharacters.contains(
                                        character.CharacterID),
                                    formatISK: FormatUtil.formatISK,
                                    formatSkillPoints: formatSkillPoints,
                                    formatRemainingTime: formatRemainingTime
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
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
                        Text(
                            NSLocalizedString(
                                isEditing ? "Main_Market_Done" : "Main_Market_Edit", comment: ""
                            )
                        )
                        .foregroundColor(.blue)
                    }
                }
            }
        }
        .alert(
            NSLocalizedString("Account_Login_Failed", comment: ""),
            isPresented: Binding(
                get: { viewModel.showingError },
                set: { viewModel.showingError = $0 }
            )
        ) {
            Button(NSLocalizedString("Common_OK", comment: ""), role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
        .alert(
            NSLocalizedString("操作成功", comment: ""),
            isPresented: $showingSuccess
        ) {
            Button(NSLocalizedString("Common_OK", comment: ""), role: .cancel) {}
        } message: {
            Text(successMessage)
        }
        .alert(
            NSLocalizedString("Account_Remove_Confirm_Title", comment: ""),
            isPresented: .init(
                get: { characterToRemove != nil },
                set: { if !$0 { characterToRemove = nil } }
            )
        ) {
            Button(NSLocalizedString("Account_Remove_Confirm_Cancel", comment: ""), role: .cancel) {
                characterToRemove = nil
            }
            Button(
                NSLocalizedString("Account_Remove_Confirm_Remove", comment: ""), role: .destructive
            ) {
                if let character = characterToRemove {
                    viewModel.removeCharacter(character)
                    // 发送通知，通知其他视图角色已被删除
                    NotificationCenter.default.post(
                        name: Notification.Name("CharacterRemoved"),
                        object: nil,
                        userInfo: ["characterId": character.CharacterID]
                    )
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
            // 初始化过期token状态
            let characterAuths = EVELogin.shared.loadCharacters()

            // 从缓存更新所有角色的数据
            Task { @MainActor in
                // 创建一个结构体来存储每个角色的所有数据
                struct CharacterCachedData {
                    let characterId: Int
                    let walletBalance: Double?
                    let skillsInfo: CharacterSkillsResponse?
                    let queue: [SkillQueueItem]?
                    let location: CharacterLocation?
                    let solarSystemInfo: SolarSystemInfo?
                    let portrait: UIImage?
                    let tokenExpired: Bool
                }
                
                // 使用TaskGroup并行获取所有角色的缓存数据
                var characterDataResults: [CharacterCachedData] = []
                
                await withTaskGroup(of: CharacterCachedData.self) { group in
                    for auth in characterAuths {
                        let characterId = auth.character.CharacterID
                        let tokenExpired = auth.character.tokenExpired
                        
                        group.addTask {
                            // 尝试从缓存获取钱包余额
                            let cachedBalanceStr = await CharacterWalletAPI.shared.getCachedWalletBalance(
                                characterId: characterId)
                            let balance = Double(cachedBalanceStr)
                            
                            // 尝试从缓存获取技能点数据
                            var skillsInfo: CharacterSkillsResponse? = nil
                            do {
                                skillsInfo = try await CharacterSkillsAPI.shared.fetchCharacterSkills(
                                    characterId: characterId,
                                    forceRefresh: false
                                )
                            } catch {
                                // 忽略错误，保持为nil
                            }
                            
                            // 尝试从缓存获取技能队列
                            var queue: [SkillQueueItem]? = nil
                            do {
                                queue = try await CharacterSkillsAPI.shared.fetchSkillQueue(
                                    characterId: characterId,
                                    forceRefresh: false
                                )
                            } catch {
                                // 忽略错误，保持为nil
                            }
                            
                            // 尝试从缓存获取位置信息
                            var location: CharacterLocation? = nil
                            var solarSystemInfo: SolarSystemInfo? = nil
                            do {
                                location = try await CharacterLocationAPI.shared.fetchCharacterLocation(
                                    characterId: characterId,
                                    forceRefresh: false
                                )
                                
                                if let loc = location {
                                    solarSystemInfo = await getSolarSystemInfo(
                                        solarSystemId: loc.solar_system_id,
                                        databaseManager: CharacterDataService.shared.databaseManager
                                    )
                                }
                            } catch {
                                // 忽略错误，保持为nil
                            }
                            
                            // 尝试从缓存获取头像
                            var portrait: UIImage? = nil
                            do {
                                portrait = try await CharacterAPI.shared.fetchCharacterPortrait(
                                    characterId: characterId,
                                    forceRefresh: false
                                )
                            } catch {
                                // 忽略错误，保持为nil
                            }
                            
                            return CharacterCachedData(
                                characterId: characterId,
                                walletBalance: balance,
                                skillsInfo: skillsInfo,
                                queue: queue,
                                location: location,
                                solarSystemInfo: solarSystemInfo,
                                portrait: portrait,
                                tokenExpired: tokenExpired
                            )
                        }
                    }
                    
                    // 收集所有结果
                    for await data in group {
                        characterDataResults.append(data)
                    }
                }
                
                // 所有数据都已获取完成，一次性更新UI
                for data in characterDataResults {
                    // 更新过期token状态
                    if data.tokenExpired {
                        expiredTokenCharacters.insert(data.characterId)
                    }
                    
                    if let index = viewModel.characters.firstIndex(where: { $0.CharacterID == data.characterId }) {
                        // 更新钱包余额
                        if let balance = data.walletBalance {
                            viewModel.characters[index].walletBalance = balance
                        }
                        
                        // 更新技能信息
                        if let skillsInfo = data.skillsInfo {
                            viewModel.characters[index].totalSkillPoints = skillsInfo.total_sp
                            viewModel.characters[index].unallocatedSkillPoints = skillsInfo.unallocated_sp
                        }
                        
                        // 更新技能队列
                        if let queue = data.queue {
                            viewModel.characters[index].skillQueueLength = queue.count
                            if let currentSkill = queue.first(where: { $0.isCurrentlyTraining }) {
                                if let skillName = SkillTreeManager.shared.getSkillName(for: currentSkill.skill_id) {
                                    viewModel.characters[index].currentSkill = EVECharacterInfo.CurrentSkillInfo(
                                        skillId: currentSkill.skill_id,
                                        name: skillName,
                                        level: currentSkill.skillLevel,
                                        progress: currentSkill.progress,
                                        remainingTime: currentSkill.remainingTime
                                    )
                                }
                            } else if let firstSkill = queue.first,
                                let skillName = SkillTreeManager.shared.getSkillName(for: firstSkill.skill_id),
                                let trainingStartSp = firstSkill.training_start_sp,
                                let levelEndSp = firstSkill.level_end_sp
                            {
                                // 计算暂停技能的实际进度
                                let calculatedProgress = SkillProgressCalculator.calculateProgress(
                                    trainingStartSp: trainingStartSp,
                                    levelEndSp: levelEndSp,
                                    finishedLevel: firstSkill.finished_level
                                )
                                viewModel.characters[index].currentSkill = EVECharacterInfo.CurrentSkillInfo(
                                    skillId: firstSkill.skill_id,
                                    name: skillName,
                                    level: firstSkill.skillLevel,
                                    progress: calculatedProgress,
                                    remainingTime: nil  // 暂停状态
                                )
                            }
                        }
                        
                        // 更新位置信息
                        if let location = data.location {
                            viewModel.characters[index].locationStatus = location.locationStatus
                            if let locationInfo = data.solarSystemInfo {
                                viewModel.characters[index].location = locationInfo
                            }
                        }
                        
                        // 更新头像
                        if let portrait = data.portrait {
                            viewModel.characterPortraits[data.characterId] = portrait
                        }
                    }
                }
            }
        }
        .onOpenURL { url in
            Task {
                viewModel.handleCallback(url: url)
                showingWebView = false
                // 如果登录成功，清除该角色的token过期状态
                if let character = viewModel.characterInfo {
                    expiredTokenCharacters.remove(character.CharacterID)
                    EVELogin.shared.resetTokenExpired(characterId: character.CharacterID)
                }
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSNotification.Name("LanguageChanged"))
        ) { _ in
            // 强制视图刷新以更新技能名称
            withAnimation {
                forceUpdate.toggle()
            }
        }
        .id(forceUpdate)
        .onChange(of: viewModel.characters.isEmpty) { _, newValue in
            if newValue {
                isEditing = false
            }
        }
        .onDisappear {
            // 当视图消失时，从本地快速更新数据
            Task {
                await mainViewModel.quickRefreshFromLocal()
            }
        }
    }

    // 添加一个帮助函数来处理 MainActor.run 的返回值
    @discardableResult
    @Sendable
    private func updateUI<T>(_ operation: @MainActor () -> T) async -> T {
        await MainActor.run { operation() }
    }

    @MainActor
    private func refreshAllCharacters() async {
        // 先让刷新指示器完成动画
        try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5秒

        isRefreshing = true
        expiredTokenCharacters.removeAll()

        // 获取所有保存的角色认证信息
        let characterAuths = EVELogin.shared.loadCharacters()

        // 初始化过期状态
        for auth in characterAuths {
            if auth.character.tokenExpired {
                expiredTokenCharacters.insert(auth.character.CharacterID)
            }
        }

        // 分批处理角色，每批最多10个
        let batchSize = 10
        for batch in stride(from: 0, to: characterAuths.count, by: batchSize) {
            let end = min(batch + batchSize, characterAuths.count)
            let currentBatch = characterAuths[batch..<end]
            
            // 创建一个结构体来存储每个角色的所有数据
            struct CharacterFullData {
                let characterId: Int
                let skills: CharacterSkillsResponse
                let queue: [SkillQueueItem]
                let balance: Double
                let portrait: UIImage
                let location: CharacterLocation
                let solarSystemInfo: SolarSystemInfo?
            }
            
            // 使用TaskGroup并行获取所有角色的所有数据
            var characterDataResults: [CharacterFullData] = []
            
            await withTaskGroup(of: CharacterFullData?.self) { group in
                for characterAuth in currentBatch {
                    let characterId = characterAuth.character.CharacterID
                    
                    // 添加角色到刷新集合
                    refreshingCharacters.insert(characterId)
                    
                    group.addTask {
                        do {
                            // 使用 TokenManager 获取有效的 token
                            let current_access_token = try await AuthTokenManager.shared
                                .getAccessToken(for: characterId)
                            Logger.info(
                                "获得角色Token \(characterAuth.character.CharacterName)(\(characterId)) token: \(String(reflecting: current_access_token))"
                            )
                            
                            let service = CharacterDataService.shared
                            
                            // 并行获取所有数据
                            async let skillInfoTask = service.getSkillInfo(
                                id: characterId, forceRefresh: true
                            )
                            async let walletTask = service.getWalletBalance(
                                id: characterId, forceRefresh: true
                            )
                            async let portraitTask = service.getCharacterPortrait(
                                id: characterId, forceRefresh: true
                            )
                            async let locationTask = service.getLocation(
                                id: characterId, forceRefresh: true
                            )
                            
                            // 等待所有基础数据获取完成
                            let ((skills, queue), balance, portrait, location) = try await (
                                skillInfoTask, walletTask, portraitTask, locationTask
                            )
                            
                            // 获取太阳系详细信息
                            let solarSystemInfo = await getSolarSystemInfo(
                                solarSystemId: location.solar_system_id,
                                databaseManager: CharacterDataService.shared.databaseManager
                            )
                            
                            // 返回完整的角色数据
                            return CharacterFullData(
                                characterId: characterId,
                                skills: skills,
                                queue: queue,
                                balance: balance,
                                portrait: portrait,
                                location: location,
                                solarSystemInfo: solarSystemInfo
                            )
                        } catch {
                            if case NetworkError.tokenExpired = error {
                                // 在主线程更新UI
                                await MainActor.run {
                                    expiredTokenCharacters.insert(characterId)
                                    // 清除过期的 token
                                    Task {
                                        await AuthTokenManager.shared.clearTokens(for: characterId)
                                    }
                                }
                            }
                            Logger.error("刷新角色信息失败: \(error)")
                            return nil
                        }
                    }
                }
                
                // 收集所有结果
                for await result in group {
                    if let data = result {
                        characterDataResults.append(data)
                    }
                }
            }
            
            // 所有数据都已获取完成，一次性更新UI
            for data in characterDataResults {
                if let index = viewModel.characters.firstIndex(where: { $0.CharacterID == data.characterId }) {
                    // 更新技能信息
                    viewModel.characters[index].totalSkillPoints = data.skills.total_sp
                    viewModel.characters[index].unallocatedSkillPoints = data.skills.unallocated_sp
                    
                    // 更新技能队列
                    viewModel.characters[index].skillQueueLength = data.queue.count
                    if let currentSkill = data.queue.first(where: { $0.isCurrentlyTraining }) {
                        if let skillName = SkillTreeManager.shared.getSkillName(for: currentSkill.skill_id) {
                            viewModel.characters[index].currentSkill = EVECharacterInfo.CurrentSkillInfo(
                                skillId: currentSkill.skill_id,
                                name: skillName,
                                level: currentSkill.skillLevel,
                                progress: currentSkill.progress,
                                remainingTime: currentSkill.remainingTime
                            )
                        }
                    }
                    
                    // 更新钱包余额
                    viewModel.characters[index].walletBalance = data.balance
                    
                    // 更新头像
                    viewModel.characterPortraits[data.characterId] = data.portrait
                    
                    // 更新位置信息
                    viewModel.characters[index].locationStatus = data.location.locationStatus
                    if let locationInfo = data.solarSystemInfo {
                        viewModel.characters[index].location = locationInfo
                    }
                }
                
                // 从刷新集合中移除角色
                refreshingCharacters.remove(data.characterId)
            }
        }

        // 更新登录状态
        self.isRefreshing = false
        self.viewModel.isLoggedIn = !self.viewModel.characters.isEmpty
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
        } else if sp >= 1000 {
            return String(format: "%.1fK", Double(sp) / 1000.0)
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

    // 添加技能队列加载方法
    private func updateCharacterSkillQueue(character: EVECharacterInfo) async {
        do {
            // 添加重试机制
            let maxRetries = 3
            var retryCount = 0
            var lastError: Error?

            while retryCount < maxRetries {
                do {
                    let queue = try await CharacterSkillsAPI.shared.fetchSkillQueue(
                        characterId: character.CharacterID
                    )

                    Logger.info("成功获取技能队列 - 角色: \(character.CharacterName), 队列长度: \(queue.count)")

                    // 查找正在训练的技能
                    if let currentSkill = queue.first(where: { $0.isCurrentlyTraining }) {
                        if let skillName = SkillTreeManager.shared.getSkillName(
                            for: currentSkill.skill_id)
                        {
                            Logger.info(
                                "找到正在训练的技能 - 技能: \(skillName), 等级: \(currentSkill.skillLevel), 进度: \(currentSkill.progress)"
                            )

                            await updateUI {
                                var updatedCharacter = character
                                updatedCharacter.currentSkill = EVECharacterInfo.CurrentSkillInfo(
                                    skillId: currentSkill.skill_id,
                                    name: skillName,
                                    level: currentSkill.skillLevel,
                                    progress: currentSkill.progress,
                                    remainingTime: currentSkill.remainingTime
                                )
                                updatedCharacter.skillQueueLength = queue.count

                                // 更新角色列表中的信息
                                if let index = viewModel.characters.firstIndex(where: {
                                    $0.CharacterID == character.CharacterID
                                }) {
                                    viewModel.characters[index] = updatedCharacter
                                }

                                // 如果是当前选中的角色，也更新 characterInfo
                                if viewModel.characterInfo?.CharacterID == character.CharacterID {
                                    viewModel.characterInfo = updatedCharacter
                                }
                            }
                        }
                    } else if let firstSkill = queue.first {
                        // 如果没有正在训练的技能，但队列有技能，说明是暂停状态
                        if let skillName = SkillTreeManager.shared.getSkillName(
                            for: firstSkill.skill_id)
                        {
                            Logger.info(
                                "找到暂停的技能 - 技能: \(skillName), 等级: \(firstSkill.skillLevel), 进度: \(firstSkill.progress)"
                            )

                            // 计算暂停技能的实际进度
                            let calculatedProgress: Double
                            if let trainingStartSp = firstSkill.training_start_sp,
                                let levelEndSp = firstSkill.level_end_sp
                            {
                                calculatedProgress = SkillProgressCalculator.calculateProgress(
                                    trainingStartSp: trainingStartSp,
                                    levelEndSp: levelEndSp,
                                    finishedLevel: firstSkill.finished_level
                                )
                            } else {
                                calculatedProgress = 0.0
                            }

                            await updateUI {
                                var updatedCharacter = character
                                updatedCharacter.currentSkill = EVECharacterInfo.CurrentSkillInfo(
                                    skillId: firstSkill.skill_id,
                                    name: skillName,
                                    level: firstSkill.skillLevel,
                                    progress: calculatedProgress,
                                    remainingTime: nil  // 暂停状态
                                )
                                updatedCharacter.skillQueueLength = queue.count

                                // 更新角色列表中的信息
                                if let index = viewModel.characters.firstIndex(where: {
                                    $0.CharacterID == character.CharacterID
                                }) {
                                    viewModel.characters[index] = updatedCharacter
                                }

                                // 如果是当前选中的角色，也更新 characterInfo
                                if viewModel.characterInfo?.CharacterID == character.CharacterID {
                                    viewModel.characterInfo = updatedCharacter
                                }
                            }
                        }
                    } else {
                        // 队列为空的情况
                        Logger.info("技能队列为空 - 角色: \(character.CharacterName)")

                        await updateUI {
                            var updatedCharacter = character
                            updatedCharacter.currentSkill = nil
                            updatedCharacter.skillQueueLength = 0

                            // 更新角色列表中的信息
                            if let index = viewModel.characters.firstIndex(where: {
                                $0.CharacterID == character.CharacterID
                            }) {
                                viewModel.characters[index] = updatedCharacter
                            }

                            // 如果是当前选中的角色，也更新 characterInfo
                            if viewModel.characterInfo?.CharacterID == character.CharacterID {
                                viewModel.characterInfo = updatedCharacter
                            }
                        }
                    }

                    // 如果成功，跳出循环
                    break

                } catch {
                    lastError = error
                    retryCount += 1
                    Logger.error(
                        "获取技能队列失败(尝试 \(retryCount)/\(maxRetries)) - 角色: \(character.CharacterName), 错误: \(error)"
                    )

                    if retryCount < maxRetries {
                        // 等待一段时间后重试
                        try await Task.sleep(nanoseconds: UInt64(1_000_000_000 * retryCount))  // 递增等待时间
                    }
                }
            }

            if retryCount == maxRetries {
                Logger.error(
                    "获取技能队列最终失败 - 角色: \(character.CharacterName), 错误: \(lastError?.localizedDescription ?? "未知错误")"
                )
            }

        } catch {
            Logger.error("获取技能队列失败 - 角色: \(character.CharacterName), 错误: \(error)")
        }
    }

    // 添加新的辅助方法用于刷新单个角色的数据
    private func refreshCharacterData(_ character: EVECharacterInfo) async {
        let service = CharacterDataService.shared

        do {
            // 添加角色到刷新集合
            await updateUI {
                refreshingCharacters.insert(character.CharacterID)
            }
            
            // 并行获取所有数据
            async let skillInfoTask = service.getSkillInfo(
                id: character.CharacterID, forceRefresh: true
            )
            async let walletTask = service.getWalletBalance(
                id: character.CharacterID, forceRefresh: true
            )
            async let portraitTask = service.getCharacterPortrait(
                id: character.CharacterID, forceRefresh: true
            )
            async let locationTask = service.getLocation(
                id: character.CharacterID, forceRefresh: true
            )

            // 等待所有基础数据获取完成
            let ((skills, queue), balance, portrait, location) = try await (
                skillInfoTask, walletTask, portraitTask, locationTask
            )
            
            // 并行获取太阳系详细信息
            async let solarSystemInfoTask = getSolarSystemInfo(
                solarSystemId: location.solar_system_id,
                databaseManager: service.databaseManager
            )

            // 一次性更新UI
            await updateUI {
                if let index = self.viewModel.characters.firstIndex(where: {
                    $0.CharacterID == character.CharacterID
                }) {
                    // 更新技能信息
                    self.viewModel.characters[index].totalSkillPoints = skills.total_sp
                    self.viewModel.characters[index].unallocatedSkillPoints =
                        skills.unallocated_sp

                    // 更新技能队列
                    self.viewModel.characters[index].skillQueueLength = queue.count
                    if let currentSkill = queue.first(where: { $0.isCurrentlyTraining }) {
                        if let skillName = SkillTreeManager.shared.getSkillName(
                            for: currentSkill.skill_id)
                        {
                            self.viewModel.characters[index].currentSkill =
                                EVECharacterInfo.CurrentSkillInfo(
                                    skillId: currentSkill.skill_id,
                                    name: skillName,
                                    level: currentSkill.skillLevel,
                                    progress: currentSkill.progress,
                                    remainingTime: currentSkill.remainingTime
                                )
                        }
                    }

                    // 更新钱包余额
                    self.viewModel.characters[index].walletBalance = balance

                    // 更新头像
                    self.viewModel.characterPortraits[character.CharacterID] = portrait

                    // 更新位置信息
                    self.viewModel.characters[index].locationStatus = location.locationStatus
                }
            }
            
            // 等待太阳系详细信息并更新
            if let locationInfo = await solarSystemInfoTask {
                await updateUI {
                    if let index = self.viewModel.characters.firstIndex(where: {
                        $0.CharacterID == character.CharacterID
                    }) {
                        self.viewModel.characters[index].location = locationInfo
                    }
                }
            }

            Logger.info("成功刷新角色数据 - \(character.CharacterName)")
        } catch {
            Logger.error("刷新角色数据失败 - \(character.CharacterName): \(error)")
        }
        
        // 从刷新集合中移除角色
        await updateUI {
            refreshingCharacters.remove(character.CharacterID)
        }
    }

    // 在AccountsView结构体内添加一个检查scopes更新时间的函数
    private func checkAndUpdateScopesIfNeeded() async {
        // 获取文档目录路径
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let latestScopesPath = documentsDirectory.appendingPathComponent("latest_scopes.json")
        
        // 检查文件是否存在
        if FileManager.default.fileExists(atPath: latestScopesPath.path) {
            do {
                // 获取文件属性
                let attributes = try FileManager.default.attributesOfItem(atPath: latestScopesPath.path)
                if let modificationDate = attributes[.modificationDate] as? Date {
                    // 计算文件最后修改时间与当前时间的差值
                    let timeInterval = Date().timeIntervalSince(modificationDate)
                    // 如果超过8小时（28800秒），则更新
                    if timeInterval > 28800 {
                        Logger.info("latest_scopes.json 文件已超过8小时未更新，正在自动刷新...")
                        // 强制刷新 scopes
                        let _ = await ScopeManager.shared.getScopes(forceRefresh: true)
                        // 更新 EVELogin 中的 scopes 配置
                        let scopes = await EVELogin.shared.getScopes()
                        Logger.info("成功自动刷新 scopes，获取到 \(scopes.count) 个权限")
                    } else {
                        Logger.info("latest_scopes.json 文件在8小时内已更新，无需刷新")
                    }
                }
            } catch {
                Logger.error("检查 latest_scopes.json 文件属性失败: \(error)")
                // 如果检查失败，尝试刷新
                let _ = await ScopeManager.shared.getScopes(forceRefresh: true)
            }
        } else {
            Logger.info("latest_scopes.json 文件不存在，正在创建...")
            // 文件不存在，强制刷新
            let _ = await ScopeManager.shared.getScopes(forceRefresh: true)
        }
    }
}

// 添加 CharacterRowView 结构体
struct CharacterRowView: View {
    let character: EVECharacterInfo
    let portrait: UIImage?
    let isRefreshing: Bool
    let isEditing: Bool
    let tokenExpired: Bool
    let formatISK: (Double) -> String
    let formatSkillPoints: (Int) -> String
    let formatRemainingTime: (TimeInterval) -> String
    @State private var currentSkillName: String = ""

    var body: some View {
        HStack {
            if let portrait = portrait {
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

            VStack(alignment: .leading, spacing: 2) {
                Text(character.CharacterName)
                    .font(.headline)
                    .frame(height: 20)

                VStack(alignment: .leading, spacing: 2) {
                    if isRefreshing {
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
                                Text(formatSystemSecurity(location.security))
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
                            Text(
                                "\(NSLocalizedString("Account_Wallet_value", comment: "")): \(FormatUtil.formatISK(balance)) ISK"
                            )
                            .font(.caption)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                        } else {
                            Text(
                                "\(NSLocalizedString("Account_Wallet_value", comment: "")): -- ISK"
                            )
                            .font(.caption)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                        }

                        // 技能点信息
                        if let totalSP = character.totalSkillPoints {
                            let spText =
                                if let unallocatedSP = character.unallocatedSkillPoints,
                                    unallocatedSP > 0
                                {
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
                                            .fill(
                                                currentSkill.remainingTime != nil
                                                    ? Color.green : Color.gray
                                            )
                                            .frame(
                                                width: geometry.size.width * currentSkill.progress,
                                                height: 4
                                            )
                                    }
                                }
                                .frame(height: 4)

                                // 技能信息
                                HStack {
                                    HStack(spacing: 4) {
                                        Image(
                                            systemName: currentSkill.remainingTime != nil
                                                ? "play.fill" : "pause.fill"
                                        )
                                        .font(.caption)
                                        .foregroundColor(
                                            currentSkill.remainingTime != nil ? .green : .gray)
                                        Text(
                                            "\(SkillTreeManager.shared.getSkillName(for: currentSkill.skillId) ?? currentSkill.name) \(currentSkill.level)"
                                        )
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
                                        Text("Paused")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        } else {
                            // 没有技能在训练时显示的进度条
                            GeometryReader { _ in
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
                .frame(height: 72)
            }
            .padding(.leading, 4)

            if isEditing {
                Spacer()
                Image(systemName: "trash")
                    .foregroundColor(.red)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }
}

// 添加 AsyncSemaphore 类来控制并发
actor AsyncSemaphore {
    private var value: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(value: Int) {
        self.value = value
    }

    func wait() async {
        if value > 0 {
            value -= 1
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
            return
        }

        value += 1
    }
}

// 技能进度计算工具类
enum SkillProgressCalculator {
    // 基准技能点数（x1倍增系数）
    static let baseSkillPoints: [Int] = [250, 1415, 8000, 45255, 256_000]

    // 计算技能的倍增系数
    static func calculateMultiplier(levelEndSp: Int, finishedLevel: Int) -> Int {
        guard finishedLevel > 0 && finishedLevel <= baseSkillPoints.count else { return 1 }
        let baseEndSp = baseSkillPoints[finishedLevel - 1]
        let multiplier = Double(levelEndSp) / Double(baseEndSp)
        return Int(round(multiplier))
    }

    // 获取前一等级的技能点数
    static func getPreviousLevelSp(finishedLevel: Int, multiplier: Int) -> Int {
        guard finishedLevel > 1 && finishedLevel <= baseSkillPoints.count else { return 0 }
        return baseSkillPoints[finishedLevel - 2] * multiplier
    }

    // 计算技能训练进度（0.0 - 1.0）
    static func calculateProgress(trainingStartSp: Int, levelEndSp: Int, finishedLevel: Int)
        -> Double
    {
        let multiplier = calculateMultiplier(levelEndSp: levelEndSp, finishedLevel: finishedLevel)
        let previousLevelSp = getPreviousLevelSp(
            finishedLevel: finishedLevel, multiplier: multiplier
        )

        let progress =
            Double(trainingStartSp - previousLevelSp) / Double(levelEndSp - previousLevelSp)
        return min(max(progress, 0.0), 1.0)  // 确保进度在0.0到1.0之间
    }
}
