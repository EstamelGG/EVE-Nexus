import SwiftUI
import SQLite3

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

        // 检查目录是否存在并且不为空
        if FileManager.default.fileExists(atPath: destinationPath.path),
           let contents = try? FileManager.default.contentsOfDirectory(atPath: destinationPath.path),
           !contents.isEmpty {
            print("Icons folder exists and contains \(contents.count) files, skipping extraction.")
            await MainActor.run {
                unzipProgress = 1.0
                loadingState = .unzippingComplete
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    loadingState = .loadingDB
                }
            }
            return
        }

        // 如果目录存在但为空，删除它
        if FileManager.default.fileExists(atPath: destinationPath.path) {
            try? FileManager.default.removeItem(at: destinationPath)
        }

        do {
            let iconURL = URL(fileURLWithPath: iconPath)
            try await IconManager.shared.unzipIcons(from: iconURL, to: destinationPath) { progress in
                Task { @MainActor in
                    unzipProgress = progress
                }
            }
            
            print("Successfully extracted icons to \(destinationPath.path)")
            await MainActor.run {
                unzipProgress = 1.0
                loadingState = .unzippingComplete
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    loadingState = .loadingDB
                }
            }
        } catch {
            print("Error during icons extraction: \(error)")
        }
    }
    
    private func initializeApp() async {
        // 解压图标
        await extractIcons()
        
        // 加载数据库
        await MainActor.run {
            databaseManager.loadDatabase()
            loadingState = .loadingDBComplete
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
