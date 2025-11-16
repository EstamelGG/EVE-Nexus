import Foundation
import SwiftUI
import UserNotifications

@main
struct EVE_NexusApp: App {
    @AppStorage("selectedLanguage") private var selectedLanguage: String?
    @AppStorage("selectedDatabaseLanguage") private var selectedDatabaseLanguage: String?
    @StateObject private var databaseManager = DatabaseManager()
    @State private var loadingState: LoadingState = .processing
    @State private var isInitialized = false
    @State private var unzipProgress: Double = 0
    @State private var needsUnzip = false

    private func getLanguageCode(_ language: String) -> String {
        return language.hasPrefix("zh-Hans") ? "zh-Hans" : "en"
    }

    init() {
        // 配置 Pulse 日志系统（必须在其他初始化之前）
        Logger.configure()

        // 隐藏 PulseUI 中的支持相关按钮，避免用户误以为是给应用开发者发送反馈
        UserDefaults.standard.set(true, forKey: "pulse-disable-support-prompts")
        UserDefaults.standard.set(true, forKey: "pulse-disable-report-issue-prompts")

        configureLanguage()
        setupNotifications()
        initializeLanguageMapSettings()
        Logger.info("App start at \(Date())")
        // 打印 UserDefaults 中的所有键值
        let defaults = UserDefaults.standard

        let dictionary = defaults.dictionaryRepresentation()
        // Logger.info("UserDefaults 内容:")

        // 使用 PropertyListSerialization 来获取实际的序列化大小
        var sizeMap: [(key: String, size: Int)] = []
        var totalSize = 0

        for (key, value) in dictionary {
            if let data = try? PropertyListSerialization.data(
                fromPropertyList: value, format: .binary, options: 0
            ) {
                let size = data.count
                totalSize += size
                sizeMap.append((key: key, size: size))

                // 检查单个键值对是否过大（比如超过1MB）
                if size > 1_000_000 {
                    Logger.error(
                        "警告：键 '\(key)' 的数据大小(\(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)))过大"
                    )
                }
            }
        }

        // 检查总大小是否接近限制（4MB）
        if totalSize > 3_072_000 {
            Logger.warning(
                "警告：UserDefaults 总大小(\(ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file)))接近限制(4MB)"
            )
            // 按大小排序并只打印超过1MB的键
            sizeMap.sort { $0.size > $1.size }
            for item in sizeMap {
                if item.size > 1_000_000 {
                    Logger.info(
                        "键: \(item.key), 大小: \(ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file))"
                    )
                }
            }
        } else {
            Logger.success(
                "UserDefaults 总大小: \(ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file))"
            )
        }

        // 初始化数据库
        _ = CharacterDatabaseManager.shared // 确保角色数据库被初始化

        // 加载本地化账单信息的文本数据
        LocalizationManager.shared.loadAccountingEntryTypes()
        validateRefreshTokens()

        // 安排后台任务
        BackgroundTaskManager.shared.scheduleDataRefresh()
        BackgroundTaskManager.shared.scheduleAssetJsonRefresh()
        BackgroundTaskManager.shared.scheduleContractRefresh()
        BackgroundTaskManager.shared.scheduleStructureOrdersRefresh()
        BackgroundTaskManager.shared.scheduleIndustryRefresh()
        BackgroundTaskManager.shared.scheduleWalletRefresh()

        // 后台检查SDE更新
        Task { @MainActor in
            await SDEUpdateChecker.shared.checkForUpdates()
        }
    }

    private func setupNotifications() {
        // 设置通知代理
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        Logger.info("通知代理设置完成")
    }

    private func configureLanguage() {
        // 只在首次启动或语言未设置时配置
        if selectedLanguage == nil {
            let systemLanguage = Locale.preferredLanguages.first ?? "en"
            let languageCode = getLanguageCode(systemLanguage)
            selectedLanguage = languageCode
            UserDefaults.standard.set([languageCode], forKey: "AppleLanguages")
            UserDefaults.standard.synchronize()
            Logger.debug("首次启动，设置为系统语言: \(systemLanguage) -> \(languageCode)")
        } else {
            // 使用已保存的语言设置
            UserDefaults.standard.set([selectedLanguage], forKey: "AppleLanguages")
            UserDefaults.standard.synchronize()
            Logger.debug("使用已保存的语言设置: \(String(describing: selectedLanguage))")
        }

        // 配置数据库语言，如果未设置则与应用语言保持一致
        if selectedDatabaseLanguage == nil {
            selectedDatabaseLanguage = selectedLanguage
            Logger.debug("首次启动，设置数据库语言与应用语言一致: \(String(describing: selectedDatabaseLanguage))")
        } else {
            Logger.debug("使用已保存的数据库语言设置: \(String(describing: selectedDatabaseLanguage))")
        }
    }

    private func initializeLanguageMapSettings() {
        // 检查是否已经设置过语言映射配置
        if UserDefaults.standard.object(forKey: LanguageMapConstants.languageMapDefaultsKey) == nil {
            // 首次使用，设置默认语言映射配置
            UserDefaults.standard.set(
                LanguageMapConstants.languageMapDefaultLanguages,
                forKey: LanguageMapConstants.languageMapDefaultsKey
            )
            Logger.info("首次使用，初始化语言映射配置为默认值: \(LanguageMapConstants.languageMapDefaultLanguages)")
        } else {
            Logger.debug("语言映射配置已存在，跳过初始化")
        }
    }

    private func validateRefreshTokens() {
        // 获取所有有效的 token
        let characterIdsWithValidRefreshToken = SecureStorage.shared.listValidRefreshTokens()
        Logger.info("App初始化: 找到 \(characterIdsWithValidRefreshToken.count) 个有效的 refresh token")

        // 获取当前保存的所有角色
        let characters = EVELogin.shared.loadCharacters()
        Logger.info("App初始化: UserDefaults 中保存了 \(characters.count) 个角色")

        // 打印详细信息
        for character in characters {
            let characterId = character.character.CharacterID
            let hasValidRefreshToken = characterIdsWithValidRefreshToken.contains(characterId)
            Logger.info(
                "App初始化: 角色 \(character.character.CharacterName) (\(characterId)) - \(hasValidRefreshToken ? "有效 refresh token" : "无效 refresh token")"
            )

            // 如果没有有效的 token，标记为过期
            if !hasValidRefreshToken {
                Logger.info(
                    "App初始化: 标记角色token过期 - \(character.character.CharacterName) (\(characterId))"
                )
                let characterToUpdate = character.character
                Task {
                    var updatedCharacter = characterToUpdate
                    updatedCharacter.refreshTokenExpired = true
                    try? await EVELogin.shared.saveCharacterInfo(updatedCharacter)
                }
            }
        }
    }

    private func checkAndExtractIcons() async {
        guard let iconPath = Bundle.main.path(forResource: "icons", ofType: "zip") else {
            Logger.error("icons.zip file not found in bundle")
            return
        }

        let destinationPath = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        )[0].appendingPathComponent("Icons")
        let iconURL = URL(fileURLWithPath: iconPath)

        // 获取当前 App 版本
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"

        // 检查是否需要重新解压
        if !shouldExtractIcons(destinationPath: destinationPath, appVersion: appVersion) {
            Logger.info("Using existing icons, skipping extraction.")
            // 即使不需要解压，也要执行初始化
            await initializeApp()
            return
        }

        // 需要重新解压
        Logger.info("Extracting icons from Bundle...")
        await MainActor.run {
            needsUnzip = true
        }

        // 如果目录存在，删除它重新解压
        if FileManager.default.fileExists(atPath: destinationPath.path) {
            try? FileManager.default.removeItem(at: destinationPath)
        }

        do {
            try await IconManager.shared.unzipIcons(from: iconURL, to: destinationPath) {
                progress in
                Task { @MainActor in
                    unzipProgress = progress
                }
            }

            // 保存 Bundle 中的 metadata.json 到 icons 目录
            if let bundleMetadata = MetadataManager.shared.readMetadataFromBundle() {
                do {
                    try MetadataManager.shared.saveMetadataToIconsDirectory(bundleMetadata)
                    Logger.info("Saved Bundle metadata.json to icons directory (icon_version: \(bundleMetadata.iconVersion))")
                } catch {
                    Logger.error("Failed to save Bundle metadata.json: \(error)")
                }
            } else {
                Logger.warning("Unable to read Bundle metadata.json")
            }

            await MainActor.run {
                loadingState = .complete
            }

            // 解压完成后执行初始化
            await initializeApp()
        } catch {
            Logger.error("Error during icons extraction: \(error)")
            // 解压失败时重置状态
            IconManager.shared.isExtractionComplete = false
            // 即使解压失败，也要执行初始化，避免应用卡在加载状态
            await initializeApp()
        }
    }

    /// 检查是否需要重新解压图标（使用 metadata.json 中的 icon_version 进行比较）
    /// - Returns: true 表示需要重新解压，false 表示可以使用现有图标
    private func shouldExtractIcons(destinationPath: URL, appVersion _: String) -> Bool {
        // 1. 检查目录是否存在且非空
        let iconsExist = FileManager.default.fileExists(atPath: destinationPath.path)
        let hasContents = (try? FileManager.default.contentsOfDirectory(atPath: destinationPath.path))?.isEmpty == false

        guard iconsExist, hasContents, IconManager.shared.isExtractionComplete else {
            Logger.info("Icons folder not found or incomplete, need extraction")
            return true // 需要解压
        }

        // 2. 获取 Bundle 中的图标版本
        guard let bundleMetadata = MetadataManager.shared.readMetadataFromBundle() else {
            Logger.warning("Unable to read metadata from Bundle, will extract icons")
            return true // 无法读取 Bundle metadata，需要解压
        }

        // 3. 获取已解压图标的版本
        guard let localMetadata = MetadataManager.shared.readMetadataFromIconsDirectory() else {
            Logger.info("Local icons has no metadata.json, need extraction")
            return true // 需要解压
        }

        // 4. 版本比较：如果 Bundle 中的版本更高，则需要重新解压
        let needExtraction = bundleMetadata.iconVersion > localMetadata.iconVersion
        Logger.info("Icon version comparison - Bundle: v\(bundleMetadata.iconVersion), Local: v\(localMetadata.iconVersion), Need Extraction: \(needExtraction)")

        return needExtraction
    }

    private func initializeApp() async {
        do {
            // 在图标解压完成后加载主权数据
            // _ = try await SovereigntyDataAPI.shared.fetchSovereigntyData()

            // 异步加载保险价格数据，不阻塞主进程
            Task.detached(priority: .background) {
                do {
                    _ = try await InsurancePricesAPI.shared.fetchInsurancePrices()
                } catch {
                    Logger.error("后台加载保险价格数据失败: \(error)")
                }
            }

            await MainActor.run {
                databaseManager.loadDatabase()
                CharacterDatabaseManager.shared.loadDatabase()

                // 清理钱包旧数据（在后台线程执行，不阻塞初始化）
                Task.detached(priority: .background) {
                    let journalDeleted = WalletJournalAPI.shared.cleanupOldData()
                    let transactionsDeleted = WalletTransactionsAPI.shared.cleanupOldData()
                    if journalDeleted > 0 || transactionsDeleted > 0 {
                        Logger.info("钱包数据清理完成 - 流水: \(journalDeleted)条, 交易: \(transactionsDeleted)条")
                    }
                }

                isInitialized = true
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if isInitialized {
                    ContentView(databaseManager: databaseManager)
                } else if needsUnzip {
                    LoadingView(loadingState: $loadingState, progress: unzipProgress) {
                        // 解压完成后会在 checkAndExtractIcons 中调用 initializeApp
                    }
                } else {
                    Color.clear
                        .onAppear {
                            Task {
                                await checkAndExtractIcons()
                            }
                        }
                }
            }
        }
    }
}
