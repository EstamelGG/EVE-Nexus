import SwiftUI
import SQLite3

// 数据模型
struct Category: Identifiable {
    let id: Int
    let name: String
    let published: Bool
}

// 数据加载函数
func loadCategories(from databasePath: String) -> ([Category], [Category]) {
    var db: OpaquePointer?
    var publishedCategories: [Category] = []
    var unpublishedCategories: [Category] = []

    if sqlite3_open(databasePath, &db) == SQLITE_OK {
        let query = "SELECT category_id, name, published FROM categories ORDER BY category_id"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = Int(sqlite3_column_int(statement, 0))
                let name = String(cString: sqlite3_column_text(statement, 1))
                let published = sqlite3_column_int(statement, 2) != 0

                let category = Category(id: id, name: name, published: published)
                if published {
                    publishedCategories.append(category)
                } else {
                    unpublishedCategories.append(category)
                }
            }
            sqlite3_finalize(statement)
        } else {
            print("Failed to prepare statement: \(String(cString: sqlite3_errmsg(db)))")
        }

        sqlite3_close(db)
    } else {
        print("Failed to open database")
    }

    return (publishedCategories, unpublishedCategories)
}

// 获取数据库路径
func getDatabasePath() -> String? {
    if let path = Bundle.main.path(forResource: "item_db_zh", ofType: "sqlite") {
        print("Database found at path: \(path)")
        return path
    } else {
        print("Database file not found in the bundle")
        return nil
    }
}

// 子页面：DatabaseCategoryPage
struct DatabaseCategoryPage: View {
    @State private var publishedCategories: [Category] = []
    @State private var unpublishedCategories: [Category] = []

    var body: some View {
        List {
            if !publishedCategories.isEmpty {
                Section(header: Text("Published")) {
                    ForEach(publishedCategories) { category in
                        NavigationLink(destination: Text("Category \(category.name) Details")) {
                            Text(category.name)
                        }
                    }
                }
            }

            if !unpublishedCategories.isEmpty {
                Section(header: Text("Unpublished")) {
                    ForEach(unpublishedCategories) { category in
                        NavigationLink(destination: Text("Category \(category.name) Details")) {
                            Text(category.name)
                        }
                    }
                }
            }
        }
        .navigationTitle("数据库")
        .onAppear {
            loadData()
        }
    }

    // 数据加载函数
    private func loadData() {
        guard let databasePath = getDatabasePath() else {
            print("Failed to find database")
            return
        }
        let (published, unpublished) = loadCategories(from: databasePath)
        publishedCategories = published
        unpublishedCategories = unpublished
    }
}

#Preview {
    DatabaseCategoryPage()
}
