import SwiftUI
import SQLite3

// Data model for Group
struct Group: Identifiable {
    let id: Int
    let name: String
    let iconID: Int
    let categoryID: Int
    let published: Bool
    let icon_filename: String
}

// DatabaseGroupPage view
struct DatabaseGroupPage: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var publishedGroups: [Group] = []
    @State private var unpublishedGroups: [Group] = []
    @State private var searchText: String = ""
    @State private var dataLoaded: Bool = false // 添加标志变量
    
    // The categoryID passed from the previous page
    var categoryID: Int
    var categoryName: String // Added categoryName to be used as the title
    
    var body: some View {
        SearchBar(text: $searchText)
            .padding(.top)
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
                        Section(header: Text(NSLocalizedString("Main_Database_published", comment: "")).font(.headline).foregroundColor(.primary)) {
                            ForEach(publishedGroups) { group in
                                // NavigationLink to DatabaseItemPage, passing the groupID and groupName
                                NavigationLink(destination: DatabaseItemPage(databaseManager: databaseManager, groupID: group.id, groupName: group.name)) {
                                    HStack {
                                        // Load the group's icon
                                        IconManager.shared.loadImage(for: group.icon_filename)
                                            .resizable()
                                            .frame(width: 36, height: 36)
                                        Text(group.name)
                                    }
                                }
                            }
                        }
                    }

                    if !unpublishedGroups.isEmpty {
                        Section(header: Text(NSLocalizedString("Main_Database_unpublished", comment: "")).font(.headline).foregroundColor(.primary)) {
                            ForEach(unpublishedGroups) { group in
                                // NavigationLink to DatabaseItemPage, passing the groupID and groupName
                                NavigationLink(destination: DatabaseItemPage(databaseManager: databaseManager, groupID: group.id, groupName: group.name)) {
                                    HStack {
                                        // Load the group's icon
                                        IconManager.shared.loadImage(for: group.icon_filename)
                                            .resizable()
                                            .frame(width: 36, height: 36)
                                            .cornerRadius(6)
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
                // 只在首次加载时调用 loadGroups
                if !dataLoaded {
                    loadGroups(for: categoryID)
                    dataLoaded = true
                }
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
        let query = "SELECT group_id, name, iconID, categoryID, published, icon_filename FROM groups WHERE categoryID = ? ORDER BY group_id"
        
        let groups = executeQuery(db: db, query: query, bindParams: [categoryID], bind: { statement in
            // 绑定 categoryID 到查询
            sqlite3_bind_int(statement, 1, Int32(categoryID))
        }, resultProcessor: { statement in
            let id = Int(sqlite3_column_int(statement, 0))
            var name = String(cString: sqlite3_column_text(statement, 1))
            if name.isEmpty {
                name = "Unknown"
            }
            let iconID = Int(sqlite3_column_int(statement, 2))
            let categoryID = Int(sqlite3_column_int(statement, 3))
            let published = sqlite3_column_int(statement, 4) != 0
            var icon_filename = String(cString: sqlite3_column_text(statement, 5))
            if icon_filename.isEmpty {
                icon_filename = "items_73_16_50.png"
            }
            
            return Group(id: id, name: name, iconID: iconID, categoryID: categoryID, published: published, icon_filename: icon_filename)
        })

        // 根据 published 字段分组
        let publishedGroups = groups.filter { $0.published }
        let unpublishedGroups = groups.filter { !$0.published }

        return (publishedGroups, unpublishedGroups)
    }
}
