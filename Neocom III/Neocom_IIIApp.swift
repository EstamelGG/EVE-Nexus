import SwiftUI
import SwiftData
import Zip

@main
struct Neocom_IIIApp: App {
    @AppStorage("selectedLanguage") private var selectedLanguage: String?

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    // Initialize language settings
    init() {
        if let language = selectedLanguage {
            // Set the app language
            UserDefaults.standard.set([language], forKey: "AppleLanguages")
            UserDefaults.standard.synchronize()
        } else {
            // Use the system default language
            let systemLanguage = Locale.preferredLanguages.first ?? "en"
            UserDefaults.standard.set([systemLanguage], forKey: "AppleLanguages")
            UserDefaults.standard.synchronize()
        }

        // Decompress the icons.zip file only if the Icons folder doesn't exist
        decompressIconsZip()
    }

    // Decompress icons.zip file (only if the folder doesn't exist)
    private func decompressIconsZip() {
        // Get the path to the app's resources
        guard let zipFilePath = Bundle.main.url(forResource: "icons", withExtension: "zip") else {
            print("icons.zip file not found")
            return
        }

        // Get the destination folder for the unzipped files
        let destinationPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Icons")

        // Check if the destination folder exists
        if FileManager.default.fileExists(atPath: destinationPath.path) {
            // If the folder exists, don't unzip again
            print("Icons folder already exists, skipping extraction.")
            return
        }

        // If the folder doesn't exist, unzip the file
        do {
            try Zip.unzipFile(zipFilePath, destination: destinationPath, overwrite: true, password: nil)
            print("Successfully unzipped icons.zip to \(destinationPath.path)")
        } catch {
            print("Error unzipping icons.zip: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
