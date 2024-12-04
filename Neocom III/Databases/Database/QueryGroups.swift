import SQLite3

struct Group: Identifiable {
    let id: Int
    let name: String
    let iconID: Int
    let categoryID: Int
    let published: Bool
    let icon_filename: String
}

class QueryGroups {
    static func loadGroups(for categoryID: Int, db: OpaquePointer?) -> ([Group], [Group]) {
        var publishedGroups: [Group] = []
        var unpublishedGroups: [Group] = []
        
        // 确保 db 非 nil
        guard let db = db else {
            return ([], []) // 如果 db 为 nil，返回空数据
        }

        let query = """
        SELECT group_id, name, iconID, categoryID, published, icon_filename 
        FROM groups 
        WHERE categoryID = ? 
        ORDER BY group_id
        """
        
        let groups: [Group] = executeQuery(
            db: db,
            query: query, bindParams: [categoryID],
            bind: { statement in
                sqlite3_bind_int(statement, 1, Int32(categoryID))
            },
            resultProcessor: { statement in
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
            }
        )
        
        // 将分组根据 published 字段分类
        publishedGroups = groups.filter { $0.published }
        unpublishedGroups = groups.filter { !$0.published }

        return (publishedGroups, unpublishedGroups)
    }
}
