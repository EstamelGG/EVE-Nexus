import SwiftUI

struct ItemListView: View {
    @Binding var publishedItems: [DatabaseItem]
    @Binding var unpublishedItems: [DatabaseItem]
    @Binding var metaGroupNames: [Int: String]
    var current_title: String
    
    var body: some View {
        VStack {
            List {
                if publishedItems.isEmpty && unpublishedItems.isEmpty {
                    Text(NSLocalizedString("Main_Database_nothing_found", comment: ""))
                        .font(.headline)
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    // 显示已发布的条目
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
                    
                    // 显示未发布的条目
                    if !unpublishedItems.isEmpty {
                        Section(header: Text(NSLocalizedString("Main_Database_unpublished", comment: ""))
                            .font(.headline)
                            .foregroundColor(.primary)) {
                            ForEach(unpublishedItems) { item in
                                itemRow(for: item)
                            }
                        }
                    }
                }
            }
            .navigationTitle(current_title)
        }
    }
    
    private func itemRow(for item: DatabaseItem) -> some View {
        NavigationLink(destination: ShowItemInfo(databaseManager: DatabaseManager(), itemID: item.id)) {
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
}
