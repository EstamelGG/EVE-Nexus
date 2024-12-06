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
    @Environment(\.dismiss) private var dismiss  // 添加环境变量用于返回
    
    let title: String
    let groupingType: GroupingType
    let loadData: (DatabaseManager) -> ([DatabaseListItem], [Int: String])
    let searchData: ((DatabaseManager, String) -> ([DatabaseListItem], [Int: String]))?
    
    @State private var items: [DatabaseListItem] = []
    @State private var metaGroupNames: [Int: String] = [:]
    @State private var searchText = ""
    @State private var isSearching = false
    
    // 添加防抖发布者
    @StateObject private var searchTextDebouncer = DebouncedText()
    
    var body: some View {
        VStack {
            SearchBar(text: $searchText, isSearching: $isSearching, onCancel: {
                loadInitialData()
                if !searchText.isEmpty {
                    searchText = ""
                }
            }, onSearch: {
                // 用户点击搜索按钮时，立即执行搜索
                if !searchText.isEmpty {
                    isSearching = true
                    performSearch(with: searchText)
                    // 取消防抖搜索
                    searchTextDebouncer.text = ""
                }
            })
            .onChange(of: searchText) { _, newValue in
                isSearching = true
                // 只有在用户输入时才更新防抖文本
                if !newValue.isEmpty {
                    searchTextDebouncer.text = newValue
                }
            }
            
            ZStack {
                if isSearching {
                    // 搜索状态下显示遮罩
                    Color.black.opacity(0.3)
                        .edgesIgnoringSafeArea(.all)
                } else if !searchText.isEmpty {
                    // 搜索完成且有搜索文本的状态
                    if items.isEmpty {
                        // 无搜索结果时显示空状态
                        ContentUnavailableView {
                            Label("Not Found", systemImage: "magnifyingglass")
                        } description: {
                            Text("No items match your search")
                        }
                    } else {
                        // 有搜索结果时显示结果列表
                        searchResultsList
                    }
                } else {
                    // 普通浏览状态
                    normalBrowseList
                }
            }
        }
        .navigationTitle(title)
        .onAppear {
            loadInitialData()
        }
        .onReceive(searchTextDebouncer.$debouncedText) { debouncedText in
            if debouncedText.isEmpty {
                if searchText.isEmpty {
                    loadInitialData()
                    isSearching = false
                }
            } else {
                performSearch(with: debouncedText)
            }
        }
    }
    
    // 搜索结果列表视图
    private var searchResultsList: some View {
        List {
            // 已发布的物品（按衍生等级分组）
            let publishedItems = items.filter { $0.published }
            if !publishedItems.isEmpty {
                ForEach(groupItemsByMetaGroup(publishedItems), id: \.id) { group in
                    Section(header: Text(group.name).textCase(.none)) {
                        ForEach(group.items) { item in
                            NavigationLink(destination: item.navigationDestination) {
                                DatabaseListItemView(item: item)
                            }
                        }
                    }
                }
            }
            
            // 未发布的物品（单独分组）
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
    }
    
    // 普通浏览列表视图
    private var normalBrowseList: some View {
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
    }
    
    private func loadInitialData() {
        let (loadedItems, loadedMetaGroupNames) = loadData(databaseManager)
        items = loadedItems
        metaGroupNames = loadedMetaGroupNames
    }
    
    private func performSearch(with text: String) {
        guard let searchData = searchData else { return }
        
        let (searchResults, searchMetaGroupNames) = searchData(databaseManager, text)
        items = searchResults
        
        // 更新 metaGroupNames
        if searchMetaGroupNames.isEmpty {
            let metaGroupIDs = Set(searchResults.compactMap { $0.metaGroupID })
            metaGroupNames = databaseManager.loadMetaGroupNames(for: Array(metaGroupIDs))
        } else {
            metaGroupNames = searchMetaGroupNames
        }
        
        // 搜索完成后，如果有结果，关闭搜索状态
        if !searchResults.isEmpty {
            isSearching = false
        }
    }
    
    // 已发布物品的分组
    private var groupedPublishedItems: [(id: Int, name: String, items: [DatabaseListItem])] {
        let publishedItems = items.filter { $0.published }
        
        // 只有在搜索完成后（有搜索文本且不在搜索状态）才使用 metaGroups 分组
        if !searchText.isEmpty && !isSearching {
            return groupItemsByMetaGroup(publishedItems)
        }
        
        switch groupingType {
        case .publishedOnly:
            return [(id: 0, name: NSLocalizedString("Main_Database_published", comment: ""), items: publishedItems)]
            
        case .metaGroups:
            return groupItemsByMetaGroup(publishedItems)
        }
    }
    
    // 添加一个辅助方法来处理 metaGroups 分组
    private func groupItemsByMetaGroup(_ items: [DatabaseListItem]) -> [(id: Int, name: String, items: [DatabaseListItem])] {
        // 创建一个临时字典来存储分组
        var grouped: [Int: [DatabaseListItem]] = [:]
        
        // 对物品进行分组
        for item in items {
            let metaGroupID = item.metaGroupID ?? 0
            if grouped[metaGroupID] == nil {
                grouped[metaGroupID] = []
            }
            grouped[metaGroupID]?.append(item)
        }
        
        // 按 metaGroupID 排序并转换为最终格式
        return grouped.sorted { $0.key < $1.key }
            .map { (metaGroupID, items) in
                if metaGroupID == 0 {
                    return (id: 0, name: NSLocalizedString("Main_Database_base", comment: "基础物品"), items: items)
                }
                
                // 确保从 metaGroupNames 中获取到名称
                if let groupName = metaGroupNames[metaGroupID] {
                    return (id: metaGroupID, name: groupName, items: items)
                } else {
                    print("警告: MetaGroupID \(metaGroupID) 没有对应的名称")
                    return (id: metaGroupID, name: "MetaGroup \(metaGroupID)", items: items)
                }
            }
            .filter { !$0.items.isEmpty }  // 过滤掉空的组
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

// 防抖文本处理类
class DebouncedText: ObservableObject {
    @Published var text: String = ""
    @Published var debouncedText: String = ""
    private var cancellable: AnyCancellable?
    
    init() {
        cancellable = $text
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] value in
                DispatchQueue.main.async {
                    self?.debouncedText = value
                }
            }
    }
    
    deinit {
        cancellable?.cancel()
    }
}
