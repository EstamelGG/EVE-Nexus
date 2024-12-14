import SwiftUI

// 基础市场视图
struct MarketBaseView<Content: View>: View {
    @ObservedObject var databaseManager: DatabaseManager
    let title: String
    let content: () -> Content  // 常规内容视图
    let searchQuery: (String) -> String  // SQL查询语句生成器
    let searchParameters: (String) -> [Any]  // SQL参数生成器
    
    @State private var items: [DatabaseListItem] = []
    @State private var marketGroupNames: [Int: String] = [:]
    @State private var searchText = ""
    @State private var isSearchActive = false
    @State private var isLoading = false
    @State private var isShowingSearchResults = false
    @StateObject private var searchController = SearchController()
    
    // 搜索结果分组
    var groupedSearchResults: [(id: Int, name: String, items: [DatabaseListItem])] {
        guard !items.isEmpty else { return [] }
        
        // 按物品组分类
        var groupItems: [Int: (name: String, items: [DatabaseListItem])] = [:]
        var ungroupedItems: [DatabaseListItem] = []
        
        for item in items {
            if let groupID = item.groupID, let groupName = item.groupName {
                if groupItems[groupID] == nil {
                    groupItems[groupID] = (name: groupName, items: [])
                }
                groupItems[groupID]?.items.append(item)
            } else {
                ungroupedItems.append(item)
            }
        }
        
        var result: [(id: Int, name: String, items: [DatabaseListItem])] = []
        
        // 添加有物品组的物品
        for (groupID, group) in groupItems.sorted(by: { $0.value.name < $1.value.name }) {
            result.append((id: groupID, name: group.name, items: group.items))
        }
        
        // 添加未分组的物品
        if !ungroupedItems.isEmpty {
            result.append((id: -1, name: "未分组", items: ungroupedItems))
        }
        
        return result
    }
    
    var body: some View {
        List {
            if isShowingSearchResults {
                // 搜索结果视图，按市场组分类显示
                ForEach(groupedSearchResults, id: \.id) { group in
                    Section(header: Text(group.name)
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
                            Text("正在搜索...")
                                .foregroundColor(.secondary)
                                .padding(.top, 8)
                        }
                    }
            } else if items.isEmpty && !searchText.isEmpty {
                ContentUnavailableView {
                    Label("未找到", systemImage: "magnifyingglass")
                } description: {
                    Text("没有找到匹配的项目")
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
        
        let query = searchQuery(text)
        let parameters = searchParameters(text)
        
        if case .success(let rows) = databaseManager.executeQuery(query, parameters: parameters) {
            items = rows.compactMap { row in
                guard let id = row["id"] as? Int,
                      let name = row["name"] as? String
                else { return nil }
                
                let iconFileName = (row["iconFileName"] as? String) ?? "items_7_64_15.png"
                let published = (row["published"] as? Int) ?? 0
                let groupID = row["groupID"] as? Int
                let groupName = row["groupName"] as? String
                
                return DatabaseListItem(
                    id: id,
                    name: name,
                    iconFileName: iconFileName,
                    published: published == 1,
                    categoryID: row["categoryID"] as? Int,
                    groupID: groupID,
                    groupName: groupName,
                    pgNeed: row["pgNeed"] as? Int,
                    cpuNeed: row["cpuNeed"] as? Int,
                    rigCost: row["rigCost"] as? Int,
                    emDamage: row["emDamage"] as? Double,
                    themDamage: row["themDamage"] as? Double,
                    kinDamage: row["kinDamage"] as? Double,
                    expDamage: row["expDamage"] as? Double,
                    highSlot: row["highSlot"] as? Int,
                    midSlot: row["midSlot"] as? Int,
                    lowSlot: row["lowSlot"] as? Int,
                    rigSlot: row["rigSlot"] as? Int,
                    gunSlot: row["gunSlot"] as? Int,
                    missSlot: row["missSlot"] as? Int,
                    metaGroupID: row["metaGroupID"] as? Int,
                    marketGroupID: row["marketGroupID"] as? Int,
                    navigationDestination: AnyView(EmptyView())
                )
            }
            isShowingSearchResults = true
        }
        
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
                        MarketGroupRow(group: group, allGroups: marketGroups, databaseManager: databaseManager)
                    }
                },
                searchQuery: { text in
                    """
                    SELECT t.type_id as id, t.name, t.published, t.icon_filename as iconFileName,
                           t.categoryID, t.groupID, t.metaGroupID, t.marketGroupID,
                           t.pg_need as pgNeed, t.cpu_need as cpuNeed, t.rig_cost as rigCost,
                           t.em_damage as emDamage, t.them_damage as themDamage, t.kin_damage as kinDamage, t.exp_damage as expDamage,
                           t.high_slot as highSlot, t.mid_slot as midSlot, t.low_slot as lowSlot,
                           t.rig_slot as rigSlot, t.gun_slot as gunSlot, t.miss_slot as missSlot,
                           g.name as groupName
                    FROM types t
                    LEFT JOIN groups g ON t.groupID = g.group_id
                    WHERE t.marketGroupID IS NOT NULL AND t.name LIKE ?
                    ORDER BY t.metaGroupID
                    """
                },
                searchParameters: { text in
                    ["%\(text)%"]
                }
            )
            .onAppear {
                marketGroups = MarketManager.shared.loadMarketGroups(databaseManager: databaseManager)
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
                    MarketGroupRow(group: subGroup, allGroups: allGroups, databaseManager: databaseManager)
                }
            },
            searchQuery: { text in
                let groupIDs = MarketManager.shared.getAllSubGroupIDs(allGroups, startingFrom: group.id)
                let groupIDsString = groupIDs.map { String($0) }.joined(separator: ",")
                return """
                    SELECT t.type_id as id, t.name, t.published, t.icon_filename as iconFileName,
                           t.categoryID, t.groupID, t.metaGroupID, t.marketGroupID,
                           t.pg_need as pgNeed, t.cpu_need as cpuNeed, t.rig_cost as rigCost,
                           t.em_damage as emDamage, t.them_damage as themDamage, t.kin_damage as kinDamage, t.exp_damage as expDamage,
                           t.high_slot as highSlot, t.mid_slot as midSlot, t.low_slot as lowSlot,
                           t.rig_slot as rigSlot, t.gun_slot as gunSlot, t.miss_slot as missSlot,
                           g.name as groupName
                    FROM types t
                    LEFT JOIN groups g ON t.groupID = g.group_id
                    WHERE t.marketGroupID IN (\(groupIDsString)) AND t.name LIKE ?
                    ORDER BY t.metaGroupID
                    """
            },
            searchParameters: { text in
                ["%\(text)%"]
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
                let name = metaGroupNames[techLevel] ?? NSLocalizedString("Main_Database_base", comment: "基础物品")
                result.append((id: techLevel, name: name, items: items))
            }
        }
        
        // 添加未分组的物品
        if let ungroupedItems = techLevelGroups[nil], !ungroupedItems.isEmpty {
            result.append((id: -2, name: NSLocalizedString("Main_Database_ungrouped", comment: "未分组"), items: ungroupedItems))
        }
        
        // 添加未发布物品组
        if !unpublishedItems.isEmpty {
            result.append((id: -1, name: NSLocalizedString("Main_Database_unpublished", comment: "未发布"), items: unpublishedItems))
        }
        
        return result
    }
    
    var body: some View {
        MarketBaseView(
            databaseManager: databaseManager,
            title: title,
            content: {
                ForEach(groupedItems, id: \.id) { group in
                    Section(header: Text(group.name)
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
            searchQuery: { text in
                """
                SELECT t.type_id as id, t.name, t.published, t.icon_filename as iconFileName,
                       t.categoryID, t.groupID, t.metaGroupID,
                       t.pg_need as pgNeed, t.cpu_need as cpuNeed, t.rig_cost as rigCost,
                       t.em_damage as emDamage, t.them_damage as themDamage, t.kin_damage as kinDamage, t.exp_damage as expDamage,
                       t.high_slot as highSlot, t.mid_slot as midSlot, t.low_slot as lowSlot,
                       t.rig_slot as rigSlot, t.gun_slot as gunSlot, t.miss_slot as missSlot,
                       g.name as groupName
                FROM types t
                LEFT JOIN groups g ON t.groupID = g.group_id
                WHERE t.marketGroupID = ? AND t.name LIKE ?
                ORDER BY t.metaGroupID
                """
            },
            searchParameters: { text in
                [marketGroupID, "%\(text)%"]
            }
        )
        .onAppear {
            loadItems()
        }
    }
    
    private func loadItems() {
        let query = """
            SELECT t.type_id as id, t.name, t.published, t.icon_filename as iconFileName,
                   t.categoryID, t.groupID, t.metaGroupID,
                   t.pg_need as pgNeed, t.cpu_need as cpuNeed, t.rig_cost as rigCost,
                   t.em_damage as emDamage, t.them_damage as themDamage, t.kin_damage as kinDamage, t.exp_damage as expDamage,
                   t.high_slot as highSlot, t.mid_slot as midSlot, t.low_slot as lowSlot,
                   t.rig_slot as rigSlot, t.gun_slot as gunSlot, t.miss_slot as missSlot,
                   g.name as groupName
            FROM types t
            LEFT JOIN groups g ON t.groupID = g.group_id
            WHERE t.marketGroupID = ?
            ORDER BY t.metaGroupID
        """
        
        if case .success(let rows) = databaseManager.executeQuery(query, parameters: [marketGroupID]) {
            items = rows.compactMap { row in
                guard let id = row["id"] as? Int,
                      let name = row["name"] as? String,
                      let iconFileName = row["iconFileName"] as? String,
                      let published = row["published"] as? Int
                else { return nil }
                
                return DatabaseListItem(
                    id: id,
                    name: name,
                    iconFileName: iconFileName,
                    published: published == 1,
                    categoryID: row["categoryID"] as? Int,
                    groupID: row["groupID"] as? Int,
                    groupName: row["groupName"] as? String,
                    pgNeed: row["pgNeed"] as? Int,
                    cpuNeed: row["cpuNeed"] as? Int,
                    rigCost: row["rigCost"] as? Int,
                    emDamage: row["emDamage"] as? Double,
                    themDamage: row["themDamage"] as? Double,
                    kinDamage: row["kinDamage"] as? Double,
                    expDamage: row["expDamage"] as? Double,
                    highSlot: row["highSlot"] as? Int,
                    midSlot: row["midSlot"] as? Int,
                    lowSlot: row["lowSlot"] as? Int,
                    rigSlot: row["rigSlot"] as? Int,
                    gunSlot: row["gunSlot"] as? Int,
                    missSlot: row["missSlot"] as? Int,
                    metaGroupID: row["metaGroupID"] as? Int,
                    marketGroupID: marketGroupID,
                    navigationDestination: AnyView(EmptyView())
                )
            }
            
            // 加载科技等级名称
            let metaGroupIDs = Set(items.compactMap { $0.metaGroupID })
            metaGroupNames = databaseManager.loadMetaGroupNames(for: Array(metaGroupIDs))
        }
    }
}

// 保持原有的MarketGroupRow和MarketGroupLabel不变
// ... existing code ...

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

#Preview {
    MarketBrowserView(databaseManager: DatabaseManager())
} 
