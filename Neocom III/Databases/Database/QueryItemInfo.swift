import SQLite3

struct ItemDetails {
    let name: String
    let description: String
    let iconFileName: String
    let groupName: String
    let categoryName: String
}


class QueryInfo {
    static func loadItemDetails(for itemID: Int, db: OpaquePointer?) -> ItemDetails? {
        guard let db = db else {
            print("Database not available")
            return nil
        }

        let query = """
        SELECT name, description, icon_filename, group_name, category_name 
        FROM types 
        WHERE type_id = ? 
        """

        // 使用通用的查询函数
        let results: [ItemDetails] = executeQuery(
            db: db,
            query: query, bindParams: [itemID],
            bind: { statement in
                sqlite3_bind_int(statement, 1, Int32(itemID))
            },
            resultProcessor: { statement in
                let name = String(cString: sqlite3_column_text(statement, 0))
                let description = String(cString: sqlite3_column_text(statement, 1))
                let iconFileName = String(cString: sqlite3_column_text(statement, 2))
                let groupName = String(cString: sqlite3_column_text(statement, 3))
                let categoryName = String(cString: sqlite3_column_text(statement, 4))
                
                // 检查 iconFileName 是否为空并设置默认值
                let finalIconFileName = iconFileName.isEmpty ? "items_7_64_15.png" : iconFileName
                
                // 返回一个 `ItemDetails` 实例
                return ItemDetails(
                    name: name,
                    description: description,
                    iconFileName: finalIconFileName,
                    groupName: groupName,
                    categoryName: categoryName
                )
            }
        )

        // 如果查询结果不为空，返回第一个作为详情
        return results.first
    }
}
