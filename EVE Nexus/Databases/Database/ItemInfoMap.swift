import SwiftUI

enum ItemInfoMap {
    // 缓存结构，存储物品ID对应的分类信息
    private static var categoryCache: [Int: (categoryID: Int, groupID: Int?)] = [:]

    /// 初始化缓存，加载所有物品的分类信息
    static func initializeCache(databaseManager: DatabaseManager) {
        let query = """
            SELECT type_id, categoryID, groupID
            FROM types
            """

        if case let .success(rows) = databaseManager.executeQuery(query) {
            for row in rows {
                if let typeID = row["type_id"] as? Int,
                    let categoryID = row["categoryID"] as? Int
                {
                    let groupID = row["groupID"] as? Int
                    categoryCache[typeID] = (categoryID: categoryID, groupID: groupID)
                }
            }
        }
    }

    /// 根据物品ID返回对应的详情视图
    /// - Parameters:
    ///   - itemID: 物品ID
    ///   - databaseManager: 数据库管理器
    /// - Returns: 对应的详情视图类型
    static func getItemInfoView(
        itemID: Int,
        databaseManager: DatabaseManager
    ) -> AnyView {
        // 从缓存中获取分类信息
        guard let itemCategory = categoryCache[itemID] else {
            Logger.error("ItemInfoMap - 无法获取物品分类信息，itemID: \(itemID)")
            return AnyView(Text(NSLocalizedString("Item_load_error", comment: "")))
        }

        let categoryID = itemCategory.categoryID
        let groupID = itemCategory.groupID

        Logger.debug(
            "ItemInfoMap - 选择视图类型，itemID: \(itemID), categoryID: \(String(describing: categoryID)), groupID: \(String(describing: groupID))"
        )

        // 首先检查特定的categoryID和groupID组合
        if categoryID == 17 && groupID == 1964 {  // 突变质体
            return AnyView(ShowMutationInfo(itemID: itemID, databaseManager: databaseManager))
        }

        // 然后根据分类选择合适的视图类型
        switch categoryID {
        case 9, 34:  // 蓝图和冬眠者蓝图
            return AnyView(ShowBluePrintInfo(blueprintID: itemID, databaseManager: databaseManager))

        case 42, 43:  // 行星开发相关
            return AnyView(ShowPlanetaryInfo(itemID: itemID, databaseManager: databaseManager))

        default:  // 普通物品
            return AnyView(ShowItemInfo(databaseManager: databaseManager, itemID: itemID))
        }
    }
}
