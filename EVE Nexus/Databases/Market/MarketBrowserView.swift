import SwiftUI

/// 用于 .sheet(item:) 的 marketGroupID 包装
private struct QuickCompareID: Identifiable { let id: Int }

// 「精准匹配」置顶 section 的哨兵 ID（不与真实 group id 重叠）

/// 结果数超过该阈值时使用目录模式（逐级下钻），否则平铺
private let searchDirectoryModeThreshold = 50

/// 基础市场视图
struct MarketBaseView<Content: View>: View {
    @ObservedObject var databaseManager: DatabaseManager
    let title: String
    let content: () -> Content
    let searchQuery: (String) -> String
    let searchParameters: (String) -> [Any]
    /// 提供市场目录树时，搜索结果按剪枝目录树展示（仅保留含命中物品的分支）；否则扁平分组
    var searchTree: MarketTree? = nil
    /// 目录树展示的根节点（nil = 从 roots 开始）
    var searchTreeRootID: Int? = nil

    @State private var items: [DatabaseListItem] = []
    @State private var searchText = ""
    @State private var isSearchActive = false
    @State private var isLoading = false
    @State private var isShowingSearchResults = false
    @State private var quickCompareID: QuickCompareID?

    /// 命中物品按 marketGroup 聚合 + 子树命中数沿祖先累积（目录模式用）
    private var searchDirectoryModel: (itemsByGroup: [Int: [DatabaseListItem]], matchCount: [Int: Int]) {
        let itemsByGroup = Dictionary(grouping: items) { $0.marketGroupID ?? 0 }
        var matchCount: [Int: Int] = [:]
        if let tree = searchTree {
            for (groupID, groupItems) in itemsByGroup {
                var current: Int? = groupID
                while let groupID = current {
                    matchCount[groupID, default: 0] += groupItems.count
                    current = tree.group(byID: groupID)?.parentGroupID
                }
            }
        }
        return (itemsByGroup, matchCount)
    }

    static func sortItemsForMarketSearchSection(_ list: [DatabaseListItem]) -> [DatabaseListItem] {
        list.sorted { item1, item2 in
            if item1.metaGroupID != item2.metaGroupID {
                return (item1.metaGroupID ?? -1) < (item2.metaGroupID ?? -1)
            }
            return item1.name.localizedCaseInsensitiveCompare(item2.name) == .orderedAscending
        }
    }

    private func groupMarketSearchItems(_ items: [DatabaseListItem]) -> [SearchResultSection<DatabaseListItem>] {
        guard !items.isEmpty else { return [] }

        var groupedByCategory: [Int: [(groupID: Int, name: String, items: [DatabaseListItem])]] = [:]
        for item in items {
            let categoryID = item.categoryID ?? 0
            let groupID = item.groupID ?? 0
            let groupName = item.groupName ?? "Unknown Group"
            if let index = groupedByCategory[categoryID]?.firstIndex(where: { $0.groupID == groupID }) {
                groupedByCategory[categoryID]?[index].items.append(item)
            } else {
                groupedByCategory[categoryID, default: []].append(
                    (groupID: groupID, name: groupName, items: [item])
                )
            }
        }

        let sortedCategories = groupedByCategory.keys.sorted { cat1, cat2 in
            let index1 = MarketManager.categoryPriority.firstIndex(of: cat1) ?? Int.max
            let index2 = MarketManager.categoryPriority.firstIndex(of: cat2) ?? Int.max
            return index1 == index2 ? cat1 < cat2 : index1 < index2
        }

        var result: [SearchResultSection<DatabaseListItem>] = []
        for categoryID in sortedCategories {
            for group in (groupedByCategory[categoryID] ?? []).sorted(by: { $0.groupID < $1.groupID }) {
                result.append(
                    SearchResultSection(
                        identity: .group(group.groupID), name: group.name,
                        items: Self.sortItemsForMarketSearchSection(group.items)
                    )
                )
            }
        }
        return result.filter { !$0.items.isEmpty }
    }

    var body: some View {
        List {
            if isShowingSearchResults {
                if let tree = searchTree, items.count > searchDirectoryModeThreshold {
                    // 目录模式：与原浏览一致的分组行 + 命中数，逐级下钻
                    let model = searchDirectoryModel
                    MarketSearchDirectoryRows(
                        tree: tree, rootGroupID: searchTreeRootID,
                        itemsByGroup: model.itemsByGroup, matchCount: model.matchCount,
                        databaseManager: databaseManager
                    )
                } else {
                    // 平铺模式：按分组分 section
                    ForEach(groupMarketSearchItems(items), id: \.id) { group in
                        Section(
                            header: Text(group.name)
                                .fontWeight(.semibold)
                                .font(.system(size: 18))
                                .foregroundColor(.primary)
                                .textCase(.none)
                        ) {
                            ForEach(group.items) { item in
                                searchResultItemRow(item)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
            } else {
                content()
            }
        }
        .searchable(
            text: $searchText,
            isPresented: $isSearchActive,
            prompt: Text(NSLocalizedString("Main_Database_Search", comment: ""))
        )
        .onSubmit(of: .search) {
            if !searchText.isEmpty {
                performSearch(with: searchText)
            }
        }
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty {
                isShowingSearchResults = false
                isLoading = false
                items = []
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
                    Label(NSLocalizedString("Misc_Not_Found", comment: ""), systemImage: "magnifyingglass")
                }
            } else if searchText.isEmpty && isSearchActive {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .onTapGesture { isSearchActive = false }
            }
        }
        .navigationTitle(title)
        .sheet(item: $quickCompareID) { id in
            AttributeQuickCompareSheet(databaseManager: databaseManager, marketGroupID: id.id)
        }
    }

    private func performSearch(with text: String) {
        isLoading = true
        // 无数量上限：结果按剪枝目录树承载索引；精确匹配由 SQL 排序优先返回
        items = databaseManager.loadMarketItems(
            whereClause: searchQuery(text), parameters: searchParameters(text),
            eligibleMarketGroupIDs: AttributeCompareMarketPolicy.eligibleMarketGroupIDs,
            exactMatchText: text
        )
        isShowingSearchResults = true
        isLoading = false
    }

    private func searchResultItemRow(_ item: DatabaseListItem) -> some View {
        MarketSearchItemRow(item: item, databaseManager: databaseManager) { marketGroupID in
            quickCompareID = QuickCompareID(id: marketGroupID)
        }
    }
}

/// 搜索结果物品行：详情跳转 + 属性快速对比入口
private struct MarketSearchItemRow: View {
    let item: DatabaseListItem
    let databaseManager: DatabaseManager
    let onQuickCompare: (Int) -> Void

    var body: some View {
        NavigationLink {
            MarketItemDetailView(databaseManager: databaseManager, itemID: item.id)
        } label: {
            DatabaseListItemView(
                item: item,
                showDetails: true,
                onAttributeQuickCompare: onQuickCompare
            )
        }
    }
}

/// 目录模式的行集合：当前层级中含命中的子组（带命中数），叶子组导向命中物品列表
private struct MarketSearchDirectoryRows: View {
    let tree: MarketTree
    /// 当前层级根节点（nil = 从 roots 开始）
    let rootGroupID: Int?
    let itemsByGroup: [Int: [DatabaseListItem]]
    let matchCount: [Int: Int]
    let databaseManager: DatabaseManager

    private var visibleGroups: [MarketGroup] {
        let candidates = rootGroupID.map { tree.children(of: $0) } ?? tree.roots
        return candidates.filter { (matchCount[$0.id] ?? 0) > 0 }
    }

    var body: some View {
        // 当前层根节点的直属命中物品（如有）
        if let rootGroupID, let directItems = itemsByGroup[rootGroupID], !directItems.isEmpty {
            ForEach(
                MarketBaseView<EmptyView>.sortItemsForMarketSearchSection(directItems)
            ) { item in
                MarketSearchItemRow(item: item, databaseManager: databaseManager) { _ in }
            }
        }

        ForEach(visibleGroups) { group in
            NavigationLink {
                if tree.isLeaf(group) {
                    MarketSearchItemsView(
                        title: group.name,
                        items: itemsByGroup[group.id] ?? [],
                        databaseManager: databaseManager
                    )
                } else {
                    MarketSearchDirectoryView(
                        group: group, tree: tree,
                        itemsByGroup: itemsByGroup, matchCount: matchCount,
                        databaseManager: databaseManager
                    )
                }
            } label: {
                HStack {
                    MarketGroupLabel(group: group)
                    Text("\(matchCount[group.id] ?? 0)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

/// 目录模式下钻页：某一市场分组内的剪枝目录，与原浏览 UI 一致
private struct MarketSearchDirectoryView: View {
    let group: MarketGroup
    let tree: MarketTree
    let itemsByGroup: [Int: [DatabaseListItem]]
    let matchCount: [Int: Int]
    let databaseManager: DatabaseManager

    var body: some View {
        List {
            MarketSearchDirectoryRows(
                tree: tree, rootGroupID: group.id,
                itemsByGroup: itemsByGroup, matchCount: matchCount,
                databaseManager: databaseManager
            )
            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
        }
        .navigationTitle(group.name)
    }
}

/// 目录模式叶子页：某一市场分组的全部命中物品
private struct MarketSearchItemsView: View {
    let title: String
    let items: [DatabaseListItem]
    let databaseManager: DatabaseManager
    @State private var quickCompareID: QuickCompareID?

    var body: some View {
        List {
            ForEach(MarketBaseView<EmptyView>.sortItemsForMarketSearchSection(items)) { item in
                MarketSearchItemRow(item: item, databaseManager: databaseManager) { marketGroupID in
                    quickCompareID = QuickCompareID(id: marketGroupID)
                }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
        }
        .navigationTitle(title)
        .sheet(item: $quickCompareID) { id in
            AttributeQuickCompareSheet(databaseManager: databaseManager, marketGroupID: id.id)
        }
    }
}

/// 重构后的MarketBrowserView
struct MarketBrowserView: View {
    @ObservedObject var databaseManager: DatabaseManager
    /// 一次性构建的目录树索引：所有子节点查找/叶子判断/子树 ID 枚举均通过它 O(1) 完成
    @State private var marketTree: MarketTree = .init([])
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            MarketBaseView(
                databaseManager: databaseManager,
                title: NSLocalizedString("Main_Market", comment: ""),
                content: {
                    ForEach(marketTree.roots) { group in
                        MarketGroupRow(
                            group: group, tree: marketTree, databaseManager: databaseManager,
                            path: $path
                        )
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                },
                searchQuery: { _ in
                    "t.marketGroupID IS NOT NULL AND (\(LocalizedText.typeLangNameLikeSQL) OR t.type_id = ?)"
                },
                searchParameters: { text in
                    LocalizedText.typeLangNameLikeParams(text) + ["\(text)"]
                },
                searchTree: marketTree
            )
            .navigationDestination(for: MarketGroup.self) { group in
                MarketGroupView(
                    databaseManager: databaseManager,
                    group: group,
                    tree: marketTree,
                    path: $path
                )
            }
            .navigationDestination(for: MarketItemDestination.self) { destination in
                MarketItemListView(
                    databaseManager: databaseManager,
                    marketGroupID: destination.marketGroupID,
                    title: destination.title,
                    path: $path
                )
            }
            .onAppear {
                // 一次性加载所有市场组并构建索引树；后续导航不再触碰 SQL
                // 属性对比资格集合由 AttributeCompareMarketPolicy.eligibleMarketGroupIDs 懒加载，
                // 首次访问时从同一份 SDE 展开并缓存，此处无需再维护
                marketTree = MarketManager.shared.buildTree(
                    from: MarketManager.shared.loadMarketGroups(databaseManager: databaseManager)
                )
            }
        }
    }
}

/// 为物品列表创建目的地类型
struct MarketItemDestination: Hashable {
    let marketGroupID: Int
    let title: String
}

/// 重构后的MarketGroupView
struct MarketGroupView: View {
    @ObservedObject var databaseManager: DatabaseManager
    let group: MarketGroup
    let tree: MarketTree
    @Binding var path: NavigationPath

    var body: some View {
        MarketBaseView(
            databaseManager: databaseManager,
            title: group.name,
            content: {
                ForEach(tree.children(of: group.id)) { subGroup in
                    MarketGroupRow(
                        group: subGroup, tree: tree, databaseManager: databaseManager,
                        path: $path
                    )
                }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            },
            searchQuery: { _ in
                // 通过索引树一次性枚举当前节点所有子孙组 ID，限定搜索范围到子树
                let groupIDs = tree.allSubGroupIDs(from: group.id)
                let groupIDsString = groupIDs.sorted().map { String($0) }.joined(separator: ",")
                return
                    "t.marketGroupID IN (\(groupIDsString)) AND \(LocalizedText.typeLangNameLikeSQL)"
            },
            searchParameters: { text in
                LocalizedText.typeLangNameLikeParams(text)
            },
            searchTree: tree,
            searchTreeRootID: group.id
        )
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    // 清空导航路径，返回到根视图
                    path.removeLast(path.count)
                }) {
                    Image(systemName: "house")
                }
            }
        }
    }
}

/// 重构后的MarketItemListView
struct MarketItemListView: View {
    @ObservedObject var databaseManager: DatabaseManager
    let marketGroupID: Int
    let title: String
    @State private var items: [DatabaseListItem] = []
    @State private var metaGroupNames: [Int: String] = [:]
    @Binding var path: NavigationPath
    @State private var leafQuickCompareID: QuickCompareID?

    var groupedItems: [(id: Int, name: String, items: [DatabaseListItem])] {
        let publishedItems = items.filter { $0.published }
        let unpublishedItems = items.filter { !$0.published }

        var result: [(id: Int, name: String, items: [DatabaseListItem])] = []

        // 按科技等级分组
        var techLevelGroups: [Int?: [DatabaseListItem]] = [:]
        for item in publishedItems {
            techLevelGroups[item.metaGroupID, default: []].append(item)
        }

        // 添加已发布物品组
        for (techLevel, items) in techLevelGroups.sorted(by: { ($0.key ?? -1) < ($1.key ?? -1) }) {
            if let techLevel = techLevel {
                let name = metaGroupNames[techLevel] ?? NSLocalizedString("Main_Database_base", comment: "基础物品")
                let sortedItems = items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                result.append((id: techLevel, name: name, items: sortedItems))
            }
        }

        // 添加未分组的物品
        if let ungroupedItems = techLevelGroups[nil], !ungroupedItems.isEmpty {
            let sortedItems = ungroupedItems.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            result.append((id: -2, name: NSLocalizedString("Main_Database_ungrouped", comment: "未分组"), items: sortedItems))
        }

        // 添加未发布物品组
        if !unpublishedItems.isEmpty {
            let sortedItems = unpublishedItems.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            result.append((id: -1, name: NSLocalizedString("Main_Database_unpublished", comment: "未发布"), items: sortedItems))
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
                            .fontWeight(.semibold)
                            .font(.system(size: 18))
                            .foregroundColor(.primary)
                            .textCase(.none)
                    ) {
                        ForEach(group.items) { item in
                            NavigationLink {
                                MarketItemDetailView(databaseManager: databaseManager, itemID: item.id)
                            } label: {
                                DatabaseListItemView(
                                    item: item,
                                    showDetails: true,
                                    onAttributeQuickCompare: { leafQuickCompareID = QuickCompareID(id: $0) }
                                )
                            }
                        }
                    }
                }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            },
            searchQuery: { _ in "t.marketGroupID = ? AND \(LocalizedText.typeLangNameLikeSQL)" },
            searchParameters: { text in [marketGroupID] + LocalizedText.typeLangNameLikeParams(text) }
        )
        .sheet(item: $leafQuickCompareID) { id in
            AttributeQuickCompareSheet(databaseManager: databaseManager, marketGroupID: id.id)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { path.removeLast(path.count) }) {
                    Image(systemName: "house")
                }
            }
        }
        .onAppear { loadItems() }
    }

    private func loadItems() {
        items = databaseManager.loadMarketItems(
            whereClause: "t.marketGroupID = ?",
            parameters: [marketGroupID],
            eligibleMarketGroupIDs: AttributeCompareMarketPolicy.eligibleMarketGroupIDs
        )

        // 加载科技等级名称
        let metaGroupIDs = Set(items.compactMap { $0.metaGroupID })
        metaGroupNames = databaseManager.loadMetaGroupNames(for: Array(metaGroupIDs))
    }
}

struct MarketGroupRow: View {
    let group: MarketGroup
    let tree: MarketTree
    let databaseManager: DatabaseManager
    @Binding var path: NavigationPath

    var body: some View {
        if tree.isLeaf(group) {
            // 最后一级目录，显示物品列表
            NavigationLink(value: MarketItemDestination(marketGroupID: group.id, title: group.name)) {
                MarketGroupLabel(group: group)
            }
        } else {
            // 非最后一级目录，显示子目录
            NavigationLink(value: group) {
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
                .foregroundColor(.primary)
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = group.name
                    } label: {
                        Label(
                            NSLocalizedString("Misc_Copy", comment: ""), systemImage: "doc.on.doc"
                        )
                    }
                }

            Spacer()
        }
    }
}
