import SwiftUI

struct ShowCategory: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var publishedCategories: [Category] = []
    @State private var unpublishedCategories: [Category] = []
    @State private var searchText: String = ""
    @State private var dataLoaded: Bool = false
    @State private var db: OpaquePointer?
        
    var body: some View {
        VStack {
            // Search bar
            SearchBar(text: $searchText, sourcePage: "category", db: databaseManager.db)
                .padding(.top)

            // List
            List {
                if publishedCategories.isEmpty && unpublishedCategories.isEmpty {
                    // 显示空数据提示
                    Text(NSLocalizedString("Main_Database_nothing_found", comment: ""))
                        .font(.headline)
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    // 已发布的分类
                    if !publishedCategories.isEmpty {
                        Section(header: Text(NSLocalizedString("Main_Database_published", comment: "")).font(.headline).foregroundColor(.primary)) {
                            ForEach(publishedCategories) { category in
                                NavigationLink(destination: ShowGroups(databaseManager: databaseManager, categoryID: category.id, categoryName: category.name)) {
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

                    // 未发布的分类
                    if !unpublishedCategories.isEmpty {
                        Section(header: Text(NSLocalizedString("Main_Database_unpublished", comment: "")).font(.headline).foregroundColor(.primary)) {
                            ForEach(unpublishedCategories) { category in
                                NavigationLink(destination: ShowGroups(databaseManager: databaseManager, categoryID: category.id, categoryName: category.name)) {
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
            .onAppear {
                if !dataLoaded {
                    loadCategories()
                    dataLoaded = true
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
