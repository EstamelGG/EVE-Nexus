import Foundation
import SQLite3

class DatabaseManager: ObservableObject {
    private(set) var db: OpaquePointer? = nil
    @Published var databaseUpdated = false
    
    init() {
        loadDatabase()
    }

    // Load the database
    func loadDatabase() {
        // Close existing database if open
        closeDatabase()
        
        // Get the localized database name
        guard let databaseName = getLocalizedDatabaseName() else {
            print("Database name not found")
            return
        }
        print(databaseName)
        // Get the database file path
        if let databasePath = Bundle.main.path(forResource: databaseName, ofType: "sqlite") {
            print("Database found at path: \(databasePath)")
            // Open the database
            if sqlite3_open(databasePath, &db) != SQLITE_OK {
                print("Failed to open database")
            } else {
                print("Database connection successful")
                // 通知数据库已更新
                DispatchQueue.main.async {
                    self.databaseUpdated.toggle()
                }
            }
        } else {
            print("Database file not found")
        }
    }

    
    private func getLocalizedDatabaseName() -> String? {
        return NSLocalizedString("DatabaseName", comment: "")
    }

    // Close the database when the app ends
    func closeDatabase() {
        if db != nil {
            sqlite3_close(db)
            db = nil
            print("Database closed")
        }
    }
    
    // 重新加载数据库
    func reloadDatabase() {
        loadDatabase()
    }
    
    deinit {
        closeDatabase()
    }
}
