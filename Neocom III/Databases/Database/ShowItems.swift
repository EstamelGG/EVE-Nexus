import SwiftUI

// 用于过滤 HTML 标签并处理换行的函数
func filterText(_ text: String) -> String {
    // 1. 替换 <b> 和 </b> 标签为一个空格
    var filteredText = text.replacingOccurrences(of: "<b>", with: " ")
    filteredText = filteredText.replacingOccurrences(of: "</b>", with: " ")
    filteredText = filteredText.replacingOccurrences(of: "<br>", with: "\n")
    // 2. 替换 <link> 和 </link> 标签为一个空格
    filteredText = filteredText.replacingOccurrences(of: "<link.*?>", with: " ", options: .regularExpression)
    filteredText = filteredText.replacingOccurrences(of: "</link>", with: " ", options: .regularExpression)
    
    // 3. 删除其他 HTML 标签
    let regex = try! NSRegularExpression(pattern: "<(?!b|link)(.*?)>", options: .caseInsensitive)
    filteredText = regex.stringByReplacingMatches(in: filteredText, options: [], range: NSRange(location: 0, length: filteredText.utf16.count), withTemplate: "")
    
    // 4. 替换多个连续的换行符为一个换行符
    filteredText = filteredText.replacingOccurrences(of: "\n\n+", with: "\n\n", options: .regularExpression)
    
    return filteredText
}

struct ShowItems: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var publishedItems: [DatabaseItem] = []
    @State private var unpublishedItems: [DatabaseItem] = []
    @State private var metaGroupNames: [Int: String] = [:]
    @State private var searchText: String = ""
    @State private var dataLoaded: Bool = false
    @State private var db: OpaquePointer?
    
    var groupID: Int
    var groupName: String
    
    var body: some View {
        SearchBar(text: $searchText, sourcePage: "item", group_id: groupID, db: databaseManager.db)
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
