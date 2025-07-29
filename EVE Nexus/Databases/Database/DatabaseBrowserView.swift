import SwiftUI

// 浏览层级
enum BrowserLevel: Hashable {
    case categories  // 分类层级
    case groups(categoryID: Int, categoryName: String)  // 组层级
    case items(groupID: Int, groupName: String)  // 物品层级

    // 实现 Hashable
    func hash(into hasher: inout Hasher) {
        switch self {
        case .categories:
            hasher.combine(0)
        case let .groups(categoryID, _):
            hasher.combine(1)
            hasher.combine(categoryID)
        case let .items(groupID, _):
            hasher.combine(2)
            hasher.combine(groupID)
        }
    }
}

struct DatabaseBrowserView: View {
    @ObservedObject var databaseManager: DatabaseManager
    let level: BrowserLevel

    // 静态缓存
    private static var navigationCache:
        [BrowserLevel: ([DatabaseListItem], [Int: String], [Int: String])] = [:]
    private static let maxCacheSize = 10  // 最大缓存层级数
    private static var cacheAccessTime: [BrowserLevel: Date] = [:]  // 记录访问时间

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
    private func getCachedData(for level: BrowserLevel) -> (
        [DatabaseListItem], [Int: String], [Int: String]
    )? {
        if let cachedData = Self.navigationCache[level] {
            // 更新访问时间
            Self.updateAccessTime(for: level)
            Logger.info("使用导航缓存: \(level)")
            return cachedData
        }
        return nil
    }

    // 设置缓存数据
    private func setCacheData(
        for level: BrowserLevel, data: ([DatabaseListItem], [Int: String], [Int: String])
    ) {
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

    var body: some View {
        NavigationStack {
            DatabaseListView(
                databaseManager: databaseManager,
                title: title,
                groupingType: groupingType,  // 使用根据层级确定的分组类型
                loadData: { dbManager in
                    // 检查缓存
                    if let cachedData = getCachedData(for: level) {
                        return (cachedData.0, cachedData.1)
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

                    return (data.0, data.1)
                },
                searchData: { dbManager, searchText in
                    // 搜索不使用缓存
                    let searchResult: ([DatabaseListItem], [Int: String], [Int: String])

                    switch level {
                    case .categories:
                        searchResult = dbManager.searchItems(searchText: searchText)
                    case let .groups(categoryID, _):
                        searchResult = dbManager.searchItems(
                            searchText: searchText, categoryID: categoryID)
                    case let .items(groupID, _):
                        searchResult = dbManager.searchItems(
                            searchText: searchText, groupID: groupID)
                    }

                    let (items, metaGroupNames, _) = searchResult

                    // 对搜索结果进行排序：先按科技等级，再按名称
                    let sortedItems = items.sorted { item1, item2 in
                        // 首先按科技等级排序
                        if item1.metaGroupID != item2.metaGroupID {
                            return (item1.metaGroupID ?? -1) < (item2.metaGroupID ?? -1)
                        }
                        // 科技等级相同时按名称排序
                        return item1.name.localizedCaseInsensitiveCompare(item2.name)
                            == .orderedAscending
                    }

                    return (sortedItems, metaGroupNames, [:])
                }
            )
        }
        .onDisappear {
            // 当视图消失时，保留当前层级和上一层级的缓存，清除其他缓存
            cleanupCache()
        }
    }

    // 根据层级加载数据
    private func loadDataForLevel(_ dbManager: DatabaseManager) -> (
        [DatabaseListItem], [Int: String], [Int: String]
    ) {
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
    private func loadDataFromDatabase(_ dbManager: DatabaseManager) -> (
        [DatabaseListItem], [Int: String], [Int: String]
    ) {
        switch level {
        case .categories:
            let (published, unpublished) = dbManager.loadCategories()
            let items = (published + unpublished).map { category in
                DatabaseListItem(
                    id: category.id,
                    name: category.name,
                    enName: category.enName,
                    iconFileName: category.iconFileNew,
                    published: category.published,
                    categoryID: nil,
                    groupID: nil,
                    groupName: nil,
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
                    marketGroupID: nil,
                    navigationDestination: AnyView(
                        DatabaseBrowserView(
                            databaseManager: databaseManager,
                            level: .groups(categoryID: category.id, categoryName: category.name)
                        )
                    )
                )
            }
            return (items, [:], [:])

        case let .groups(categoryID, _):
            let (published, unpublished) = dbManager.loadGroups(for: categoryID)
            let items = (published + unpublished).map { group in
                DatabaseListItem(
                    id: group.id,
                    name: group.name,
                    enName: group.enName,
                    iconFileName: group.icon_filename,
                    published: group.published,
                    categoryID: group.categoryID,
                    groupID: group.id,
                    groupName: group.name,
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
                    marketGroupID: nil,
                    navigationDestination: AnyView(
                        DatabaseBrowserView(
                            databaseManager: databaseManager,
                            level: .items(groupID: group.id, groupName: group.name)
                        )
                    )
                )
            }
            return (items, [:], [:])

        case let .items(groupID, groupName):
            let (published, unpublished, metaGroupNames) = dbManager.loadItems(for: groupID)
            // 对物品进行排序：先按科技等级，再按名称
            let sortedItems = (published + unpublished).sorted { item1, item2 in
                // 首先按科技等级排序
                if item1.metaGroupID != item2.metaGroupID {
                    return (item1.metaGroupID) < (item2.metaGroupID)
                }
                // 科技等级相同时按名称排序
                return item1.name.localizedCaseInsensitiveCompare(item2.name) == .orderedAscending
            }

            let items = sortedItems.map { item in
                DatabaseListItem(
                    id: item.id,
                    name: item.name,
                    enName: item.enName,
                    iconFileName: item.iconFileName,
                    published: item.published,
                    categoryID: item.categoryID,
                    groupID: groupID,
                    groupName: groupName,
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
                    marketGroupID: nil,
                    navigationDestination: ItemInfoMap.getItemInfoView(
                        itemID: item.id,
                        databaseManager: databaseManager
                    )
                )
            }
            return (items, metaGroupNames, [:])
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
            break  // 没有上一层级
        case .groups:
            levels.insert(.categories)
        case let .items(_, groupName):
            // 尝试从组名推断出分类ID
            if let categoryID = getCategoryIDFromGroupName(groupName) {
                levels.insert(.groups(categoryID: categoryID, categoryName: ""))
            }
        }

        return levels
    }

    // 从组名推断分类ID（这个方法需要根据你的数据结构来实现）
    private func getCategoryIDFromGroupName(_: String) -> Int? {
        // TODO: 实现从组名获取分类ID的逻辑
        return nil
    }

    // 根据层级返回标题
    private var title: String {
        switch level {
        case .categories:
            return NSLocalizedString("Main_Database_title", comment: "")
        case let .groups(_, categoryName):
            return categoryName
        case let .items(_, groupName):
            return groupName
        }
    }
}

// 数据库列表项视图
struct DatabaseListItemView: View {
    let item: DatabaseListItem
    let showDetails: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // 加载并显示图标
                Image(uiImage: IconManager.shared.loadUIImage(for: item.iconFileName))
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)
                Text(item.name)
            }

            if showDetails, let categoryID = item.categoryID {
                VStack(alignment: .leading, spacing: 2) {
                    // 装备、建筑装备和改装件
                    if categoryID == 7 || categoryID == 66 {
                        HStack(spacing: 8) {
                            if let pgNeed = item.pgNeed {
                                IconWithValueView(
                                    iconName: "pg", numericValue: Int(pgNeed), unit: " MW"
                                )
                            }
                            if let cpuNeed = item.cpuNeed {
                                IconWithValueView(
                                    iconName: "cpu", numericValue: Int(cpuNeed), unit: " Tf"
                                )
                            }
                            if let rigCost = item.rigCost {
                                IconWithValueView(
                                    iconName: "rigcost", numericValue: rigCost
                                )
                            }
                        }
                    }
                    // 弹药和无人机
                    else if categoryID == 18 || categoryID == 8 {
                        if hasAnyDamage {  // 添加检查是否有任何伤害值
                            HStack(spacing: 8) {  // 增加整体的间距
                                // 电磁伤害
                                HStack(spacing: 4) {  // 增加图标和条之间的间距
                                    Image("em")
                                        .resizable()
                                        .frame(width: 18, height: 18)
                                    DamageBarView(
                                        percentage: calculateDamagePercentage(item.emDamage ?? 0),
                                        color: Color(
                                            red: 74 / 255, green: 128 / 255, blue: 192 / 255
                                        )
                                    )
                                }

                                // 热能伤害
                                HStack(spacing: 4) {  // 增加图标和条之间的间距
                                    Image("th")
                                        .resizable()
                                        .frame(width: 18, height: 18)
                                    DamageBarView(
                                        percentage: calculateDamagePercentage(item.themDamage ?? 0),
                                        color: Color(
                                            red: 176 / 255, green: 53 / 255, blue: 50 / 255
                                        )
                                    )
                                }

                                // 动能伤害
                                HStack(spacing: 4) {  // 增加图标和条之间的间距
                                    Image("ki")
                                        .resizable()
                                        .frame(width: 18, height: 18)
                                    DamageBarView(
                                        percentage: calculateDamagePercentage(item.kinDamage ?? 0),
                                        color: Color(
                                            red: 155 / 255, green: 155 / 255, blue: 155 / 255
                                        )
                                    )
                                }

                                // 爆炸伤害
                                HStack(spacing: 4) {  // 增加图标和条之间的间距
                                    Image("ex")
                                        .resizable()
                                        .frame(width: 18, height: 18)
                                    DamageBarView(
                                        percentage: calculateDamagePercentage(item.expDamage ?? 0),
                                        color: Color(
                                            red: 185 / 255, green: 138 / 255, blue: 62 / 255
                                        )
                                    )
                                }
                            }
                        }
                    }
                    // 舰船
                    else if categoryID == 6 {
                        HStack(spacing: 8) {  // 减小槽位之间的间距
                            if let highSlot = item.highSlot, highSlot != 0 {
                                IconWithValueView(iconName: "highSlot", numericValue: highSlot)
                            }
                            if let midSlot = item.midSlot, midSlot != 0 {
                                IconWithValueView(iconName: "midSlot", numericValue: midSlot)
                            }
                            if let lowSlot = item.lowSlot, lowSlot != 0 {
                                IconWithValueView(iconName: "lowSlot", numericValue: lowSlot)
                            }
                            if let rigSlot = item.rigSlot, rigSlot != 0 {
                                IconWithValueView(iconName: "rigSlot", numericValue: rigSlot)
                            }
                            if let gunSlot = item.gunSlot, gunSlot != 0 {
                                IconWithValueView(iconName: "gunSlot", numericValue: gunSlot)
                            }
                            if let missSlot = item.missSlot, missSlot != 0 {
                                IconWithValueView(iconName: "missSlot", numericValue: missSlot)
                            }
                        }
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }.contextMenu {
            if !item.name.isEmpty {
                Button {
                    UIPasteboard.general.string = item.name
                } label: {
                    Label(NSLocalizedString("Misc_Copy_Name", comment: ""), systemImage: "doc.on.doc")
                }
                if let enName = item.enName, !enName.isEmpty && enName != item.name {
                    Button {
                        UIPasteboard.general.string = enName
                    } label: {
                        Label(NSLocalizedString("Misc_Copy_Trans", comment: ""), systemImage: "translate")
                    }
                }
            }
        }
    }

    private var hasAnyDamage: Bool {
        let damages = [item.emDamage, item.themDamage, item.kinDamage, item.expDamage]
        return !damages.contains(nil) && damages.compactMap { $0 }.contains { $0 > 0 }
    }

    private func calculateDamagePercentage(_ damage: Double) -> Int {
        let damages = [
            item.emDamage,
            item.themDamage,
            item.kinDamage,
            item.expDamage,
        ].compactMap { $0 }

        let totalDamage = damages.reduce(0, +)
        guard totalDamage > 0 else { return 0 }

        // 直接计算百分比并四舍五入
        return Int(round((damage / totalDamage) * 100))
    }
}

// 图标和数值的组合图
struct IconWithValueView: View {
    let iconName: String
    let value: String

    // 添加一个便利初始化方法，用于处理数值类型
    init(iconName: String, numericValue: Int, unit: String? = nil) {
        self.iconName = iconName
        value =
            unit.map { "\(FormatUtil.format(Double(numericValue)))\($0)" }
            ?? FormatUtil.format(Double(numericValue))
    }

    var body: some View {
        HStack(spacing: 2) {
            Image(iconName)
                .resizable()
                .frame(width: 18, height: 18)
            Text(value)
        }
    }
}
