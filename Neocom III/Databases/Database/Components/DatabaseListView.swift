import SwiftUI

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
    let title: String
    let groupingType: GroupingType
    let loadData: (DatabaseManager) -> ([DatabaseListItem], [Int: String])
    
    // 状态
    @State private var items: [DatabaseListItem] = []
    @State private var metaGroupNames: [Int: String] = [:]
    @State private var searchText: String = ""
    @State private var isSearching: Bool = false
    @State private var searchResults: [DatabaseListItem] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 搜索栏
            SearchBar(text: $searchText, placeholder: NSLocalizedString("Main_Database_Search", comment: "")) {
                performSearch()
            }
            .padding(.horizontal)
            .frame(height: 60)
            
            Divider()
            
            // 内容列表
            if isSearching {
                searchResultsList
            } else {
                mainContentList
            }
        }
        .navigationTitle(title)
        .onAppear {
            loadItems()
        }
    }
    
    // 主内容列表
    private var mainContentList: some View {
        List {
            if items.isEmpty {
                Text(NSLocalizedString("Main_Database_nothing_found", comment: ""))
                    .font(.headline)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                if groupingType == .publishedOnly {
                    // Categories 和 Groups 的显示逻辑
                    publishedGroupsSection
                } else {
                    // Items 的显示逻辑
                    metaGroupsSection
                }
            }
        }
        .listStyle(.insetGrouped)
    }
    
    // 搜索结果列表
    private var searchResultsList: some View {
        List {
            if searchResults.isEmpty {
                Text(NSLocalizedString("Main_Database_no_search_results", comment: ""))
                    .font(.headline)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                if groupingType == .metaGroups {
                    // 按 MetaGroup 分组显示搜索结果
                    ForEach(Array(Dictionary(grouping: searchResults.filter { $0.published }, by: { $0.metaGroupID ?? 0 })), id: \.key) { metaGroupID, items in
                        if !items.isEmpty {
                            Section(header: Text(metaGroupNames[metaGroupID] ?? "Unknown")) {
                                ForEach(items) { item in
                                    itemRow(for: item)
                                }
                            }
                        }
                    }
                    
                    // 未发布的搜索结果
                    let unpublishedResults = searchResults.filter { !$0.published }
                    if !unpublishedResults.isEmpty {
                        Section(header: Text(NSLocalizedString("Main_Database_unpublished", comment: ""))) {
                            ForEach(unpublishedResults) { item in
                                itemRow(for: item)
                            }
                        }
                    }
                } else {
                    // 简单分为已发布和未发布两组
                    let publishedResults = searchResults.filter { $0.published }
                    let unpublishedResults = searchResults.filter { !$0.published }
                    
                    if !publishedResults.isEmpty {
                        Section(header: Text(NSLocalizedString("Main_Database_published", comment: ""))) {
                            ForEach(publishedResults) { item in
                                itemRow(for: item)
                            }
                        }
                    }
                    
                    if !unpublishedResults.isEmpty {
                        Section(header: Text(NSLocalizedString("Main_Database_unpublished", comment: ""))) {
                            ForEach(unpublishedResults) { item in
                                itemRow(for: item)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
    
    // 已发布/未发布分组
    private var publishedGroupsSection: some View {
        SwiftUI.Group {  // 使用完整的命名空间
            // 已发布项目
            if !publishedItems.isEmpty {
                Section(header: Text(NSLocalizedString("Main_Database_published", comment: ""))) {
                    ForEach(publishedItems) { item in
                        itemRow(for: item)
                    }
                }
            }
            
            // 未发布项目
            if !unpublishedItems.isEmpty {
                Section(header: Text(NSLocalizedString("Main_Database_unpublished", comment: ""))) {
                    ForEach(unpublishedItems) { item in
                        itemRow(for: item)
                    }
                }
            }
        }
    }
    
    // MetaGroup 分组
    private var metaGroupsSection: some View {
        SwiftUI.Group {  // 使用完整的命名空间
            // 按 MetaGroup 分组的项目
            ForEach(sortedMetaGroupIDs(), id: \.self) { metaGroupID in
                if let items = itemsByMetaGroup[metaGroupID], !items.isEmpty {
                    Section(header: Text(metaGroupNames[metaGroupID] ?? "Unknown")) {
                        ForEach(items) { item in
                            itemRow(for: item)
                        }
                    }
                }
            }
            
            // 未发布项目
            if !unpublishedItems.isEmpty {
                Section(header: Text(NSLocalizedString("Main_Database_unpublished", comment: ""))) {
                    ForEach(unpublishedItems) { item in
                        itemRow(for: item)
                    }
                }
            }
        }
    }
    
    private func itemRow(for item: DatabaseListItem) -> some View {
        NavigationLink(destination: item.navigationDestination) {
            HStack {
                IconManager.shared.loadImage(for: item.iconFileName)
                    .resizable()
                    .frame(width: 36, height: 36)
                    .cornerRadius(6)
                Text(item.name)
            }
        }
    }
    
    // 计算属性
    private var publishedItems: [DatabaseListItem] {
        items.filter { $0.published }
    }
    
    private var unpublishedItems: [DatabaseListItem] {
        items.filter { !$0.published }
    }
    
    private var itemsByMetaGroup: [Int: [DatabaseListItem]] {
        Dictionary(grouping: items.filter { $0.published }) { $0.metaGroupID ?? 0 }
    }
    
    private func sortedMetaGroupIDs() -> [Int] {
        Array(Set(items.compactMap { $0.metaGroupID })).sorted()
    }
    
    // 数据加载
    private func loadItems() {
        let (loadedItems, groupNames) = loadData(databaseManager)
        items = loadedItems
        metaGroupNames = groupNames
    }
    
    // 搜索
    private func performSearch() {
        let cleanedText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedText.isEmpty {
            isSearching = false
            searchResults = []
            return
        }
        
        // 简单的本地搜索实现
        searchResults = items.filter { item in
            item.name.localizedCaseInsensitiveContains(cleanedText)
        }
        isSearching = true
    }
} 