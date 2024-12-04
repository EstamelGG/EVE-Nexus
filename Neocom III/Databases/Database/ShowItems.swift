import SwiftUI

struct ShowItems: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var publishedItems: [DatabaseItem] = []
    @State private var unpublishedItems: [DatabaseItem] = []
    @State private var metaGroupNames: [Int: String] = [:]
    @State private var searchText: String = ""
    @State private var dataLoaded: Bool = false
    
    var groupID: Int
    var groupName: String
    
    var body: some View {
        SearchBar(text: $searchText)
            .padding(.top)
        
        VStack {
            List {
                if publishedItems.isEmpty && unpublishedItems.isEmpty {
                    Text(NSLocalizedString("Main_Database_nothing_found", comment: ""))
                        .font(.headline)
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    // 显示已发布条目
                    if !publishedItems.isEmpty {
                        ForEach(sortedMetaGroupIDs(), id: \.self) { metaGroupID in
                            Section(header: Text(metaGroupNames[metaGroupID] ?? NSLocalizedString("Unknown_MetaGroup", comment: ""))
                                .font(.headline).foregroundColor(.primary)) {
                                ForEach(publishedItems.filter { $0.metaGroupID == metaGroupID }) { item in
                                    itemRow(for: item)
                                }
                            }
                        }
                    }
                    // 显示未发布条目
                    if !unpublishedItems.isEmpty {
                        Section(header: Text(NSLocalizedString("Main_Database_unpublished", comment: "")).font(.headline).foregroundColor(.primary)) {
                            ForEach(unpublishedItems) { item in
                                itemRow(for: item)
                            }
                        }
                    }
                }
            }
            .navigationTitle(groupName)
            .onAppear {
                if !dataLoaded {
                    loadItems(for: groupID)
                    dataLoaded = true
                }
            }
        }
    }
    
    private func itemRow(for item: DatabaseItem) -> some View {
        NavigationLink(destination: ShowItemInfo(databaseManager: databaseManager, itemID: item.id)) {
            HStack {
                IconManager.shared.loadImage(for: item.iconFileName)
                    .resizable()
                    .frame(width: 36, height: 36)
                    .cornerRadius(6)
                Text(item.name)
            }
        }
    }

    private func sortedMetaGroupIDs() -> [Int] {
        Array(Set(publishedItems.map { $0.metaGroupID })).sorted()
    }
    
    private func loadItems(for groupID: Int) {
        guard let db = databaseManager.db else { return }
        
        // 使用 QueryItems 来加载数据
        let (publishedItems, unpublishedItems, metaGroupNames) = QueryItems.loadItems(for: groupID, db: db)
        
        self.publishedItems = publishedItems
        self.unpublishedItems = unpublishedItems
        self.metaGroupNames = metaGroupNames
    }
}
