import SwiftUI
import SQLite3
import Zip

@main
struct EVE_NexusApp: App {
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
        
        // 使用 PropertyListSerialization 来获取实际的序列化大小
        var sizeMap: [(key: String, size: Int)] = []
        var totalSize: Int = 0
        
        for (key, value) in dictionary {
            if let data = try? PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0) {
                let size = data.count
                totalSize += size
                sizeMap.append((key: key, size: size))
                
                // 检查单个键值对是否过大（比如超过1MB）
                if size > 1_000_000 {
                    Logger.error("警告：键 '\(key)' 的数据大小(\(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)))过大")
                }
            }
        }
        
        // 按大小排序并打印
        sizeMap.sort { $0.size > $1.size }
        for item in sizeMap {
            Logger.info("键: \(item.key), 大小: \(ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file))")
        }
        
        Logger.info("UserDefaults 总大小: \(ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file))")
        
        // 检查总大小是否接近限制（4MB）
        if totalSize > 3_000_000 {
            Logger.error("警告：UserDefaults 总大小接近系统限制(4MB)，请检查是否有过大的数据存储")
        }
        
        // 初始化数据库
        _ = CharacterDatabaseManager.shared  // 确保角色数据库被初始化
        
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
        // 检查图标是否已解压
        if IconManager.shared.isExtractionComplete {
            Logger.info("图标已解压，跳过解压步骤")
            await initializeApp()
            return
        }
        
        // 获取图标文件路径
        guard let iconURL = Bundle.main.url(forResource: "icons", withExtension: "zip") else {
            Logger.error("找不到图标文件")
            await initializeApp()
            return
        }
        
        // 获取解压目标路径
        let fileManager = FileManager.default
        let destinationPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("icons")
        
        // 如果目标文件夹已存在，先删除
        if fileManager.fileExists(atPath: destinationPath.path) {
            do {
                try fileManager.removeItem(at: destinationPath)
            } catch {
                Logger.error("删除旧图标文件夹失败: \(error)")
            }
        }
        
        // 设置需要解压标志
        await MainActor.run {
            needsUnzip = true
        }
        
        do {
            try await IconManager.shared.unzipIcons(from: iconURL, to: destinationPath) { progress in
                Task { @MainActor in
                    unzipProgress = progress
                }
            }
            
            await MainActor.run {
                databaseManager.loadDatabase()
                CharacterDatabaseManager.shared.loadDatabase()  // 加载角色数据库
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
                // 加载静态数据库
                databaseManager.loadDatabase()
                // 加载角色数据库
                CharacterDatabaseManager.shared.loadDatabase()
                isInitialized = true
            }
        } catch {
            Logger.error("初始化主权数据失败: \(error)")
            // 即使主权数据加载失败，也继续初始化应用
            await MainActor.run {
                databaseManager.loadDatabase()
                CharacterDatabaseManager.shared.loadDatabase()
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
