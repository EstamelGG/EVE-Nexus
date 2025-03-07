import CommonCrypto
import SQLite3
import SwiftUI
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

        // 检查并设置useEnglishSystemNames的默认值
        if defaults.object(forKey: "useEnglishSystemNames") == nil {
            Logger.debug("正在初始化 useEnglishSystemNames 为 true")
            defaults.set(true, forKey: "useEnglishSystemNames")
        }

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

        Logger.info(
            "UserDefaults 总大小: \(ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file))"
        )

        // 检查总大小是否接近限制（4MB）
        if totalSize > 3_000_000 {
            Logger.error("警告：UserDefaults 总大小接近系统限制(4MB)，请检查是否有过大的数据存储")
        }
        // 按大小排序并打印
        sizeMap.sort { $0.size > $1.size }
        for item in sizeMap {
            Logger.info(
                "键: \(item.key), 大小: \(ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file))"
            )
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
            Logger.info(
                "App初始化: 角色 \(character.character.CharacterName) (\(characterId)) - \(hasValidToken ? "有效token" : "无效token")"
            )

            // 如果没有有效的 token，移除该角色
            if !hasValidToken {
                Logger.info(
                    "App初始化: 移除无效 token 的角色 - \(character.character.CharacterName) (\(characterId))"
                )
                EVELogin.shared.removeCharacter(characterId: characterId)
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

        // 计算当前 icons.zip 的 SHA256 值
        let currentHash = calculateSHA256(filePath: iconPath)
        let storedHash = UserDefaults.standard.string(forKey: "IconsZipHash")

        // 如果哈希值不同，需要重新解压
        let needsReExtract = currentHash != storedHash

        // 检查是否已经成功解压过
        if !needsReExtract,
            IconManager.shared.isExtractionComplete,
            FileManager.default.fileExists(atPath: destinationPath.path),
            let contents = try? FileManager.default.contentsOfDirectory(
                atPath: destinationPath.path),
            !contents.isEmpty
        {
            Logger.debug(
                "Icons folder exists and contains \(contents.count) files, skipping extraction.")
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
            try await IconManager.shared.unzipIcons(from: iconURL, to: destinationPath) {
                progress in
                Task { @MainActor in
                    unzipProgress = progress
                }
            }

            // 保存新的哈希值
            if let hash = currentHash {
                UserDefaults.standard.set(hash, forKey: "IconsZipHash")
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

    private func calculateSHA256(filePath: String) -> String? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)) else {
            return nil
        }

        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))

        _ = data.withUnsafeBytes { buffer in
            CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &digest)
        }

        return digest.reduce("") { $0 + String(format: "%02x", $1) }
    }

    private func initializeDatabases() {
        // 初始化静态数据库
        databaseManager.loadDatabase()
        // 初始化角色数据库
        CharacterDatabaseManager.shared.loadDatabase()
    }

    private func initializeApp() async {
        do {
            // 在图标解压完成后加载主权数据
            _ = try await SovereigntyDataAPI.shared.fetchSovereigntyData()
            await MainActor.run {
                databaseManager.loadDatabase()
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
