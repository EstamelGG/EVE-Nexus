import SwiftUI
import SQLite3

// 浏览层级
enum BrowserLevel {
    case categories    // 分类层级
    case groups(categoryID: Int, categoryName: String)    // 组层级
    case items(groupID: Int, groupName: String)    // 物品层级
}

struct DatabaseBrowserView: View {
    @ObservedObject var databaseManager: DatabaseManager
    let level: BrowserLevel
    
    var body: some View {
        DatabaseListView(
            databaseManager: databaseManager,
            title: title,
            groupingType: groupingType,
            loadData: { dbManager in
                guard let db = dbManager.db else { return ([], [:]) }
                
                switch level {
                case .categories:
                    // 加载分类数据
                    let (published, unpublished) = QueryCategory.loadCategories(from: db)
                    let items = published.map { category in
                        DatabaseListItem(
                            id: category.id,
                            name: category.name,
                            iconFileName: category.iconFileNew,
                            published: true,
                            metaGroupID: nil,
                            navigationDestination: AnyView(
                                DatabaseBrowserView(
                                    databaseManager: databaseManager,
                                    level: .groups(categoryID: category.id, categoryName: category.name)
                                )
                            )
                        )
                    } + unpublished.map { category in
                        DatabaseListItem(
                            id: category.id,
                            name: category.name,
                            iconFileName: category.iconFileNew,
                            published: false,
                            metaGroupID: nil,
                            navigationDestination: AnyView(
                                DatabaseBrowserView(
                                    databaseManager: databaseManager,
                                    level: .groups(categoryID: category.id, categoryName: category.name)
                                )
                            )
                        )
                    }
                    return (items, [:])
                    
                case .groups(let categoryID, _):
                    // 加载组数据
                    let (published, unpublished) = QueryGroups.loadGroups(for: categoryID, db: db)
                    let items = published.map { group in
                        DatabaseListItem(
                            id: group.id,
                            name: group.name,
                            iconFileName: group.icon_filename,
                            published: true,
                            metaGroupID: nil,
                            navigationDestination: AnyView(
                                DatabaseBrowserView(
                                    databaseManager: databaseManager,
                                    level: .items(groupID: group.id, groupName: group.name)
                                )
                            )
                        )
                    } + unpublished.map { group in
                        DatabaseListItem(
                            id: group.id,
                            name: group.name,
                            iconFileName: group.icon_filename,
                            published: false,
                            metaGroupID: nil,
                            navigationDestination: AnyView(
                                DatabaseBrowserView(
                                    databaseManager: databaseManager,
                                    level: .items(groupID: group.id, groupName: group.name)
                                )
                            )
                        )
                    }
                    return (items, [:])
                    
                case .items(let groupID, _):
                    // 加载物品数据
                    let (published, unpublished, metaGroupNames) = QueryItems.loadItems(for: groupID, db: db)
                    let items = published.map { item in
                        DatabaseListItem(
                            id: item.id,
                            name: item.name,
                            iconFileName: item.iconFileName,
                            published: true,
                            metaGroupID: item.metaGroupID,
                            navigationDestination: AnyView(
                                ShowItemInfo(
                                    databaseManager: databaseManager,
                                    itemID: item.id
                                )
                            )
                        )
                    } + unpublished.map { item in
                        DatabaseListItem(
                            id: item.id,
                            name: item.name,
                            iconFileName: item.iconFileName,
                            published: false,
                            metaGroupID: item.metaGroupID,
                            navigationDestination: AnyView(
                                ShowItemInfo(
                                    databaseManager: databaseManager,
                                    itemID: item.id
                                )
                            )
                        )
                    }
                    return (items, metaGroupNames)
                }
            },
            searchData: { dbManager, searchText in
                guard let db = dbManager.db else { return ([], [:]) }
                
                // 构建搜索 SQL
                var query = """
                    SELECT t.type_id, t.name, t.icon_filename, t.published, t.metaGroupID
                    FROM types t
                    WHERE t.name LIKE ?
                """
                var params: [String] = ["%\(searchText)%"]
                
                // 根据当前层级添加过滤条件
                switch level {
                case .categories:
                    // 在全部数据库中搜索
                    break
                case .groups(let categoryID, _):
                    // 限制在当前分类下搜索
                    query += " AND t.categoryID = ?"
                    params.append(String(categoryID))
                case .items(let groupID, _):
                    // 限制在当前组下搜索
                    query += " AND t.groupID = ?"
                    params.append(String(groupID))
                }
                
                query += " ORDER BY t.metaGroupID"
                
                // 执行搜索
                var statement: OpaquePointer?
                var items: [DatabaseListItem] = []
                var metaGroupNames: [Int: String] = [:]
                
                if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
                    // 绑定参数
                    for (index, param) in params.enumerated() {
                        sqlite3_bind_text(statement, Int32(index + 1), (param as NSString).utf8String, -1, nil)
                    }
                    
                    // 获取结果
                    while sqlite3_step(statement) == SQLITE_ROW {
                        let id = Int(sqlite3_column_int(statement, 0))
                        let name = String(cString: sqlite3_column_text(statement, 1))
                        let iconFileName = String(cString: sqlite3_column_text(statement, 2))
                        let published = sqlite3_column_int(statement, 3) != 0
                        let metaGroupID = Int(sqlite3_column_int(statement, 4))
                        
                        items.append(DatabaseListItem(
                            id: id,
                            name: name,
                            iconFileName: iconFileName,
                            published: published,
                            metaGroupID: metaGroupID,
                            navigationDestination: AnyView(
                                ShowItemInfo(
                                    databaseManager: databaseManager,
                                    itemID: id
                                )
                            )
                        ))
                    }
                    
                    sqlite3_finalize(statement)
                    
                    // 加载 metaGroup 名称
                    let metaGroupQuery = "SELECT metaGroup_id, name FROM metaGroups"
                    if sqlite3_prepare_v2(db, metaGroupQuery, -1, &statement, nil) == SQLITE_OK {
                        while sqlite3_step(statement) == SQLITE_ROW {
                            let id = Int(sqlite3_column_int(statement, 0))
                            let name = String(cString: sqlite3_column_text(statement, 1))
                            metaGroupNames[id] = name
                        }
                        sqlite3_finalize(statement)
                    }
                }
                
                return (items, metaGroupNames)
            }
        )
    }
    
    // 根据层级返回标题
    private var title: String {
        switch level {
        case .categories:
            return NSLocalizedString("Main_Database_title", comment: "")
        case .groups(_, let categoryName):
            return categoryName
        case .items(_, let groupName):
            return groupName
        }
    }
    
    // 根据层级返回分组类型
    private var groupingType: GroupingType {
        switch level {
        case .categories, .groups:
            return .publishedOnly
        case .items:
            return .metaGroups
        }
    }
}

#Preview {
    DatabaseBrowserView(
        databaseManager: DatabaseManager(),
        level: .categories
    )
} 
