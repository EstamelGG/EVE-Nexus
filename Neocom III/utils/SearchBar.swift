import SwiftUI
import SQLite3
import Foundation

func cleanKeywordWithRegex(_ keyword: String) -> String {
    let regex = try! NSRegularExpression(pattern: "[^a-zA-Z0-9]", options: [])
    let range = NSRange(location: 0, length: keyword.utf16.count)
    let cleanedKeyword = regex.stringByReplacingMatches(in: keyword, options: [], range: range, withTemplate: "")
    return cleanedKeyword
}

struct SearchBar: View {
    @Binding var text: String
    var sourcePage: String
    var category_id: Int?
    var group_id: Int?
    var db: OpaquePointer?
    
    @Binding var publishedItems: [DatabaseItem]
    @Binding var unpublishedItems: [DatabaseItem]
    @Binding var metaGroupNames: [Int: String]

    @State private var debounceTimer: Timer? = nil
    
    var body: some View {
        HStack {
            TextField("Search", text: $text)
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
        debounceTimer?.invalidate()
        
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { _ in
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
        let keyword = cleanKeywordWithRegex(keyword)
        if keyword.isEmpty { return }
        
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
            WHERE name LIKE "%\(keyword)%" AND categoryID = \(category_id!)
            ORDER BY metaGroupID
            """
            bindParams = ["%\(keyword)%", String(category_id!)]
        case "item":
            query = """
            SELECT type_id, name, icon_filename, pg_need, cpu_need, metaGroupID, published
            FROM types
            WHERE name LIKE "%\(keyword)%" AND groupID = \(group_id!)
            ORDER BY metaGroupID
            """
            bindParams = ["%\(keyword)%", String(group_id!)]
        default:
            return
        }
        
        // 执行查询
        let results: [DatabaseItem] = executeQuery(
            db: db,
            query: query,
            bindParams: bindParams,
            bind: { statement in },
            resultProcessor: { statement in
                let item = DatabaseItem(
                    id: Int(sqlite3_column_int(statement, 0)),
                    typeID: Int(sqlite3_column_int(statement, 0)),
                    name: String(cString: sqlite3_column_text(statement, 1)),
                    iconFileName: String(cString: sqlite3_column_text(statement, 2)).isEmpty ? "items_7_64_15.png" : String(cString: sqlite3_column_text(statement, 2)),
                    pgNeed: Int(sqlite3_column_int(statement, 3)),
                    cpuNeed: Int(sqlite3_column_int(statement, 4)),
                    metaGroupID: Int(sqlite3_column_int(statement, 5)),
                    published: sqlite3_column_int(statement, 6) != 0
                )
                return item
            }
        )
        
        // 根据 published 字段分类
        let (publishedItems, unpublishedItems, metaGroupNames) = classifyResults(results)
        
        // 更新父视图中的搜索结果
        self.publishedItems = publishedItems
        self.unpublishedItems = unpublishedItems
        self.metaGroupNames = metaGroupNames
    }
    
    // 分类结果：已发布、未发布以及 metaGroupNames
    private func classifyResults(_ items: [DatabaseItem]) -> ([DatabaseItem], [DatabaseItem], [Int: String]) {
        var publishedItems: [DatabaseItem] = []
        var unpublishedItems: [DatabaseItem] = []
        var metaGroupNames: [Int: String] = [:]
        
        for item in items {
            // 按 published 字段分类
            if item.published {
                publishedItems.append(item)
            } else {
                unpublishedItems.append(item)
            }
            
            // 获取 metaGroupName
            metaGroupNames[item.metaGroupID] = "Meta Group \(item.metaGroupID)" // 这里可以通过其他方式来设置名称
        }
        
        return (publishedItems, unpublishedItems, metaGroupNames)
    }
}
