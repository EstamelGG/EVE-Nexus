import SwiftUI

struct ShowGroups: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var publishedGroups: [Group] = []
    @State private var unpublishedGroups: [Group] = []
    @State private var searchText: String = ""
    @State private var dataLoaded: Bool = false
    @State private var db: OpaquePointer?

    @State private var publishedItems: [DatabaseItem] = []
    @State private var unpublishedItems: [DatabaseItem] = []
    @State private var metaGroupNames: [Int: String] = [:]
    
    @State private var isSearching: Bool = false  // 控制是否显示搜索结果
    
    var categoryID: Int
    var categoryName: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 使用 SearchBar 搜索条目并传递结果
            VStack(alignment: .leading, spacing: 8) {
                Searcher(
                    text: $searchText,
                    sourcePage: "group",
                    category_id: categoryID,
                    db: databaseManager.db,
                    publishedItems: $publishedItems,
                    unpublishedItems: $unpublishedItems,
                    metaGroupNames: $metaGroupNames,
                    isSearching: $isSearching
                )
            }
            .padding(.horizontal)
            .padding(.top)
            
            Divider() // 分隔线
            
            // 根据 isSearching 控制显示内容
            if isSearching {
                // 当有搜索时显示 ItemListView
                ItemListView(
                    publishedItems: $publishedItems,
                    unpublishedItems: $unpublishedItems,
                    metaGroupNames: $metaGroupNames,
                    current_title: categoryName
                )
            } else {
                // 没有搜索时显示原本的分组列表
                List {
                    if publishedGroups.isEmpty && unpublishedGroups.isEmpty {
                        Text(NSLocalizedString("Main_Database_nothing_found", comment: ""))
                            .font(.headline)
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        // 显示已发布的分组
                        if !publishedGroups.isEmpty {
                            Section(header: Text(NSLocalizedString("Main_Database_published", comment: "")).font(.headline).foregroundColor(.primary)) {
                                ForEach(publishedGroups) { group in
                                    NavigationLink(destination: ShowItems(databaseManager: databaseManager, groupID: group.id, groupName: group.name)) {
                                        HStack {
                                            IconManager.shared.loadImage(for: group.icon_filename)
                                                .resizable()
                                                .frame(width: 36, height: 36)
                                                .cornerRadius(6)
                                            Text(group.name)
                                        }
                                    }
                                }
                            }
                        }
                        
                        // 显示未发布的分组
                        if !unpublishedGroups.isEmpty {
                            Section(header: Text(NSLocalizedString("Main_Database_unpublished", comment: "")).font(.headline).foregroundColor(.primary)) {
                                ForEach(unpublishedGroups) { group in
                                    NavigationLink(destination: ShowItems(databaseManager: databaseManager, groupID: group.id, groupName: group.name)) {
                                        HStack {
                                            IconManager.shared.loadImage(for: group.icon_filename)
                                                .resizable()
                                                .frame(width: 36, height: 36)
                                                .cornerRadius(6)
                                            Text(group.name)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .navigationTitle(categoryName)
                .listStyle(.insetGrouped) // 更美观的列表样式
                .onAppear {
                    if !dataLoaded {
                        loadGroups(for: categoryID)
                        dataLoaded = true
                    }
                }
            }
        }
    }
    
    private func loadGroups(for categoryID: Int) {
        guard let db = databaseManager.db else { return }
        
        // 使用 QueryGroups 来加载数据
        let (publishedGroups, unpublishedGroups) = QueryGroups.loadGroups(for: categoryID, db: db)
        
        self.publishedGroups = publishedGroups
        self.unpublishedGroups = unpublishedGroups
    }
}
