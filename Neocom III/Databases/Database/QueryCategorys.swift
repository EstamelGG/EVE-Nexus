import SQLite3

// Data model
struct Category: Identifiable {
    let id: Int
    let name: String
    let published: Bool
    let iconID: Int
    let iconFileNew: String
}

private let categoryIconMapping: [Int: String] = [
    0: "items_7_64_4.png",
    1: "items_70_128_11.png",
    2: "items_30_64_4.png",
    3: "items_27_64_16.png",
    5: "icon_44992_64.png",
    6: "items_26_64_2.png",
    7: "items_2_64_11.png",
    8: "items_5_64_2.png",
    9: "icon_1002_64.png",
    10: "items_6_64_3.png",
    11: "items_26_64_10.png",
    14: "items_modules_fleetboost_infobase.png",
    17: "items_49_64_1.png",
    18: "icon_2454_64.png",
    20: "items_40_64_16.png",
    22: "icon_33475_64.png",
    23: "icon_12239_64.png",
    24: "items_comprfuel_amarr.png",
    25: "items_inventory_moonasteroid_r4.png",
    30: "items_inventory_cratexvishirt.png",
    32: "items_76_64_7.png",
    34: "items_55_64_15.png",
    35: "items_55_64_11.png",
    39: "items_95_64_6.png",
    40: "icon_32458_64.png",
    41: "icon_2133_64.png",
    42: "items_97_64_10.png",
    43: "items_99_64_8.png",
    46: "icon_2233_64.png",
    63: "icon_19658_64.png",
    65: "icon_40340_64.png",
    66: "icon_35923_64.png",
    87: "icon_23061_64.png",
]

class QueryCategory {
    static func loadCategories(from db: OpaquePointer?) -> ([Category], [Category]) {
        var publishedCategories: [Category] = []
        var unpublishedCategories: [Category] = []
        
        // 确保 db 是有效的
        guard let db = db else {
            return ([], []) // 如果 db 为 nil，返回空数据
        }

        let query = """
        SELECT category_id, name, published, iconID FROM categories ORDER BY category_id
        """
        
        let categories: [Category] = executeQuery(
            db: db,
            query: query, bindParams: [], bind: nil,
            resultProcessor: { statement in
                let id = Int(sqlite3_column_int(statement, 0))
                let name = String(cString: sqlite3_column_text(statement, 1))
                let published = sqlite3_column_int(statement, 2) != 0
                let iconID = Int(sqlite3_column_int(statement, 3))
                
                // 处理 iconFileNew
                var iconFileNew: String
                if let mappedIconFile = categoryIconMapping[id] {
                    iconFileNew = mappedIconFile
                } else {
                    iconFileNew = SelectIconName(from: db, iconID: iconID)
                }
                
                if iconFileNew.isEmpty {
                    iconFileNew = "items_73_16_50.png"
                }

                // 创建 Category 对象并返回
                return Category(id: id, name: name, published: published, iconID: iconID, iconFileNew: iconFileNew)
            }
        )
        
        // 将分类按 published 字段分组
        publishedCategories = categories.filter { $0.published }
        unpublishedCategories = categories.filter { !$0.published }

        return (publishedCategories, unpublishedCategories)
    }
}
