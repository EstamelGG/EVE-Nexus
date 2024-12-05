import SwiftUI
import SQLite3

// 清理关键字，只去除英文标点符号
func cleanKeywordWithRegex(_ keyword: String) -> String {
    let regex = try! NSRegularExpression(pattern: "[\\p{P}&&[^\\p{L}\\p{N}]]", options: [])
    let range = NSRange(location: 0, length: keyword.utf16.count)
    let cleanedKeyword = regex.stringByReplacingMatches(in: keyword, options: [], range: range, withTemplate: "")
    return cleanedKeyword
}

struct Searcher: UIViewRepresentable {
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
        var parent: Searcher
        private var debounceWorkItem: DispatchWorkItem?
        init(parent: Searcher) {
            self.parent = parent
        }

        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            debounceWorkItem?.cancel() // 取消之前的防抖任务
            parent.text = searchText

            // 检查是否正在输入未完成的候选字
            if let textField = searchBar.value(forKey: "searchField") as? UITextField,
               let markedTextRange = textField.markedTextRange,
               textField.position(from: markedTextRange.start, offset: 0) != nil {
                // 当前处于未完成的输入状态（有候选字），不触发搜索
                return
            }
            
            if searchText.isEmpty {
                parent.isSearching = false
                parent.publishedItems = []
                parent.unpublishedItems = []
                parent.metaGroupNames = [:]
                return
            }

            // 创建新的防抖任务
            let workItem = DispatchWorkItem { [weak self] in
                self?.parent.executeQueryForSourcePage(keyword: searchText)
            }
            debounceWorkItem = workItem

            // 延迟后执行查询
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
        }

        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
            debounceWorkItem?.cancel()  // 立即执行搜索逻辑，跳过防抖
            parent.executeQueryForSourcePage(keyword: searchBar.text ?? "")
            searchBar.resignFirstResponder()  // 收起键盘
        }

        func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
            debounceWorkItem?.cancel() // 取消防抖任务
            parent.text = ""
            parent.isSearching = false
            parent.publishedItems = []
            parent.unpublishedItems = []
            parent.metaGroupNames = [:]
            searchBar.resignFirstResponder() // 关闭键盘
            parent.onCancelSearch?()
        }
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UISearchBar {
        let searchBar = UISearchBar()
        searchBar.placeholder = "Search"
        searchBar.delegate = context.coordinator
        searchBar.searchBarStyle = .minimal // 使用 minimal 风格去除多余样式
        searchBar.showsCancelButton = true // 显示取消按钮
        searchBar.sizeToFit()  // 确保 searchBar 大小合适
        return searchBar
    }

    func updateUIView(_ uiView: UISearchBar, context: Context) {
        uiView.text = text
        uiView.showsCancelButton = true // 确保取消按钮始终显示
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
        print("Get param:\(text), \(sourcePage), \(category_id), \(group_id)")
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
