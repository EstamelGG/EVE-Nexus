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

    private func decompressIconsZip() async {
        guard let zipFilePath = Bundle.main.url(forResource: "icons", withExtension: "zip") else {
            print("icons.zip file not found")
            return
        }

        let destinationPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Icons")

        if FileManager.default.fileExists(atPath: destinationPath.path) {
            print("Icons folder already exists, skipping extraction.")
            await MainActor.run {
                unzipProgress = 1.0
                loadingState = .unzippingComplete
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    loadingState = .loadingDB
                }
            }
            return
        }

        do {
            // 创建临时解压目录
            let tempExtractPath = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempExtractPath, withIntermediateDirectories: true)
            
            // 先解压到临时目录
            try Zip.unzipFile(zipFilePath, destination: tempExtractPath, overwrite: true, password: nil)
            
            // 获取所有文件
            let fileEnumerator = FileManager.default.enumerator(at: tempExtractPath, includingPropertiesForKeys: [.fileSizeKey])
            let totalFiles = (try? FileManager.default.contentsOfDirectory(at: tempExtractPath, includingPropertiesForKeys: nil).count) ?? 0
            var processedFiles = 0
            
            // 创建最终目录
            try FileManager.default.createDirectory(at: destinationPath, withIntermediateDirectories: true)
            
            // 逐个移动文件并更新进度
            while let fileURL = fileEnumerator?.nextObject() as? URL {
                let fileName = fileURL.lastPathComponent
                let targetURL = destinationPath.appendingPathComponent(fileName)
                
                try FileManager.default.moveItem(at: fileURL, to: targetURL)
                
                processedFiles += 1
                let progress = Double(processedFiles) / Double(totalFiles)
                
                await MainActor.run {
                    unzipProgress = progress
                }
            }
            
            // 清理临时目录
            try FileManager.default.removeItem(at: tempExtractPath)
            
            print("Successfully unzipped icons.zip to \(destinationPath.path)")
            await MainActor.run {
                unzipProgress = 1.0
                loadingState = .unzippingComplete
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    loadingState = .loadingDB
                }
            }
        } catch {
            print("Error unzipping icons.zip: \(error)")
        }
    }
    
    private func initializeApp() async {
        await decompressIconsZip()
        
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
