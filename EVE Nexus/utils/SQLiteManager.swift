import Foundation
import SQLite3

/// SQL查询结果类型
enum SQLiteResult {
    case success([[String: Any]]) // 查询成功，返回结果数组
    case error(String) // 查询失败，返回错误信息
}

/// 直读查询列解析器：按列名取 SELECT 列索引（prepare 后构建一次，行内不查找）。
/// 名字不在 SELECT 中时启动即报错（debug 断言崩溃 / release 记 error 日志），
/// 消除"SELECT 列顺序 ↔ 回调数字索引"的隐式耦合。
struct SQLiteColumnResolver {
    fileprivate let indexes: [String: Int32]
    fileprivate let context: String

    /// 按名取列索引；列不存在时报错并返回 0（debug 下先行断言崩溃）
    func index(_ name: String) -> Int32 {
        guard let index = indexes[name] else {
            let msg = "[SDE] 列解析失败 [\(context)]: SELECT 中不存在列 \(name)，请检查 SELECT 与取值列名"
            Logger.error(msg)
            assertionFailure(msg)
            return 0
        }
        return index
    }
}

class SQLiteManager {
    // 单例模式
    static let shared = SQLiteManager()
    private var db: OpaquePointer?
    private let dbAccessQueue = DispatchQueue(label: "com.eve.nexus.sqlite.access", attributes: .concurrent)

    /// 查询缓存（NSCache 本身是线程安全的）
    private let queryCache: NSCache<NSString, NSArray> = {
        let cache = NSCache<NSString, NSArray>()
        cache.countLimit = 2000 // 设置最大缓存条数
        return cache
    }()

    // 查询日志（仅用于调试）
    private let logsQueue = DispatchQueue(label: "com.eve.nexus.sqlite.logs")
    private var queryLogs: [(query: String, parameters: [Any], timestamp: Date)] = []

    private init() {}

    /// 打开数据库连接
    func openDatabase(withName name: String) -> Bool {
        // 使用 barrier 确保打开数据库时没有其他读写操作
        return dbAccessQueue.sync(flags: .barrier) {
            // 使用StaticResourceManager获取数据库路径
            guard let finalDatabasePath = StaticResourceManager.shared.getDatabasePath(name: name) else {
                let pathError = "[SQLite] 数据库文件不存在: \(name).sqlite"
                Logger.error(pathError)
                return false
            }

            // 关闭旧数据库连接（如果存在）
            // 使用 sqlite3_close_v2 而不是 sqlite3_close，可以自动处理未 finalize 的 statement
            if let oldDb = db {
                sqlite3_close_v2(oldDb)
                db = nil
            }

            // 清理查询缓存，确保使用新数据库时不会使用旧缓存
            clearCache()

            // 使用 sqlite3_open_v2 并启用完全互斥模式（FULLMUTEX）
            // SQLITE_OPEN_READONLY: 只读模式
            // SQLITE_OPEN_FULLMUTEX: SQLite 内部会处理所有线程同步，确保线程安全
            let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
            let result = sqlite3_open_v2(finalDatabasePath, &db, flags, nil)

            if result == SQLITE_OK {
                Logger.info("数据库连接成功: \(finalDatabasePath)")
                let language = UserDefaults.standard.string(forKey: "selectedDatabaseLanguage")
                if !SDELocalization.apply(to: db!, languageCode: language) {
                    Logger.error("应用 SDE 本地化视图失败")
                    return false
                }
                return true
            } else {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                let connectionError =
                    "[SQLite] 数据库连接失败 - 路径: \(finalDatabasePath), 错误代码: \(result), 错误信息: \(errorMessage)"
                Logger.error(connectionError)
                return false
            }
        }
    }

    /// 清除缓存
    func clearCache() {
        queryCache.removeAllObjects()
        Logger.info("查询缓存已清空")
    }

    /// 添加查询日志
    private func addQueryLog(query: String, parameters: [Any]) {
        logsQueue.async {
            self.queryLogs.append((query: query, parameters: parameters, timestamp: Date()))
            // 限制日志条数，避免内存过度使用
            if self.queryLogs.count > 1000 {
                self.queryLogs.removeFirst(100)
            }
        }
    }

    /// 执行查询并返回结果
    func executeQuery(_ query: String, parameters: [Any] = [], useCache: Bool = true)
        -> SQLiteResult
    {
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

        // 如果启用缓存且缓存中存在结果，直接返回（无需加锁，NSCache 本身线程安全）
        if useCache, let cachedResult = queryCache.object(forKey: cacheKey) as? [[String: Any]] {
            // Logger.debug("从缓存中获取 \(cacheKey) 的结果: \(cachedResult.count)行")
            return .success(cachedResult)
        }

        // 使用并发队列读取数据库（SQLite FULLMUTEX 模式会处理内部同步）
        return dbAccessQueue.sync {
            // 检查数据库连接是否有效
            guard let db = self.db else {
                let connectionError = "[SQLite] 数据库连接未打开 - SQL: \(query)"
                Logger.error(connectionError)
                return .error(connectionError)
            }

            let paramPart = parameters.isEmpty ? "" : "?#\(parameters)"
            // 记录查询日志
            addQueryLog(query: query, parameters: parameters)

            var statement: OpaquePointer?
            var results: [[String: Any]] = []

            // 准备语句
            if sqlite3_prepare_v2(db, query, -1, &statement, nil) != SQLITE_OK {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                let msg = "[SQLite] \(query)\(paramPart) - 失败 准备语句失败: \(errorMessage)"
                Logger.error(msg)
                return .error(msg)
            }

            // 绑定参数 - 使用原始参数顺序，而不是排序后的参数
            for (index, parameter) in parameters.enumerated() {
                let parameterIndex = Int32(index + 1)
                var bindResult: Int32 = SQLITE_OK

                switch parameter {
                case let value as Int:
                    bindResult = sqlite3_bind_int64(statement, parameterIndex, Int64(value))
                case let value as Double:
                    bindResult = sqlite3_bind_double(statement, parameterIndex, value)
                case let value as String:
                    // 使用 SQLITE_TRANSIENT 让 SQLite 拷贝字符串，防止内存提前释放
                    let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
                    bindResult = sqlite3_bind_text(
                        statement, parameterIndex, (value as NSString).utf8String, -1, SQLITE_TRANSIENT
                    )
                case let value as Data:
                    value.withUnsafeBytes { bytes in
                        bindResult = sqlite3_bind_blob(
                            statement, parameterIndex, bytes.baseAddress, Int32(value.count), nil
                        )
                    }
                case is NSNull:
                    bindResult = sqlite3_bind_null(statement, parameterIndex)
                default:
                    sqlite3_finalize(statement)
                    let typeError =
                        "[SQLite] 不支持的参数类型: \(type(of: parameter)) - 参数索引: \(index) - SQL: \(query)"
                    Logger.error(typeError)
                    return .error(typeError)
                }

                // 检查参数绑定是否成功
                if bindResult != SQLITE_OK {
                    let errorMessage = String(cString: sqlite3_errmsg(db))
                    sqlite3_finalize(statement)
                    let msg = "[SQLite] \(query)\(paramPart) - 失败 参数绑定失败[索引\(index), 值\(parameter)]: \(errorMessage)"
                    Logger.error(msg)
                    return .error(msg)
                }
            }

            // 执行查询
            // 列名在整个查询期间不变：循环外取一次，避免每行每列重复构造字符串（全表加载热点）
            let columnCount = sqlite3_column_count(statement)
            var columnNames: [String] = []
            columnNames.reserveCapacity(Int(columnCount))
            for i in 0 ..< columnCount {
                columnNames.append(String(cString: sqlite3_column_name(statement, i)))
            }

            var stepResult = sqlite3_step(statement)
            while stepResult == SQLITE_ROW {
                var row: [String: Any] = [:]
                row.reserveCapacity(Int(columnCount))

                for i in 0 ..< columnCount {
                    if let value = getValue(from: statement, column: i) {
                        row[columnNames[Int(i)]] = value
                    }
                }

                // Logger.debug("查询结果行: \(row)")
                results.append(row)
                stepResult = sqlite3_step(statement)
            }

            // 检查 SQL 执行是否出错
            if stepResult != SQLITE_DONE {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                sqlite3_finalize(statement)
                let msg = "[SQLite] \(query)\(paramPart) - 失败 SQL执行失败[代码\(stepResult)]: \(errorMessage)"
                Logger.error(msg)
                return .error(msg)
            }

            // 释放语句
            sqlite3_finalize(statement)

            // 缓存结果（NSCache 本身线程安全）
            if useCache {
                queryCache.setObject(results as NSArray, forKey: cacheKey)
            }

            // 记录执行成功日志（含完整 SQL、参数、状态）
            Logger.info("[SQLite] \(query)\(paramPart) - 成功")

            return .success(results)
        }
    }

    /// 按名取列的直读查询（SDE 全表加载专用）：
    /// prepare 后从实际 SELECT 列构建"列名→索引"解析器，`makeRow` 按列名解析出索引常量
    /// 并返回行闭包；行内只消费常量，热路径与手写数字索引等价、无每行字典查找。
    /// SELECT 重排/增删列均不影响取值正确性，列名不存在时启动即报错。
    /// - Parameters:
    ///   - query: 无参数 SQL
    ///   - context: 表/loader 名，出错定位用
    ///   - makeRow: prepare 后调用一次；返回的闭包在每行回调，回调内不要 finalize/step
    /// - Returns: 是否执行成功（错误已记录日志）
    @discardableResult
    func executeQueryMapped(
        _ query: String,
        context: String,
        makeRow: (SQLiteColumnResolver) -> (OpaquePointer?) -> Void
    ) -> Bool {
        return dbAccessQueue.sync {
            guard let db = self.db else {
                Logger.error("[SQLite] 数据库连接未打开 - SQL: \(query)")
                return false
            }

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                Logger.error("[SQLite] \(query) - 失败 准备语句失败: \(errorMessage)")
                return false
            }
            defer { sqlite3_finalize(statement) }

            var indexes: [String: Int32] = [:]
            let columnCount = sqlite3_column_count(statement)
            for i in 0 ..< columnCount {
                let name = String(cString: sqlite3_column_name(statement, i))
                indexes[name] = i
            }
            let rowHandler = makeRow(SQLiteColumnResolver(indexes: indexes, context: context))

            var stepResult = sqlite3_step(statement)
            while stepResult == SQLITE_ROW {
                rowHandler(statement)
                stepResult = sqlite3_step(statement)
            }

            guard stepResult == SQLITE_DONE else {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                Logger.error("[SQLite] \(query) - 失败 SQL执行失败[代码\(stepResult)]: \(errorMessage)")
                return false
            }
            return true
        }
    }

    /// 生成缓存键
    private func generateCacheKey(query: String, parameters: [Any]) -> String {
        // 将参数转换为字符串
        let paramStrings = parameters.map { param -> String in
            switch param {
            case let value as Int:
                return "i\(value)" // 添加类型前缀以区分不同类型的相同值
            case let value as Double:
                return "d\(value)"
            case let value as String:
                return "s\(value)"
            case let value as Data:
                return "b\(value.count)" // 对于二进制数据，只使用其长度
            case is NSNull:
                return "n"
            default:
                return "u" // unknown
            }
        }

        // 组合 SQL 和参数生成缓存键
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let paramString = paramStrings.joined(separator: "|")
        return "\(normalizedQuery)#\(paramString)"
    }

    private func getValue(from statement: OpaquePointer?, column: Int32) -> Any? {
        guard let statement = statement else {
            Logger.error("[SQLite] getValue: statement 为 nil")
            return nil
        }

        let type = sqlite3_column_type(statement, column)

        /// 列名仅在错误分支需要：延迟构造，避免每个单元格一次无谓的字符串分配（全表加载热点）
        func columnNameForLog() -> String {
            String(cString: sqlite3_column_name(statement, column))
        }

        switch type {
        case SQLITE_INTEGER:
            return Int(sqlite3_column_int64(statement, column))
        case SQLITE_FLOAT:
            return Double(sqlite3_column_double(statement, column))
        case SQLITE_TEXT:
            guard let cString = sqlite3_column_text(statement, column) else {
                Logger.error("[SQLite] getValue: 无法获取 TEXT 类型数据，列名: \(columnNameForLog())")
                return nil
            }
            return String(cString: cString)
        case SQLITE_NULL:
            return nil
        case SQLITE_BLOB:
            guard let blob = sqlite3_column_blob(statement, column) else {
                Logger.error("[SQLite] getValue: 无法获取 BLOB 类型数据，列名: \(columnNameForLog())")
                return nil
            }
            let size = Int(sqlite3_column_bytes(statement, column))
            return Data(bytes: blob, count: size)
        default:
            Logger.error("[SQLite] getValue: 未知的列类型 \(type)，列名: \(columnNameForLog())")
            return nil
        }
    }
}
