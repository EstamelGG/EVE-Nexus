import Foundation
import SwiftUI

// 市场关注列表项目
struct MarketQuickbar: Identifiable, Codable {
    let id: UUID
    var name: String
    var items: [QuickbarItem]  // 存储物品的 typeID 和数量
    var lastUpdated: Date
    var regionID: Int  // 直接存储星域 ID
    var marketLocation: String?  // 用于 JSON 存储的市场位置字符串

    init(
        id: UUID = UUID(), name: String, items: [QuickbarItem] = [],
        regionID: Int = 10_000_002  // 默认使用 The Forge 星域
    ) {
        self.id = id
        self.name = name
        self.items = items
        lastUpdated = Date()
        self.regionID = regionID
        self.marketLocation = "region_id:\(regionID)"  // 设置默认的市场位置字符串
    }

    // 自定义编码
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(items, forKey: .items)
        try container.encode(lastUpdated, forKey: .lastUpdated)
        try container.encode(regionID, forKey: .regionID)
        try container.encode("region_id:\(regionID)", forKey: .marketLocation)
    }

    // 自定义解码
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        items = try container.decode([QuickbarItem].self, forKey: .items)
        lastUpdated = try container.decode(Date.self, forKey: .lastUpdated)

        // 尝试解码 regionID
        if let newRegionID = try? container.decode(Int.self, forKey: .regionID) {
            regionID = newRegionID
        } else {
            regionID = 10_000_002  // 默认值
        }

        // 设置 marketLocation
        marketLocation = "region_id:\(regionID)"
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, items, lastUpdated, regionID, marketLocation
    }
}

struct QuickbarItem: Codable, Equatable {
    let typeID: Int
    var quantity: Int64  // 使用 Int64 来存储更大的数值

    init(typeID: Int, quantity: Int64 = 1) {
        self.typeID = typeID
        self.quantity = max(1, min(quantity, 999_999_999))  // 限制最大数量为 9.99 亿
    }
}

// 管理市场关注列表的文件存储
class MarketQuickbarManager {
    static let shared = MarketQuickbarManager()

    private init() {
        createQuickbarDirectory()
    }

    private var quickbarDirectory: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("MarketQuickbars", isDirectory: true)
    }

    private func createQuickbarDirectory() {
        do {
            try FileManager.default.createDirectory(
                at: quickbarDirectory, withIntermediateDirectories: true
            )
        } catch {
            Logger.error("创建市场关注列表目录失败: \(error)")
        }
    }

    func saveQuickbar(_ quickbar: MarketQuickbar) {
        let fileName = "market_quickbar_\(quickbar.id).json"
        let fileURL = quickbarDirectory.appendingPathComponent(fileName)

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .formatted(DateFormatter.iso8601Full)
            let data = try encoder.encode(quickbar)
            try data.write(to: fileURL)
            Logger.debug("保存市场关注列表成功: \(fileName)")
        } catch {
            Logger.error("保存市场关注列表失败: \(error)")
        }
    }

    func loadQuickbars() -> [MarketQuickbar] {
        let fileManager = FileManager.default

        do {
            Logger.debug("开始加载市场关注列表")
            let files = try fileManager.contentsOfDirectory(
                at: quickbarDirectory, includingPropertiesForKeys: nil
            )
            Logger.debug("找到文件数量: \(files.count)")

            let quickbars = files.filter { url in
                url.lastPathComponent.hasPrefix("market_quickbar_") && url.pathExtension == "json"
            }.compactMap { url -> MarketQuickbar? in
                do {
                    Logger.debug("尝试解析文件: \(url.lastPathComponent)")
                    let data = try Data(contentsOf: url)

                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .formatted(DateFormatter.iso8601Full)
                    let quickbar = try decoder.decode(MarketQuickbar.self, from: data)
                    return quickbar
                } catch {
                    Logger.error("读取市场关注列表失败: \(error)")
                    try? FileManager.default.removeItem(at: url)
                    return nil
                }
            }
            .sorted { $0.lastUpdated < $1.lastUpdated }

            Logger.debug("成功加载市场关注列表数量: \(quickbars.count)")
            return quickbars

        } catch {
            Logger.error("读取市场关注列表目录失败: \(error)")
            return []
        }
    }

    func deleteQuickbar(_ quickbar: MarketQuickbar) {
        let fileName = "market_quickbar_\(quickbar.id).json"
        let fileURL = quickbarDirectory.appendingPathComponent(fileName)

        do {
            try FileManager.default.removeItem(at: fileURL)
            Logger.debug("删除市场关注列表成功: \(fileName)")
        } catch {
            Logger.error("删除市场关注列表失败: \(error)")
        }
    }
}

// 市场物品选择器基础视图
struct MarketItemSelectorBaseView<Content: View>: View {
    @ObservedObject var databaseManager: DatabaseManager
    let title: String
    let content: () -> Content
    let searchQuery: (String) -> String
    let searchParameters: (String) -> [Any]
    let existingItems: Set<Int>
    let onItemSelected: (DatabaseListItem) -> Void
    let onItemDeselected: (DatabaseListItem) -> Void
    let onDismiss: () -> Void
    let showSelected: Bool  // 要不要展示已选/未选的指示图标

    @State private var items: [DatabaseListItem] = []
    @State private var metaGroupNames: [Int: String] = [:]  // 添加科技等级名称字典
    @State private var searchText = ""
    @State private var isSearchActive = false
    @State private var isLoading = false
    @State private var isShowingSearchResults = false
    @StateObject private var searchController = SearchController()

    // 搜索结果分组
    var groupedSearchResults: [(id: Int, name: String, items: [DatabaseListItem])] {
        guard !items.isEmpty else { return [] }

        // 按categoryID和groupID组织数据
        var groupedByCategory: [Int: [(groupID: Int, name: String, items: [DatabaseListItem])]] =
            [:]

        // 首先按categoryID和groupID分组
        for item in items {
            let categoryID = item.categoryID ?? 0
            let groupID = item.groupID ?? 0
            let groupName = item.groupName ?? "Unknown Group"

            if groupedByCategory[categoryID] == nil {
                groupedByCategory[categoryID] = []
            }

            // 在当前分类中查找或创建groupID组
            if let index = groupedByCategory[categoryID]?.firstIndex(where: {
                $0.groupID == groupID
            }) {
                groupedByCategory[categoryID]?[index].items.append(item)
            } else {
                groupedByCategory[categoryID]?.append(
                    (groupID: groupID, name: groupName, items: [item]))
            }
        }

        // 定义分类优先级顺序
        let categoryPriority = [6, 7, 32, 8, 4, 16, 18, 87, 20, 22, 9, 5]

        // 按优先级顺序排序分类
        var result: [(id: Int, name: String, items: [DatabaseListItem])] = []
        for categoryID in categoryPriority {
            if let groups = groupedByCategory[categoryID] {
                for group in groups.sorted(by: { $0.groupID < $1.groupID }) {
                    // 对每个组内的物品进行排序
                    let sortedItems = group.items.sorted { item1, item2 in
                        // 首先按科技等级排序
                        if item1.metaGroupID != item2.metaGroupID {
                            return (item1.metaGroupID ?? -1) < (item2.metaGroupID ?? -1)
                        }
                        // 科技等级相同时按名称排序
                        return item1.name.localizedCaseInsensitiveCompare(item2.name)
                            == .orderedAscending
                    }
                    result.append((id: group.groupID, name: group.name, items: sortedItems))
                }
            }
        }

        // 添加未在优先级列表中的分类
        for (categoryID, groups) in groupedByCategory {
            if !categoryPriority.contains(categoryID) {
                for group in groups.sorted(by: { $0.groupID < $1.groupID }) {
                    // 对每个组内的物品进行排序
                    let sortedItems = group.items.sorted { item1, item2 in
                        // 首先按科技等级排序
                        if item1.metaGroupID != item2.metaGroupID {
                            return (item1.metaGroupID ?? -1) < (item2.metaGroupID ?? -1)
                        }
                        // 科技等级相同时按名称排序
                        return item1.name.localizedCaseInsensitiveCompare(item2.name)
                            == .orderedAscending
                    }
                    result.append((id: group.groupID, name: group.name, items: sortedItems))
                }
            }
        }

        return result
    }

    var body: some View {
        List {
            if isShowingSearchResults {
                // 搜索结果视图，按市场组分类显示
                ForEach(groupedSearchResults, id: \.id) { group in
                    Section(
                        header: Text(group.name)
                            .fontWeight(.semibold)
                            .font(.system(size: 18))
                            .foregroundColor(.primary)
                            .textCase(.none)
                    ) {
                        ForEach(group.items) { item in
                            Button {
                                if existingItems.contains(item.id) {
                                    onItemDeselected(item)
                                } else {
                                    onItemSelected(item)
                                }
                            } label: {
                                HStack {
                                    DatabaseListItemView(
                                        item: item,
                                        showDetails: true
                                    )

                                    Spacer()
                                    if showSelected {
                                        Image(
                                            systemName: existingItems.contains(item.id)
                                                ? "checkmark.circle.fill" : "circle"
                                        )
                                        .foregroundColor(
                                            existingItems.contains(item.id)
                                                ? .accentColor : .secondary)
                                    }
                                }
                            }
                            .foregroundColor(existingItems.contains(item.id) ? .primary : .primary)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    }
                }
            } else {
                content()
            }
        }
        .searchable(
            text: $searchText,
            isPresented: $isSearchActive,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text(NSLocalizedString("Main_Database_Search", comment: ""))
        )
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty {
                isShowingSearchResults = false
                isLoading = false
                items = []
            } else {
                isLoading = true
                items = []
                if newValue.count >= 1 {
                    searchController.processSearchInput(newValue)
                }
            }
        }
        .overlay {
            if isLoading {
                Color(.systemBackground)
                    .ignoresSafeArea()
                    .overlay {
                        VStack {
                            ProgressView()
                            Text(NSLocalizedString("Main_Database_Searching", comment: ""))
                                .foregroundColor(.secondary)
                                .padding(.top, 8)
                        }
                    }
            } else if items.isEmpty && !searchText.isEmpty {
                ContentUnavailableView {
                    Label(
                        NSLocalizedString("Misc_Not_Found", comment: ""),
                        systemImage: "magnifyingglass")
                }
            } else if searchText.isEmpty && isSearchActive {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .onTapGesture {
                        isSearchActive = false
                    }
            }
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(NSLocalizedString("Misc_Done", comment: "")) {
                    onDismiss()
                }
            }
        }
        .onAppear {
            setupSearch()
            // 加载科技等级名称
            let metaGroupIDs = Set(items.compactMap { $0.metaGroupID })
            metaGroupNames = databaseManager.loadMetaGroupNames(for: Array(metaGroupIDs))
        }
    }

    private func setupSearch() {
        searchController.debouncedSearchPublisher
            .receive(on: DispatchQueue.main)
            .sink { query in
                guard !searchText.isEmpty else { return }
                performSearch(with: query)
            }
            .store(in: &searchController.cancellables)
    }

    private func performSearch(with text: String) {
        isLoading = true

        let whereClause = searchQuery(text)
        let parameters = searchParameters(text)

        items = databaseManager.loadMarketItems(
            whereClause: whereClause, parameters: parameters, limit: 100)
        isShowingSearchResults = true

        isLoading = false
    }
}

// 市场物品选择器视图
struct MarketItemSelectorView: View {
    @ObservedObject var databaseManager: DatabaseManager
    let existingItems: Set<Int>
    let onItemSelected: (DatabaseListItem) -> Void
    let onItemDeselected: (DatabaseListItem) -> Void
    let showSelected: Bool
    let allowTypeIDs: Set<Int>?  // 新增：物品ID白名单
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            MarketItemSelectorIntegratedView(
                databaseManager: databaseManager,
                title: NSLocalizedString("Main_Market_Watch_List_Add_Item", comment: ""),
                allowedMarketGroups: [],  // 空集表示允许所有市场分组
                allowTypeIDs: allowTypeIDs,  // 传递物品ID白名单
                existingItems: existingItems,
                onItemSelected: onItemSelected,
                onItemDeselected: onItemDeselected,
                onDismiss: { dismiss() },
                showSelected: showSelected
            )
            .interactiveDismissDisabled()
        }
    }
}

// 市场物品选择器组视图
struct MarketItemSelectorGroupView: View {
    @ObservedObject var databaseManager: DatabaseManager
    let group: MarketGroup
    let allGroups: [MarketGroup]
    let validGroups: Set<Int>  // 新增：有效的组ID集合
    let allowTypeIDs: Set<Int>?  // 新增：物品ID白名单
    let existingItems: Set<Int>
    let onItemSelected: (DatabaseListItem) -> Void
    let onItemDeselected: (DatabaseListItem) -> Void
    let onDismiss: () -> Void
    let showSelected: Bool

    var body: some View {
        MarketItemSelectorBaseView(
            databaseManager: databaseManager,
            title: group.name,
            content: {
                ForEach(getValidSubGroups()) { subGroup in
                    MarketItemSelectorGroupRow(
                        group: subGroup,
                        allGroups: allGroups,
                        validGroups: validGroups,  // 新增：传递有效组ID
                        allowTypeIDs: allowTypeIDs,  // 新增：传递物品ID白名单
                        databaseManager: databaseManager,
                        existingItems: existingItems,
                        onItemSelected: onItemSelected,
                        onItemDeselected: onItemDeselected,
                        onDismiss: onDismiss,
                        showSelected: showSelected
                    )
                }
            },
            searchQuery: { _ in
                let groupIDs = MarketManager.shared.getAllSubGroupIDsFromID(
                    allGroups, startingFrom: group.id
                )
                let groupIDsString = groupIDs.sorted().map { String($0) }.joined(separator: ",")

                if let typeIDs = allowTypeIDs, !typeIDs.isEmpty {
                    // 如果有物品ID白名单，添加物品ID筛选条件
                    let typeIDsString = typeIDs.map { String($0) }.joined(separator: ",")
                    return
                        "t.marketGroupID IN (\(groupIDsString)) AND t.type_id IN (\(typeIDsString)) AND (t.name LIKE ? OR t.en_name LIKE ?)"
                } else {
                    // 否则只筛选市场分组
                    return
                        "t.marketGroupID IN (\(groupIDsString)) AND (t.name LIKE ? OR t.en_name LIKE ?)"
                }
            },
            searchParameters: { text in
                ["%\(text)%", "%\(text)%"]
            },
            existingItems: existingItems,
            onItemSelected: onItemSelected,
            onItemDeselected: onItemDeselected,
            onDismiss: onDismiss,
            showSelected: showSelected
        )
    }

    // 获取有效的子组
    private func getValidSubGroups() -> [MarketGroup] {
        let subGroups = MarketManager.shared.getSubGroups(allGroups, for: group.id)

        // 如果没有物品ID白名单，或者白名单为空，或者有效组ID列表为空，则返回所有子组
        if allowTypeIDs == nil || allowTypeIDs!.isEmpty || validGroups.isEmpty {
            return subGroups
        }

        // 否则只返回在有效组ID列表中的子组
        return subGroups.filter { validGroups.contains($0.id) }
    }
}

// 市场物品选择器组行视图
struct MarketItemSelectorGroupRow: View {
    let group: MarketGroup
    let allGroups: [MarketGroup]
    let validGroups: Set<Int>  // 新增：有效的组ID集合
    let allowTypeIDs: Set<Int>?  // 新增：物品ID白名单
    let databaseManager: DatabaseManager
    let existingItems: Set<Int>
    let onItemSelected: (DatabaseListItem) -> Void
    let onItemDeselected: (DatabaseListItem) -> Void
    let onDismiss: () -> Void
    let showSelected: Bool

    var body: some View {
        if shouldShowGroup() {
            if MarketManager.shared.isLeafGroup(group, in: allGroups) {
                // 最后一级目录，显示物品列表
                NavigationLink {
                    MarketItemSelectorItemListView(
                        databaseManager: databaseManager,
                        marketGroupID: group.id,
                        allowTypeIDs: allowTypeIDs,  // 新增：传递物品ID白名单
                        title: group.name,
                        existingItems: existingItems,
                        onItemSelected: onItemSelected,
                        onItemDeselected: onItemDeselected,
                        onDismiss: onDismiss,
                        showSelected: showSelected
                    )
                } label: {
                    MarketGroupLabel(group: group)
                }
            } else {
                // 非最后一级目录，显示子目录
                NavigationLink {
                    MarketItemSelectorGroupView(
                        databaseManager: databaseManager,
                        group: group,
                        allGroups: allGroups,
                        validGroups: validGroups,  // 新增：传递有效组ID
                        allowTypeIDs: allowTypeIDs,  // 新增：传递物品ID白名单
                        existingItems: existingItems,
                        onItemSelected: onItemSelected,
                        onItemDeselected: onItemDeselected,
                        onDismiss: onDismiss,
                        showSelected: showSelected
                    )
                } label: {
                    MarketGroupLabel(group: group)
                }
            }
        }
    }

    // 判断是否应该显示该组
    private func shouldShowGroup() -> Bool {
        // 如果没有物品ID白名单，或者该组在有效组列表中，则显示
        if allowTypeIDs == nil || allowTypeIDs!.isEmpty || validGroups.isEmpty {
            return true
        }

        return validGroups.contains(group.id)
    }
}

// 市场物品选择器物品列表视图
struct MarketItemSelectorItemListView: View {
    @ObservedObject var databaseManager: DatabaseManager
    let marketGroupID: Int
    let allowTypeIDs: Set<Int>?  // 新增：物品ID白名单
    let title: String
    let existingItems: Set<Int>
    let onItemSelected: (DatabaseListItem) -> Void
    let onItemDeselected: (DatabaseListItem) -> Void
    let onDismiss: () -> Void
    let showSelected: Bool

    @State private var items: [DatabaseListItem] = []
    @State private var metaGroupNames: [Int: String] = [:]

    var groupedItems: [(id: Int, name: String, items: [DatabaseListItem])] {
        let publishedItems = items.filter { $0.published }
        let unpublishedItems = items.filter { !$0.published }

        var result: [(id: Int, name: String, items: [DatabaseListItem])] = []

        // 按科技等级分组
        var techLevelGroups: [Int?: [DatabaseListItem]] = [:]
        for item in publishedItems {
            let techLevel = item.metaGroupID
            if techLevelGroups[techLevel] == nil {
                techLevelGroups[techLevel] = []
            }
            techLevelGroups[techLevel]?.append(item)
        }

        // 添加已发布物品组
        for (techLevel, items) in techLevelGroups.sorted(by: { ($0.key ?? -1) < ($1.key ?? -1) }) {
            if let techLevel = techLevel {
                let name =
                    metaGroupNames[techLevel]
                    ?? NSLocalizedString("Main_Database_base", comment: "基础物品")
                result.append((id: techLevel, name: name, items: items))
            }
        }

        // 添加未分组的物品
        if let ungroupedItems = techLevelGroups[nil], !ungroupedItems.isEmpty {
            result.append(
                (
                    id: -2, name: NSLocalizedString("Main_Database_ungrouped", comment: "未分组"),
                    items: ungroupedItems
                ))
        }

        // 添加未发布物品组
        if !unpublishedItems.isEmpty {
            result.append(
                (
                    id: -1, name: NSLocalizedString("Main_Database_unpublished", comment: "未发布"),
                    items: unpublishedItems
                ))
        }

        return result
    }

    var body: some View {
        MarketItemSelectorBaseView(
            databaseManager: databaseManager,
            title: title,
            content: {
                ForEach(groupedItems, id: \.id) { group in
                    Section(
                        header: Text(group.name)
                            .fontWeight(.semibold)
                            .font(.system(size: 18))
                            .foregroundColor(.primary)
                            .textCase(.none)
                    ) {
                        ForEach(group.items) { item in
                            Button {
                                if existingItems.contains(item.id) {
                                    onItemDeselected(item)
                                } else {
                                    onItemSelected(item)
                                }
                            } label: {
                                HStack {
                                    DatabaseListItemView(
                                        item: item,
                                        showDetails: true
                                    )
                                    if showSelected {
                                        Spacer()

                                        Image(
                                            systemName: existingItems.contains(item.id)
                                                ? "checkmark.circle.fill" : "circle"
                                        )
                                        .foregroundColor(
                                            existingItems.contains(item.id)
                                                ? .accentColor : .secondary)
                                    }
                                }
                            }
                            .foregroundColor(existingItems.contains(item.id) ? .primary : .primary)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    }
                }
            },
            searchQuery: { _ in
                var query = "t.marketGroupID = ?"

                // 如果有物品ID白名单，添加物品ID筛选条件
                if let typeIDs = allowTypeIDs, !typeIDs.isEmpty {
                    let typeIDsString = typeIDs.map { String($0) }.joined(separator: ",")
                    query += " AND t.type_id IN (\(typeIDsString))"
                }

                query += " AND (t.name LIKE ? OR t.en_name LIKE ?)"
                return query
            },
            searchParameters: { text in
                [marketGroupID, "%\(text)%", "%\(text)%"]
            },
            existingItems: existingItems,
            onItemSelected: onItemSelected,
            onItemDeselected: onItemDeselected,
            onDismiss: onDismiss,
            showSelected: showSelected
        )
        .onAppear {
            loadItems()
        }
    }

    private func loadItems() {
        var whereClause = "t.marketGroupID = ?"
        let parameters: [Any] = [marketGroupID]

        // 如果有物品ID白名单，添加物品ID筛选条件
        if let typeIDs = allowTypeIDs, !typeIDs.isEmpty {
            let typeIDsString = typeIDs.map { String($0) }.joined(separator: ",")
            whereClause += " AND t.type_id IN (\(typeIDsString))"
        }

        items = databaseManager.loadMarketItems(
            whereClause: whereClause,
            parameters: parameters
        )

        // 加载科技等级名称
        let metaGroupIDs = Set(items.compactMap { $0.metaGroupID })
        metaGroupNames = databaseManager.loadMetaGroupNames(for: Array(metaGroupIDs))
    }
}

// 市场关注列表主视图
struct MarketQuickbarView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var quickbars: [MarketQuickbar] = []
    @State private var isShowingAddAlert = false
    @State private var newQuickbarName = ""
    @State private var searchText = ""

    private var filteredQuickbars: [MarketQuickbar] {
        if searchText.isEmpty {
            return quickbars
        } else {
            return quickbars.filter { quickbar in
                quickbar.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    var body: some View {
        List {
            if filteredQuickbars.isEmpty {
                if searchText.isEmpty {
                    Text(NSLocalizedString("Main_Market_Watch_List_Empty", comment: ""))
                        .foregroundColor(.secondary)
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                } else {
                    Text(String(format: NSLocalizedString("Main_EVE_Mail_No_Results", comment: "")))
                        .foregroundColor(.secondary)
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
            } else {
                ForEach(filteredQuickbars) { quickbar in
                    NavigationLink {
                        MarketQuickbarDetailView(
                            databaseManager: databaseManager,
                            quickbar: quickbar
                        )
                    } label: {
                        quickbarRowView(quickbar)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
                .onDelete(perform: deleteQuickbar)
            }
        }
        .navigationTitle(NSLocalizedString("Main_Market_Watch_List", comment: ""))
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: NSLocalizedString("Main_Database_Search", comment: "")
        )
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    newQuickbarName = ""
                    isShowingAddAlert = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert(
            NSLocalizedString("Main_Market_Watch_List_Add", comment: ""),
            isPresented: $isShowingAddAlert
        ) {
            TextField(
                NSLocalizedString("Main_Market_Watch_List_Name", comment: ""),
                text: $newQuickbarName
            )

            Button(NSLocalizedString("Misc_Done", comment: "")) {
                if !newQuickbarName.isEmpty {
                    let newQuickbar = MarketQuickbar(
                        name: newQuickbarName,
                        items: []
                    )
                    quickbars.append(newQuickbar)
                    MarketQuickbarManager.shared.saveQuickbar(newQuickbar)
                    newQuickbarName = ""
                }
            }
            .disabled(newQuickbarName.isEmpty)

            Button(NSLocalizedString("Main_EVE_Mail_Cancel", comment: ""), role: .cancel) {
                newQuickbarName = ""
            }
        }
        .task {
            quickbars = MarketQuickbarManager.shared.loadQuickbars()
        }
    }

    private func quickbarRowView(_ quickbar: MarketQuickbar) -> some View {
        HStack {
            // 显示列表图标
            if !quickbar.items.isEmpty, let firstItem = quickbar.items.first {
                // 直接查询并显示第一个物品的图标
                let icon = getItemIcon(typeID: firstItem.typeID)
                Image(uiImage: icon)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(4)
                    .padding(.trailing, 8)
            } else {
                Image("Folder")
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(4)
                    .padding(.trailing, 8)
            }

            Text(quickbar.name)
                .lineLimit(1)
            Spacer()
            Text(
                String(
                    format: NSLocalizedString("Main_Market_Watch_List_Items", comment: ""),
                    quickbar.items.count
                )
            )
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    // 获取物品图标的辅助函数
    private func getItemIcon(typeID: Int) -> UIImage {
        let itemData = databaseManager.loadMarketItems(
            whereClause: "t.type_id = ?",
            parameters: [typeID]
        )

        if let item = itemData.first {
            return IconManager.shared.loadUIImage(for: item.iconFileName)
        } else {
            // 如果找不到图标，返回一个默认图标
            return UIImage(named: "not_found") ?? UIImage()
        }
    }

    private func deleteQuickbar(at offsets: IndexSet) {
        let quickbarsToDelete = offsets.map { filteredQuickbars[$0] }
        for quickbar in quickbarsToDelete {
            MarketQuickbarManager.shared.deleteQuickbar(quickbar)
            if let index = quickbars.firstIndex(where: { $0.id == quickbar.id }) {
                quickbars.remove(at: index)
            }
        }
    }
}

// 市场关注列表详情视图
struct MarketQuickbarDetailView: View {
    let databaseManager: DatabaseManager
    @State var quickbar: MarketQuickbar
    @State private var isShowingItemSelector = false
    @State private var items: [DatabaseListItem] = []
    @State private var isEditingQuantity = false
    @State private var itemQuantities: [Int: Int64] = [:]  // typeID: quantity
    @State private var selectedRegion: String = ""  // 默认不设置，将从数据库获取
    @State private var regions: [(id: Int, name: String)] = []  // 存储星域列表
    @State private var marketOrders: [Int: [MarketOrder]] = [:]  // typeID: orders
    @State private var isLoadingOrders = false
    @State private var orderType: OrderType = .sell  // 新增：订单类型选择
    @State private var hasLoadedOrders = false  // 标记是否已加载过订单
    @State private var showRegionPicker = false  // 新增：控制星域选择器显示
    @State private var saveSelection = false  // 不保存默认市场位置
    @State private var selectedRegionID: Int = 0  // 新增：选中的星域ID
    @State private var selectedRegionName: String = ""  // 新增：选中的星域名称
    @State private var showSelected = true
    @State private var structureOrdersProgress: StructureOrdersProgress? = nil  // 建筑订单加载进度

    // 新增：订单类型枚举
    private enum OrderType: String, CaseIterable {
        case buy = "Main_Market_Order_Buy"
        case sell = "Main_Market_Order_Sell"

        var localizedName: String {
            NSLocalizedString(rawValue, comment: "")
        }
    }

    // 获取当前选择的星域ID
    private var currentRegionID: Int {
        return quickbar.regionID
    }

    var sortedItems: [DatabaseListItem] {
        items.sorted(by: { $0.id < $1.id })
    }

    var body: some View {
        List {
            if quickbar.items.isEmpty {
                Text(NSLocalizedString("Main_Market_Watch_List_Empty", comment: ""))
                    .foregroundColor(.secondary)
            } else {
                Section {
                    // 星域选择器
                    HStack {
                        Text(NSLocalizedString("Main_Market_Location", comment: ""))
                        Spacer()
                        Button {
                            // 在打开选择器之前，确保 selectedRegionID 与当前 quickbar.regionID 一致
                            selectedRegionID = quickbar.regionID
                            showRegionPicker = true
                        } label: {
                            HStack {
                                Text(selectedRegion)
                                    .foregroundColor(.primary)
                                Image(systemName: "chevron.up.chevron.down")
                                    .foregroundColor(.secondary)
                                    .imageScale(.small)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(uiColor: .secondarySystemBackground))
                            .cornerRadius(8)
                        }
                    }
                    .onChange(of: quickbar.regionID) { oldValue, newValue in
                        if oldValue != newValue {
                            // 根据是否是建筑ID更新显示
                            if StructureMarketManager.isStructureId(newValue) {
                                // 是建筑ID，查找建筑名称
                                if let structureId = StructureMarketManager.getStructureId(from: newValue),
                                   let structure = getStructureById(structureId) {
                                    selectedRegion = structure.structureName
                                    selectedRegionName = structure.structureName
                                } else {
                                    selectedRegion = "Unknown Structure"
                                    selectedRegionName = "Unknown Structure"
                                }
                            } else {
                                // 是星域ID，查找星域名称
                                if let region = regions.first(where: { $0.id == newValue }) {
                                    selectedRegion = region.name
                                    selectedRegionName = region.name
                                }
                            }
                            // 保存更改
                            MarketQuickbarManager.shared.saveQuickbar(quickbar)
                            // 强制刷新市场订单
                            Task {
                                await loadAllMarketOrders()
                            }
                        }
                    }
                    .onChange(of: selectedRegionID) { oldValue, newValue in
                        if oldValue != newValue {
                            // 更新 quickbar 的 regionID
                            quickbar.regionID = newValue
                        }
                    }

                    // 订单类型选择器
                    HStack {
                        Text(NSLocalizedString("Main_Market_Order_Type", comment: ""))
                        Spacer()
                        Picker("", selection: $orderType) {
                            Text(OrderType.sell.localizedName).tag(OrderType.sell)
                            Text(OrderType.buy.localizedName).tag(OrderType.buy)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 140)
                    }

                    // 价格显示行
                    HStack {
                        Text(NSLocalizedString("Main_Market_Price", comment: ""))
                        Spacer()
                        if isLoadingOrders {
                            if StructureMarketManager.isStructureId(currentRegionID),
                               let progress = structureOrdersProgress {
                                switch progress {
                                case .loading(let currentPage, let totalPages):
                                    HStack(spacing: 4) {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                        Text("\(currentPage)/\(totalPages)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                case .completed:
                                    ProgressView()
                                        .scaleEffect(0.7)
                                }
                            } else {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                        } else {
                            let priceInfo = calculateTotalPrice()
                            if priceInfo.total > 0 {
                                Text("\(FormatUtil.formatISK(priceInfo.total))")
                                    .foregroundColor(
                                        priceInfo.hasInsufficientStock ? .red : .secondary)
                            } else {
                                Text(NSLocalizedString("Main_Market_No_Orders", comment: ""))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text(NSLocalizedString("Main_Market_QuickBar_info", comment: ""))
                        .fontWeight(.semibold)
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                        .textCase(.none)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

                Section {
                    ForEach(sortedItems, id: \.id) { item in
                        itemRow(item)
                    }
                    .onDelete { indexSet in
                        let itemsToDelete = indexSet.map { sortedItems[$0].id }
                        quickbar.items.removeAll { itemsToDelete.contains($0.typeID) }
                        items.removeAll { itemsToDelete.contains($0.id) }
                        MarketQuickbarManager.shared.saveQuickbar(quickbar)
                        // 删除物品后自动加载市场订单
                        Task {
                            // 强制刷新市场订单
                            await loadAllMarketOrders()
                        }
                    }
                } header: {
                    HStack {
                        Text(NSLocalizedString("Main_Market_Item_List", comment: ""))
                            .fontWeight(.semibold)
                            .font(.system(size: 18))
                            .foregroundColor(.primary)
                            .textCase(.none)
                        Spacer()
                        Button(
                            isEditingQuantity
                                ? NSLocalizedString("Main_Market_Done_Edit", comment: "")
                                : NSLocalizedString("Main_Market_Edit_Quantity", comment: "")
                        ) {
                            withAnimation {
                                // 如果正在退出编辑模式，保存数据
                                if isEditingQuantity {
                                    Logger.info("编辑完成，进行保存")
                                    // 保存所有更改，包括物品数量和市场位置
                                    MarketQuickbarManager.shared.saveQuickbar(quickbar)
                                }
                                isEditingQuantity.toggle()
                            }
                        }
                        .foregroundColor(.accentColor)
                        .font(.system(size: 14))
                    }
                }
            }
        }
        .refreshable {
            // 强制刷新市场订单
            await loadAllMarketOrders(forceRefresh: true)
        }
        .navigationTitle(quickbar.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    isShowingItemSelector = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $isShowingItemSelector) {
            MarketItemSelectorView(
                databaseManager: databaseManager,
                existingItems: Set(quickbar.items.map { $0.typeID }),
                onItemSelected: { item in
                    if !quickbar.items.contains(where: { $0.typeID == item.id }) {
                        items.append(item)
                        quickbar.items.append(QuickbarItem(typeID: item.id))
                        // 重新排序并保存
                        let sorted = items.sorted(by: { $0.id < $1.id })
                        items = sorted
                        quickbar.items = sorted.map { item in
                            QuickbarItem(
                                typeID: item.id,
                                quantity: quickbar.items.first(where: { $0.typeID == item.id })?
                                    .quantity ?? 1
                            )
                        }
                        MarketQuickbarManager.shared.saveQuickbar(quickbar)
                        // 添加物品后自动加载市场订单
                        Task {
                            await loadAllMarketOrders()
                        }
                    }
                },
                onItemDeselected: { item in
                    if let index = items.firstIndex(where: { $0.id == item.id }) {
                        items.remove(at: index)
                        quickbar.items.removeAll { $0.typeID == item.id }
                        MarketQuickbarManager.shared.saveQuickbar(quickbar)
                    }
                },
                showSelected: showSelected,
                allowTypeIDs: nil  // 不限制物品ID
            )
        }
        .sheet(isPresented: $showRegionPicker) {
            MarketRegionPickerView(
                selectedRegionID: $selectedRegionID,
                selectedRegionName: $selectedRegionName,
                saveSelection: $saveSelection,  // 通过市场关注列表查看和设置订单信息，不保存默认市场位置
                databaseManager: databaseManager
            )
        }
        .task {
            loadItems()
            loadRegions()
            
            // 验证当前选择的区域ID是否有效
            if isValidRegionID(currentRegionID) {
                selectedRegionID = currentRegionID
            } else {
                Logger.warning("关注列表中的区域ID \(currentRegionID) 无效，回退到Jita")
                selectedRegionID = 10000002 // The Forge (Jita)
                // 更新quickbar的regionID
                quickbar.regionID = selectedRegionID
                MarketQuickbarManager.shared.saveQuickbar(quickbar)
            }
            
            // 根据是否是建筑ID来设置显示名称
            if StructureMarketManager.isStructureId(selectedRegionID) {
                // 是建筑ID，查找建筑名称
                if let structureId = StructureMarketManager.getStructureId(from: selectedRegionID),
                   let structure = getStructureById(structureId) {
                    selectedRegion = structure.structureName
                } else {
                    selectedRegion = "Unknown Structure"
                }
            } else {
                // 是星域ID，查找星域名称
                selectedRegion = regions.first(where: { $0.id == selectedRegionID })?.name ?? ""
            }
            
            selectedRegionName = selectedRegion

            // 只在第一次加载时获取市场订单
            if !hasLoadedOrders {
                await loadAllMarketOrders()
                hasLoadedOrders = true
            }
        }
    }

    // 加载所有物品的市场订单
    private func loadAllMarketOrders(forceRefresh: Bool = false) async {
        guard !items.isEmpty else { return }

        isLoadingOrders = true
        defer {
            isLoadingOrders = false
            hasLoadedOrders = true  // 标记已加载过订单
        }

        // 清除旧数据
        marketOrders.removeAll()

        // 判断是否选择了建筑
        if StructureMarketManager.isStructureId(currentRegionID) {
            // 选择了建筑，使用批量建筑订单API
            guard let structureId = StructureMarketManager.getStructureId(from: currentRegionID) else {
                Logger.error("无效的建筑ID: \(currentRegionID)")
                return
            }
            
            // 获取建筑对应的角色ID
            guard let structure = getStructureById(structureId) else {
                Logger.error("未找到建筑信息: \(structureId)")
                return
            }
            
            do {
                let typeIds = items.map { $0.id }
                let batchOrders = try await StructureMarketManager.shared.getBatchItemOrdersInStructure(
                    structureId: structureId,
                    characterId: structure.characterId,
                    typeIds: typeIds,
                    forceRefresh: forceRefresh,
                    progressCallback: { progress in
                        Task { @MainActor in
                            structureOrdersProgress = progress
                        }
                    }
                )
                
                marketOrders = batchOrders
                Logger.info("从建筑 \(structure.structureName) 批量获取了 \(typeIds.count) 个物品的订单数据")
            } catch {
                Logger.error("批量加载建筑订单失败: \(error)")
            }
        } else {
            // 选择了星域，使用原有的并发API加载
            // 计算并发数
            let concurrency = max(1, min(10, items.count))
            Logger.info("强制刷新: \(forceRefresh)")
            // 创建任务组
            await withTaskGroup(of: (Int, [MarketOrder])?.self) { group in
                var pendingItems = items

                // 初始添加并发数量的任务
                for _ in 0..<concurrency {
                    if !pendingItems.isEmpty {
                        let item = pendingItems.removeFirst()
                        group.addTask {
                            do {
                                let orders = try await MarketOrdersAPI.shared.fetchMarketOrders(
                                    typeID: item.id,
                                    regionID: currentRegionID,
                                    forceRefresh: forceRefresh
                                )
                                return (item.id, orders)
                            } catch {
                                Logger.error("加载市场订单失败: \(error)")
                                return nil
                            }
                        }
                    }
                }

                // 处理结果并添加新任务
                while let result = await group.next() {
                    if let (typeID, orders) = result {
                        marketOrders[typeID] = orders
                    }

                    // 如果还有待处理的物品，添加新任务
                    if !pendingItems.isEmpty {
                        let item = pendingItems.removeFirst()
                        group.addTask {
                            do {
                                let orders = try await MarketOrdersAPI.shared.fetchMarketOrders(
                                    typeID: item.id,
                                    regionID: currentRegionID,
                                    forceRefresh: forceRefresh
                                )
                                return (item.id, orders)
                            } catch {
                                Logger.error("加载市场订单失败: \(error)")
                                return nil
                            }
                        }
                    }
                }
            }
        }
    }

    // 获取列表的总价和库存状态
    private func getListPrice(for item: DatabaseListItem) -> (
        price: Double?, insufficientStock: Bool
    ) {
        guard let orders = marketOrders[item.id] else { return (nil, true) }
        let quantity = quickbar.items.first(where: { $0.typeID == item.id })?.quantity ?? 1

        // 根据订单类型过滤订单
        var filteredOrders = orders.filter { $0.isBuyOrder == (orderType == .buy) }

        // 根据订单类型排序（买单从高到低，卖单从低到高）
        filteredOrders.sort { orderType == .buy ? $0.price > $1.price : $0.price < $1.price }

        var remainingQuantity = quantity
        var totalPrice: Double = 0
        var availableQuantity: Int64 = 0

        // 从最优价格开始累加，直到满足需求数量
        for order in filteredOrders {
            if remainingQuantity <= 0 {
                break
            }

            let orderQuantity = min(remainingQuantity, Int64(order.volumeRemain))
            totalPrice += Double(orderQuantity) * order.price
            remainingQuantity -= orderQuantity
            availableQuantity += orderQuantity
        }

        // 如果没有足够的订单满足数量需求，但有部分订单
        if remainingQuantity > 0 && availableQuantity > 0 {
            return (totalPrice / Double(availableQuantity), true)
        } else if remainingQuantity > 0 {
            return (nil, true)
        }

        // 返回平均单价和库存充足状态
        return (totalPrice / Double(quantity), false)
    }

    @ViewBuilder
    private func itemRow(_ item: DatabaseListItem) -> some View {
        if isEditingQuantity {
            HStack(spacing: 12) {
                Image(uiImage: IconManager.shared.loadUIImage(for: item.iconFileName))
                    .resizable()
                    .frame(width: 40, height: 40)
                    .cornerRadius(6)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .lineLimit(1)

                    let priceInfo = getListPrice(for: item)
                    if let price = priceInfo.price {
                        Text(
                            NSLocalizedString("Main_Market_Avg_Price", comment: "")
                                + FormatUtil.format(price)
                                + " ISK"
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                        HStack(spacing: 4) {
                            Text(
                                NSLocalizedString("Main_Market_Total_Price", comment: "")
                                    + FormatUtil.format(
                                        price * Double(itemQuantities[item.id] ?? 1))
                                    + " ISK"
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                            if priceInfo.insufficientStock {
                                Text(
                                    NSLocalizedString("Main_Market_Insufficient_Stock", comment: "")
                                )
                                .font(.caption)
                                .foregroundColor(.red)
                            }
                        }
                    } else {
                        Text(NSLocalizedString("Main_Market_No_Orders", comment: ""))
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                Spacer()

                TextField(
                    "",
                    text: Binding(
                        get: { String(itemQuantities[item.id] ?? 1) },
                        set: { newValue in
                            if let quantity = Int64(newValue) {
                                let validValue = max(1, min(999_999_999, quantity))
                                itemQuantities[item.id] = validValue
                                if let index = quickbar.items.firstIndex(where: {
                                    $0.typeID == item.id
                                }) {
                                    quickbar.items[index].quantity = validValue
                                }
                            } else {
                                itemQuantities[item.id] = 1
                                if let index = quickbar.items.firstIndex(where: {
                                    $0.typeID == item.id
                                }) {
                                    quickbar.items[index].quantity = 1
                                }
                            }
                        }
                    )
                )
                .keyboardType(.numberPad)
                .multilineTextAlignment(.leading)
                .frame(width: 60)
                .background(Color(uiColor: .secondarySystemBackground))
                .cornerRadius(2)
            }
        } else {
            NavigationLink {
                MarketItemDetailView(
                    databaseManager: databaseManager,
                    itemID: item.id,
                    selectedRegionID: currentRegionID  // 添加当前选中的星域ID
                )
            } label: {
                HStack(spacing: 12) {
                    Image(uiImage: IconManager.shared.loadUIImage(for: item.iconFileName))
                        .resizable()
                        .frame(width: 40, height: 40)
                        .cornerRadius(6)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .lineLimit(1)

                        let priceInfo = getListPrice(for: item)
                        if let price = priceInfo.price {
                            Text(
                                NSLocalizedString("Main_Market_Avg_Price", comment: "")
                                    + FormatUtil.format(price)
                                    + " ISK"
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                            Text(
                                NSLocalizedString("Main_Market_Total_Price", comment: "")
                                    + FormatUtil.format(
                                        price
                                            * Double(
                                                quickbar.items.first(where: { $0.typeID == item.id }
                                                )?.quantity ?? 1))
                                    + " ISK"
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                            if priceInfo.insufficientStock {
                                Text(
                                    NSLocalizedString("Main_Market_Insufficient_Stock", comment: "")
                                )
                                .font(.caption)
                                .foregroundColor(.red)
                            }
                        } else {
                            Text(NSLocalizedString("Main_Market_No_Orders", comment: ""))
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }

                    Spacer()

                    Text(getItemQuantity(for: item))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func getItemQuantity(for item: DatabaseListItem) -> String {
        let quantity = quickbar.items.first(where: { $0.typeID == item.id })?.quantity ?? 1
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: quantity)) ?? "1"
    }

    private func loadItems() {
        if !quickbar.items.isEmpty {
            let itemIDs = quickbar.items.map { String($0.typeID) }.joined(separator: ",")
            items = databaseManager.loadMarketItems(
                whereClause: "t.type_id IN (\(itemIDs))",
                parameters: []
            )
            // 按 type_id 排序并更新
            let sorted = items.sorted(by: { $0.id < $1.id })
            items = sorted
            // 更新 itemQuantities
            itemQuantities = Dictionary(
                uniqueKeysWithValues: quickbar.items.map { ($0.typeID, $0.quantity) })
            // 确保 quickbar.items 的顺序与加载的物品顺序一致
            quickbar.items = sorted.map { item in
                QuickbarItem(
                    typeID: item.id,
                    quantity: quickbar.items.first(where: { $0.typeID == item.id })?.quantity ?? 1
                )
            }
        }
    }

    private func loadRegions() {
        let query = """
                SELECT r.regionID, r.regionName
                FROM regions r
                WHERE r.regionID < 11000000
                ORDER BY r.regionName
            """

        if case let .success(rows) = databaseManager.executeQuery(query) {
            for row in rows {
                if let regionId = row["regionID"] as? Int,
                    let regionNameLocal = row["regionName"] as? String
                {
                    let regionName = regionNameLocal
                    regions.append((id: regionId, name: regionName))
                }
            }
        }
    }

    // 计算所有物品的总价格和库存状态
    private func calculateTotalPrice() -> (total: Double, hasInsufficientStock: Bool) {
        var total: Double = 0
        var hasInsufficientStock = false

        for item in items {
            let priceInfo = getListPrice(for: item)
            if let price = priceInfo.price {
                let quantity = quickbar.items.first(where: { $0.typeID == item.id })?.quantity ?? 1
                total += price * Double(quantity)
            }
            if priceInfo.insufficientStock {
                hasInsufficientStock = true
            }
        }
        return (total, hasInsufficientStock)
    }
}

// 集成版市场物品选择器视图
struct MarketItemSelectorIntegratedView: View {
    @ObservedObject var databaseManager: DatabaseManager
    let title: String
    let allowedMarketGroups: Set<Int>
    let allowTypeIDs: Set<Int>?  // 新增：物品ID白名单
    let existingItems: Set<Int>
    let onItemSelected: (DatabaseListItem) -> Void
    let onItemDeselected: (DatabaseListItem) -> Void
    let onDismiss: () -> Void
    let showSelected: Bool

    @State private var marketGroups: [MarketGroup] = []
    @State private var validMarketGroups: Set<Int> = []  // 新增：缓存有效的市场组ID

    var body: some View {
        MarketItemSelectorBaseView(
            databaseManager: databaseManager,
            title: title,
            content: {
                ForEach(
                    getFilteredRootGroups()
                ) { group in
                    MarketItemSelectorGroupRow(
                        group: group,
                        allGroups: marketGroups,
                        validGroups: validMarketGroups,  // 新增：传递有效组ID
                        allowTypeIDs: allowTypeIDs,  // 新增：传递物品ID白名单
                        databaseManager: databaseManager,
                        existingItems: existingItems,
                        onItemSelected: onItemSelected,
                        onItemDeselected: onItemDeselected,
                        onDismiss: onDismiss,
                        showSelected: showSelected
                    )
                }
            },
            searchQuery: { text in
                let groupIDsString = MarketManager.shared.getAllSubGroupIDsFromIDs(
                    marketGroups, allowedIDs: allowedMarketGroups.isEmpty ? [] : allowedMarketGroups
                ).map { String($0) }.joined(separator: ",")
                
                var groupIDsStringIn = "IS NOT NULL"
                if !groupIDsString.isEmpty {
                    groupIDsStringIn = "IN (\(groupIDsString))"
                }

                if let typeIDs = allowTypeIDs, !typeIDs.isEmpty {
                    // 如果有物品ID白名单，添加物品ID筛选条件
                    let typeIDsString = typeIDs.map { String($0) }.joined(separator: ",")
                    return
                        "t.marketGroupID \(groupIDsStringIn) AND t.type_id IN (\(typeIDsString)) AND (t.name LIKE ? OR t.en_name LIKE ? OR t.type_id = ?)"
                } else {
                    // 否则只筛选市场分组
                    return
                        "t.marketGroupID \(groupIDsStringIn) AND (t.name LIKE ? OR t.en_name LIKE ? OR t.type_id = ?)"
                }
            },
            searchParameters: { text in
                ["%\(text)%", "%\(text)%", text]
            },
            existingItems: existingItems,
            onItemSelected: onItemSelected,
            onItemDeselected: onItemDeselected,
            onDismiss: onDismiss,
            showSelected: showSelected
        )
        .onAppear {
            marketGroups = MarketManager.shared.loadMarketGroups(databaseManager: databaseManager)

            // 如果有typeID白名单，计算有效的市场组
            if let typeIDs = allowTypeIDs, !typeIDs.isEmpty {
                Task {
                    validMarketGroups = await calculateValidMarketGroups(typeIDs: typeIDs)
                }
            }
        }
    }

    // 根据筛选条件获取根目录
    private func getFilteredRootGroups() -> [MarketGroup] {
        // 根据市场组ID白名单筛选初始根组
        let initialRootGroups: [MarketGroup]
        if allowedMarketGroups.isEmpty {
            initialRootGroups = MarketManager.shared.getRootGroups(marketGroups)
        } else {
            initialRootGroups = MarketManager.shared.setRootGroups(
                marketGroups, allowedIDs: allowedMarketGroups)
        }

        // 如果有物品ID白名单且有效组ID已计算，过滤出有效的根目录
        let validRootGroups: [MarketGroup]
        if allowTypeIDs != nil, !validMarketGroups.isEmpty {
            validRootGroups = initialRootGroups.filter { validMarketGroups.contains($0.id) }
        } else {
            validRootGroups = initialRootGroups
        }

        // 应用剪枝逻辑，压缩只有单个子节点的顶层路径
        return pruneTopLevelPath(validRootGroups)
    }

    // 剪枝函数：仅压缩顶层单一路径，直接返回最后一个分支的子节点
    private func pruneTopLevelPath(_ groups: [MarketGroup]) -> [MarketGroup] {
        // 如果有多个根组，则不需要剪枝
        if groups.count > 1 {
            return groups
        }

        // 空组直接返回
        if groups.isEmpty {
            return []
        }

        // 获取当前唯一根节点
        let currentGroup = groups[0]

        // 获取子节点
        let subGroups = MarketManager.shared.getSubGroups(marketGroups, for: currentGroup.id)

        // 过滤有效的子组（如果存在物品白名单）
        let validSubGroups: [MarketGroup]
        if allowTypeIDs != nil, !validMarketGroups.isEmpty {
            validSubGroups = subGroups.filter { validMarketGroups.contains($0.id) }
        } else {
            validSubGroups = subGroups
        }

        // 如果没有子节点，返回当前节点
        if validSubGroups.isEmpty {
            return [currentGroup]
        }

        // 如果只有一个子节点，继续沿着单一路径向下剪枝
        if validSubGroups.count == 1 {
            return pruneTopLevelPath(validSubGroups)
        }

        // 有多个子节点，表示到达分支点，返回所有子节点而不是当前节点
        return validSubGroups
    }

    // 计算有效的市场组ID（有物品在allowTypeIDs中的组）
    private func calculateValidMarketGroups(typeIDs: Set<Int>) async -> Set<Int> {
        guard !typeIDs.isEmpty else { return Set() }

        let typeIDsString = typeIDs.map { String($0) }.joined(separator: ",")

        // 查询所有在白名单中的物品及其市场组ID
        let query = """
                SELECT DISTINCT marketGroupID
                FROM types
                WHERE type_id IN (\(typeIDsString))
                AND marketGroupID IS NOT NULL
            """

        var validGroupIDs = Set<Int>()

        if case let .success(rows) = databaseManager.executeQuery(query) {
            for row in rows {
                if let groupID = row["marketGroupID"] as? Int {
                    validGroupIDs.insert(groupID)

                    // 添加所有父级组ID
                    var currentGroup = marketGroups.first { $0.id == groupID }
                    while let group = currentGroup, let parentID = group.parentGroupID {
                        validGroupIDs.insert(parentID)
                        currentGroup = marketGroups.first { $0.id == parentID }
                    }
                }
            }
        }

        return validGroupIDs
    }
}

// MARK: - MarketQuickbarDetailView扩展

extension MarketQuickbarDetailView {
    // 根据建筑ID获取建筑信息
    private func getStructureById(_ structureId: Int64) -> MarketStructure? {
        return MarketStructureManager.shared.structures.first { $0.structureId == Int(structureId) }
    }
    
    // 验证区域ID是否有效（星域或存在的建筑）
    private func isValidRegionID(_ regionID: Int) -> Bool {
        // 检查是否是建筑ID（负数表示建筑）
        if StructureMarketManager.isStructureId(regionID) {
            // 验证建筑是否存在
            guard let structureId = StructureMarketManager.getStructureId(from: regionID) else {
                return false
            }
            return getStructureById(structureId) != nil
        }
        
        // 检查是否是有效的星域ID
        if regionID > 0 && regionID < 11000000 {
            // 查询数据库验证星域是否存在
            let query = """
                    SELECT regionID
                    FROM regions
                    WHERE regionID = ?
                """
            if case let .success(rows) = databaseManager.executeQuery(query, parameters: [regionID]) {
                return !rows.isEmpty
            }
        }
        
        return false
    }
}
