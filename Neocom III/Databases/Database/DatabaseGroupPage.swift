import SwiftUI
import SQLite3

// Data model for Group
struct Group: Identifiable {
    let id: Int
    let name: String
    let iconID: Int
    let categoryID: Int
    let published: Bool  // Added published field
}

// DatabaseGroupPage view
struct DatabaseGroupPage: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var publishedGroups: [Group] = []
    @State private var unpublishedGroups: [Group] = []
    
    // The categoryID passed from the previous page
    var categoryID: Int
    var categoryName: String // Added categoryName to be used as the title
    
    var body: some View {
        VStack {
            // List of groups, divided by published and unpublished categories
            List {
                if publishedGroups.isEmpty && unpublishedGroups.isEmpty {
                    // 显示空数据提示
                    Text(NSLocalizedString("Main_Database_nothing_found", comment: ""))
                        .font(.headline)
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    if !publishedGroups.isEmpty {
                        Section(header: Text(NSLocalizedString("Main_Database_published", comment: "")).font(.title3)) {
                            ForEach(publishedGroups) { group in
                                // NavigationLink to DatabaseItemPage, passing the groupID and groupName
                                NavigationLink(destination: DatabaseItemPage(databaseManager: databaseManager, groupID: group.id, groupName: group.name)) {
                                    HStack {
                                        // Load the group's icon
                                        IconManager.shared.loadImage(for: getIconFileName(for: group.iconID))
                                            .resizable()
                                            .frame(width: 36, height: 36)
                                        Text(group.name)
                                    }
                                }
                            }
                        }
                    }

                    if !unpublishedGroups.isEmpty {
                        Section(header: Text(NSLocalizedString("Main_Database_unpublished", comment: "")).font(.title3)) {
                            ForEach(unpublishedGroups) { group in
                                // NavigationLink to DatabaseItemPage, passing the groupID and groupName
                                NavigationLink(destination: DatabaseItemPage(databaseManager: databaseManager, groupID: group.id, groupName: group.name)) {
                                    HStack {
                                        // Load the group's icon
                                        IconManager.shared.loadImage(for: getIconFileName(for: group.iconID))
                                            .resizable()
                                            .frame(width: 36, height: 36)
                                        Text(group.name)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(categoryName) // Use the category's name as the title
            .onAppear {
                loadGroups(for: categoryID)
            }
        }
    }

    // Load groups from the database based on categoryID
    private func loadGroups(for categoryID: Int) {
        guard let db = databaseManager.db else {
            print("Database not available")
            return
        }

        // Load groups from the database
        let (published, unpublished) = loadGroupsFromDatabase(for: categoryID, db: db)
        publishedGroups = published
        unpublishedGroups = unpublished
    }

    // Query the database for groups of a specific category
    private func loadGroupsFromDatabase(for categoryID: Int, db: OpaquePointer) -> ([Group], [Group]) {
        var publishedGroups: [Group] = []
        var unpublishedGroups: [Group] = []
        let query = "SELECT group_id, name, iconID, categoryID, published FROM groups WHERE categoryID = ? ORDER BY group_id"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            // Bind categoryID to the query
            sqlite3_bind_int(statement, 1, Int32(categoryID))

            while sqlite3_step(statement) == SQLITE_ROW {
                let id = Int(sqlite3_column_int(statement, 0))
                let name = String(cString: sqlite3_column_text(statement, 1))
                let iconID = Int(sqlite3_column_int(statement, 2))
                let categoryID = Int(sqlite3_column_int(statement, 3))
                let published = sqlite3_column_int(statement, 4) != 0  // Check published flag

                let group = Group(id: id, name: name, iconID: iconID, categoryID: categoryID, published: published)
                
                // Separate published and unpublished groups
                if published {
                    publishedGroups.append(group)
                } else {
                    unpublishedGroups.append(group)
                }
            }
            sqlite3_finalize(statement)
        } else {
            print("Failed to prepare statement")
        }

        return (publishedGroups, unpublishedGroups)
    }

    // Helper function to get the icon file name for a group
    private func getIconFileName(for iconID: Int) -> String {
        guard let db = databaseManager.db else {
            return "items_73_16_50.png"  // Default image if database is unavailable
        }
        if iconID == 0 {
                return "items_73_16_50.png"
            }

        // Query iconIDs table to get the iconFile_new for the given iconID
        let query = "SELECT iconFile_new FROM iconIDs WHERE icon_id = ?"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            // Bind the iconID to the query
            sqlite3_bind_int(statement, 1, Int32(iconID))

            if sqlite3_step(statement) == SQLITE_ROW {
                // Get the iconFile_new from the query result
                if let iconFileNew = sqlite3_column_text(statement, 0) {
                    var iconFileName = String(cString: iconFileNew)
                    
                    // 检查 iconFileName 是否为空
                    if iconFileName.isEmpty {
                        iconFileName = "items_73_16_50.png" // 赋值默认值
                    }
                    
                    sqlite3_finalize(statement)
                    
                    return iconFileName // 返回最终的 iconFileName 值
                }
            }
            sqlite3_finalize(statement)
        }

        // If no result or if iconID is 0, return default image
        return "items_73_16_50.png"
    }
}
