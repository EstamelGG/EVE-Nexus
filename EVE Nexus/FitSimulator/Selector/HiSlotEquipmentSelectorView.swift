import SwiftUI

/// 高槽装备选择器视图
struct HiSlotEquipmentSelectorView: View {
    @ObservedObject var databaseManager: DatabaseManager

    // 添加选择槽位的信息和回调
    let slotFlag: FittingFlag
    let onModuleSelected: ((Int) -> Void)?
    /// 添加飞船ID
    let shipTypeID: Int

    /// 初始化方法
    init(
        databaseManager: DatabaseManager,
        slotFlag: FittingFlag,
        onModuleSelected: ((Int) -> Void)? = nil,
        shipTypeID: Int = 0
    ) {
        self.databaseManager = databaseManager
        self.slotFlag = slotFlag
        self.onModuleSelected = onModuleSelected
        self.shipTypeID = shipTypeID
    }

    var body: some View {
        SlotEquipmentSelectorView(
            databaseManager: databaseManager,
            config: SlotEquipmentSelectorConfig(
                title: NSLocalizedString("Fitting_Select_Item", comment: "选择装备"),
                parentGroupId: 9, // 使用舰船装备(ID: 9)作为父节点
                groupIDKey: shipTypeID > 0
                    ? "LastVisitedHighSlotGroupID_\(shipTypeID)" : "LastVisitedHighSlotGroupID",
                searchKey: shipTypeID > 0
                    ? "LastHighSlotSearchKeyword_\(shipTypeID)" : "LastHighSlotSearchKeyword",
                logTag: "高槽装备",
                loadAllowedTypeIDs: { databaseManager in
                    // 获取effect_id=12的高槽装备信息，并确保是已发布的(published=1)
                    SlotEquipmentSelectorQueries.loadTypeIDs(
                        databaseManager: databaseManager,
                        query: """
                            SELECT DISTINCT te.type_id, t.name, t.en_name, t.marketGroupID
                            FROM typeEffects te
                            JOIN types t ON te.type_id = t.type_id
                            WHERE te.effect_id = 12
                            AND t.published = 1
                        """,
                        logTag: "高槽装备"
                    )
                },
                onItemSelected: { item in onModuleSelected?(item.id) }
            )
        )
    }
}
