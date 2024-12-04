import SwiftUI
import SQLite3

// 定义结构体 ItemDetails
struct ItemDetails {
    let name: String
    let description: String
    let iconFileName: String
    let groupName: String
    let categoryName: String
}

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
        guard let db = databaseManager.db else {
            print("Database not available")
            return
        }
        
        let query = """
        SELECT name, description, icon_filename, group_name, category_name 
        FROM types 
        WHERE type_id = ? 
        """
        
        // 使用通用的查询函数
        let results: [ItemDetails] = executeQuery(
            db: db,
            query: query,bindParams: [itemID],
            bind: { statement in
                sqlite3_bind_int(statement, 1, Int32(itemID))
            },
            resultProcessor: { statement in
                let name = String(cString: sqlite3_column_text(statement, 0))
                let description = String(cString: sqlite3_column_text(statement, 1))
                let iconFileName = String(cString: sqlite3_column_text(statement, 2))
                let groupName = String(cString: sqlite3_column_text(statement, 3))
                let categoryName = String(cString: sqlite3_column_text(statement, 4))
                
                // 检查 iconFileName 是否为空并设置默认值
                let finalIconFileName = iconFileName.isEmpty ? "items_7_64_15.png" : iconFileName
                
                // 返回一个 `ItemDetails` 实例
                return ItemDetails(
                    name: name,
                    description: description,
                    iconFileName: finalIconFileName,
                    groupName: groupName,
                    categoryName: categoryName
                )
            }
        )
        
        // 如果查询结果不为空，取第一个作为详情
        if let itemDetail = results.first {
            itemDetails = itemDetail
        } else {
            print("Item details not found for ID: \(itemID)")
        }
    }
}
