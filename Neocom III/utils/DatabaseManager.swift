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
        let query = "SELECT category_id, name, published, icon_filename FROM categories ORDER BY category_id"
        let result = executeQuery(query)
        
        var published: [Category] = []
        var unpublished: [Category] = []
        
        switch result {
        case .success(let rows):
            print("加载分类 - 获取到 \(rows.count) 行数据")
            for (index, row) in rows.enumerated() {
                print("处理第 \(index + 1) 行: \(row)")
                
                // 确保所有必需的字段都存在且类型正确
                guard let categoryId = row["category_id"] as? Int,
                      let name = row["name"] as? String,
                      let iconFilename = row["icon_filename"] as? String else {
                    print("行 \(index + 1) 数据不完整或类型不正确: \(row)")
                    continue
                }
                
                let isPublished = (row["published"] as? Int ?? 0) != 0
                
                let category = Category(
                    id: categoryId,
                    name: name,
                    published: isPublished,
                    iconID: categoryId,  // 保持 iconID 为 categoryId
                    iconFileNew: iconFilename.isEmpty ? DatabaseConfig.defaultIcon : iconFilename
                )
                
                print("创建分类: id=\(category.id), name=\(category.name), published=\(category.published)")
                
                if category.published {
                    published.append(category)
                } else {
                    unpublished.append(category)
                }
            }
            
            print("处理完成 - 已发布: \(published.count), 未发布: \(unpublished.count)")
            
        case .error(let error):
            print("加载分类失败: \(error)")
        }
        
        return (published, unpublished)
    }
    
    // 加载组
    func loadGroups(for categoryID: Int) -> ([Group], [Group]) {
        let query = """
            SELECT group_id, name, categoryID, published, icon_filename
            FROM groups
            WHERE categoryID = ?
        """
        
        let result = executeQuery(query, parameters: [categoryID])
        
        var published: [Group] = []
        var unpublished: [Group] = []
        
        switch result {
        case .success(let rows):
            for row in rows {
                guard let groupId = row["group_id"] as? Int,
                      let name = row["name"] as? String,
                      let catId = row["categoryID"] as? Int,
                      let iconFilename = row["icon_filename"] as? String else {
                    continue
                }
                
                let isPublished = (row["published"] as? Int ?? 0) != 0
                
                let group = Group(
                    id: groupId,
                    name: name,
                    iconID: groupId,  // 保持 iconID 为 groupId
                    categoryID: catId,
                    published: isPublished,
                    icon_filename: iconFilename.isEmpty ? DatabaseConfig.defaultIcon : iconFilename
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
        // 首先获取所有 metaGroups 的名称，不使用缓存
        let metaQuery = """
            SELECT metagroup_id, name 
            FROM metaGroups 
            ORDER BY metagroup_id ASC
        """
        let metaResult = executeQuery(metaQuery, useCache: false)
        var metaGroupNames: [Int: String] = [:]
        
        if case .success(let metaRows) = metaResult {
            print("加载 metaGroups - 获取到 \(metaRows.count) 行数据")
            for row in metaRows {
                if let id = row["metagroup_id"] as? Int,
                   let name = row["name"] as? String {
                    metaGroupNames[id] = name
                    print("加载 MetaGroup: ID=\(id), Name=\(name)")
                } else {
                    print("警告: MetaGroup 行数据类型不正确:", row)
                }
            }
        } else {
            print("加载 metaGroups 失败")
        }
        
        // 查询物品
        let query = """
            SELECT t.type_id, t.name, t.icon_filename, t.pg_need, t.cpu_need, t.metaGroupID, t.published
            FROM types t
            WHERE t.groupID = ?
            ORDER BY t.name ASC
        """
        
        let result = executeQuery(query, parameters: [groupID])
        
        var published: [DatabaseItem] = []
        var unpublished: [DatabaseItem] = []
        
        switch result {
        case .success(let rows):
            for row in rows {
                guard let typeId = row["type_id"] as? Int,
                      let name = row["name"] as? String,
                      let iconFilename = row["icon_filename"] as? String,
                      let pgNeed = row["pg_need"] as? Int,
                      let cpuNeed = row["cpu_need"] as? Int,
                      let metaGroupId = row["metaGroupID"] as? Int,
                      let isPublished = row["published"] as? Int else {
                    print("警告: 物品数据不完整:", row)
                    continue
                }
                
                // 打印调试信息
                print("处理物品: ID=\(typeId), Name=\(name), MetaGroupID=\(metaGroupId)")
                if let metaName = metaGroupNames[metaGroupId] {
                    print("找到对应的 MetaGroup: \(metaName)")
                } else {
                    print("警告: 找不到 MetaGroupID \(metaGroupId) 对应的名称")
                }
                
                let item = DatabaseItem(
                    id: typeId,
                    typeID: typeId,
                    name: name,
                    iconFileName: iconFilename.isEmpty ? DatabaseConfig.defaultItemIcon : iconFilename,
                    pgNeed: pgNeed,
                    cpuNeed: cpuNeed,
                    metaGroupID: metaGroupId,
                    published: isPublished != 0
                )
                
                if isPublished != 0 {
                    published.append(item)
                } else {
                    unpublished.append(item)
                }
            }
            
        case .error(let error):
            print("加载物品失败: \(error)")
        }
        
        // 打印最终的 metaGroupNames 内容
        print("最终的 metaGroupNames 内容:")
        for (id, name) in metaGroupNames.sorted(by: { $0.key < $1.key }) {
            print("ID: \(id) -> Name: \(name)")
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
            guard let row = rows.first,
                  let name = row["name"] as? String,
                  let description = row["description"] as? String,
                  let iconFilename = row["icon_filename"] as? String,
                  let groupName = row["group_name"] as? String,
                  let categoryName = row["category_name"] as? String else {
                return nil
            }
            
            return ItemDetails(
                name: name,
                description: description,
                iconFileName: iconFilename.isEmpty ? DatabaseConfig.defaultItemIcon : iconFilename,
                groupName: groupName,
                categoryName: categoryName
            )
            
        case .error(let error):
            print("加载物品详情失败: \(error)")
            return nil
        }
    }
    
    // 搜索物品
    func searchItems(searchText: String, categoryID: Int? = nil, groupID: Int? = nil) -> ([DatabaseListItem], [Int: String]) {
        // 首先获取所有 metaGroups 的名称
        let metaQuery = """
            SELECT metagroup_id, name 
            FROM metaGroups 
            ORDER BY metagroup_id ASC
        """
        let metaResult = executeQuery(metaQuery)
        var metaGroupNames: [Int: String] = [:]
        
        if case .success(let metaRows) = metaResult {
            for row in metaRows {
                if let id = row["metagroup_id"] as? Int,
                   let name = row["name"] as? String {
                    metaGroupNames[id] = name
                    print("加载 MetaGroup: ID=\(id), Name=\(name)")
                }
            }
        }
        
        // 搜索物品
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
        
        query += " ORDER BY t.metaGroupID, t.name"  // 先按 metaGroupID 排序，再按名称排序
        
        let result = executeQuery(query, parameters: params)
        var items: [DatabaseListItem] = []
        
        switch result {
        case .success(let rows):
            print("搜索到 \(rows.count) 个物品")
            for row in rows {
                guard let id = row["type_id"] as? Int,
                      let name = row["name"] as? String,
                      let iconFilename = row["icon_filename"] as? String,
                      let metaGroupId = row["metaGroupID"] as? Int else {
                    continue
                }
                
                let isPublished = (row["published"] as? Int ?? 0) != 0
                print("处理搜索结果: ID=\(id), Name=\(name), MetaGroupID=\(metaGroupId), Published=\(isPublished)")
                
                let item = DatabaseListItem(
                    id: id,
                    name: name,
                    iconFileName: iconFilename.isEmpty ? DatabaseConfig.defaultItemIcon : iconFilename,
                    published: isPublished,
                    metaGroupID: metaGroupId,
                    navigationDestination: AnyView(
                        ShowItemInfo(
                            databaseManager: self,
                            itemID: id
                        )
                    )
                )
                items.append(item)
            }
            
        case .error(let error):
            print("搜索物品失败: \(error)")
        }
        
        // 打印最终的数据
        print("搜索完成: 找到 \(items.count) 个物品")
        print("MetaGroup 数据: \(metaGroupNames)")
        
        return (items, metaGroupNames)
    }
    
    // 加载 MetaGroup 名称
    func loadMetaGroupNames(for metaGroupIDs: [Int]) -> [Int: String] {
        let placeholders = String(repeating: "?,", count: metaGroupIDs.count).dropLast()
        let query = """
            SELECT metagroup_id, name
            FROM metaGroups
            WHERE metagroup_id IN (\(placeholders))
        """
        
        let result = executeQuery(query, parameters: metaGroupIDs)
        var metaGroupNames: [Int: String] = [:]
        
        switch result {
        case .success(let rows):
            for row in rows {
                if let id = row["metagroup_id"] as? Int,
                   let name = row["name"] as? String {
                    metaGroupNames[id] = name
                }
            }
        case .error(let error):
            print("加载 MetaGroup 名称失败: \(error)")
        }
        
        return metaGroupNames
    }
}
