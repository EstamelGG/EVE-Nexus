import SQLite3

/// 通用的 SQL 查询函数
/// - Parameters:
///   - db: 数据库指针
///   - query: 要执行的 SQL 查询语句
///   - bind: 可选的绑定参数闭包（默认为 `nil`），用于在查询中绑定变量
///   - resultProcessor: 结果处理闭包，用于将每一行的结果转换为指定类型
/// - Returns: 返回一个包含查询结果的数组
public func executeQuery<T>(
    db: OpaquePointer,
    query: String,
    bind: ((OpaquePointer) -> Void)? = nil,
    resultProcessor: @escaping (OpaquePointer) -> T?
) -> [T] {
    var results: [T] = []
    var statement: OpaquePointer?

    // 准备 SQL 查询语句
    if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK, let statement = statement {
        
        // 绑定参数（如果有）
        bind?(statement)

        // 执行查询并处理每一行结果
        print("Execute sql: \(query)")
        while sqlite3_step(statement) == SQLITE_ROW {
            if let result = resultProcessor(statement) {
                results.append(result)
            }
        }

        // 释放 statement 资源
        sqlite3_finalize(statement)
    } else {
        // 查询准备失败时打印错误信息
        let errorMessage = String(cString: sqlite3_errmsg(db))
        print("Failed to prepare statement: \(errorMessage)")
    }

    return results
}
