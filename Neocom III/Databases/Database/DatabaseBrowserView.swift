import SwiftUI

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
