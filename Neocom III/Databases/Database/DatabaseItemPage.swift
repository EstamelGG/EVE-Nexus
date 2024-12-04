import SwiftUI
import SQLite3

// Data model for DatabaseItem
struct DatabaseItem: Identifiable {
    let id: Int
    let typeID: Int
    let name: String
    let iconFileName: String
    let pgNeed: Int
    let cpuNeed: Int
    let metaGroupID: Int
    let published: Bool
}

// DatabaseItemPage view
struct DatabaseItemPage: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var publishedItems: [DatabaseItem] = []
    @State private var unpublishedItems: [DatabaseItem] = []
    @State private var metaGroupNames: [Int: String] = [:]
    @State private var dataLoaded: Bool = false // 添加标志变量
    
    var groupID: Int
    var groupName: String
    
    var body: some View {
        VStack {
            List {
                if publishedItems.isEmpty && unpublishedItems.isEmpty {
                    Text(NSLocalizedString("Main_Database_nothing_found", comment: ""))
                        .font(.headline)
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    // Published Items
                    if !publishedItems.isEmpty {
                        ForEach(sortedMetaGroupIDs(), id: \.self) { metaGroupID in
                            Section(header: Text(metaGroupNames[metaGroupID] ?? NSLocalizedString("Unknown_MetaGroup", comment: ""))
                                .font(.title3)) {
                                ForEach(publishedItems.filter { $0.metaGroupID == metaGroupID }) { item in
                                    itemRow(for: item)
                                }
                            }
                        }
                    }
                    // Unpublished Items
                    if !unpublishedItems.isEmpty {
                        Section(header: Text(NSLocalizedString("Main_Database_unpublished", comment: "")).font(.title3)) {
                            ForEach(unpublishedItems) { item in
                                itemRow(for: item)
                            }
                        }
                    }
                }
            }
            .navigationTitle(groupName)
            .onAppear {
                // 只在首次加载时调用 loadItems
                if !dataLoaded {
                    loadItems(for: groupID)
                    dataLoaded = true
                }
            }
        }
    }
    
    private func itemRow(for item: DatabaseItem) -> some View {
        NavigationLink(destination: ShowItemInfo(databaseManager: databaseManager, itemID: item.id)) {
            HStack {
                IconManager.shared.loadImage(for: item.iconFileName)
                    .resizable()
                    .frame(width: 36, height: 36)
                    .cornerRadius(6)
                Text(item.name)
            }
        }
    }

    private func sortedMetaGroupIDs() -> [Int] {
        Array(Set(publishedItems.map { $0.metaGroupID })).sorted()
    }
    
    private func loadItems(for groupID: Int) {
        guard let db = databaseManager.db else { return }
        
        let query = """
        SELECT type_id, name, icon_filename, pg_need, cpu_need, metaGroupID, published 
        FROM types 
        WHERE groupID = ? 
        ORDER BY metaGroupID
        """
        
        // 使用通用的查询函数
        let results: [DatabaseItem] = executeQuery(
            db: db,
            query: query,
            bind: { statement in
                sqlite3_bind_int(statement, 1, Int32(groupID))
            },
            resultProcessor: { statement in
                // 创建 DatabaseItem 实例
                let item = DatabaseItem(
                    id: Int(sqlite3_column_int(statement, 0)),
                    typeID: Int(sqlite3_column_int(statement, 0)),
                    name: String(cString: sqlite3_column_text(statement, 1)),
                    iconFileName: String(cString: sqlite3_column_text(statement, 2)).isEmpty ? "items_7_64_15.png" : String(cString: sqlite3_column_text(statement, 2)),
                    pgNeed: Int(sqlite3_column_int(statement, 3)),
                    cpuNeed: Int(sqlite3_column_int(statement, 4)),
                    metaGroupID: Int(sqlite3_column_int(statement, 5)),
                    published: sqlite3_column_int(statement, 6) != 0
                )
                return item
            }
        )

        // 将结果分类到 publishedItems 和 unpublishedItems
        for item in results {
            if item.published {
                publishedItems.append(item)
            } else {
                unpublishedItems.append(item)
            }
            loadMetaGroupName(for: item.metaGroupID)
        }
    }
    
    private func loadMetaGroupName(for metaGroupID: Int) {
        guard let db = databaseManager.db else { return }
        
        let query = "SELECT name FROM metaGroups WHERE metaGroup_id = ?"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(metaGroupID))
            if sqlite3_step(statement) == SQLITE_ROW, let name = sqlite3_column_text(statement, 0) {
                metaGroupNames[metaGroupID] = String(cString: name)
            }
            sqlite3_finalize(statement)
        }
    }
}
