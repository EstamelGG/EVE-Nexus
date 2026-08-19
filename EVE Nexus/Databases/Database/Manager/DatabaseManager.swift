import Foundation
import SwiftUI

class DatabaseManager: ObservableObject, @unchecked Sendable {
    static let shared = DatabaseManager()
    @Published var databaseUpdated = false
    private let sqliteManager = SQLiteManager.shared

    /// 加载数据库（单库多语言，语言通过 TEMP VIEW 切换）
    /// - Parameter progress: 内存索引逐表构建进度回调 (已完成数, 总数)，在后台线程触发
    func loadDatabase(
        progress: ((Int, Int) -> Void)? = nil
    ) {
        let databaseName = "item_db"
        if StaticResourceManager.shared.getDatabasePath(name: databaseName) == nil {
            Logger.error("数据库文件不存在: \(databaseName).sqlite")
            return
        }

        if sqliteManager.openDatabase(withName: databaseName) {
            DispatchQueue.main.async {
                self.databaseUpdated.toggle()
            }
            ItemInfoMap.initializeCache(databaseManager: self, progress: progress)
        }
    }

    /// 清除查询缓存
    func clearCache() {
        sqliteManager.clearCache()
    }

    /// 执行查询
    func executeQuery(_ query: String, parameters: [Any] = [], useCache: Bool = true)
        -> SQLiteResult
    {
        return sqliteManager.executeQuery(query, parameters: parameters, useCache: useCache)
    }

    /// 按名取列的直读查询（SDE 全表加载热点专用，详见 SQLiteManager.executeQueryMapped）
    @discardableResult
    func executeQueryMapped(
        _ query: String,
        context: String,
        makeRow: (SQLiteColumnResolver) -> (OpaquePointer?) -> Void
    ) -> Bool {
        return sqliteManager.executeQueryMapped(query, context: context, makeRow: makeRow)
    }
}
