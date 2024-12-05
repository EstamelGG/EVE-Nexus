import SwiftUI
import SQLite3

// 清理关键字，只去除英文标点符号
func cleanKeywordWithRegex(_ keyword: String) -> String {
    let regex = try! NSRegularExpression(pattern: "[\\p{P}&&[^\\p{L}\\p{N}]]", options: [])
    let range = NSRange(location: 0, length: keyword.utf16.count)
    let cleanedKeyword = regex.stringByReplacingMatches(in: keyword, options: [], range: range, withTemplate: "")
    return cleanedKeyword
}

struct Searcher: View {
    @Binding var text: String
    var sourcePage: String
    var category_id: Int?
    var group_id: Int?
    var db: OpaquePointer?

    @Binding var publishedItems: [DatabaseItem]
    @Binding var unpublishedItems: [DatabaseItem]
    @Binding var metaGroupNames: [Int: String]
    @Binding var isSearching: Bool  // 控制是否在搜索

    var onCancelSearch: (() -> Void)?

    // 防抖处理
    @State private var debounceWorkItem: DispatchWorkItem?

    var body: some View {
        VStack {
            // 搜索框
            SearchBar(text: $text, placeholder: "Search", onSearch: performSearch)

            // 显示搜索结果的列表
            List {
                ForEach(publishedItems) { item in
                    Text(item.name)  // 替换为实际的数据项展示
                }
            }
            .listStyle(PlainListStyle())
        }
        .onChange(of: text) { _, newValue in
            if debounceWorkItem != nil {
                debounceWorkItem?.cancel()
            }
            
            // 防抖操作，避免频繁查询
            debounceWorkItem = DispatchWorkItem {
                performSearch()
            }
            if let workItem = debounceWorkItem {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
            }
        }
    }

    // 执行搜索
    private func performSearch() {
        let keyword = cleanKeywordWithRegex(text)
        guard !keyword.isEmpty else {
            publishedItems = []
            unpublishedItems = []
            metaGroupNames = [:]
            return
        }

        executeQueryForSourcePage(keyword: keyword)
    }

    // 根据 sourcePage 执行不同的查询
    private func executeQueryForSourcePage(keyword: String) {
        guard let db = db else {
            print("Database not available")
            return
        }
        
        var query: String
        var bindParams: [String] = []

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
            bind: { _ in },
            resultProcessor: { statement in
                DatabaseItem(
                    id: Int(sqlite3_column_int(statement, 0)),
                    typeID: Int(sqlite3_column_int(statement, 0)),
                    name: String(cString: sqlite3_column_text(statement, 1)),
                    iconFileName: String(cString: sqlite3_column_text(statement, 2)).isEmpty ? "items_7_64_15.png" : String(cString: sqlite3_column_text(statement, 2)),
                    pgNeed: Int(sqlite3_column_int(statement, 3)),
                    cpuNeed: Int(sqlite3_column_int(statement, 4)),
                    metaGroupID: Int(sqlite3_column_int(statement, 5)),
                    published: sqlite3_column_int(statement, 6) != 0
                )
            }
        )
        
        // 根据 published 字段分类
        let (publishedItems, unpublishedItems, metaGroupNames) = classifyResults(results, db: db)

        self.publishedItems = publishedItems
        self.unpublishedItems = unpublishedItems
        self.metaGroupNames = metaGroupNames
        self.isSearching = true
    }

    // 分类结果：已发布、未发布以及 metaGroupNames
    private func classifyResults(_ items: [DatabaseItem], db: OpaquePointer) -> ([DatabaseItem], [DatabaseItem], [Int: String]) {
        var publishedItems: [DatabaseItem] = []
        var unpublishedItems: [DatabaseItem] = []
        var metaGroupNames: [Int: String] = [:]
        
        // 获取每个 item 对应的 metaGroupName
        for item in items {
            // 加载 metaGroupName
            loadMetaGroupName(for: item.metaGroupID, db: db, metaGroupNames: &metaGroupNames)
            
            // 根据 published 标记分类
            if item.published {
                publishedItems.append(item)
            } else {
                unpublishedItems.append(item)
            }
        }
        
        return (publishedItems, unpublishedItems, metaGroupNames)
    }

    // 添加你的 loadMetaGroupName 方法
    private func loadMetaGroupName(for metaGroupID: Int, db: OpaquePointer, metaGroupNames: inout [Int: String]) {
        let query = "SELECT name FROM metaGroups WHERE metaGroup_id = ?"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(metaGroupID))
            if sqlite3_step(statement) == SQLITE_ROW, let name = sqlite3_column_text(statement, 0) {
                metaGroupNames[metaGroupID] = String(cString: name)
            }
            sqlite3_finalize(statement)
        }
    }
}

struct SearchBar: View {
    @Binding var text: String
    var placeholder: String
    var onSearch: () -> Void

    var body: some View {
        TextField(placeholder, text: $text, onCommit: onSearch)
            .padding(10)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            .padding([.horizontal])
    }
}

#Preview {
    Searcher(text: .constant(""), sourcePage: "item", category_id: 1, group_id: 1, db: nil, publishedItems: .constant([]), unpublishedItems: .constant([]), metaGroupNames: .constant([:]), isSearching: .constant(false))
}
