import Foundation
import SQLite3

// SQL查询结果类型
enum SQLiteResult {
    case success([[String: Any]])  // 查询成功，返回结果数组
    case error(String)             // 查询失败，返回错误信息
}

class SQLiteManager {
    // 单例模式
    static let shared = SQLiteManager()
    private var db: OpaquePointer?
    
    // 查询缓存
    private var queryCache: [String: [[String: Any]]] = [:]
    
    // 查询日志
    private var queryLogs: [(query: String, parameters: [Any], timestamp: Date)] = []
    
    private init() {}
    
    // 打开数据库连接
    func openDatabase(withName name: String) -> Bool {
        if let databasePath = Bundle.main.path(forResource: name, ofType: "sqlite") {
            if sqlite3_open(databasePath, &db) == SQLITE_OK {
                print("数据库连接成功: \(databasePath)")
                return true
            }
        }
        print("数据库连接失败")
        return false
    }
    
    // 关闭数据库连接
    func closeDatabase() {
        if db != nil {
            sqlite3_close(db)
            db = nil
            // 清空缓存
            queryCache.removeAll()
            print("数据库已关闭")
        }
    }
    
    // 清除缓存
    func clearCache() {
        queryCache.removeAll()
        print("查询缓存已清空")
    }
    
    // 获取查询日志
    func getQueryLogs() -> [(query: String, parameters: [Any], timestamp: Date)] {
        return queryLogs
    }
    
    // 执行查询并返回结果
    func executeQuery(_ query: String, parameters: [Any] = [], useCache: Bool = true) -> SQLiteResult {
        // 生成缓存键
        let cacheKey = generateCacheKey(query: query, parameters: parameters)
        
        // 如果启用缓存且缓存中存在结果，直接返回
        if useCache, let cachedResult = queryCache[cacheKey] {
            print("从缓存中获取结果: \(cacheKey)")
            return .success(cachedResult)
        }
        
        // 记录查询日志
        queryLogs.append((query: query, parameters: parameters, timestamp: Date()))
        
        var statement: OpaquePointer?
        var results: [[String: Any]] = []
        
        // 准备语句
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) != SQLITE_OK {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            return .error("准备语句失败: \(errorMessage)")
        }
        
        // 绑定参数
        for (index, parameter) in parameters.enumerated() {
            let parameterIndex = Int32(index + 1)
            switch parameter {
            case let value as Int:
                sqlite3_bind_int(statement, parameterIndex, Int32(value))
            case let value as Double:
                sqlite3_bind_double(statement, parameterIndex, value)
            case let value as String:
                sqlite3_bind_text(statement, parameterIndex, (value as NSString).utf8String, -1, nil)
            case let value as Data:
                value.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(statement, parameterIndex, bytes.baseAddress, Int32(value.count), nil)
                }
            case is NSNull:
                sqlite3_bind_null(statement, parameterIndex)
            default:
                sqlite3_finalize(statement)
                return .error("不支持的参数类型: \(type(of: parameter))")
            }
        }
        
        // 执行查询
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: Any] = [:]
            let columnCount = sqlite3_column_count(statement)
            
            for i in 0..<columnCount {
                let columnName = String(cString: sqlite3_column_name(statement, i))
                let columnType = sqlite3_column_type(statement, i)
                
                switch columnType {
                case SQLITE_INTEGER:
                    row[columnName] = Int(sqlite3_column_int64(statement, i))
                case SQLITE_FLOAT:
                    row[columnName] = sqlite3_column_double(statement, i)
                case SQLITE_TEXT:
                    if let text = sqlite3_column_text(statement, i) {
                        row[columnName] = String(cString: text)
                    } else {
                        row[columnName] = ""
                    }
                case SQLITE_BLOB:
                    if let blob = sqlite3_column_blob(statement, i) {
                        let size = Int(sqlite3_column_bytes(statement, i))
                        row[columnName] = Data(bytes: blob, count: size)
                    } else {
                        row[columnName] = Data()
                    }
                case SQLITE_NULL:
                    row[columnName] = nil
                default:
                    row[columnName] = nil
                }
            }
            
            print("查询结果行: \(row)") // 添加调试输出
            results.append(row)
        }
        
        // 释放语句
        sqlite3_finalize(statement)
        
        // 缓存结果
        if useCache {
            queryCache[cacheKey] = results
        }
        
        print("查询总行数: \(results.count)") // 添加调试输出
        return .success(results)
    }
    
    // 生成缓存键
    private func generateCacheKey(query: String, parameters: [Any]) -> String {
        // 将参数转换为字符串
        let paramStrings = parameters.map { param -> String in
            switch param {
            case let value as Int:
                return "i\(value)"  // 添加类型前缀以区分不同类型的相同值
            case let value as Double:
                return "d\(value)"
            case let value as String:
                return "s\(value)"
            case let value as Data:
                return "b\(value.count)"  // 对于二进制数据，只使用其长度
            case is NSNull:
                return "n"
            default:
                return "u"  // unknown
            }
        }
        
        // 组合 SQL 和参数生成缓存键
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let paramString = paramStrings.joined(separator: "|")
        return "\(normalizedQuery)#\(paramString)"
    }
} 