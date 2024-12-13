import SwiftUI
import SQLite3

// 浏览层级
enum BrowserLevel: Hashable {
    case categories    // 分类层级
    case groups(categoryID: Int, categoryName: String)    // 组层级
    case items(groupID: Int, groupName: String)    // 物品层级
    
    // 实现 Hashable
    func hash(into hasher: inout Hasher) {
        switch self {
        case .categories:
            hasher.combine(0)
        case .groups(let categoryID, _):
            hasher.combine(1)
            hasher.combine(categoryID)
        case .items(let groupID, _):
            hasher.combine(2)
            hasher.combine(groupID)
        }
    }
}

struct DatabaseBrowserView: View {
    @ObservedObject var databaseManager: DatabaseManager
    let level: BrowserLevel
    
    // 静态缓存
    private static var navigationCache: [BrowserLevel: ([DatabaseListItem], [Int: String])] = [:]
    private static let maxCacheSize = 10 // 最大缓存层级数
    private static var cacheAccessTime: [BrowserLevel: Date] = [:] // 记录访问时间
    
    // 清除缓存的方法
    static func clearCache() {
        navigationCache.removeAll()
        cacheAccessTime.removeAll()
    }
    
    // 更新缓存访问时间
    private static func updateAccessTime(for level: BrowserLevel) {
        cacheAccessTime[level] = Date()
        
        // 如果超出最大缓存大小，移除最旧的缓存
        if navigationCache.count > maxCacheSize {
            let oldestLevel = cacheAccessTime.sorted { $0.value < $1.value }.first?.key
            if let oldestLevel = oldestLevel {
                navigationCache.removeValue(forKey: oldestLevel)
                cacheAccessTime.removeValue(forKey: oldestLevel)
            }
        }
    }
    
    // 获取缓存数据
    private func getCachedData(for level: BrowserLevel) -> ([DatabaseListItem], [Int: String])? {
        if let cachedData = Self.navigationCache[level] {
            // 更新访问时间
            Self.updateAccessTime(for: level)
            Logger.info("使用导航缓存: \(level)")
            return cachedData
        }
        return nil
    }
    
    // 设置缓存数据
    private func setCacheData(for level: BrowserLevel, data: ([DatabaseListItem], [Int: String])) {
        Self.navigationCache[level] = data
        Self.updateAccessTime(for: level)
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
    
    // 搜索时使用的分组类型
    private var searchGroupingType: GroupingType {
        // 搜索结果总是显示衍生等级
        return .metaGroups
    }
    
    var body: some View {
        NavigationStack {
            DatabaseListView(
                databaseManager: databaseManager,
                title: title,
                groupingType: groupingType,  // 使用根据层级确定的分组类型
                loadData: { dbManager in
                    // 检查缓存
                    if let cachedData = getCachedData(for: level) {
                        return cachedData
                    }
                    
                    // 如果没有缓存，加载数据并缓存
                    let data = loadDataForLevel(dbManager)
                    setCacheData(for: level, data: data)
                    
                    // 预加载图标
                    if case .categories = level {
                        // 预加载分类图标
                        let icons = data.0.map { $0.iconFileName }
                        IconManager.shared.preloadCommonIcons(icons: icons)
                    }
                    
                    return data
                },
                searchData: { dbManager, searchText in
                    // 搜索不使用缓存
                    switch level {
                    case .categories:
                        return dbManager.searchItems(searchText: searchText)
                    case .groups(let categoryID, _):
                        return dbManager.searchItems(searchText: searchText, categoryID: categoryID)
                    case .items(let groupID, _):
                        return dbManager.searchItems(searchText: searchText, groupID: groupID)
                    }
                }
            )
        }
        .onDisappear {
            // 当视图消失时，保留当前层级和上一层级的缓存，清除其他缓存
            cleanupCache()
        }
    }
    
    // 根据层级加载数据
    private func loadDataForLevel(_ dbManager: DatabaseManager) -> ([DatabaseListItem], [Int: String]) {
        // 检查缓存
        if let cachedData = getCachedData(for: level) {
            return cachedData
        }
        
        // 如果没有缓存，加载数据并缓存
        let data = loadDataFromDatabase(dbManager)
        setCacheData(for: level, data: data)
        
        // 预加载图标
        if case .categories = level {
            // 预加载分类图标
            let icons = data.0.map { $0.iconFileName }
            IconManager.shared.preloadCommonIcons(icons: icons)
        }
        
        return data
    }
    
    // 从数据库加载数据
    private func loadDataFromDatabase(_ dbManager: DatabaseManager) -> ([DatabaseListItem], [Int: String]) {
        switch level {
        case .categories:
            let (published, unpublished) = dbManager.loadCategories()
            let items = published.map { category in
                DatabaseListItem(
                    id: category.id,
                    name: category.name,
                    iconFileName: category.iconFileNew,
                    published: true,
                    categoryID: nil,
                    groupID: nil,
                    pgNeed: nil,
                    cpuNeed: nil,
                    rigCost: nil,
                    emDamage: nil,
                    themDamage: nil,
                    kinDamage: nil,
                    expDamage: nil,
                    highSlot: nil,
                    midSlot: nil,
                    lowSlot: nil,
                    rigSlot: nil,
                    gunSlot: nil,
                    missSlot: nil,
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
                    categoryID: nil,
                    groupID: nil,
                    pgNeed: nil,
                    cpuNeed: nil,
                    rigCost: nil,
                    emDamage: nil,
                    themDamage: nil,
                    kinDamage: nil,
                    expDamage: nil,
                    highSlot: nil,
                    midSlot: nil,
                    lowSlot: nil,
                    rigSlot: nil,
                    gunSlot: nil,
                    missSlot: nil,
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
            let (published, unpublished) = dbManager.loadGroups(for: categoryID)
            let items = published.map { group in
                DatabaseListItem(
                    id: group.id,
                    name: group.name,
                    iconFileName: group.icon_filename,
                    published: true,
                    categoryID: group.categoryID,
                    groupID: group.id,
                    pgNeed: nil,
                    cpuNeed: nil,
                    rigCost: nil,
                    emDamage: nil,
                    themDamage: nil,
                    kinDamage: nil,
                    expDamage: nil,
                    highSlot: nil,
                    midSlot: nil,
                    lowSlot: nil,
                    rigSlot: nil,
                    gunSlot: nil,
                    missSlot: nil,
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
                    categoryID: group.categoryID,
                    groupID: group.id,
                    pgNeed: nil,
                    cpuNeed: nil,
                    rigCost: nil,
                    emDamage: nil,
                    themDamage: nil,
                    kinDamage: nil,
                    expDamage: nil,
                    highSlot: nil,
                    midSlot: nil,
                    lowSlot: nil,
                    rigSlot: nil,
                    gunSlot: nil,
                    missSlot: nil,
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
            let (published, unpublished, metaGroupNames) = dbManager.loadItems(for: groupID)
            let items = published.map { item in
                DatabaseListItem(
                    id: item.id,
                    name: item.name,
                    iconFileName: item.iconFileName,
                    published: true,
                    categoryID: item.categoryID,
                    groupID: groupID,
                    pgNeed: item.pgNeed,
                    cpuNeed: item.cpuNeed,
                    rigCost: item.rigCost,
                    emDamage: item.emDamage,
                    themDamage: item.themDamage,
                    kinDamage: item.kinDamage,
                    expDamage: item.expDamage,
                    highSlot: item.highSlot,
                    midSlot: item.midSlot,
                    lowSlot: item.lowSlot,
                    rigSlot: item.rigSlot,
                    gunSlot: item.gunSlot,
                    missSlot: item.missSlot,
                    metaGroupID: item.metaGroupID,
                    navigationDestination: ItemInfoMap.getItemInfoView(
                        itemID: item.id,
                        categoryID: item.categoryID,
                        databaseManager: databaseManager
                    )
                )
            } + unpublished.map { item in
                DatabaseListItem(
                    id: item.id,
                    name: item.name,
                    iconFileName: item.iconFileName,
                    published: false,
                    categoryID: item.categoryID,
                    groupID: groupID,
                    pgNeed: item.pgNeed,
                    cpuNeed: item.cpuNeed,
                    rigCost: item.rigCost,
                    emDamage: item.emDamage,
                    themDamage: item.themDamage,
                    kinDamage: item.kinDamage,
                    expDamage: item.expDamage,
                    highSlot: item.highSlot,
                    midSlot: item.midSlot,
                    lowSlot: item.lowSlot,
                    rigSlot: item.rigSlot,
                    gunSlot: item.gunSlot,
                    missSlot: item.missSlot,
                    metaGroupID: item.metaGroupID,
                    navigationDestination: ItemInfoMap.getItemInfoView(
                        itemID: item.id,
                        categoryID: item.categoryID,
                        databaseManager: databaseManager
                    )
                )
            }
            return (items, metaGroupNames)
        }
    }
    
    // 清理缓存，只保留当前层级和上一层级的数据
    private func cleanupCache() {
        let keysToKeep = getRelevantLevels()
        Self.navigationCache = Self.navigationCache.filter { keysToKeep.contains($0.key) }
    }
    
    // 获取需要保留的层级
    private func getRelevantLevels() -> Set<BrowserLevel> {
        var levels = Set<BrowserLevel>([level])
        
        // 添加上一层级
        switch level {
        case .categories:
            break // 没有上一层级
        case .groups(_, _):
            levels.insert(.categories)
        case .items(_, let groupName):
            // 尝试从组名推断出分类ID
            if let categoryID = getCategoryIDFromGroupName(groupName) {
                levels.insert(.groups(categoryID: categoryID, categoryName: ""))
            }
        }
        
        return levels
    }
    
    // 从组名推断分类ID（这个方法需要根据你的数据结构来实现）
    private func getCategoryIDFromGroupName(_ groupName: String) -> Int? {
        // TODO: 实现从组名获取分类ID的逻辑
        return nil
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
}

#Preview {
    DatabaseBrowserView(
        databaseManager: DatabaseManager(),
        level: .categories
    )
} 
