import SwiftUI

/// 改装槽装备选择器视图
struct RigSlotEquipmentSelectorView: View {
    @ObservedObject var databaseManager: DatabaseManager

    /// 船只ID，用于查询匹配的改装件
    let shipTypeID: Int
    // 添加槽位信息和回调函数
    let slotFlag: FittingFlag
    let onModuleSelected: ((Int) -> Void)?

    /// 初始化方法
    init(
        databaseManager: DatabaseManager,
        shipTypeID: Int,
        slotFlag: FittingFlag,
        onModuleSelected: ((Int) -> Void)? = nil
    ) {
        self.databaseManager = databaseManager
        self.shipTypeID = shipTypeID
        self.slotFlag = slotFlag
        self.onModuleSelected = onModuleSelected
    }

    var body: some View {
        SlotEquipmentSelectorView(
            databaseManager: databaseManager,
            config: SlotEquipmentSelectorConfig(
                title: NSLocalizedString("Fitting_Select_Item", comment: "选择装备"),
                parentGroupId: 1111, // 使用改装件(ID: 1111)作为父节点
                groupIDKey: "LastVisitedRigSlotGroupID_\(shipTypeID)",
                searchKey: "LastRigSlotSearchKeyword_\(shipTypeID)",
                logTag: "改装件",
                loadAllowedTypeIDs: { databaseManager in
                    // 获取effect_id=2663且尺寸匹配当前飞船的改装件装备信息，并确保是已发布的(published=1)
                    SlotEquipmentSelectorQueries.loadTypeIDs(
                        databaseManager: databaseManager,
                        query: """
                            SELECT DISTINCT te.type_id, t.name, t.en_name, t.marketGroupID
                            FROM typeEffects te
                            JOIN typeAttributes ta1 ON te.type_id = ta1.type_id
                            JOIN types t ON te.type_id = t.type_id
                            JOIN (
                                SELECT value
                                FROM typeAttributes
                                WHERE attribute_id = 1547 AND type_id = \(shipTypeID)
                            ) ship ON ta1.value = ship.value
                            WHERE te.effect_id = 2663 --- 属于改装件槽位
                            AND ta1.attribute_id = 1547 -- 改装件尺寸
                            AND t.published = 1
                        """,
                        logTag: "改装件装备"
                    )
                },
                onItemSelected: { item in onModuleSelected?(item.id) }
            )
        )
    }
}
