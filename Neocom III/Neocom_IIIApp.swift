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
    @State private var needsUnzip = false

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

    private func checkAndExtractIcons() async {
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
            print("Error during icons extraction: \(error)")
            // 解压失败时重置状态
            IconManager.shared.isExtractionComplete = false
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if isInitialized {
                    ContentView(databaseManager: databaseManager)
                } else if needsUnzip {
                    LoadingView(loadingState: $loadingState, progress: unzipProgress) {
                        isInitialized = true
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
