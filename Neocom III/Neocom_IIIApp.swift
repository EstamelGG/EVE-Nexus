import SwiftUI
import SQLite3
import Zip

@main
struct Neocom_IIIApp: App {
    @AppStorage("selectedLanguage") private var selectedLanguage: String?
    @StateObject private var databaseManager = DatabaseManager()
    @State private var loadingState: LoadingState = .unzipping
    @State private var isInitialized = false
    @State private var unzipProgress: Double = 0

    init() {
        configureLanguage()
    }

    private func configureLanguage() {
        if let language = selectedLanguage {
            UserDefaults.standard.set([language], forKey: "AppleLanguages")
            UserDefaults.standard.synchronize()
        } else {
            let systemLanguage = Locale.preferredLanguages.first ?? "en"
            UserDefaults.standard.set([systemLanguage], forKey: "AppleLanguages")
            UserDefaults.standard.synchronize()
        }
    }

    private func extractIcons() async {
        guard let iconPath = Bundle.main.path(forResource: "icons", ofType: "zip") else {
            print("icons.zip file not found in bundle")
            return
        }

        let destinationPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Icons")
        let iconURL = URL(fileURLWithPath: iconPath)

        // 检查是否已经成功解压过
        if IconManager.shared.isExtractionComplete,
           FileManager.default.fileExists(atPath: destinationPath.path),
           let contents = try? FileManager.default.contentsOfDirectory(atPath: destinationPath.path),
           !contents.isEmpty {
            print("Icons folder exists and contains \(contents.count) files, skipping extraction.")
            await MainActor.run {
                unzipProgress = 1.0
                loadingState = .unzippingComplete
            }
            return
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
                unzipProgress = 1.0
                loadingState = .unzippingComplete
            }
        } catch {
            print("Error during icons extraction: \(error)")
            // 解压失败时重置状态
            IconManager.shared.isExtractionComplete = false
        }
    }
    
    private func initializeApp() async {
        // 解压图标
        await extractIcons()
        
        // 加载数据库
        await MainActor.run {
            databaseManager.loadDatabase()
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if isInitialized {
                    ContentView(databaseManager: databaseManager)
                } else {
                    LoadingView(loadingState: $loadingState, progress: unzipProgress) {
                        isInitialized = true
                    }
                    .onAppear {
                        Task {
                            await initializeApp()
                        }
                    }
                }
            }
        }
    }
}
