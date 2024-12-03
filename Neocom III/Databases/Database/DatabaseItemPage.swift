import SwiftUI
import SQLite3

// Data model for DatabaseItem
struct DatabaseItem: Identifiable {
    let id: Int
    let typeID: Int
    let name: String
    let iconFileName: String // 直接存储图标文件名
    let pgNeed: Int
    let cpuNeed: Int
    let metaGroupID: Int
    let published: Bool
}

// DatabaseItemPage view
struct DatabaseItemPage: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var items: [DatabaseItem] = []  // 存储已发布的 items 数据
    @State private var unpublishedItems: [DatabaseItem] = []  // 存储未发布的 items 数据
    @State private var metaGroupNames: [Int: String] = [:]  // 存储 metaGroupID 对应的名称
    var groupID: Int  // 当前点击的 groupID
    var groupName: String  // 显示在标题上的 group 名称

    var body: some View {
        VStack {
            // 按照 metaGroupID 分组，显示多个列表
            List {
                if items.isEmpty && unpublishedItems.isEmpty {
                    // 显示空数据提示
                    Text(NSLocalizedString("Main_Database_nothing_found", comment: ""))
                        .font(.headline)
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    // 显示已发布的项目
                    ForEach(sortedMetaGroupIDs(), id: \.self) { metaGroupID in
                        Section(header: Text(metaGroupNames[metaGroupID] ?? NSLocalizedString("Unknown_MetaGroup", comment: ""))
                                    .font(.title3)) {
                            ForEach(items.filter { $0.metaGroupID == metaGroupID }) { item in
                                HStack {
                                    // 使用 IconManager 来加载 icon
                                    IconManager.shared.loadImage(for: item.iconFileName)
                                        .resizable()
                                        .frame(width: 36, height: 36)
                                    Text(item.name)
                                }
                            }
                        }
                    }
                }

                // 显示未发布的项目
                if !unpublishedItems.isEmpty {
                    Section(header: Text(NSLocalizedString("Main_Database_unpublished", comment: ""))) {
                        ForEach(unpublishedItems) { item in
                            HStack {
                                // 使用 IconManager 来加载 icon
                                IconManager.shared.loadImage(for: item.iconFileName)
                                    .resizable()
                                    .frame(width: 36, height: 36)
                                Text(item.name)
                            }
                        }
                    }
                }
            }
            .navigationTitle(groupName)  // 使用 groupName 作为页面标题
            .onAppear {
                loadItems(for: groupID)
            }
        }
    }

    // 按 metaGroupID 排序
    private func sortedMetaGroupIDs() -> [Int] {
        return Array(Set(items.map { $0.metaGroupID })).sorted()
    }

    // 加载 groupID 对应的所有 items 数据
    private func loadItems(for groupID: Int) {
        guard let db = databaseManager.db else {
            print("Database not available")
            return
        }

        // 查询 types 表，获取 groupID 对应的所有项目
        let query = """
        SELECT type_id, name, icon_filename, pg_need, cpu_need, metaGroupID, published 
        FROM types 
        WHERE groupID = ? 
        ORDER BY metaGroupID
        """
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(groupID))

            while sqlite3_step(statement) == SQLITE_ROW {
                let typeID = Int(sqlite3_column_int(statement, 0))
                let name = String(cString: sqlite3_column_text(statement, 1))
                let iconFileName = String(cString: sqlite3_column_text(statement, 2))
                let pgNeed = Int(sqlite3_column_int(statement, 3))
                let cpuNeed = Int(sqlite3_column_int(statement, 4))
                let metaGroupID = Int(sqlite3_column_int(statement, 5))
                let published = sqlite3_column_int(statement, 6) != 0
                // 如果 iconFileName 为空，使用默认值
                let finalIconFileName = iconFileName.isEmpty ? "items_7_64_15.png" : iconFileName

                // 创建 DatabaseItem 对象
                let item = DatabaseItem(
                    id: typeID,
                    typeID: typeID,
                    name: name,
                    iconFileName: finalIconFileName,
                    pgNeed: pgNeed,
                    cpuNeed: cpuNeed,
                    metaGroupID: metaGroupID,
                    published: published
                )

                if published {
                    // 如果 published 为 true，加入已发布列表
                    items.append(item)
                    loadMetaGroupName(for: metaGroupID)
                } else {
                    // 如果 published 为 false，加入未发布列表
                    unpublishedItems.append(item)
                }
            }

            sqlite3_finalize(statement)
        } else {
            print("Failed to prepare statement")
        }
    }

    // 加载 metaGroupID 对应的名称
    private func loadMetaGroupName(for metaGroupID: Int) {
        guard let db = databaseManager.db else {
            return
        }

        let query = "SELECT name FROM metaGroups WHERE metaGroup_id = ?"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(metaGroupID))

            if sqlite3_step(statement) == SQLITE_ROW {
                if let name = sqlite3_column_text(statement, 0) {
                    let metaGroupName = String(cString: name)
                    metaGroupNames[metaGroupID] = metaGroupName
                }
            }

            sqlite3_finalize(statement)
        }
    }
}
