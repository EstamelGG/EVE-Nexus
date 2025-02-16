import SwiftUI

struct ItemInfoMap {
    /// 根据物品的categoryID返回对应的详情视图
    /// - Parameters:
    ///   - itemID: 物品ID
    ///   - categoryID: 物品分类ID
    ///   - databaseManager: 数据库管理器
    /// - Returns: 对应的详情视图类型
    static func getItemInfoView(itemID: Int, categoryID: Int, databaseManager: DatabaseManager) -> AnyView {
        Logger.debug("ItemInfoMap - 选择视图类型，itemID: \(itemID), categoryID: \(categoryID)")
        
        // 仅根据分类选择合适的视图类型
        switch categoryID {
        case 9, 34: // 蓝图和冬眠者蓝图
            return AnyView(ShowBluePrintInfo(blueprintID: itemID, databaseManager: databaseManager))
            
        case 42, 43: // 行星开发相关
            return AnyView(ShowPlanetaryInfo(itemID: itemID, databaseManager: databaseManager))
            
        default: // 普通物品
            return AnyView(ShowItemInfo(databaseManager: databaseManager, itemID: itemID))
        }
    }
} 
