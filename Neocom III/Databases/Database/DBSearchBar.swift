import SwiftUI
import UIKit
import SQLite3

// 清理关键字，只去除英文标点符号
func cleanKeywordWithRegex(_ keyword: String) -> String {
    let regex = try! NSRegularExpression(pattern: "[\\p{P}&&[^\\p{L}\\p{N}]]", options: [])
    let range = NSRange(location: 0, length: keyword.utf16.count)
    let cleanedKeyword = regex.stringByReplacingMatches(in: keyword, options: [], range: range, withTemplate: "")
    return cleanedKeyword
}

struct SearchBar: UIViewRepresentable {
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

    class Coordinator: NSObject, UISearchBarDelegate {
        var parent: SearchBar

        init(parent: SearchBar) {
            self.parent = parent
        }

        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            parent.text = searchText
            if !searchText.isEmpty {
                parent.executeQueryForSourcePage(keyword: searchText)
            } else {
                parent.isSearching = false
                parent.publishedItems = []
                parent.unpublishedItems = []
                parent.metaGroupNames = [:]
            }
        }

        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
            parent.executeQueryForSourcePage(keyword: searchBar.text ?? "")
        }

        func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
            parent.text = ""
            parent.isSearching = false
            parent.onCancelSearch?()  // 触发取消搜索的回调
        }
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UISearchBar {
        let searchBar = UISearchBar()
        searchBar.placeholder = "Search"
        searchBar.delegate = context.coordinator
        return searchBar
    }

    func updateUIView(_ uiView: UISearchBar, context: Context) {
        uiView.text = text
    }

    // 根据 sourcePage 执行不同的查询
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
        let (publishedItems, unpublishedItems, metaGroupNames) = classifyResults(results, db: db)
        
        // 更新父视图中的搜索结果
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
