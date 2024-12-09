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
    @State private var isShowingSearchResults = false
    @State private var isSearchActive = false  // 新增：控制搜索框激活状态
    
    // Combine 用于处理搜索
    @StateObject private var searchController = SearchController()
    
    // 新增：提取已发布物品的视图
    private var publishedItemsView: some View {
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
    
    // 新增：提取未发布物品的视图
    private var unpublishedItemsView: some View {
        Section(header: Text(NSLocalizedString("Main_Database_unpublished", comment: "未发布"))
            .fontWeight(.bold)
            .font(.system(size: 18))
            .foregroundColor(.primary)
            .textCase(.none)
        ) {
            ForEach(items.filter { !$0.published }) { item in
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
    
    // 新增：提取加载状态的视图
    @ViewBuilder
    private var loadingOverlay: some View {
        if isLoading || (!searchText.isEmpty && !isShowingSearchResults) {
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
            // 添加一个可点击的半透明遮罩
            Color.black.opacity(0.2)
                .ignoresSafeArea()
                .onTapGesture {
                    isSearchActive = false
                }
        }
    }
    
    var body: some View {
        List {
            // 已发布的物品
            let publishedItems = items.filter { $0.published }
            if !publishedItems.isEmpty {
                publishedItemsView
            }
            
            // 未发布的物品
            let unpublishedItems = items.filter { !$0.published }
            if !unpublishedItems.isEmpty {
                unpublishedItemsView
            }
        }
        .listStyle(.insetGrouped)
        .searchable(
            text: $searchText,
            isPresented: $isSearchActive,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text(NSLocalizedString("Main_Database_Search", comment: ""))
        )
        .refreshable {
            isSearchActive = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isSearchActive = true
            }
        }
        .gesture(
            DragGesture()
                .onEnded { gesture in
                    // 检测右划动作（x轴位移为正）
                    if gesture.translation.width > 50 && isShowingSearchResults {
                        searchText = ""
                        isSearchActive = false
                        loadInitialData()
                    }
                }
        )
        .navigationBarBackButtonHidden(isShowingSearchResults)
        .toolbar {
            if isShowingSearchResults {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        searchText = ""
                        isSearchActive = false
                        loadInitialData()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("返回")
                        }
                    }
                }
            }
        }
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty {
                loadInitialData()
                isLoading = false
                lastSearchResults = nil
            } else {
                if newValue.count >= 1 {
                    searchController.processSearchInput(newValue)
                }
            }
        }
        .overlay(loadingOverlay)
        .navigationTitle(title)
        .onAppear {
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
        lastSearchResults = nil  // 清除搜索结果缓存
    }
    
    private func setupSearch() {
        searchController.debouncedSearchPublisher
            .receive(on: DispatchQueue.main)
            .sink { query in
                // 如果当前搜索文本为空，不执行搜索
                guard !searchText.isEmpty else { return }
                performSearch(with: query)
            }
            .store(in: &searchController.cancellables)
    }
    
    private func performSearch(with text: String) {
        guard let searchData = searchData else { return }
        
        isLoading = true  // 开始搜索，显示加载状态
        
        // 在主线程中执行搜索
        DispatchQueue.main.async {
            let (searchResults, searchMetaGroupNames) = searchData(databaseManager, text)
            
            // 更新 UI
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
            
            isLoading = false  // 搜索完成，隐藏加载状态
        }
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
            .map { text -> String? in
                // 如果文本为空，立即返回 nil
                text.isEmpty ? nil : text
            }
            .debounce(for: .seconds(debounceInterval), scheduler: DispatchQueue.main)
            // 过滤掉 nil 值（空文本）
            .compactMap { $0 }
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
                Image(uiImage: IconManager.shared.loadUIImage(for: item.iconFileName))
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)
                    .frame(width: 32, height: 32)
                Text(item.name)
            }
            
            if showDetails, let categoryID = item.categoryID {
                VStack(alignment: .leading, spacing: 2) {
                    // 装备、建筑装备和改装件
                    if categoryID == 7 || categoryID == 66 {
                        HStack(spacing: 8) {
                            if let pgNeed = item.pgNeed {
                                IconWithValueView(iconName: "icon_1539_64.png", numericValue: pgNeed, unit: " MW")
                            }
                            if let cpuNeed = item.cpuNeed {
                                IconWithValueView(iconName: "icon_3887_64.png", numericValue: cpuNeed, unit: " Tf")
                            }
                            if let rigCost = item.rigCost {
                                IconWithValueView(iconName: "icon_41312_64.png", numericValue: rigCost)
                            }
                        }
                    }
                    // 弹药和无人机
                    else if categoryID == 18 || categoryID == 8 {
                        if hasAnyDamage {  // 添加检查是否有任何伤害值
                            HStack(spacing: 8) {  // 增加整体的间距
                                // 电磁伤害
                                HStack(spacing: 4) {  // 增加图标和条之间的间距
                                    IconManager.shared.loadImage(for: "items_22_32_12.png")
                                        .resizable()
                                        .frame(width: 18, height: 18)
                                    DamageBarView(
                                        percentage: calculateDamagePercentage(item.emDamage ?? 0),
                                        color: Color(red: 74/255, green: 128/255, blue: 192/255)
                                    )
                                }
                                
                                // 热能伤害
                                HStack(spacing: 4) {  // 增加图标和条之间的间距
                                    IconManager.shared.loadImage(for: "items_22_32_10.png")
                                        .resizable()
                                        .frame(width: 18, height: 18)
                                    DamageBarView(
                                        percentage: calculateDamagePercentage(item.themDamage ?? 0),
                                        color: Color(red: 176/255, green: 53/255, blue: 50/255)
                                    )
                                }
                                
                                // 动能伤害
                                HStack(spacing: 4) {  // 增加图标和条之间的间距
                                    IconManager.shared.loadImage(for: "items_22_32_9.png")
                                        .resizable()
                                        .frame(width: 18, height: 18)
                                    DamageBarView(
                                        percentage: calculateDamagePercentage(item.kinDamage ?? 0),
                                        color: Color(red: 155/255, green: 155/255, blue: 155/255)
                                    )
                                }
                                
                                // 爆炸伤害
                                HStack(spacing: 4) {  // 增加图标和条之间的间距
                                    IconManager.shared.loadImage(for: "items_22_32_11.png")
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
                        HStack(spacing: 8) {  // 减小槽位之间的间距
                            if let highSlot = item.highSlot, highSlot != 0 {
                                IconWithValueView(iconName: "items_8_64_11.png", numericValue: highSlot)
                            }
                            if let midSlot = item.midSlot, midSlot != 0 {
                                IconWithValueView(iconName: "items_8_64_10.png", numericValue: midSlot)
                            }
                            if let lowSlot = item.lowSlot, lowSlot != 0 {
                                IconWithValueView(iconName: "items_8_64_9.png", numericValue: lowSlot)
                            }
                            if let rigSlot = item.rigSlot, rigSlot != 0 {
                                IconWithValueView(iconName: "items_68_64_1.png", numericValue: rigSlot)
                            }
                            if let gunSlot = item.gunSlot, gunSlot != 0 {
                                IconWithValueView(iconName: "icon_484_64.png", numericValue: gunSlot)
                            }
                            if let missSlot = item.missSlot, missSlot != 0 {
                                IconWithValueView(iconName: "icon_44102_64.png", numericValue: missSlot)
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
        let damages = [item.emDamage, item.themDamage, item.kinDamage, item.expDamage]
        return !damages.contains(nil) && damages.compactMap { $0 }.contains { $0 > 0 }
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

// 图标和数值的组合图
struct IconWithValueView: View {
    let iconName: String
    let value: String
    
    // 添加一个便利初始化方法，用于处理数值类型
    init(iconName: String, numericValue: Int, unit: String? = nil) {
        self.iconName = iconName
        self.value = unit.map { "\(NumberFormatUtil.format(Double(numericValue)))\($0)" } ?? NumberFormatUtil.format(Double(numericValue))
    }
    
    // 原有的字符串初始化方法
    init(iconName: String, value: String) {
        self.iconName = iconName
        self.value = value
    }
    
    var body: some View {
        HStack(spacing: 2) {
            IconManager.shared.loadImage(for: iconName)
                .resizable()
                .frame(width: 18, height: 18)
            Text(value)
        }
    }
}
