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
            SearchBar(text: $searchText, onCancel: {
                loadInitialData()
                if !searchText.isEmpty {
                    dismiss()  // 如果有搜索文本，取消时返回上一页
                }
            })
            .onChange(of: searchText) { _, newValue in
                searchTextDebouncer.text = newValue
                if newValue.isEmpty {
                    dismiss()  // 当搜索文本被清空时返回上一页
                }
            }
            
            if items.isEmpty {
                ContentUnavailableView("Not Found", systemImage: "magnifyingglass")
            } else {
                List {
                    // 已发布的物品
                    let publishedItems = items.filter { $0.published }
                    if !publishedItems.isEmpty {
                        ForEach(groupedPublishedItems, id: \.key) { group in
                            Section(header: Text(group.key).textCase(.none)) {
                                ForEach(group.value) { item in
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
                        Section(header: Text(NSLocalizedString("Main_Database_unpublished", comment: "")).textCase(.none)) {
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
    }
    
    // 已发布物品的分组
    private var groupedPublishedItems: [(key: String, value: [DatabaseListItem])] {
        let publishedItems = items.filter { $0.published }
        
        switch groupingType {
        case .publishedOnly:
            return [(NSLocalizedString("Main_Database_published", comment: ""), publishedItems)]
            
        case .metaGroups:
            // 按元组分组
            let grouped = Dictionary(grouping: publishedItems) { item in
                if let metaGroupID = item.metaGroupID,
                   let metaGroupName = metaGroupNames[metaGroupID] {
                    return metaGroupName
                }
                return "未分组"
            }
            return grouped.sorted { $0.key < $1.key }
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
