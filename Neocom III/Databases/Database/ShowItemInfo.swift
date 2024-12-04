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

