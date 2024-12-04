import SwiftUI
import SQLite3

struct SearchBar: View {
    @Binding var text: String
    var sourcePage: String
    var category_id: Int?
    var group_id: Int?
    var db: OpaquePointer?
    
    @State private var debounceTimer: Timer? = nil
    
    var body: some View {
        HStack {
            TextField("Search...", text: $text)
                .padding(7)
                .padding(.horizontal, 25)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .overlay(
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                            .padding(.leading, 10)
                        
                        Spacer()
                    }
                )
                .padding(.horizontal)
                .onChange(of: text) { oldValue, newValue in
                    debounceSearch(keyword: newValue)
                }
        }
    }
    
    // 延迟查询函数
    private func debounceSearch(keyword: String) {
        // 取消之前的计时器（如果有）
        debounceTimer?.invalidate()
        
        // 创建新的延迟 0.5 秒的计时器
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
            executeQueryForSourcePage(keyword: keyword)
        }
    }
    
    // 根据 sourcePage 调用不同的查询接口
    private func executeQueryForSourcePage(keyword: String) {
        guard let db = db else {
            print("Database not available")
            return
        }
        
        var query: String
        var bindParams: [String] = []
        // 根据 sourcePage 设置不同的查询语句
        switch sourcePage {
        case "category":
            query = """
            SELECT type_id, name, icon_filename, pg_need, cpu_need, metaGroupID, published
            FROM types
            WHERE name LIKE "%\(keyword)%"
            ORDER BY metaGroupID
            """
            bindParams = ["%\(keyword)%"]
        case "group":
            query = """
            SELECT type_id, name, icon_filename, pg_need, cpu_need, metaGroupID, published
            FROM types
            WHERE name LIKE "%\(keyword)%" AND categoryID = \(String(category_id!))
            ORDER BY metaGroupID
            """
            bindParams = ["%\(keyword)%", String(category_id!)]
        case "item":
            query = """
            SELECT type_id, name, icon_filename, pg_need, cpu_need, metaGroupID, published
            FROM types
            WHERE name LIKE "%\(keyword)%" AND groupID = \(String(group_id!))
            ORDER BY metaGroupID
            """
            bindParams = ["%\(keyword)%", String(group_id!)]
        default:
            print("Unknown sourcePage")
            return
        }
        
        // 执行查询
        let results: [ItemDetails] = executeQuery(
            db: db,
            query: query,
            bindParams: bindParams,
            bind: {statement in },
            resultProcessor: { statement in
                let name = String(cString: sqlite3_column_text(statement, 1))
                let iconFileName = String(cString: sqlite3_column_text(statement, 2))
                let groupName = String(cString: sqlite3_column_text(statement, 3))
                let categoryName = String(cString: sqlite3_column_text(statement, 4))
                
                let finalIconFileName = iconFileName.isEmpty ? "items_7_64_15.png" : iconFileName
                
                return ItemDetails(
                    name: name,
                    description: "", // 根据需要调整
                    iconFileName: finalIconFileName,
                    groupName: groupName,
                    categoryName: categoryName
                )
            }
        )
        
        // 处理查询结果
        if !results.isEmpty {
            print("Found \(results.count) items for keyword: \(keyword)")
        } else {
            print("No results found for keyword: \(keyword)")
        }
    }
}
