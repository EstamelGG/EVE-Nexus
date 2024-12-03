import SwiftUI
import SQLite3

struct ShowItemInfo: View {
    @ObservedObject var databaseManager: DatabaseManager
    var itemID: Int  // 接收传入的 itemID

    @State private var itemName: String = ""
    @State private var itemDescription: String = ""
    @State private var iconFileName: String = ""
    @State private var category: String = ""
    @State private var group: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                // 左侧图标
                IconManager.shared.loadImage(for: iconFileName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                
                VStack(alignment: .leading) {
                    // 第一行标题: name
                    Text(itemName)
                        .font(.title)
                        .fontWeight(.bold)
                    
                    // 第二行副标题: category / group
                    Text("\(category) / \(group)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
            
            // description
            Text(itemDescription)
                .font(.body)
                .padding(.top, 10)
        }
        .padding()
        .onAppear {
            loadItemDetails()
        }
    }
    
    // 加载 itemID 对应的物品详细信息
    private func loadItemDetails() {
        guard let db = databaseManager.db else {
            print("Database not available")
            return
        }

        let query = "SELECT name, description, icon_filename, groupID FROM types WHERE type_id = ?"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(itemID))
            
            if sqlite3_step(statement) == SQLITE_ROW {
                itemName = String(cString: sqlite3_column_text(statement, 0))
                itemDescription = String(cString: sqlite3_column_text(statement, 1))
                iconFileName = String(cString: sqlite3_column_text(statement, 2))
                let groupID = Int(sqlite3_column_int(statement, 3))
                
                // 获取物品的分类和组名
                loadCategoryAndGroupNames(for: groupID)
            }
            
            sqlite3_finalize(statement)
        }
    }
    
    // 加载物品的 category 和 group 信息
    private func loadCategoryAndGroupNames(for groupID: Int) {
        guard let db = databaseManager.db else {
            return
        }
        
        let query = "SELECT name FROM categories WHERE groupID = ?"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(groupID))
            
            if sqlite3_step(statement) == SQLITE_ROW {
                category = String(cString: sqlite3_column_text(statement, 0))
            }
            
            sqlite3_finalize(statement)
        }
        
        // 获取物品的组名
        let queryGroup = "SELECT name FROM groups WHERE groupID = ?"
        if sqlite3_prepare_v2(db, queryGroup, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(groupID))
            
            if sqlite3_step(statement) == SQLITE_ROW {
                group = String(cString: sqlite3_column_text(statement, 0))
            }
            
            sqlite3_finalize(statement)
        }
    }
}
