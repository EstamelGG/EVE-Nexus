import Foundation
import SwiftUI

class DatabaseManager: ObservableObject, @unchecked Sendable {
    static let shared = DatabaseManager()
    @Published var databaseUpdated = false
    private let sqliteManager = SQLiteManager.shared

    /// 加载数据库（单库多语言，语言通过 TEMP VIEW 切换）
    func loadDatabase() {
        let databaseName = "item_db"
        if StaticResourceManager.shared.getDatabasePath(name: databaseName) == nil {
            Logger.error("数据库文件不存在: \(databaseName).sqlite")
            return
        }

        if sqliteManager.openDatabase(withName: databaseName) {
            DispatchQueue.main.async {
                self.databaseUpdated.toggle()
            }
            ItemInfoMap.initializeCache(databaseManager: self)
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
}
