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

// ShowItemInfo view
struct ShowItemInfo: View {
    @ObservedObject var databaseManager: DatabaseManager
    var itemID: Int  // 从上一页面传递过来的 itemID
    
    @State private var itemDetails: ItemDetails? // 改为使用可选类型
    
    var body: some View {
        VStack {
            if let itemDetails = itemDetails { // 解包 itemDetails
                // 显示物品的名称、分类、描述信息
                HStack {
                    // 加载并显示 icon
                    IconManager.shared.loadImage(for: itemDetails.iconFileName)
                        .resizable()
                        .frame(width: 60, height: 60)
                        .cornerRadius(8)
                    
                    VStack(alignment: .leading) {
                        Text(itemDetails.name)
                            .font(.title)  // 第一行标题
                        Text("\(itemDetails.categoryName) / \(itemDetails.groupName)")  // 第二行副标题，可以替换为实际的 category/group 名称
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                }
                .padding()
                
                Text(itemDetails.description)
                    .padding()
            } else {
                // 如果没有数据，显示加载中
                Text("Details not found")
                    .foregroundColor(.gray)
            }
            Spacer()
        }
        .onAppear {
            loadItemDetails(for: itemID)  // 加载物品详细信息
        }
        .navigationTitle("Info")  // 设置页面标题
    }
    
    // 加载 item 详细信息
    private func loadItemDetails(for itemID: Int) {
        guard let db = databaseManager.db else {
            print("Database not available")
            return
        }
        // print("Fetching details for item \(itemID)")
        let query = """
        SELECT name, description, icon_filename, group_name, category_name 
        FROM types 
        WHERE type_id = ? 
        """
        
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(itemID))
            
            if sqlite3_step(statement) == SQLITE_ROW {
                let name = String(cString: sqlite3_column_text(statement, 0))
                let description = String(cString: sqlite3_column_text(statement, 1))
                var iconFileName = String(cString: sqlite3_column_text(statement, 2))
                let group_name = String(cString: sqlite3_column_text(statement, 3))
                let category_name = String(cString: sqlite3_column_text(statement, 4))
                // 检查 iconFileName 是否为空
                if iconFileName.isEmpty {
                    iconFileName = "items_7_64_15.png" // 赋值默认值
                }
                itemDetails = ItemDetails(name: name, description: description, iconFileName: iconFileName, groupName: group_name, categoryName: category_name)
            } else {
                print("Item details not found for ID: \(itemID)")
            }
            
            sqlite3_finalize(statement)
        } else {
            print("Failed to prepare statement")
        }
    }
}
