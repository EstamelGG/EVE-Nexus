import SwiftUI

struct MarketBrowserView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var marketGroups: [MarketGroup] = []
    @State private var items: [DatabaseListItem] = []
    @State private var marketGroupNames: [Int: String] = [:]
    @State private var searchText = ""
    @State private var isSearchActive = false
    @State private var isLoading = false
    @State private var isShowingSearchResults = false
    @StateObject private var searchController = SearchController()
    
    var groupedSearchResults: [(id: Int, name: String, items: [DatabaseListItem])] {
        guard !items.isEmpty else { return [] }
        
        // 按市场组分类
        var marketGroupItems: [Int: [DatabaseListItem]] = [:]
        var ungroupedItems: [DatabaseListItem] = []
        
        for item in items {
            if let marketGroupID = item.marketGroupID {
                if marketGroupItems[marketGroupID] == nil {
                    marketGroupItems[marketGroupID] = []
                }
                marketGroupItems[marketGroupID]?.append(item)
            } else {
                ungroupedItems.append(item)
            }
        }
        
        var result: [(id: Int, name: String, items: [DatabaseListItem])] = []
        
        // 添加有市场组的物品
        for (groupID, items) in marketGroupItems.sorted(by: { $0.key < $1.key }) {
            let name = marketGroupNames[groupID] ?? "未知市场组"
            result.append((id: groupID, name: name, items: items))
        }
        
        // 添加未分组的物品
        if !ungroupedItems.isEmpty {
            result.append((id: -1, name: "未分组", items: ungroupedItems))
        }
        
        return result
    }
    
    var body: some View {
        NavigationStack {
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
                    // 常规市场分组视图
                    ForEach(MarketManager.shared.getRootGroups(marketGroups)) { group in
                        MarketGroupRow(group: group, allGroups: marketGroups, databaseManager: databaseManager)
                    }
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
                    isLoading = true  // 立即显示加载状态
                    items = []  // 清空当前显示的物品
                    if newValue.count >= 1 {
                        searchController.processSearchInput(newValue)
                    }
                }
            }
            .overlay {
                if isLoading {
                    Color(.systemBackground)  // 使用系统背景色作为不透明遮罩
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
                    // 添加半透明遮罩
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()
                        .onTapGesture {
                            isSearchActive = false
                        }
                }
            }
            .navigationTitle(NSLocalizedString("Main_Market", comment: ""))
            .onAppear {
                marketGroups = MarketManager.shared.loadMarketGroups(databaseManager: databaseManager)
                setupSearch()
            }
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
        
        // 搜索所有市场物品（marketGroupID不为0的物品）
        let query = """
            SELECT t.type_id as id, t.name, t.published, t.icon_filename as iconFileName,
                   t.categoryID, t.groupID, t.metaGroupID, t.marketGroupID,
                   t.pg_need as pgNeed, t.cpu_need as cpuNeed, t.rig_cost as rigCost,
                   t.em_damage as emDamage, t.them_damage as themDamage, t.kin_damage as kinDamage, t.exp_damage as expDamage,
                   t.high_slot as highSlot, t.mid_slot as midSlot, t.low_slot as lowSlot,
                   t.rig_slot as rigSlot, t.gun_slot as gunSlot, t.miss_slot as missSlot,
                   m.name as marketGroupName
            FROM types t
            LEFT JOIN marketGroups m ON t.marketGroupID = m.group_id
            WHERE t.marketGroupID IS NOT NULL AND t.name LIKE ?
            ORDER BY t.name
        """
        
        let searchPattern = "%\(text)%"
        if case .success(let rows) = databaseManager.executeQuery(query, parameters: [searchPattern as Any]) {
            items = rows.compactMap { row in
                guard let id = row["id"] as? Int,
                      let name = row["name"] as? String
                else { return nil }
                
                // 其他字段可以为空
                let iconFileName = (row["iconFileName"] as? String) ?? "items_7_64_15.png"
                let published = (row["published"] as? Int) ?? 0
                let marketGroupID = row["marketGroupID"] as? Int
                
                // 保存市场组名称
                if let marketGroupID = marketGroupID,
                   let marketGroupName = row["marketGroupName"] as? String {
                    marketGroupNames[marketGroupID] = marketGroupName
                }
                
                return DatabaseListItem(
                    id: id,
                    name: name,
                    iconFileName: iconFileName,
                    published: published == 1,
                    categoryID: row["categoryID"] as? Int,
                    groupID: row["groupID"] as? Int,
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
            isShowingSearchResults = true
        }
        
        isLoading = false
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

// 新增：市场分组视图（用于非叶子节点）
struct MarketGroupView: View {
    @ObservedObject var databaseManager: DatabaseManager
    let group: MarketGroup
    let allGroups: [MarketGroup]
    
    @State private var searchText = ""
    @State private var isSearchActive = false
    @State private var isLoading = false
    @State private var isShowingSearchResults = false
    @State private var items: [DatabaseListItem] = []
    @State private var marketGroupNames: [Int: String] = [:]
    @StateObject private var searchController = SearchController()
    
    var groupedSearchResults: [(id: Int, name: String, items: [DatabaseListItem])] {
        guard !items.isEmpty else { return [] }
        
        // 按市场组分类
        var marketGroupItems: [Int: [DatabaseListItem]] = [:]
        var ungroupedItems: [DatabaseListItem] = []
        
        for item in items {
            if let marketGroupID = item.marketGroupID {
                if marketGroupItems[marketGroupID] == nil {
                    marketGroupItems[marketGroupID] = []
                }
                marketGroupItems[marketGroupID]?.append(item)
            } else {
                ungroupedItems.append(item)
            }
        }
        
        var result: [(id: Int, name: String, items: [DatabaseListItem])] = []
        
        // 添加有市场组的物品
        for (groupID, items) in marketGroupItems.sorted(by: { $0.key < $1.key }) {
            let name = marketGroupNames[groupID] ?? "未知市场组"
            result.append((id: groupID, name: name, items: items))
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
                // 常规子分组视图
                ForEach(MarketManager.shared.getSubGroups(allGroups, for: group.id)) { subGroup in
                    MarketGroupRow(group: subGroup, allGroups: allGroups, databaseManager: databaseManager)
                }
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
                isLoading = true  // 立即显示加载状态
                items = []  // 清空当前显示的物品
                if newValue.count >= 1 {
                    searchController.processSearchInput(newValue)
                }
            }
        }
        .overlay {
            if isLoading {
                Color(.systemBackground)  // 使用系统背景色作为不透明遮罩
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
                // 添加半透明遮罩
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .onTapGesture {
                        isSearchActive = false
                    }
            }
        }
        .navigationTitle(group.name)
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
        
        // 获取当前组及其所有子组的ID
        let groupIDs = MarketManager.shared.getAllSubGroupIDs(allGroups, startingFrom: group.id)
        let groupIDsString = groupIDs.map { String($0) }.joined(separator: ",")
        
        // 在当前组及其所有子组中搜索物品
        let query = """
            SELECT t.type_id as id, t.name, t.published, t.icon_filename as iconFileName,
                   t.categoryID, t.groupID, t.metaGroupID, t.marketGroupID,
                   t.pg_need as pgNeed, t.cpu_need as cpuNeed, t.rig_cost as rigCost,
                   t.em_damage as emDamage, t.them_damage as themDamage, t.kin_damage as kinDamage, t.exp_damage as expDamage,
                   t.high_slot as highSlot, t.mid_slot as midSlot, t.low_slot as lowSlot,
                   t.rig_slot as rigSlot, t.gun_slot as gunSlot, t.miss_slot as missSlot,
                   m.name as marketGroupName
            FROM types t
            LEFT JOIN marketGroups m ON t.marketGroupID = m.group_id
            WHERE t.marketGroupID IN (\(groupIDsString)) AND t.name LIKE ?
            ORDER BY t.name
        """
        
        let searchPattern = "%\(text)%"
        if case .success(let rows) = databaseManager.executeQuery(query, parameters: [searchPattern as Any]) {
            items = rows.compactMap { row in
                guard let id = row["id"] as? Int,
                      let name = row["name"] as? String
                else { return nil }
                
                // 其他字段可以为空
                let iconFileName = (row["iconFileName"] as? String) ?? "items_7_64_15.png"
                let published = (row["published"] as? Int) ?? 0
                let marketGroupID = row["marketGroupID"] as? Int
                
                // 保存市场组名称
                if let marketGroupID = marketGroupID,
                   let marketGroupName = row["marketGroupName"] as? String {
                    marketGroupNames[marketGroupID] = marketGroupName
                }
                
                return DatabaseListItem(
                    id: id,
                    name: name,
                    iconFileName: iconFileName,
                    published: published == 1,
                    categoryID: row["categoryID"] as? Int,
                    groupID: row["groupID"] as? Int,
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
            isShowingSearchResults = true
        }
        
        isLoading = false
    }
}

struct MarketItemListView: View {
    @ObservedObject var databaseManager: DatabaseManager
    let marketGroupID: Int
    let title: String
    
    @State private var items: [DatabaseListItem] = []
    @State private var metaGroupNames: [Int: String] = [:]
    @State private var searchText = ""
    @State private var isSearchActive = false
    @State private var isLoading = false
    @State private var isShowingSearchResults = false
    @State private var searchResults: [DatabaseListItem] = []
    @StateObject private var searchController = SearchController()
    
    var groupedItems: [(id: Int, name: String, items: [DatabaseListItem])] {
        let itemsToGroup = isShowingSearchResults ? searchResults : items
        let publishedItems = itemsToGroup.filter { $0.published }
        let unpublishedItems = itemsToGroup.filter { !$0.published }
        
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
        // 先添加有metaGroupID的物品组
        for (techLevel, items) in techLevelGroups.sorted(by: { ($0.key ?? -1) < ($1.key ?? -1) }) {
            if let techLevel = techLevel {
                let name = metaGroupNames[techLevel] ?? NSLocalizedString("Main_Database_base", comment: "基础物品")
                result.append((id: techLevel, name: name, items: items))
            }
        }
        
        // 添加未分组（metaGroupID为nil）的物品组
        if let ungroupedItems = techLevelGroups[nil], !ungroupedItems.isEmpty {
            result.append((
                id: -2, // 使用-2作为未分组的ID（因为-1已被未发布物品组使用）
                name: NSLocalizedString("Main_Database_ungrouped", comment: "未分组"),
                items: ungroupedItems
            ))
        }
        
        // 添加未发布物品组
        if !unpublishedItems.isEmpty {
            result.append((
                id: -1,
                name: NSLocalizedString("Main_Database_unpublished", comment: "未发布"),
                items: unpublishedItems
            ))
        }
        
        return result
    }
    
    var body: some View {
        List {
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
        }
        .listStyle(.insetGrouped)
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
                searchResults = []
            } else {
                isLoading = true  // 立即显示加载状态
                searchResults = []  // 清空当前显示的物品
                if newValue.count >= 1 {
                    searchController.processSearchInput(newValue)
                }
            }
        }
        .overlay {
            if isLoading {
                Color(.systemBackground)  // 使用系统背景色作为不透明遮罩
                    .ignoresSafeArea()
                    .overlay {
                        VStack {
                            ProgressView()
                            Text("正在搜索...")
                                .foregroundColor(.secondary)
                                .padding(.top, 8)
                        }
                    }
            } else if searchResults.isEmpty && !searchText.isEmpty {
                ContentUnavailableView {
                    Label("未找到", systemImage: "magnifyingglass")
                } description: {
                    Text("没有找到匹配的项目")
                }
            } else if searchText.isEmpty && isSearchActive {
                // 添加半透明遮罩
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .onTapGesture {
                        isSearchActive = false
                    }
            }
        }
        .navigationTitle(title)
        .onAppear {
            loadItems()
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
        
        // 在当前市场组内搜索
        let query = """
            SELECT type_id as id, name, published, icon_filename as iconFileName,
                   categoryID, groupID, metaGroupID,
                   pg_need as pgNeed, cpu_need as cpuNeed, rig_cost as rigCost,
                   em_damage as emDamage, them_damage as themDamage, kin_damage as kinDamage, exp_damage as expDamage,
                   high_slot as highSlot, mid_slot as midSlot, low_slot as lowSlot,
                   rig_slot as rigSlot, gun_slot as gunSlot, miss_slot as missSlot
            FROM types
            WHERE marketGroupID = ? AND name LIKE ?
            ORDER BY name
        """
        
        let searchPattern = "%\(text)%"
        if case .success(let rows) = databaseManager.executeQuery(query, parameters: [marketGroupID, searchPattern]) {
            searchResults = rows.compactMap { row in
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
            isShowingSearchResults = true
        }
        
        isLoading = false
    }
    
    private func loadItems() {
        // 加载该市场组下的所有物品
        let query = """
            SELECT type_id as id, name, published, icon_filename as iconFileName,
                   categoryID, groupID, metaGroupID,
                   pg_need as pgNeed, cpu_need as cpuNeed, rig_cost as rigCost,
                   em_damage as emDamage, them_damage as themDamage, kin_damage as kinDamage, exp_damage as expDamage,
                   high_slot as highSlot, mid_slot as midSlot, low_slot as lowSlot,
                   rig_slot as rigSlot, gun_slot as gunSlot, miss_slot as missSlot
            FROM types
            WHERE marketGroupID = ?
            ORDER BY name
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
