import SwiftUI
import SQLite3
import Zip
import BackgroundTasks

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // 注册后台任务
        registerBackgroundTasks()
        return true
    }
    
    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.evenexus.tokenrefresh",
            using: nil
        ) { task in
            self.handleRefreshTask(task: task as! BGAppRefreshTask)
        }
        
        Logger.info("AppDelegate: 后台任务注册成功")
    }
    
    private func handleRefreshTask(task: BGAppRefreshTask) {
        // 安排下一次刷新任务
        scheduleNextRefresh()
        
        // 设置任务超时处理
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        
        // 执行令牌刷新
        Task {
            do {
                try await EVELogin.shared.performBackgroundRefresh()
                task.setTaskCompleted(success: true)
            } catch {
                Logger.error("AppDelegate: 后台刷新失败: \(error)")
                task.setTaskCompleted(success: false)
            }
        }
    }
    
    private func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.evenexus.tokenrefresh")
        // 设置为20天后执行
        request.earliestBeginDate = Calendar.current.date(byAdding: .day, value: 20, to: Date())
        
        do {
            try BGTaskScheduler.shared.submit(request)
            Logger.info("AppDelegate: 已安排下一次后台刷新任务")
        } catch {
            Logger.error("AppDelegate: 安排后台刷新任务失败: \(error)")
        }
    }
}

@main
struct EVE_NexusApp: App {
    // 注册 AppDelegate
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    @AppStorage("selectedLanguage") private var selectedLanguage: String?
    @StateObject private var databaseManager = DatabaseManager()
    @State private var loadingState: LoadingState = .unzipping
    @State private var isInitialized = false
    @State private var unzipProgress: Double = 0
    @State private var needsUnzip = false

    init() {
        // 打印 UserDefaults 中的所有键值
        let defaults = UserDefaults.standard
        let dictionary = defaults.dictionaryRepresentation()
        Logger.info("UserDefaults 内容:")
        var totalSize = 0
        for (key, value) in dictionary {
            let size = String(describing: value).utf8.count
            totalSize += size
            Logger.info("键: \(key), 大小: \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))")
        }
        Logger.info("UserDefaults 总大小: \(ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file))")
        
        configureLanguage()
        validateTokens()
    }

    private func configureLanguage() {
        if let language = selectedLanguage {
            Logger.debug("正在写入 UserDefaults，键: AppleLanguages, 值: [\(language)]")
            UserDefaults.standard.set([language], forKey: "AppleLanguages")
            UserDefaults.standard.synchronize()
        } else {
            let systemLanguage = Locale.preferredLanguages.first ?? "en"
            Logger.debug("正在写入 UserDefaults，键: AppleLanguages, 值: [\(systemLanguage)]")
            UserDefaults.standard.set([systemLanguage], forKey: "AppleLanguages")
            UserDefaults.standard.synchronize()
        }
    }
    
    private func validateTokens() {
        // 获取所有有效的 token
        let validCharacterIds = SecureStorage.shared.listValidTokens()
        Logger.info("App初始化: 找到 \(validCharacterIds.count) 个有效的 refresh token")
        
        // 获取当前保存的所有角色
        let characters = EVELogin.shared.loadCharacters()
        Logger.info("App初始化: UserDefaults 中保存了 \(characters.count) 个角色")
        
        // 打印详细信息
        for character in characters {
            let characterId = character.character.CharacterID
            let hasValidToken = validCharacterIds.contains(characterId)
            Logger.info("App初始化: 角色 \(character.character.CharacterName) (\(characterId)) - \(hasValidToken ? "有效token" : "无效token")")
            
            // 如果没有有效的 token，移除该角色
            if !hasValidToken {
                Logger.info("App初始化: 移除无效 token 的角色 - \(character.character.CharacterName) (\(characterId))")
                EVELogin.shared.removeCharacter(characterId: characterId)
            }
        }
    }

    private func checkAndExtractIcons() async {
        guard let iconPath = Bundle.main.path(forResource: "icons", ofType: "zip") else {
            Logger.error("icons.zip file not found in bundle")
            return
        }

        let destinationPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Icons")
        let iconURL = URL(fileURLWithPath: iconPath)

        // 检查是否已经成功解压过
        if IconManager.shared.isExtractionComplete,
           FileManager.default.fileExists(atPath: destinationPath.path),
           let contents = try? FileManager.default.contentsOfDirectory(atPath: destinationPath.path),
           !contents.isEmpty {
            Logger.debug("Icons folder exists and contains \(contents.count) files, skipping extraction.")
            await MainActor.run {
                databaseManager.loadDatabase()
                isInitialized = true
            }
            return
        }

        // 需要解压
        await MainActor.run {
            needsUnzip = true
        }

        // 如果目录存在但未完全解压，删除它重新解压
        if FileManager.default.fileExists(atPath: destinationPath.path) {
            try? FileManager.default.removeItem(at: destinationPath)
        }

        do {
            try await IconManager.shared.unzipIcons(from: iconURL, to: destinationPath) { progress in
                Task { @MainActor in
                    unzipProgress = progress
                }
            }
            
            await MainActor.run {
                databaseManager.loadDatabase()
                loadingState = .complete
            }
        } catch {
            Logger.error("Error during icons extraction: \(error)")
            // 解压失败时重置状态
            IconManager.shared.isExtractionComplete = false
        }
    }

    private func initializeApp() async {
        do {
            // 在图标解压完成后加载主权数据
            _ = try await SovereigntyDataAPI.shared.fetchSovereigntyData()
            await MainActor.run {
                databaseManager.loadDatabase()
                isInitialized = true
            }
        } catch {
            Logger.error("初始化主权数据失败: \(error)")
            // 即使主权数据加载失败，也继续初始化应用
            await MainActor.run {
                databaseManager.loadDatabase()
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
                        Task {
                            await initializeApp()
                        }
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
