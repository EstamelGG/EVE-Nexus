import SwiftUI

struct ShowCategory: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var publishedCategories: [Category] = []
    @State private var unpublishedCategories: [Category] = []
    @State private var searchText: String = ""
    @State private var dataLoaded: Bool = false
    @State private var db: OpaquePointer?
    
    @State private var publishedItems: [DatabaseItem] = []
    @State private var unpublishedItems: [DatabaseItem] = []
    @State private var metaGroupNames: [Int: String] = [:]
    
    @State private var isSearching: Bool = false // 控制是否显示搜索结果
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Searcher(
                    text: $searchText,
                    sourcePage: "category",
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
            
            // 主体内容
            if isSearching {
                // 搜索结果
                ItemListView(
                    publishedItems: $publishedItems,
                    unpublishedItems: $unpublishedItems,
                    metaGroupNames: $metaGroupNames
                )
            } else {
                // 分类列表
                List {
                    if publishedCategories.isEmpty && unpublishedCategories.isEmpty {
                        Text(NSLocalizedString("Main_Database_nothing_found", comment: ""))
                            .font(.headline)
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        // 已发布分类
                        if !publishedCategories.isEmpty {
                            Section(header: Text(NSLocalizedString("Main_Database_published", comment: "")).font(.headline).foregroundColor(.primary)) {
                                ForEach(publishedCategories) { category in
                                    NavigationLink(
                                        destination: ShowGroups(
                                            databaseManager: databaseManager,
                                            categoryID: category.id,
                                            categoryName: category.name
                                        )
                                    ) {
                                        HStack {
                                            IconManager.shared.loadImage(for: category.iconFileNew)
                                                .resizable()
                                                .frame(width: 36, height: 36)
                                                .cornerRadius(6)
                                            Text(category.name)
                                        }
                                    }
                                }
                            }
                        }
                        
                        // 未发布分类
                        if !unpublishedCategories.isEmpty {
                            Section(header: Text(NSLocalizedString("Main_Database_unpublished", comment: "")).font(.headline).foregroundColor(.primary)) {
                                ForEach(unpublishedCategories) { category in
                                    NavigationLink(
                                        destination: ShowGroups(
                                            databaseManager: databaseManager,
                                            categoryID: category.id,
                                            categoryName: category.name
                                        ).navigationTitle(category.name)
                                    ) {
                                        HStack {
                                            IconManager.shared.loadImage(for: category.iconFileNew)
                                                .resizable()
                                                .frame(width: 36, height: 36)
                                                .cornerRadius(6)
                                            Text(category.name)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .navigationTitle(NSLocalizedString("Main_Database_title", comment: ""))
                .listStyle(.insetGrouped) // 更美观的列表样式
                .onAppear {
                    if !dataLoaded {
                        loadCategories()
                        dataLoaded = true
                    }
                }
            }
        }
    }
    
    private func loadCategories() {
        guard let db = databaseManager.db else { return }
        
        // 使用 QueryCategory 来加载数据
        let (published, unpublished) = QueryCategory.loadCategories(from: db)
        publishedCategories = published
        unpublishedCategories = unpublished
    }
}
