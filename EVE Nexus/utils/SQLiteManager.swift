import Foundation
import SQLite3

// SQL查询结果类型
enum SQLiteResult {
    case success([[String: Any]])  // 查询成功，返回结果数组
    case error(String)  // 查询失败，返回错误信息
}

class SQLiteManager {
    // 单例模式
    static let shared = SQLiteManager()
    private var db: OpaquePointer?

    // 查询缓存
    private let queryCache: NSCache<NSString, NSArray> = {
        let cache = NSCache<NSString, NSArray>()
        cache.countLimit = 2000  // 设置最大缓存条数
        return cache
    }()

    // 查询日志和同步机制
    private let logsQueue = DispatchQueue(label: "com.eve.nexus.sqlite.logs")
    private var queryLogs: [(query: String, parameters: [Any], timestamp: Date)] = []

    // 数据库操作队列
    private let dbQueue = DispatchQueue(label: "com.eve.nexus.sqlite.db")
    private let dbLock = NSLock()

    private init() {}

    // 打开数据库连接
    func openDatabase(withName name: String) -> Bool {
        return dbQueue.sync {
            dbLock.lock()
            defer { dbLock.unlock() }

            if let databasePath = Bundle.main.path(forResource: name, ofType: "sqlite") {
                if sqlite3_open(databasePath, &db) == SQLITE_OK {
                    Logger.info("数据库连接成功: \(databasePath)")
                    return true
                }
            }
            Logger.error("数据库连接失败")
            return false
        }
    }

    // 关闭数据库连接
    func closeDatabase() {
        dbQueue.sync {
            dbLock.lock()
            defer { dbLock.unlock() }

            if db != nil {
                sqlite3_close(db)
                db = nil
                // 清空缓存
                clearCache()
                Logger.info("数据库已关闭")
            }
        }
    }

    // 清除缓存
    func clearCache() {
        queryCache.removeAllObjects()
        Logger.info("查询缓存已清空")
    }

    // 获取查询日志
    func getQueryLogs() -> [(query: String, parameters: [Any], timestamp: Date)] {
        return logsQueue.sync {
            queryLogs
        }
    }

    // 添加查询日志
    private func addQueryLog(query: String, parameters: [Any]) {
        logsQueue.async {
            self.queryLogs.append((query: query, parameters: parameters, timestamp: Date()))
        }
    }

    // 执行查询并返回结果
    func executeQuery(_ query: String, parameters: [Any] = [], useCache: Bool = true)
        -> SQLiteResult
    {
        return dbQueue.sync {
            dbLock.lock()
            defer { dbLock.unlock() }

            // 对参数进行排序以生成一致的缓存键
            let sortedParameters: [Any]
            if parameters.count > 1 {
                // 对参数进行排序，确保相同参数集合但顺序不同的查询能够使用相同的缓存
                sortedParameters = parameters.sorted { 
                    let str1 = String(describing: $0)
                    let str2 = String(describing: $1)
                    return str1 < str2
                }
            } else {
                sortedParameters = parameters
            }

            // 生成缓存键
            let cacheKey = generateCacheKey(query: query, parameters: sortedParameters) as NSString

            // 如果启用缓存且缓存中存在结果，直接返回
            if useCache, let cachedResult = queryCache.object(forKey: cacheKey) as? [[String: Any]]
            {
                // Logger.debug("从缓存中获取结果: \(cacheKey)")
                return .success(cachedResult)
            }
            
            // 记录开始时间
            let startTime = CFAbsoluteTimeGetCurrent()
            
            Logger.info("\(query)?#\(parameters)")
            // 记录查询日志
            addQueryLog(query: query, parameters: parameters)

            var statement: OpaquePointer?
            var results: [[String: Any]] = []

            // 准备语句
            if sqlite3_prepare_v2(db, query, -1, &statement, nil) != SQLITE_OK {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                Logger.error("准备语句失败: \(errorMessage)")
                return .error("准备语句失败: \(errorMessage)")
            }

            // 绑定参数 - 使用原始参数顺序，而不是排序后的参数
            for (index, parameter) in parameters.enumerated() {
                let parameterIndex = Int32(index + 1)
                switch parameter {
                case let value as Int:
                    sqlite3_bind_int64(statement, parameterIndex, Int64(value))
                case let value as Double:
                    sqlite3_bind_double(statement, parameterIndex, value)
                case let value as String:
                    sqlite3_bind_text(
                        statement, parameterIndex, (value as NSString).utf8String, -1, nil
                    )
                case let value as Data:
                    value.withUnsafeBytes { bytes in
                        _ = sqlite3_bind_blob(
                            statement, parameterIndex, bytes.baseAddress, Int32(value.count), nil
                        )
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
                    if let value = getValue(from: statement, column: i) {
                        row[columnName] = value
                    }
                }

                // Logger.debug("查询结果行: \(row)")
                results.append(row)
            }

            // 释放语句
            sqlite3_finalize(statement)
            
            // 计算查询耗时
            let endTime = CFAbsoluteTimeGetCurrent()
            let elapsedTime = (endTime - startTime) * 1000 // 转换为毫秒
            
            // 记录查询耗时
            Logger.info("查询耗时: \(String(format: "%.2f", elapsedTime))ms")

            // 缓存结果
            if useCache {
                // Logger.info("记录到缓存中: \(cacheKey)")
                queryCache.setObject(results as NSArray, forKey: cacheKey)
            }

            // Logger.debug("查询总行数: \(results.count)")
            return .success(results)
        }
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

    private func getValue(from statement: OpaquePointer?, column: Int32) -> Any? {
        let type = sqlite3_column_type(statement, column)
        switch type {
        case SQLITE_INTEGER:
            return Int(sqlite3_column_int64(statement, column))
        case SQLITE_FLOAT:
            return Double(sqlite3_column_double(statement, column))
        case SQLITE_TEXT:
            guard let cString = sqlite3_column_text(statement, column) else { return nil }
            return String(cString: cString)
        case SQLITE_NULL:
            return nil
        case SQLITE_BLOB:
            if let blob = sqlite3_column_blob(statement, column) {
                let size = Int(sqlite3_column_bytes(statement, column))
                return Data(bytes: blob, count: size)
            }
            return nil
        default:
            return nil
        }
    }
}
