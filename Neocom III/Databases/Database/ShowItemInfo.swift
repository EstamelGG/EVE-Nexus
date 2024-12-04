import SwiftUI

// ShowItemInfo view
struct ShowItemInfo: View {
    @ObservedObject var databaseManager: DatabaseManager
    var itemID: Int  // 从上一页面传递过来的 itemID
    
    @State private var itemDetails: ItemDetails? // 改为使用可选类型
    
    var body: some View {
        Form {
            if let itemDetails = itemDetails {
                Section {
                    HStack {
                        // 加载并显示 icon
                        IconManager.shared.loadImage(for: itemDetails.iconFileName)
                            .resizable()
                            .frame(width: 60, height: 60)
                            .cornerRadius(8)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(itemDetails.name)
                                .font(.title)
                            Text("\(itemDetails.categoryName) / \(itemDetails.groupName)")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.vertical, 8)
                    let desc = filterText(itemDetails.description)
                    if !desc.isEmpty {
                        Text(desc)
                            .font(.body)
                            .foregroundColor(.primary)
                    }
                }
                
                Section(header: Text("Additional Information")) {
                    Text("More details can go here.")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            } else {
                Section {
                    Text("Details not found")
                        .foregroundColor(.gray)
                }
            }
        }
        .navigationTitle("Info") // 设置页面标题
        .onAppear {
            loadItemDetails(for: itemID) // 加载物品详细信息
        }
    }
    
    // 加载 item 详细信息
    private func loadItemDetails(for itemID: Int) {
        if let itemDetail = QueryInfo.loadItemDetails(for: itemID, db: databaseManager.db) {
            itemDetails = itemDetail
        } else {
            print("Item details not found for ID: \(itemID)")
        }
    }
}

