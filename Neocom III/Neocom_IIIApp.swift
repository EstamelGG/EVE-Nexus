import SwiftUI
import SQLite3
import Zip

@main
struct Neocom_IIIApp: App {
    @AppStorage("selectedLanguage") private var selectedLanguage: String?
    @StateObject private var databaseManager = DatabaseManager() // 共享的数据库管理器

    init() {
        // 设置语言
        configureLanguage()
        // 解压图标文件
        decompressIconsZip()
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

    private func decompressIconsZip() {
        guard let zipFilePath = Bundle.main.url(forResource: "icons", withExtension: "zip") else {
            print("icons.zip file not found")
            return
        }

        let destinationPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Icons")

        if FileManager.default.fileExists(atPath: destinationPath.path) {
            print("Icons folder already exists, skipping extraction.")
            return
        }

        do {
            try Zip.unzipFile(zipFilePath, destination: destinationPath, overwrite: true, password: nil)
            print("Successfully unzipped icons.zip to \(destinationPath.path)")
        } catch {
            print("Error unzipping icons.zip: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(databaseManager: databaseManager)
                .onAppear {
                    // 在应用启动时加载数据库
                    databaseManager.loadDatabase()
                }
        }
    }
}
