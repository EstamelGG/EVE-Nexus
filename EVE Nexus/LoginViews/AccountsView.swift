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
                                let scopes = await ScopeManager.shared.getLatestScopes(forceRefresh: true)

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
                                viewModel.showingError = false
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
                            let _ = await ScopeManager.shared.getLatestScopes(forceRefresh: true)

                            // 更新 EVELogin 中的 scopes 配置
                            let scopes = await EVELogin.shared.getScopes()
                            Logger.info("成功刷新 scopes，获取到 \(scopes.count) 个权限")

                            // 显示成功提示
                            await MainActor.run {
                                isRefreshingScopes = false  // 重置刷新状态
                                successMessage = String(
                                    format: NSLocalizedString(
                                        "Scopes_Refresh_Success", comment: ""), scopes.count)
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
                                    refreshTokenhasExpired: expiredTokenCharacters.contains(
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
                                    refreshTokenhasExpired: expiredTokenCharacters.contains(
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
            NSLocalizedString("Operation_Success", comment: ""),
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
                    // 清除该角色的 RefreshTokenExpired 状态
                    EVELogin.shared.resetRefreshTokenExpired(characterId: character.CharacterID)
                    // 从过期token集合中移除该角色
                    expiredTokenCharacters.remove(character.CharacterID)
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
                for auth in characterAuths {
                    if auth.character.refreshTokenExpired {
                        expiredTokenCharacters.insert(auth.character.CharacterID)
                    }

                    if let index = viewModel.characters.firstIndex(where: {
                        $0.CharacterID == auth.character.CharacterID
                    }) {
                        // 尝试从缓存获取钱包余额
                        let cachedBalance = await CharacterWalletAPI.shared.getCachedWalletBalance(
                            characterId: auth.character.CharacterID)
                        if let balance = Double(cachedBalance) {
                            viewModel.characters[index].walletBalance = balance
                        }

                        // 尝试从缓存获取技能点数据
                        if let skillsInfo = try? await CharacterSkillsAPI.shared
                            .fetchCharacterSkills(
                                characterId: auth.character.CharacterID,
                                forceRefresh: false
                            )
                        {
                            viewModel.characters[index].totalSkillPoints = skillsInfo.total_sp
                            viewModel.characters[index].unallocatedSkillPoints =
                                skillsInfo.unallocated_sp
                        }

                        // 尝试从缓存获取技能队列
                        if let queue = try? await CharacterSkillsAPI.shared.fetchSkillQueue(
                            characterId: auth.character.CharacterID,
                            forceRefresh: false
                        ) {
                            viewModel.characters[index].skillQueueLength = queue.count
                            if let currentSkill = queue.first(where: { $0.isCurrentlyTraining }) {
                                if let skillName = SkillTreeManager.shared.getSkillName(
                                    for: currentSkill.skill_id)
                                {
                                    viewModel.characters[index].currentSkill =
                                        EVECharacterInfo.CurrentSkillInfo(
                                            skillId: currentSkill.skill_id,
                                            name: skillName,
                                            level: currentSkill.skillLevel,
                                            progress: currentSkill.progress,
                                            remainingTime: currentSkill.remainingTime
                                        )
                                }
                            } else if let firstSkill = queue.first,
                                let skillName = SkillTreeManager.shared.getSkillName(
                                    for: firstSkill.skill_id),
                                let trainingStartSp = firstSkill.training_start_sp,
                                let levelEndSp = firstSkill.level_end_sp
                            {
                                // 计算暂停技能的实际进度
                                let calculatedProgress = SkillProgressCalculator.calculateProgress(
                                    trainingStartSp: trainingStartSp,
                                    levelEndSp: levelEndSp,
                                    finishedLevel: firstSkill.finished_level
                                )
                                viewModel.characters[index].currentSkill =
                                    EVECharacterInfo.CurrentSkillInfo(
                                        skillId: firstSkill.skill_id,
                                        name: skillName,
                                        level: firstSkill.skillLevel,
                                        progress: calculatedProgress,
                                        remainingTime: nil  // 暂停状态
                                    )
                            }
                        }

                        // 尝试从缓存获取位置信息
                        if let location = try? await CharacterLocationAPI.shared
                            .fetchCharacterLocation(
                                characterId: auth.character.CharacterID,
                                forceRefresh: false
                            )
                        {
                            viewModel.characters[index].locationStatus = location.locationStatus
                            let locationInfo = await getSolarSystemInfo(
                                solarSystemId: location.solar_system_id,
                                databaseManager: viewModel.databaseManager
                            )
                            if let locationInfo = locationInfo {
                                viewModel.characters[index].location = locationInfo
                            }
                        }

                        // 尝试从缓存获取头像
                        if let portrait = try? await CharacterAPI.shared.fetchCharacterPortrait(
                            characterId: auth.character.CharacterID,
                            forceRefresh: false
                        ) {
                            viewModel.characterPortraits[auth.character.CharacterID] = portrait
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
                    EVELogin.shared.resetRefreshTokenExpired(characterId: character.CharacterID)
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
        let service = CharacterDataService.shared

        // 初始化过期状态
        for auth in characterAuths {
            if auth.character.refreshTokenExpired {
                expiredTokenCharacters.insert(auth.character.CharacterID)
            }
        }

        // 分批处理角色，每批最多 10 个
        let batchSize = 10
        for batch in stride(from: 0, to: characterAuths.count, by: batchSize) {
            let end = min(batch + batchSize, characterAuths.count)
            let currentBatch = characterAuths[batch..<end]

            // 使用 TaskGroup 并行处理当前批次的角色数据刷新
            await withTaskGroup(of: Void.self) { group in
                for characterAuth in currentBatch {
                    group.addTask {
                        // 添加角色到刷新集合
                        await updateUI {
                            refreshingCharacters.insert(characterAuth.character.CharacterID)
                        }

                        do {
                            // 使用 TokenManager 获取有效的 token
                            let current_access_token = try await AuthTokenManager.shared
                                .getAccessToken(for: characterAuth.character.CharacterID)
                            Logger.info(
                                "获得角色Token \(characterAuth.character.CharacterName)(\(characterAuth.character.CharacterID)) token: \(String(reflecting: current_access_token))"
                            )

                            // 并行获取所有数据
                            async let skillInfoTask = service.getSkillInfo(
                                id: characterAuth.character.CharacterID, forceRefresh: true
                            )
                            async let walletTask = service.getWalletBalance(
                                id: characterAuth.character.CharacterID, forceRefresh: true
                            )
                            async let portraitTask = service.getCharacterPortrait(
                                id: characterAuth.character.CharacterID, forceRefresh: true
                            )
                            async let locationTask = service.getLocation(
                                id: characterAuth.character.CharacterID, forceRefresh: true
                            )

                            // 等待所有数据获取完成
                            let ((skillsResponse, queue), balance, portrait, location) = try await (
                                skillInfoTask, walletTask, portraitTask, locationTask
                            )

                            // 更新UI
                            await updateUI {
                                if let index = self.viewModel.characters.firstIndex(where: {
                                    $0.CharacterID == characterAuth.character.CharacterID
                                }) {
                                    // 更新技能信息
                                    self.viewModel.characters[index].totalSkillPoints =
                                        skillsResponse.total_sp
                                    self.viewModel.characters[index].unallocatedSkillPoints =
                                        skillsResponse.unallocated_sp

                                    // 更新技能队列
                                    self.viewModel.characters[index].skillQueueLength = queue.count
                                    if let currentSkill = queue.first(where: {
                                        $0.isCurrentlyTraining
                                    }) {
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
                                    self.viewModel.characterPortraits[
                                        characterAuth.character.CharacterID
                                    ] = portrait

                                    // 更新位置信息
                                    self.viewModel.characters[index].locationStatus =
                                        location.locationStatus
                                    Task {
                                        if let locationInfo = await getSolarSystemInfo(
                                            solarSystemId: location.solar_system_id,
                                            databaseManager: self.viewModel.databaseManager
                                        ) {
                                            await MainActor.run {
                                                self.viewModel.characters[index].location =
                                                    locationInfo
                                            }
                                        }
                                    }
                                }
                            }

                        } catch {
                            if case NetworkError.refreshTokenExpired = error {
                                await updateUI {
                                    expiredTokenCharacters.insert(
                                        characterAuth.character.CharacterID
                                    )
                                }
                            }
                            Logger.error("刷新角色信息失败: \(error)")
                        }

                        // 从刷新集合中移除角色
                        await updateUI {
                            refreshingCharacters.remove(characterAuth.character.CharacterID)
                        }
                    }
                }

                // 等待当前批次的所有任务完成
                await group.waitForAll()
            }
        }

        // 更新登录状态
        await updateUI {
            self.isRefreshing = false
            // self.viewModel.isLoggedIn = !self.viewModel.characters.isEmpty
        }
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

            // 等待所有数据获取完成
            let ((skillsResponse, queue), balance, portrait, location) = try await (
                skillInfoTask, walletTask, portraitTask, locationTask
            )

            // 更新UI
            await updateUI {
                if let index = self.viewModel.characters.firstIndex(where: {
                    $0.CharacterID == character.CharacterID
                }) {
                    // 更新技能信息
                    self.viewModel.characters[index].totalSkillPoints = skillsResponse.total_sp
                    self.viewModel.characters[index].unallocatedSkillPoints =
                        skillsResponse.unallocated_sp

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
                    Task {
                        if let locationInfo = await getSolarSystemInfo(
                            solarSystemId: location.solar_system_id,
                            databaseManager: self.viewModel.databaseManager
                        ) {
                            await MainActor.run {
                                self.viewModel.characters[index].location = locationInfo
                            }
                        }
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
        Logger.info("检查并更新 scopes...")
        // 只调用一次 getScopes，它会内部调用 getLatestScopes
        let scopes = await EVELogin.shared.getScopes()
        Logger.info("完成 scopes 检查，当前共有 \(scopes.count) 个权限")
    }
}

// 添加 CharacterRowView 结构体
struct CharacterRowView: View {
    let character: EVECharacterInfo
    let portrait: UIImage?
    let isRefreshing: Bool
    let isEditing: Bool
    let refreshTokenhasExpired: Bool
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
                    } else if refreshTokenhasExpired {
                        // 使用TokenExpiredOverlay组件
                        TokenExpiredOverlay()
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
                    } else if refreshTokenhasExpired {
                        // 使用TokenExpiredOverlay组件
                        TokenExpiredOverlay()
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
                                "\(NSLocalizedString("Account_Wallet_value", comment: "")): \(FormatUtil.formatISK(balance))"
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
