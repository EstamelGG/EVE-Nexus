import SwiftUI
import Combine

// 通用的数据项模型
struct DatabaseListItem: Identifiable {
    let id: Int
    let name: String
    let iconFileName: String
    let published: Bool
    let metaGroupID: Int?    // 可选，只有 Items 需要
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
    @State private var lastSearchResults: ([DatabaseListItem], [Int: String])? = nil  // 添加搜索结果缓存
    
    // Combine 用于处理搜索
    @StateObject private var searchController = SearchController()
    
    var body: some View {
        List {
            // 已发布的物品
            let publishedItems = items.filter { $0.published }
            if !publishedItems.isEmpty {
                ForEach(groupedPublishedItems, id: \.id) { group in
                    Section(header: Text(group.name).textCase(.none)) {
                        ForEach(group.items) { item in
                            NavigationLink(destination: item.navigationDestination) {
                                DatabaseListItemView(item: item)
                            }
                        }
                    }
                }
            }
            
            // 未发布的物品
            let unpublishedItems = items.filter { !$0.published }
            if !unpublishedItems.isEmpty {
                Section(header: Text(NSLocalizedString("Main_Database_unpublished", comment: "未发布")).textCase(.none)) {
                    ForEach(unpublishedItems) { item in
                        NavigationLink(destination: item.navigationDestination) {
                            DatabaseListItemView(item: item)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer,
            prompt: Text("搜索")
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
        
        isLoading = false
    }
    
    // 已发布物品的分组
    private var groupedPublishedItems: [(id: Int, name: String, items: [DatabaseListItem])] {
        let publishedItems = items.filter { $0.published }
        
        switch groupingType {
        case .publishedOnly:
            return [(id: 0, name: NSLocalizedString("Main_Database_published", comment: ""), items: publishedItems)]
            
        case .metaGroups:
            return groupItemsByMetaGroup(publishedItems)
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
    
    var body: some View {
        HStack {
            // 加载并显示图标
            IconManager.shared.loadImage(for: item.iconFileName)
                .resizable()
                .frame(width: 32, height: 32)
                .cornerRadius(6)
            
            Text(item.name)
        }
    }
}
