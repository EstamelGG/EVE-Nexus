import SwiftUI
import SQLite3

// Data model
struct Category: Identifiable {
    let id: Int
    let name: String
    let published: Bool
    let iconID: Int
}

// SearchBar view
struct SearchBar: View {
    @Binding var text: String
    
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
        }
    }
}

struct DatabaseCategoryPage: View {
    @ObservedObject var databaseManager: DatabaseManager // 使用传递的数据库管理器
    @State private var publishedCategories: [Category] = []
    @State private var unpublishedCategories: [Category] = []
    
    // Search text
    @State private var searchText: String = ""

    var body: some View {
        VStack {
            // Search bar
            SearchBar(text: $searchText)
                .padding(.top)

            // List
            List {
                if !publishedCategories.isEmpty {
                    Section(header: Text(NSLocalizedString("Main_Database_published", comment: ""))) {
                        ForEach(publishedCategories) { category in
                            NavigationLink(destination: Text("Category \(category.name) Details")) {
                                Text(category.name)
                            }
                        }
                    }
                }

                if !unpublishedCategories.isEmpty {
                    Section(header: Text(NSLocalizedString("Main_Database_unpublished", comment: ""))) {
                        ForEach(unpublishedCategories) { category in
                            NavigationLink(destination: Text("Category \(category.name) Details")) {
                                Text(category.name)
                            }
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Main_Database_title", comment: ""))
            .onAppear {
                loadData()
            }
        }
    }

    // Load categories from the database
    private func loadData() {
        guard let db = databaseManager.db else {
            print("Database not available")
            return
        }

        // Load categories using the open database
        let (published, unpublished) = loadCategories(from: db)
        publishedCategories = published
        unpublishedCategories = unpublished
    }

    // Load categories from the database
    private func loadCategories(from db: OpaquePointer) -> ([Category], [Category]) {
        var publishedCategories: [Category] = []
        var unpublishedCategories: [Category] = []

        let query = "SELECT category_id, name, published, iconID FROM categories ORDER BY category_id"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = Int(sqlite3_column_int(statement, 0))
                let name = String(cString: sqlite3_column_text(statement, 1))
                let published = sqlite3_column_int(statement, 2) != 0
                let iconID = Int(sqlite3_column_int(statement, 3))
                let category = Category(id: id, name: name, published: published, iconID: iconID)
                if published {
                    publishedCategories.append(category)
                } else {
                    unpublishedCategories.append(category)
                }
            }
            sqlite3_finalize(statement)
        } else {
            print("Failed to prepare statement")
        }

        return (publishedCategories, unpublishedCategories)
    }
}
