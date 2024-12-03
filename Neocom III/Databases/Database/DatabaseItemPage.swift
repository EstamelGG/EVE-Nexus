import SwiftUI
import SQLite3

// Data model for DatabaseItem
struct DatabaseItem: Identifiable {
    let id: Int
    let typeID: Int
    let name: String
    let iconID: Int
    let pgNeed: Int
    let cpuNeed: Int
    let metaGroupID: Int
}

// DatabaseItemPage view
struct DatabaseItemPage: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var items: [DatabaseItem] = []  // 存储查询到的 items 数据
    @State private var metaGroupNames: [Int: String] = [:]  // 存储 metaGroupID 对应的名称
    var groupID: Int  // 当前点击的 groupID
    var groupName: String  // 显示在标题上的 group 名称

    var body: some View {
        VStack {
            // 按照 metaGroupID 分组，显示多个列表
            List {
                ForEach(sortedMetaGroupIDs(), id: \.self) { metaGroupID in
                    Section(header: Text(metaGroupNames[metaGroupID] ?? "Unknown MetaGroup").font(.title3)) {
                        ForEach(items.filter { $0.metaGroupID == metaGroupID }) { item in
                            HStack {
                                // 使用 IconManager 来加载 icon
                                IconManager.shared.loadImage(for: getIconFileName(for: item.iconID))
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
        let query = "SELECT type_id, name, iconID, pg_need, cpu_need, metaGroupID FROM types WHERE groupID = ? ORDER BY metaGroupID"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(groupID))

            while sqlite3_step(statement) == SQLITE_ROW {
                let typeID = Int(sqlite3_column_int(statement, 0))
                let name = String(cString: sqlite3_column_text(statement, 1))
                let iconID = Int(sqlite3_column_int(statement, 2))
                let pgNeed = Int(sqlite3_column_int(statement, 3))
                let cpuNeed = Int(sqlite3_column_int(statement, 4))
                let metaGroupID = Int(sqlite3_column_int(statement, 5))

                // 使用 typeID 作为 id 来创建 DatabaseItem 对象
                let item = DatabaseItem(id: typeID, typeID: typeID, name: name, iconID: iconID, pgNeed: pgNeed, cpuNeed: cpuNeed, metaGroupID: metaGroupID)

                // 获取 metaGroupID 对应的名称
                loadMetaGroupName(for: metaGroupID)

                items.append(item)
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

    // 获取 icon 文件名
    private func getIconFileName(for iconID: Int) -> String {
        guard let db = databaseManager.db else {
            return "items_73_16_50.png"  // 默认图标
        }

        let query = "SELECT iconFile_new FROM iconIDs WHERE icon_id = ?"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(iconID))

            if sqlite3_step(statement) == SQLITE_ROW {
                if let iconFileNew = sqlite3_column_text(statement, 0) {
                    let iconFileName = String(cString: iconFileNew)
                    sqlite3_finalize(statement)
                    return iconFileName
                }
            }

            sqlite3_finalize(statement)
        }

        return "items_73_16_50.png"  // 默认图标
    }
}
