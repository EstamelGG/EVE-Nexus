import SwiftUI

struct ItemInfoMap {
    /// 根据物品的categoryID返回对应的详情视图
    /// - Parameters:
    ///   - itemID: 物品ID
    ///   - categoryID: 物品分类ID
    ///   - databaseManager: 数据库管理器
    /// - Returns: 对应的详情视图
    static func getItemInfoView(itemID: Int, categoryID: Int, databaseManager: DatabaseManager) -> AnyView {
        Logger.debug("ItemInfoMap - 开始创建视图，itemID: \(itemID), categoryID: \(categoryID)")
        
        switch categoryID {
        case 9: // 蓝图
            Logger.debug("ItemInfoMap - 创建蓝图视图")
            return AnyView(
                ShowBluePrintInfo(
                    blueprintID: itemID,
                    databaseManager: databaseManager
                )
            )
        case 34: // 冬眠者蓝图
            Logger.debug("ItemInfoMap - 创建冬眠者蓝图视图")
            return AnyView(
                ShowBluePrintInfo(
                    blueprintID: itemID,
                    databaseManager: databaseManager
                )
            )
        case 42: // 行星开发 - 商品
            Logger.debug("ItemInfoMap - 创建行星商品视图")
            return AnyView(
                ShowPlanetaryInfo(
                    itemID: itemID,
                    databaseManager: databaseManager
                )
            )
        case 43: // 行星开发 - 资源
            Logger.debug("ItemInfoMap - 创建行星资源视图")
            return AnyView(
                ShowPlanetaryInfo(
                    itemID: itemID,
                    databaseManager: databaseManager
                )
            )
        default: // 默认显示普通物品信息
            Logger.debug("ItemInfoMap - 创建普通物品视图")
            return AnyView(
                ShowItemInfo(
                    databaseManager: databaseManager,
                    itemID: itemID
                )
            )
        }
    }
} 
