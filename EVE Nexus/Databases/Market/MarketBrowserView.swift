import SwiftUI

// 基础市场视图
struct MarketBaseView<Content: View>: View {
    @ObservedObject var databaseManager: DatabaseManager
    let title: String
    let content: () -> Content  // 常规内容视图
    let searchQuery: (String) -> String  // SQL查询语句生成器
    let searchParameters: (String) -> [Any]  // SQL参数生成器

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
        let sortedCategories = groupedByCategory.keys.sorted { cat1, cat2 in
            let index1 = categoryPriority.firstIndex(of: cat1) ?? Int.max
            let index2 = categoryPriority.firstIndex(of: cat2) ?? Int.max
            if index1 == index2 {
                return cat1 < cat2  // 如果都不在优先级列表中，按ID升序
            }
            return index1 < index2  // 按优先级排序
        }

        // 构建最终结果
        var result: [(id: Int, name: String, items: [DatabaseListItem])] = []

        for categoryID in sortedCategories {
            if let categoryGroups = groupedByCategory[categoryID] {
                // 在每个分类内部，按groupID排序
                let sortedGroups = categoryGroups.sorted { $0.groupID < $1.groupID }

                for group in sortedGroups {
                    // 对组内物品进行排序
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

        return result.filter { !$0.items.isEmpty }
    }

    var body: some View {
        List {
            if isShowingSearchResults {
                // 搜索结果视图，按市场组分类显示
                ForEach(groupedSearchResults, id: \.id) { group in
                    Section(
                        header: Text(group.name)
                            .fontWeight(.bold)
                            .font(.system(size: 18))
                            .foregroundColor(.primary)
                            .textCase(.none)
                    ) {
                        ForEach(group.items) { item in
                            NavigationLink {
                                MarketItemDetailView(
                                    databaseManager: databaseManager,
                                    itemID: item.id
                                )
                            } label: {
                                DatabaseListItemView(
                                    item: item,
                                    showDetails: true
                                )
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    }
                }
            } else {
                content()  // 显示常规内容
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

        items = databaseManager.loadMarketItems(whereClause: whereClause, parameters: parameters, limit: 100)
        isShowingSearchResults = true

        isLoading = false
    }
}

// 重构后的MarketBrowserView
struct MarketBrowserView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var marketGroups: [MarketGroup] = []

    var body: some View {
        NavigationStack {
            MarketBaseView(
                databaseManager: databaseManager,
                title: NSLocalizedString("Main_Market", comment: ""),
                content: {
                    ForEach(MarketManager.shared.getRootGroups(marketGroups)) { group in
                        MarketGroupRow(
                            group: group, allGroups: marketGroups, databaseManager: databaseManager
                        )
                    }
                },
                searchQuery: { _ in
                    "t.marketGroupID IS NOT NULL AND (t.name LIKE ? OR t.en_name LIKE ? OR t.type_id = ?)"
                },
                searchParameters: { text in
                    ["%\(text)%", "%\(text)%", "\(text)"]
                }
            )
            .onAppear {
                marketGroups = MarketManager.shared.loadMarketGroups(
                    databaseManager: databaseManager)
            }
        }
    }
}

// 重构后的MarketGroupView
struct MarketGroupView: View {
    @ObservedObject var databaseManager: DatabaseManager
    let group: MarketGroup
    let allGroups: [MarketGroup]

    var body: some View {
        MarketBaseView(
            databaseManager: databaseManager,
            title: group.name,
            content: {
                ForEach(MarketManager.shared.getSubGroups(allGroups, for: group.id)) { subGroup in
                    MarketGroupRow(
                        group: subGroup, allGroups: allGroups, databaseManager: databaseManager
                    )
                }
            },
            searchQuery: { _ in
                let groupIDs = MarketManager.shared.getAllSubGroupIDsFromID(
                    allGroups, startingFrom: group.id
                )
                let groupIDsString = groupIDs.sorted().map { String($0) }.joined(separator: ",")
                return
                    "t.marketGroupID IN (\(groupIDsString)) AND (t.name LIKE ? OR t.en_name LIKE ?)"
            },
            searchParameters: { text in
                ["%\(text)%", "%\(text)%"]
            }
        )
    }
}

// 重构后的MarketItemListView
struct MarketItemListView: View {
    @ObservedObject var databaseManager: DatabaseManager
    let marketGroupID: Int
    let title: String
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
                // 对每个科技等级组内的物品按名称排序
                let sortedItems = items.sorted { item1, item2 in
                    item1.name.localizedCaseInsensitiveCompare(item2.name) == .orderedAscending
                }
                result.append((id: techLevel, name: name, items: sortedItems))
            }
        }

        // 添加未分组的物品
        if let ungroupedItems = techLevelGroups[nil], !ungroupedItems.isEmpty {
            // 对未分组物品按名称排序
            let sortedItems = ungroupedItems.sorted { item1, item2 in
                item1.name.localizedCaseInsensitiveCompare(item2.name) == .orderedAscending
            }
            result.append(
                (
                    id: -2, name: NSLocalizedString("Main_Database_ungrouped", comment: "未分组"),
                    items: sortedItems
                ))
        }

        // 添加未发布物品组
        if !unpublishedItems.isEmpty {
            // 对未发布物品按名称排序
            let sortedItems = unpublishedItems.sorted { item1, item2 in
                item1.name.localizedCaseInsensitiveCompare(item2.name) == .orderedAscending
            }
            result.append(
                (
                    id: -1, name: NSLocalizedString("Main_Database_unpublished", comment: "未发布"),
                    items: sortedItems
                ))
        }

        return result
    }

    var body: some View {
        MarketBaseView(
            databaseManager: databaseManager,
            title: title,
            content: {
                ForEach(groupedItems, id: \.id) { group in
                    Section(
                        header: Text(group.name)
                            .fontWeight(.bold)
                            .font(.system(size: 18))
                            .foregroundColor(.primary)
                            .textCase(.none)
                    ) {
                        ForEach(group.items) { item in
                            NavigationLink {
                                MarketItemDetailView(
                                    databaseManager: databaseManager,
                                    itemID: item.id
                                )
                            } label: {
                                DatabaseListItemView(
                                    item: item,
                                    showDetails: true
                                )
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    }
                }
            },
            searchQuery: { _ in
                "t.marketGroupID = ? AND (t.name LIKE ? OR t.en_name LIKE ?)"
            },
            searchParameters: { text in
                [marketGroupID, "%\(text)%", "%\(text)%"]
            }
        )
        .onAppear {
            loadItems()
        }
    }

    private func loadItems() {
        items = databaseManager.loadMarketItems(
            whereClause: "t.marketGroupID = ?",
            parameters: [marketGroupID]
        )

        // 加载科技等级名称
        let metaGroupIDs = Set(items.compactMap { $0.metaGroupID })
        metaGroupNames = databaseManager.loadMetaGroupNames(for: Array(metaGroupIDs))
    }
}

struct MarketGroupRow: View {
    let group: MarketGroup
    let allGroups: [MarketGroup]
    let databaseManager: DatabaseManager

    var body: some View {
        if MarketManager.shared.isLeafGroup(group, in: allGroups) {
            // 最后一级目录，显示物品列表
            NavigationLink {
                MarketItemListView(
                    databaseManager: databaseManager,
                    marketGroupID: group.id,
                    title: group.name
                )
            } label: {
                MarketGroupLabel(group: group)
            }
        } else {
            // 非最后一级目录，显示子目录
            NavigationLink {
                MarketGroupView(
                    databaseManager: databaseManager,
                    group: group,
                    allGroups: allGroups
                )
            } label: {
                MarketGroupLabel(group: group)
            }
        }
    }
}

struct MarketGroupLabel: View {
    let group: MarketGroup

    var body: some View {
        HStack {
            IconManager.shared.loadImage(for: group.iconName)
                .resizable()
                .frame(width: 32, height: 32)
                .cornerRadius(6)

            Text(group.name)
                .font(.body)
        }
    }
}
