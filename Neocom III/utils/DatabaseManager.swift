import Foundation
import SQLite3

class DatabaseManager: ObservableObject {
    private(set) var db: OpaquePointer? = nil

    // Load the database
    func loadDatabase() {
        // Get the localized database name
        guard let databaseName = getLocalizedDatabaseName() else {
            print("Database name not found")
            return
        }

        // Get the database file path
        if let databasePath = Bundle.main.path(forResource: databaseName, ofType: "sqlite") {
            print("Database found at path: \(databasePath)")
            // Open the database
            if sqlite3_open(databasePath, &db) != SQLITE_OK {
                print("Failed to open database")
            } else {
                print("Database connection successful")
            }
        } else {
            print("Database file not found")
        }
    }

    // Get the localized database name
    private func getLocalizedDatabaseName() -> String? {
        return NSLocalizedString("DatabaseName", comment: "Database file name based on language")
    }

    // Close the database when the app ends
    func closeDatabase() {
        if db != nil {
            sqlite3_close(db)
            db = nil
            print("Database closed")
        }
    }
}
