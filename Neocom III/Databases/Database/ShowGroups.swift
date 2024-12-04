import SwiftUI

struct ShowGroups: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var publishedGroups: [Group] = []
    @State private var unpublishedGroups: [Group] = []
    @State private var searchText: String = ""
    @State private var dataLoaded: Bool = false
    
    var categoryID: Int
    var categoryName: String
    
    var body: some View {
        SearchBar(text: $searchText)
            .padding(.top)
        
        VStack {
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
            .onAppear {
                if !dataLoaded {
                    loadGroups(for: categoryID)
                    dataLoaded = true
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
