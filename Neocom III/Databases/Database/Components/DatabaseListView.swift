import SwiftUI
import Combine

// 通用的数据项模型
struct DatabaseListItem: Identifiable {
    let id: Int
    let name: String
    let iconFileName: String
    let published: Bool
    let categoryID: Int?
    let pgNeed: Int?
    let cpuNeed: Int?
    let rigCost: Int?
    let emDamage: Double?
    let themDamage: Double?
    let kinDamage: Double?
    let expDamage: Double?
    let highSlot: Int?
    let midSlot: Int?
    let lowSlot: Int?
    let rigSlot: Int?
    let gunSlot: Int?
    let missSlot: Int?
    let metaGroupID: Int?
    let navigationDestination: AnyView
}

// 分组类型
enum GroupingType {
    case publishedOnly    // Categories 和 Groups 用：只分已发布和未发布
    case metaGroups      // Items 用：按 metaGroup 分组，外加未发布组
}

// 统一的列表视图
struct DatabaseListView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @Environment(\.dismiss) private var dismiss
    
    let title: String
    let groupingType: GroupingType
    let loadData: (DatabaseManager) -> ([DatabaseListItem], [Int: String])
    let searchData: ((DatabaseManager, String) -> ([DatabaseListItem], [Int: String]))?
    
    @State private var items: [DatabaseListItem] = []
    @State private var metaGroupNames: [Int: String] = [:]
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var lastSearchResults: ([DatabaseListItem], [Int: String])? = nil
    @State private var isShowingSearchResults = false  // 添加标志来表示是否正在显示搜索结果
    
    // Combine 用于处理搜索
    @StateObject private var searchController = SearchController()
    
    var body: some View {
        List {
            // 已发布的物品
            let publishedItems = items.filter { $0.published }
            if !publishedItems.isEmpty {
                ForEach(groupedPublishedItems, id: \.id) { group in
                    Section(header: Text(group.name)
                        .fontWeight(.bold)
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                        .textCase(.none)
                    ) {
                        ForEach(group.items) { item in
                            NavigationLink(destination: item.navigationDestination) {
                                DatabaseListItemView(
                                    item: item,
                                    showDetails: groupingType == .metaGroups || isShowingSearchResults
                                )
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    }
                }
            }
            
            // 未发布的物品
            let unpublishedItems = items.filter { !$0.published }
            if !unpublishedItems.isEmpty {
                Section(header: Text(NSLocalizedString("Main_Database_unpublished", comment: "未发布"))
                    .fontWeight(.bold)
                    .font(.system(size: 18))
                    .foregroundColor(.primary)
                    .textCase(.none)
                ) {
                    ForEach(unpublishedItems) { item in
                        NavigationLink(destination: item.navigationDestination) {
                            DatabaseListItemView(
                                item: item,
                                showDetails: groupingType == .metaGroups || isShowingSearchResults
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
            placement: .navigationBarDrawer,
            prompt: Text(NSLocalizedString("Main_Database_Search", comment: ""))
        )
        .onChange(of: searchText) { _, newValue in
            searchController.processSearchInput(newValue)
        }
        .overlay {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
            } else if items.isEmpty && !searchText.isEmpty {
                ContentUnavailableView {
                    Label("未找到", systemImage: "magnifyingglass")
                } description: {
                    Text("没有找到匹配的项目")
                }
            }
        }
        .navigationTitle(title)
        .onAppear {
            // 如果有上次的搜索结果，直接使用
            if let lastResults = lastSearchResults {
                items = lastResults.0
                metaGroupNames = lastResults.1
            } else {
                loadInitialData()
            }
            setupSearch()
        }
    }
    
    private func loadInitialData() {
        let (loadedItems, loadedMetaGroupNames) = loadData(databaseManager)
        items = loadedItems
        metaGroupNames = loadedMetaGroupNames
        isShowingSearchResults = false  // 重置搜索结果标志
    }
    
    private func setupSearch() {
        searchController.debouncedSearchPublisher
            .receive(on: DispatchQueue.main)
            .sink { query in
                if query.isEmpty {
                    loadInitialData()
                    isLoading = false
                } else {
                    performSearch(with: query)
                }
            }
            .store(in: &searchController.cancellables)
    }
    
    private func performSearch(with text: String) {
        guard let searchData = searchData else { return }
        
        isLoading = true
        let (searchResults, searchMetaGroupNames) = searchData(databaseManager, text)
        items = searchResults
        
        // 更新 metaGroupNames
        if searchMetaGroupNames.isEmpty {
            let metaGroupIDs = Set(searchResults.compactMap { $0.metaGroupID })
            metaGroupNames = databaseManager.loadMetaGroupNames(for: Array(metaGroupIDs))
        } else {
            metaGroupNames = searchMetaGroupNames
        }
        
        // 保存搜索结果
        lastSearchResults = (searchResults, metaGroupNames)
        isShowingSearchResults = true  // 搜索结果标志
        
        isLoading = false
    }
    
    // 已发布物品的分组
    private var groupedPublishedItems: [(id: Int, name: String, items: [DatabaseListItem])] {
        let publishedItems = items.filter { $0.published }
        
        // 使用 isShowingSearchResults 而不是 searchText.isEmpty
        if isShowingSearchResults || groupingType == .metaGroups {
            return groupItemsByMetaGroup(publishedItems)
        } else {
            return [(id: 0, name: NSLocalizedString("Main_Database_published", comment: ""), items: publishedItems)]
        }
    }
    
    private func groupItemsByMetaGroup(_ items: [DatabaseListItem]) -> [(id: Int, name: String, items: [DatabaseListItem])] {
        var grouped: [Int: [DatabaseListItem]] = [:]
        
        for item in items {
            let metaGroupID = item.metaGroupID ?? 0
            if grouped[metaGroupID] == nil {
                grouped[metaGroupID] = []
            }
            grouped[metaGroupID]?.append(item)
        }
        
        return grouped.sorted { $0.key < $1.key }
            .map { (metaGroupID, items) in
                if metaGroupID == 0 {
                    return (id: 0, name: NSLocalizedString("Main_Database_base", comment: "基础物品"), items: items)
                }
                
                if let groupName = metaGroupNames[metaGroupID] {
                    return (id: metaGroupID, name: groupName, items: items)
                } else {
                    print("警告: MetaGroupID \(metaGroupID) 没有对应的名称")
                    return (id: metaGroupID, name: "MetaGroup \(metaGroupID)", items: items)
                }
            }
            .filter { !$0.items.isEmpty }
    }
}

// 搜索控制器
class SearchController: ObservableObject {
    private let searchSubject = PassthroughSubject<String, Never>()
    private let debounceInterval: TimeInterval = 0.5
    var cancellables = Set<AnyCancellable>()
    
    // 防抖处理后的搜索
    var debouncedSearchPublisher: AnyPublisher<String, Never> {
        searchSubject
            .debounce(for: .seconds(debounceInterval), scheduler: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
    
    func processSearchInput(_ query: String) {
        searchSubject.send(query)
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
                IconManager.shared.loadImage(for: item.iconFileName)
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
                                IconWithValueView(iconName: "icon_1539_64.png", value: pgNeed)
                            }
                            if let cpuNeed = item.cpuNeed {
                                IconWithValueView(iconName: "icon_3887_64.png", value: cpuNeed)
                            }
                            if let rigCost = item.rigCost {
                                IconWithValueView(iconName: "icon_41312_64.png", value: rigCost)
                            }
                        }
                    }
                    // 弹药和无人机
                    else if categoryID == 18 || categoryID == 8 {
                        if hasAnyDamage {  // 添加检查是否有任何伤害值
                            HStack(spacing: 8) {  // 增加整体的间距
                                // 电磁伤害
                                HStack(spacing: 4) {  // 增加图标和条之间的间距
                                    IconManager.shared.loadImage(for: "items_22_32_20.png")
                                        .resizable()
                                        .frame(width: 18, height: 18)
                                    DamageBarView(
                                        percentage: calculateDamagePercentage(item.emDamage ?? 0),
                                        color: Color(red: 74/255, green: 128/255, blue: 192/255)
                                    )
                                }
                                
                                // 热能伤害
                                HStack(spacing: 4) {  // 增加图标和条之间的间距
                                    IconManager.shared.loadImage(for: "items_22_32_18.png")
                                        .resizable()
                                        .frame(width: 18, height: 18)
                                    DamageBarView(
                                        percentage: calculateDamagePercentage(item.themDamage ?? 0),
                                        color: Color(red: 176/255, green: 53/255, blue: 50/255)
                                    )
                                }
                                
                                // 动能伤害
                                HStack(spacing: 4) {  // 增加图标和条之间的间距
                                    IconManager.shared.loadImage(for: "items_22_32_17.png")
                                        .resizable()
                                        .frame(width: 18, height: 18)
                                    DamageBarView(
                                        percentage: calculateDamagePercentage(item.kinDamage ?? 0),
                                        color: Color(red: 155/255, green: 155/255, blue: 155/255)
                                    )
                                }
                                
                                // 爆炸伤害
                                HStack(spacing: 4) {  // 增加图标和条之间的间距
                                    IconManager.shared.loadImage(for: "items_22_32_19.png")
                                        .resizable()
                                        .frame(width: 18, height: 18)
                                    DamageBarView(
                                        percentage: calculateDamagePercentage(item.expDamage ?? 0),
                                        color: Color(red: 185/255, green: 138/255, blue: 62/255)
                                    )
                                }
                            }
                        }
                    }
                    // 舰船
                    else if categoryID == 6 {
                        HStack(spacing: 4) {  // 减小槽位之间的间距
                            if let highSlot = item.highSlot {
                                IconWithValueView(iconName: "items_8_64_11.png", value: highSlot)
                            }
                            if let midSlot = item.midSlot {
                                IconWithValueView(iconName: "items_8_64_10.png", value: midSlot)
                            }
                            if let lowSlot = item.lowSlot {
                                IconWithValueView(iconName: "items_8_64_19.png", value: lowSlot)
                            }
                            if let rigSlot = item.rigSlot {
                                IconWithValueView(iconName: "items_68_64_1.png", value: rigSlot)
                            }
                            if let gunSlot = item.gunSlot {
                                IconWithValueView(iconName: "icon_484_64.png", value: gunSlot)
                            }
                            if let missSlot = item.missSlot {
                                IconWithValueView(iconName: "icon_44102_64.png", value: missSlot)
                            }
                        }
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
    }
    
    private var hasAnyDamage: Bool {
        // 只要有任何一个伤害属性不为 nil，就显示伤害条
        // 注意：0 也是有效值，不应该被排除
        return [item.emDamage, item.themDamage, item.kinDamage, item.expDamage]
            .contains { $0 != nil }
    }
    
    private func calculateDamagePercentage(_ damage: Double) -> Int {
        let damages = [
            item.emDamage,
            item.themDamage,
            item.kinDamage,
            item.expDamage
        ].compactMap { $0 }
        
        let totalDamage = damages.reduce(0, +)
        guard totalDamage > 0 else { return 0 }
        
        // 直接计算百分比并四舍五入
        return Int(round((damage / totalDamage) * 100))
    }
}

// 图标和数值的组合视图
struct IconWithValueView: View {
    let iconName: String
    let value: Int
    
    var body: some View {
        HStack(spacing: 2) {
            IconManager.shared.loadImage(for: iconName)
                .resizable()
                .frame(width: 18, height: 18)
            Text("\(value)")
        }
    }
}
