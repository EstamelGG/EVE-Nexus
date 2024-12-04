import SQLite3
import Foundation

/// 创建缓存实例，缓存 SQL 查询结果
let sqlCache = NSCache<NSString, NSArray>()

/// 通用的 SQL 查询函数
/// - Parameters:
///   - db: 数据库指针
///   - query: 要执行的 SQL 查询语句
///   - bindParams: 用于调试打印的参数数组，每个元素对应一个参数的值
///   - bind: 用于实际绑定参数到查询的闭包（默认为空闭包）
///   - resultProcessor: 结果处理闭包，用于将每一行的结果转换为指定类型
/// - Returns: 返回一个包含查询结果的数组
public func executeQuery<T>(
    db: OpaquePointer,
    query: String,
    bindParams: [Any], // 调试用的参数
    bind: ((OpaquePointer) -> Void)? = nil, // 用于绑定参数到 SQL 查询，默认为空闭包
    resultProcessor: @escaping (OpaquePointer) -> T?
) -> [T] {
    var results: [T] = []
    var statement: OpaquePointer?

    // 拼接查询语句
    var modifiedQuery = query
    var paramIndex = 0
    
    // 替换 query 中的所有 '?' 占位符
    for param in bindParams {
        let paramDescription = String(describing: param)
        // 替换第一个 "?" 为参数值
        if let range = modifiedQuery.range(of: "?") {
            modifiedQuery.replaceSubrange(range, with: paramDescription)
        }
        paramIndex += 1
    }
    
    // 生成用于缓存的查询键（去除绑定参数，仅使用查询语句）
    let cacheKey = modifiedQuery as NSString

    // 检查缓存中是否已经有该查询结果
    if let cachedResults = sqlCache.object(forKey: cacheKey) as? [T] {
        //print("Cache hit for SQL query: \(modifiedQuery)\n")
        return cachedResults
    }

    // 准备 SQL 查询语句
    if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK, let statement = statement {
        
        // 绑定参数到 SQL 查询，如果 bind 不为 nil 则执行
        bind?(statement)
        // 打印拼接后的查询语句
        //print("Execute SQL: \(modifiedQuery)\n")
        // 执行查询并处理每一行结果
        while sqlite3_step(statement) == SQLITE_ROW {
            if let result = resultProcessor(statement) {
                results.append(result)
            }
        }

        // 释放 statement 资源
        sqlite3_finalize(statement)
        
        // 缓存查询结果，限制缓存最大条数为 100
        if sqlCache.countLimit < 100 {
            sqlCache.setObject(results as NSArray, forKey: cacheKey)
        } else {
            // 如果缓存条目超过限制，移除最旧的条目
            sqlCache.removeAllObjects()
            sqlCache.setObject(results as NSArray, forKey: cacheKey)
        }
    } else {
        // 查询准备失败时打印错误信息
        let errorMessage = String(cString: sqlite3_errmsg(db))
        print("Failed to prepare statement: \(errorMessage)")
    }

    return results
}
