import SwiftUI
import Foundation

// 市场关注列表项目
struct MarketQuickbar: Identifiable, Codable {
    let id: UUID
    var name: String
    var items: [QuickbarItem]  // 存储物品的 typeID 和数量
    var lastUpdated: Date
    
    init(id: UUID = UUID(), name: String, items: [QuickbarItem] = []) {
        self.id = id
        self.name = name
        self.items = items
        self.lastUpdated = Date()
    }
}

struct QuickbarItem: Codable, Equatable {
    let typeID: Int
    var quantity: Int
    
    init(typeID: Int, quantity: Int = 1) {
        self.typeID = typeID
        self.quantity = quantity
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
            try FileManager.default.createDirectory(at: quickbarDirectory, withIntermediateDirectories: true)
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
            let files = try fileManager.contentsOfDirectory(at: quickbarDirectory, includingPropertiesForKeys: nil)
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
            .sorted { $0.lastUpdated > $1.lastUpdated }
            
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
            result.append((id: -1, name: "No group", items: ungroupedItems))
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
                                        showDetails: false
                                    )
                                    
                                    Spacer()
                                    
                                    Image(systemName: existingItems.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(existingItems.contains(item.id) ? .accentColor : .secondary)
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
                    Label("Not found", systemImage: "magnifyingglass")
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
                Button(NSLocalizedString("Main_EVE_Mail_Done", comment: "")) {
                    onDismiss()
                }
            }
        }
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
        
        let whereClause = searchQuery(text)
        let parameters = searchParameters(text)
        
        items = databaseManager.loadMarketItems(whereClause: whereClause, parameters: parameters)
        isShowingSearchResults = true
        
        isLoading = false
    }
}

// 市场物品选择器视图
struct MarketItemSelectorView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var marketGroups: [MarketGroup] = []
    let existingItems: Set<Int>
    let onItemSelected: (DatabaseListItem) -> Void
    let onItemDeselected: (DatabaseListItem) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            MarketItemSelectorBaseView(
                databaseManager: databaseManager,
                title: NSLocalizedString("Main_Market_Watch_List_Add_Item", comment: ""),
                content: {
                    ForEach(MarketManager.shared.getRootGroups(marketGroups)) { group in
                        MarketItemSelectorGroupRow(
                            group: group,
                            allGroups: marketGroups,
                            databaseManager: databaseManager,
                            existingItems: existingItems,
                            onItemSelected: onItemSelected,
                            onItemDeselected: onItemDeselected,
                            onDismiss: { dismiss() }
                        )
                    }
                },
                searchQuery: { _ in
                    "t.marketGroupID IS NOT NULL AND (t.name LIKE ? OR t.en_name LIKE ? OR t.type_id = ?)"
                },
                searchParameters: { text in
                    ["%\(text)%", "%\(text)%", "\(text)"]
                },
                existingItems: existingItems,
                onItemSelected: onItemSelected,
                onItemDeselected: onItemDeselected,
                onDismiss: { dismiss() }
            )
            .onAppear {
                marketGroups = MarketManager.shared.loadMarketGroups(databaseManager: databaseManager)
            }
            .interactiveDismissDisabled()
        }
    }
}

// 市场物品选择器组视图
struct MarketItemSelectorGroupView: View {
    @ObservedObject var databaseManager: DatabaseManager
    let group: MarketGroup
    let allGroups: [MarketGroup]
    let existingItems: Set<Int>
    let onItemSelected: (DatabaseListItem) -> Void
    let onItemDeselected: (DatabaseListItem) -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        MarketItemSelectorBaseView(
            databaseManager: databaseManager,
            title: group.name,
            content: {
                ForEach(MarketManager.shared.getSubGroups(allGroups, for: group.id)) { subGroup in
                    MarketItemSelectorGroupRow(
                        group: subGroup,
                        allGroups: allGroups,
                        databaseManager: databaseManager,
                        existingItems: existingItems,
                        onItemSelected: onItemSelected,
                        onItemDeselected: onItemDeselected,
                        onDismiss: onDismiss
                    )
                }
            },
            searchQuery: { _ in
                let groupIDs = MarketManager.shared.getAllSubGroupIDs(allGroups, startingFrom: group.id)
                let groupIDsString = groupIDs.map { String($0) }.joined(separator: ",")
                return "t.marketGroupID IN (\(groupIDsString)) AND (t.name LIKE ? OR t.en_name LIKE ?)"
            },
            searchParameters: { text in
                ["%\(text)%", "%\(text)%"]
            },
            existingItems: existingItems,
            onItemSelected: onItemSelected,
            onItemDeselected: onItemDeselected,
            onDismiss: onDismiss
        )
    }
}

// 市场物品选择器组行视图
struct MarketItemSelectorGroupRow: View {
    let group: MarketGroup
    let allGroups: [MarketGroup]
    let databaseManager: DatabaseManager
    let existingItems: Set<Int>
    let onItemSelected: (DatabaseListItem) -> Void
    let onItemDeselected: (DatabaseListItem) -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        if MarketManager.shared.isLeafGroup(group, in: allGroups) {
            // 最后一级目录，显示物品列表
            NavigationLink {
                MarketItemSelectorItemListView(
                    databaseManager: databaseManager,
                    marketGroupID: group.id,
                    title: group.name,
                    existingItems: existingItems,
                    onItemSelected: onItemSelected,
                    onItemDeselected: onItemDeselected,
                    onDismiss: onDismiss
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
                    existingItems: existingItems,
                    onItemSelected: onItemSelected,
                    onItemDeselected: onItemDeselected,
                    onDismiss: onDismiss
                )
            } label: {
                MarketGroupLabel(group: group)
            }
        }
    }
}

// 市场物品选择器物品列表视图
struct MarketItemSelectorItemListView: View {
    @ObservedObject var databaseManager: DatabaseManager
    let marketGroupID: Int
    let title: String
    let existingItems: Set<Int>
    let onItemSelected: (DatabaseListItem) -> Void
    let onItemDeselected: (DatabaseListItem) -> Void
    let onDismiss: () -> Void
    
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
        MarketItemSelectorBaseView(
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
                                        showDetails: false
                                    )
                                    
                                    Spacer()
                                    
                                    Image(systemName: existingItems.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(existingItems.contains(item.id) ? .accentColor : .secondary)
                                }
                            }
                            .foregroundColor(existingItems.contains(item.id) ? .primary : .primary)
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
            },
            existingItems: existingItems,
            onItemSelected: onItemSelected,
            onItemDeselected: onItemDeselected,
            onDismiss: onDismiss
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
                } else {
                    Text(String(format: NSLocalizedString("Main_EVE_Mail_No_Results", comment: "")))
                        .foregroundColor(.secondary)
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
                }
                .onDelete(perform: deleteQuickbar)
            }
        }
        .navigationTitle(NSLocalizedString("Main_Market_Watch_List", comment: ""))
        .searchable(text: $searchText,
                   placement: .navigationBarDrawer(displayMode: .always),
                   prompt: NSLocalizedString("Main_Database_Search", comment: ""))
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
        .alert(NSLocalizedString("Main_Market_Watch_List_Add", comment: ""), isPresented: $isShowingAddAlert) {
            TextField(NSLocalizedString("Main_Market_Watch_List_Name", comment: ""), text: $newQuickbarName)
            
            Button(NSLocalizedString("Main_EVE_Mail_Done", comment: "")) {
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
        } message: {
            Text(NSLocalizedString("Main_Market_Watch_List_Name", comment: ""))
        }
        .task {
            quickbars = MarketQuickbarManager.shared.loadQuickbars()
        }
    }
    
    private func quickbarRowView(_ quickbar: MarketQuickbar) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(quickbar.name)
                .font(.headline)
                .lineLimit(1)
            
            Text(formatDate(quickbar.lastUpdated))
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(String(format: NSLocalizedString("Main_Market_Watch_List_Items", comment: ""), quickbar.items.count))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    private func formatDate(_ date: Date) -> String {
        let now = Date()
        let components = Calendar.current.dateComponents([.minute, .hour, .day], from: date, to: now)
        
        if let days = components.day {
            if days > 30 {
                let formatter = DateFormatter()
                formatter.dateFormat = NSLocalizedString("Date_Format_Month_Day", comment: "")
                return formatter.string(from: date)
            } else if days > 0 {
                return String(format: NSLocalizedString("Time_Days_Ago", comment: ""), days)
            }
        }
        
        if let hours = components.hour, hours > 0 {
            return String(format: NSLocalizedString("Time_Hours_Ago", comment: ""), hours)
        } else if let minutes = components.minute, minutes > 0 {
            return String(format: NSLocalizedString("Time_Minutes_Ago", comment: ""), minutes)
        } else {
            return NSLocalizedString("Time_Just_Now", comment: "")
        }
    }
    
    private func deleteQuickbar(at offsets: IndexSet) {
        let quickbarsToDelete = offsets.map { filteredQuickbars[$0] }
        quickbarsToDelete.forEach { quickbar in
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
    @State private var itemQuantities: [Int: Int] = [:]  // typeID: quantity
    
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
                    ForEach(sortedItems, id: \.id) { item in
                        itemRow(item)
                    }
                    .onDelete { indexSet in
                        let itemsToDelete = indexSet.map { sortedItems[$0].id }
                        quickbar.items.removeAll { itemsToDelete.contains($0.typeID) }
                        items.removeAll { itemsToDelete.contains($0.id) }
                        MarketQuickbarManager.shared.saveQuickbar(quickbar)
                    }
                } header: {
                    HStack {
                        Text("物品列表")
                        Spacer()
                        Button(isEditingQuantity ? "完成" : "编辑数量") {
                            withAnimation {
                                isEditingQuantity.toggle()
                            }
                        }
                        .foregroundColor(.accentColor)
                    }
                }
            }
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
                                quantity: quickbar.items.first(where: { $0.typeID == item.id })?.quantity ?? 1
                            )
                        }
                        MarketQuickbarManager.shared.saveQuickbar(quickbar)
                    }
                },
                onItemDeselected: { item in
                    if let index = items.firstIndex(where: { $0.id == item.id }) {
                        items.remove(at: index)
                        quickbar.items.removeAll { $0.typeID == item.id }
                        MarketQuickbarManager.shared.saveQuickbar(quickbar)
                    }
                }
            )
        }
        .task {
            loadItems()
        }
    }
    
    @ViewBuilder
    private func itemRow(_ item: DatabaseListItem) -> some View {
        if isEditingQuantity {
            HStack {
                DatabaseListItemView(
                    item: item,
                    showDetails: false
                )
                
                Spacer()
                quantityEditor(for: item)
            }
        } else {
            NavigationLink {
                MarketItemDetailView(
                    databaseManager: databaseManager,
                    itemID: item.id
                )
            } label: {
                HStack {
                    DatabaseListItemView(
                        item: item,
                        showDetails: false
                    )
                    
                    Spacer()
                    Text("\(getItemQuantity(for: item))")
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private func quantityEditor(for item: DatabaseListItem) -> some View {
        let quantity = Binding(
            get: { itemQuantities[item.id] ?? 1 },
            set: { newValue in
                let validValue = max(1, newValue)
                itemQuantities[item.id] = validValue
                if let index = quickbar.items.firstIndex(where: { $0.typeID == item.id }) {
                    quickbar.items[index].quantity = validValue
                    MarketQuickbarManager.shared.saveQuickbar(quickbar)
                }
            }
        )
        
        return TextField("", value: quantity, formatter: NumberFormatter())
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 60)
    }
    
    private func getItemQuantity(for item: DatabaseListItem) -> Int {
        quickbar.items.first(where: { $0.typeID == item.id })?.quantity ?? 1
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
            itemQuantities = Dictionary(uniqueKeysWithValues: quickbar.items.map { ($0.typeID, $0.quantity) })
            // 确保 quickbar.items 的顺序与加载的物品顺序一致
            quickbar.items = sorted.map { item in
                QuickbarItem(typeID: item.id, quantity: quickbar.items.first(where: { $0.typeID == item.id })?.quantity ?? 1)
            }
            MarketQuickbarManager.shared.saveQuickbar(quickbar)
        }
    }
} 
