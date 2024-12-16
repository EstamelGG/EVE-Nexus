import SwiftUI
import Combine

// 通用的数据项模型
struct DatabaseListItem: Identifiable {
    let id: Int
    let name: String
    let iconFileName: String
    let published: Bool
    let categoryID: Int?
    let groupID: Int?
    let groupName: String?  // 添加物品组名称字段
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
    let marketGroupID: Int?  // 添加市场组ID字段
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
    let searchData: ((DatabaseManager, String) -> ([DatabaseListItem], [Int: String], [Int: String]))?
    
    @State private var items: [DatabaseListItem] = []
    @State private var metaGroupNames: [Int: String] = [:]
    @State private var groupNames: [Int: String] = [:]  // 添加组名字典
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var lastSearchResults: ([DatabaseListItem], [Int: String], [Int: String])? = nil
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
                groupNames = lastResults.2
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
            let (searchResults, searchMetaGroupNames, searchGroupNames) = searchData(databaseManager, text)
            
            // 更新 UI
            items = searchResults
            
            // 更新 metaGroupNames
            if searchMetaGroupNames.isEmpty {
                let metaGroupIDs = Set(searchResults.compactMap { $0.metaGroupID })
                metaGroupNames = databaseManager.loadMetaGroupNames(for: Array(metaGroupIDs))
            } else {
                metaGroupNames = searchMetaGroupNames
            }
            
            // 更新 groupNames
            if searchGroupNames.isEmpty {
                let groupIDs = Set(searchResults.compactMap { $0.groupID })
                groupNames = databaseManager.loadGroupNames(for: Array(groupIDs))
            } else {
                groupNames = searchGroupNames
            }
            
            // 保存搜索结果
            lastSearchResults = (searchResults, metaGroupNames, groupNames)
            isShowingSearchResults = true  // 搜索结果标志
            
            isLoading = false  // 搜索完成，隐藏加载状态
        }
    }
    
    // 已发布物品的分组
    private var groupedPublishedItems: [(id: Int, name: String, items: [DatabaseListItem])] {
        let publishedItems = items.filter { $0.published }
        
        // 使用 isShowingSearchResults 而不是 searchText.isEmpty
        if isShowingSearchResults {
            return groupItemsByGroup(publishedItems)
        } else if groupingType == .metaGroups {
            return groupItemsByMetaGroup(publishedItems)
        } else {
            return [(id: 0, name: NSLocalizedString("Main_Database_published", comment: ""), items: publishedItems)]
        }
    }
    
    private func groupItemsByGroup(_ items: [DatabaseListItem]) -> [(id: Int, name: String, items: [DatabaseListItem])] {
        var grouped: [Int: [DatabaseListItem]] = [:]
        
        for item in items {
            let groupID = item.groupID ?? 0
            if grouped[groupID] == nil {
                grouped[groupID] = []
            }
            grouped[groupID]?.append(item)
        }
        
        return grouped.sorted { $0.key < $1.key }
            .map { (groupID, items) in
                if groupID == 0 {
                    return (id: 0, name: NSLocalizedString("Main_Database_base", comment: "基础物品"), items: items)
                }
                
                if let groupName = groupNames[groupID] {
                    return (id: groupID, name: groupName, items: items)
                } else {
                    Logger.warning("GroupID \(groupID) 没有对应的名称")
                    return (id: groupID, name: "Group \(groupID)", items: items)
                }
            }
            .filter { !$0.items.isEmpty }
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
                    Logger.warning("MetaGroupID \(metaGroupID) 没有对应的名称")
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
