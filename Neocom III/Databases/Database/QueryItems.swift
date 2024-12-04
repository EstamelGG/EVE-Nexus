import SQLite3

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

class QueryItems {
    static func loadItems(for groupID: Int, db: OpaquePointer?) -> (publishedItems: [DatabaseItem], unpublishedItems: [DatabaseItem], metaGroupNames: [Int: String]) {
        var publishedItems: [DatabaseItem] = []
        var unpublishedItems: [DatabaseItem] = []
        var metaGroupNames: [Int: String] = [:]
        
        // 确保 db 非 nil
        guard let db = db else {
            return ([], [], [:]) // 如果 db 为 nil，返回空数据
        }

        let query = """
        SELECT type_id, name, icon_filename, pg_need, cpu_need, metaGroupID, published
        FROM types
        WHERE groupID = ?
        ORDER BY metaGroupID
        """
        
        let results: [DatabaseItem] = executeQuery(
            db: db,
            query: query, bindParams: [groupID],
            bind: { statement in
                sqlite3_bind_int(statement, 1, Int32(groupID))
            },
            resultProcessor: { statement in
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
            loadMetaGroupName(for: item.metaGroupID, db: db, metaGroupNames: &metaGroupNames)
        }
        
        return (publishedItems, unpublishedItems, metaGroupNames)
    }

    private static func loadMetaGroupName(for metaGroupID: Int, db: OpaquePointer, metaGroupNames: inout [Int: String]) {
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
