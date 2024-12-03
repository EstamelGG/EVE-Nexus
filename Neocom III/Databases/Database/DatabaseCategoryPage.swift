import SwiftUI
import SQLite3

// Data model
struct Category: Identifiable {
    let id: Int
    let name: String
    let published: Bool
    let iconID: Int
    let iconFileNew: String
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
                    Section(header: Text(NSLocalizedString("Main_Database_published", comment: "")).font(.title3)) {
                        ForEach(publishedCategories) { category in
                            NavigationLink(destination: DatabaseGroupPage(databaseManager: databaseManager, categoryID: category.id, categoryName: category.name)) {
                                HStack {
                                    // 使用 IconManager 加载图片
                                    IconManager.shared.loadImage(for: category.iconFileNew)
                                        .resizable()
                                        .frame(width: 36, height: 36)
                                    Text(category.name)
                                }
                            }
                        }
                    }
                }

                if !unpublishedCategories.isEmpty {
                    Section(header: Text(NSLocalizedString("Main_Database_unpublished", comment: "")).font(.title3)) {
                        ForEach(unpublishedCategories) { category in
                            NavigationLink(destination: DatabaseGroupPage(databaseManager: databaseManager, categoryID: category.id, categoryName: category.name)) {
                                HStack {
                                    // 使用 IconManager 加载图片
                                    IconManager.shared.loadImage(for: category.iconFileNew)
                                        .resizable()
                                        .frame(width: 36, height: 36)
                                    Text(category.name)
                                }
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

    private let categoryIconMapping: [Int: String] = [
        0: "items_7_64_4.png",
        1: "items_70_128_11.png",
        2: "items_30_64_4.png",
        3: "items_27_64_16.png",
        6: "items_26_64_2.png",
        7: "items_2_64_11.png",
        8: "items_5_64_2.png",
        10: "items_6_64_3.png",
        11: "items_26_64_10.png",
        14: "items_modules_fleetboost_infobase.png",
        17: "items_49_64_1.png",
        18: "items_105_32_48.png",
        20: "items_40_64_16.png",
        22: "items_40_64_14.png",
        23: "items_76_64_2.png",
        24: "items_comprfuel_amarr.png",
        25: "items_inventory_moonasteroid_r4.png",
        30: "items_inventory_cratexvishirt.png",
        32: "items_76_64_7.png",
        34: "items_55_64_15.png",
        35: "items_55_64_11.png",
        39: "items_95_64_6.png",
        41: "items_102_128_2.png",
        42: "items_97_64_10.png",
        43: "items_99_64_8.png",
        65: "items_127_64_3.png",
        66: "items_123_64_11.png",
        87: "items_36_64_13.png",
    ]
    
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

                // 获取 iconFile_new 值
                let iconFileNew = getIconFileNew(from: db, iconID: iconID, category_id: id)
                
                let category = Category(id: id, name: name, published: published, iconID: iconID, iconFileNew: iconFileNew)
                
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
    
    private func getIconFileNew(from db: OpaquePointer, iconID: Int, category_id: Int) -> String {
        if let mappedIconFile = categoryIconMapping[category_id] {
            return mappedIconFile
        }
        if iconID == 0 {
                return "items_73_16_50.png"
            }
        let query = "SELECT iconFile_new FROM iconIDs WHERE icon_id = ?"
        var statement: OpaquePointer?
        var iconFileNew = ""

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(iconID))

            if sqlite3_step(statement) == SQLITE_ROW {
                // 获取 iconFile_new 字段
                if let iconFileNewPointer = sqlite3_column_text(statement, 0) {
                    iconFileNew = String(cString: iconFileNewPointer)
                    if iconFileNew.isEmpty{
                        iconFileNew = "items_73_16_50.png"
                    }
                }
            }
            sqlite3_finalize(statement)
        } else {
            print("Failed to prepare iconIDs query")
        }

        return iconFileNew
    }
}
