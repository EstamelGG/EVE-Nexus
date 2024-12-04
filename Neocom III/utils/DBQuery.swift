import SQLite3

// 通用的 SQL 查询函数
public func executeQuery<T>(db: OpaquePointer, query: String, bind: ((OpaquePointer) -> Void)? = nil, resultProcessor: (OpaquePointer) -> T?) -> [T] {
    var results: [T] = []
    var statement: OpaquePointer?

    // 准备 SQL 查询语句
    if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK, let statement = statement {
        
        // 绑定参数（如果有）
        bind?(statement)

        while sqlite3_step(statement) == SQLITE_ROW {
            if let result = resultProcessor(statement) {
                results.append(result)
            }
        }
        sqlite3_finalize(statement)
    } else {
        print("Failed to prepare statement")
    }

    return results
}
