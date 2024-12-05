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
                    searchText = ""  // 只清空搜索文本，不自动返回
                }
            })
            .onChange(of: searchText) { _, newValue in
                searchTextDebouncer.text = newValue
            }
            
            ZStack {
                if items.isEmpty {
                    ContentUnavailableView("Not Found", systemImage: "magnifyingglass")
                } else {
                    List {
                        // 已发布的物品（按元组分组）
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
                    
                    // 添加遮罩层
                    if isSearching {
                        Color.black.opacity(0.3)
                            .edgesIgnoringSafeArea(.all)
                            .allowsHitTesting(true)  // 允许遮罩层接收点击事件
                    }
                }
            }
        }
        .navigationTitle(title)
        .onAppear {
            loadInitialData()
        }
        // 监听防抖后的搜索文本
        .onReceive(searchTextDebouncer.$debouncedText) { debouncedText in
            performSearch(with: debouncedText)
        }
    }
    
    private func loadInitialData() {
        let (loadedItems, loadedMetaGroupNames) = loadData(databaseManager)
        items = loadedItems
        metaGroupNames = loadedMetaGroupNames
    }
    
    private func performSearch(with text: String) {
        if text.isEmpty {
            loadInitialData()
            return
        }
        
        guard let searchData = searchData else { return }
        let (searchResults, searchMetaGroupNames) = searchData(databaseManager, text)
        items = searchResults
        metaGroupNames = searchMetaGroupNames
        // 搜索完成后，如果有结果，关闭遮罩
        if !searchResults.isEmpty {
            isSearching = false
        }
    }
    
    // 已发布物品的分组
    private var groupedPublishedItems: [(id: Int, name: String, items: [DatabaseListItem])] {
        let publishedItems = items.filter { $0.published }
        
        switch groupingType {
        case .publishedOnly:
            return [(id: 0, name: NSLocalizedString("Main_Database_published", comment: ""), items: publishedItems)]
            
        case .metaGroups:
            // 创建一个临时字典来存储分组
            var grouped: [Int: [DatabaseListItem]] = [:]
            
            // 对物品进行分组
            for item in publishedItems {
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
        }
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
                self?.debouncedText = value
            }
    }
}
