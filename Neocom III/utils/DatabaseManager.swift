import Foundation
import SQLite3
import SwiftUI

class DatabaseManager: ObservableObject {
    @Published var databaseUpdated = false
    private let sqliteManager = SQLiteManager.shared

    // 加载数据库
    func loadDatabase() {
        // 获取本地化的数据库名称
        guard let databaseName = getLocalizedDatabaseName() else {
            print("数据库名称未找到")
            return
        }

        // 使用 SQLiteManager 打开数据库
        if sqliteManager.openDatabase(withName: databaseName) {
            self.databaseUpdated.toggle()
        }
    }

    // 获取本地化的数据库名称
    private func getLocalizedDatabaseName() -> String? {
        return NSLocalizedString("DatabaseName", comment: "数据库文件名基于语言")
    }

    // 当应用结束时关闭数据库
    func closeDatabase() {
        sqliteManager.closeDatabase()
    }
    
    // 清除查询缓存
    func clearCache() {
        sqliteManager.clearCache()
    }
    
    // 获取查询日志
    func getQueryLogs() -> [(query: String, parameters: [Any], timestamp: Date)] {
        return sqliteManager.getQueryLogs()
    }
    
    // 执行查询
    func executeQuery(_ query: String, parameters: [Any] = [], useCache: Bool = true) -> SQLiteResult {
        return sqliteManager.executeQuery(query, parameters: parameters, useCache: useCache)
    }
    
    // 加载分类
    func loadCategories() -> ([Category], [Category]) {
        let query = "SELECT category_id, name, published, iconID FROM categories ORDER BY category_id"
        let result = executeQuery(query)
        
        var published: [Category] = []
        var unpublished: [Category] = []
        
        switch result {
        case .success(let rows):
            for row in rows {
                let category = Category(
                    id: row["category_id"] as? Int ?? 0,
                    name: row["name"] as? String ?? "",
                    published: row["published"] as? Int ?? 0 != 0,
                    iconID: row["iconID"] as? Int ?? 0,
                    iconFileNew: SelectIconName(iconID: row["iconID"] as? Int ?? 0)
                )
                
                if category.published {
                    published.append(category)
                } else {
                    unpublished.append(category)
                }
            }
        case .error(let error):
            print("加载分类失败: \(error)")
        }
        
        return (published, unpublished)
    }
    
    // 加载组
    func loadGroups(for categoryID: Int) -> ([Group], [Group]) {
        let query = """
            SELECT group_id, name, iconID, categoryID, published, icon_filename
            FROM groups
            WHERE categoryID = ?
        """
        
        let result = executeQuery(query, parameters: [categoryID])
        
        var published: [Group] = []
        var unpublished: [Group] = []
        
        switch result {
        case .success(let rows):
            for row in rows {
                let group = Group(
                    id: row["group_id"] as? Int ?? 0,
                    name: row["name"] as? String ?? "",
                    iconID: row["iconID"] as? Int ?? 0,
                    categoryID: row["categoryID"] as? Int ?? 0,
                    published: row["published"] as? Int ?? 0 != 0,
                    icon_filename: row["icon_filename"] as? String ?? ""
                )
                
                if group.published {
                    published.append(group)
                } else {
                    unpublished.append(group)
                }
            }
        case .error(let error):
            print("加载组失败: \(error)")
        }
        
        return (published, unpublished)
    }
    
    // 加载物品
    func loadItems(for groupID: Int) -> ([DatabaseItem], [DatabaseItem], [Int: String]) {
        let query = """
            SELECT type_id, name, icon_filename, pg_need, cpu_need, metaGroupID, published
            FROM types
            WHERE groupID = ?
        """
        
        let result = executeQuery(query, parameters: [groupID])
        
        var published: [DatabaseItem] = []
        var unpublished: [DatabaseItem] = []
        var metaGroupNames: [Int: String] = [:]
        
        switch result {
        case .success(let rows):
            for row in rows {
                let item = DatabaseItem(
                    id: row["type_id"] as? Int ?? 0,
                    typeID: row["type_id"] as? Int ?? 0,
                    name: row["name"] as? String ?? "",
                    iconFileName: row["icon_filename"] as? String ?? "",
                    pgNeed: row["pg_need"] as? Int ?? 0,
                    cpuNeed: row["cpu_need"] as? Int ?? 0,
                    metaGroupID: row["metaGroupID"] as? Int ?? 0,
                    published: row["published"] as? Int ?? 0 != 0
                )
                
                if item.published {
                    published.append(item)
                } else {
                    unpublished.append(item)
                }
            }
            
            // 加载元组名称
            let metaGroupQuery = "SELECT metaGroup_id, name FROM metaGroups"
            let metaResult = executeQuery(metaGroupQuery)
            
            if case .success(let metaRows) = metaResult {
                for row in metaRows {
                    if let id = row["metaGroup_id"] as? Int,
                       let name = row["name"] as? String {
                        metaGroupNames[id] = name
                    }
                }
            }
            
        case .error(let error):
            print("加载物品失败: \(error)")
        }
        
        return (published, unpublished, metaGroupNames)
    }
    
    // 加载物品详情
    func loadItemDetails(for itemID: Int) -> ItemDetails? {
        let query = """
            SELECT name, description, icon_filename, group_name, category_name
            FROM types
            WHERE type_id = ?
        """
        
        let result = executeQuery(query, parameters: [itemID])
        
        switch result {
        case .success(let rows):
            guard let row = rows.first else { return nil }
            
            return ItemDetails(
                name: row["name"] as? String ?? "",
                description: row["description"] as? String ?? "",
                iconFileName: row["icon_filename"] as? String ?? "",
                groupName: row["group_name"] as? String ?? "",
                categoryName: row["category_name"] as? String ?? ""
            )
            
        case .error(let error):
            print("加载物品详情失败: \(error)")
            return nil
        }
    }
    
    // 搜索物品
    func searchItems(searchText: String, categoryID: Int? = nil, groupID: Int? = nil) -> ([DatabaseListItem], [Int: String]) {
        var query = """
            SELECT t.type_id, t.name, t.icon_filename, t.published, t.metaGroupID
            FROM types t
            WHERE t.name LIKE ?
        """
        
        var params: [Any] = ["%\(searchText)%"]
        
        if let categoryID = categoryID {
            query += " AND t.categoryID = ?"
            params.append(categoryID)
        }
        
        if let groupID = groupID {
            query += " AND t.groupID = ?"
            params.append(groupID)
        }
        
        query += " ORDER BY t.metaGroupID"
        
        let result = executeQuery(query, parameters: params)
        var items: [DatabaseListItem] = []
        var metaGroupNames: [Int: String] = [:]
        
        switch result {
        case .success(let rows):
            for row in rows {
                let id = row["type_id"] as? Int ?? 0
                let item = DatabaseListItem(
                    id: id,
                    name: row["name"] as? String ?? "",
                    iconFileName: row["icon_filename"] as? String ?? "",
                    published: row["published"] as? Int ?? 0 != 0,
                    metaGroupID: row["metaGroupID"] as? Int ?? 0,
                    navigationDestination: AnyView(
                        ShowItemInfo(
                            databaseManager: self,
                            itemID: id
                        )
                    )
                )
                items.append(item)
            }
            
            // 加载元组名称
            let metaGroupQuery = "SELECT metaGroup_id, name FROM metaGroups"
            let metaResult = executeQuery(metaGroupQuery)
            
            if case .success(let metaRows) = metaResult {
                for row in metaRows {
                    if let id = row["metaGroup_id"] as? Int,
                       let name = row["name"] as? String {
                        metaGroupNames[id] = name
                    }
                }
            }
            
        case .error(let error):
            print("搜索物品失败: \(error)")
        }
        
        return (items, metaGroupNames)
    }
    
    // 获取图标名称
    private func SelectIconName(iconID: Int) -> String {
        let query = "SELECT iconFile_new FROM iconIDs WHERE icon_id = ?"
        let result = executeQuery(query, parameters: [iconID])
        
        switch result {
        case .success(let rows):
            guard let row = rows.first,
                  let iconName = row["iconFile_new"] as? String else {
                return ""
            }
            return iconName
        case .error(let error):
            print("获取图标名称失败: \(error)")
            return ""
        }
    }
}
