import SwiftUI

/// 子系统槽装备选择器视图
struct SubSysSlotEquipmentSelectorView: View {
    @ObservedObject var databaseManager: DatabaseManager

    /// 船只ID，用于查询匹配的子系统
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
                parentGroupId: 1112, // 使用子系统(ID: 1112)作为父节点
                groupIDKey: "LastVisitedSubSysSlotGroupID_\(shipTypeID)",
                searchKey: "LastSubSysSlotSearchKeyword_\(shipTypeID)",
                logTag: "子系统",
                loadAllowedTypeIDs: { databaseManager in
                    // 获取effect_id=3772且匹配当前飞船的子系统装备信息，并确保是已发布的(published=1)
                    SlotEquipmentSelectorQueries.loadTypeIDs(
                        databaseManager: databaseManager,
                        query: """
                            SELECT DISTINCT te.type_id, t.name, t.en_name, t.marketGroupID
                            FROM typeEffects te
                            INNER JOIN typeAttributes ta ON te.type_id = ta.type_id
                            JOIN types t ON te.type_id = t.type_id
                            WHERE te.effect_id = 3772
                            AND ta.attribute_id = 1380 
                            AND ta.value = \(shipTypeID)
                            AND t.published = 1
                        """,
                        logTag: "子系统装备"
                    )
                },
                onItemSelected: { item in onModuleSelected?(item.id) }
            )
        )
    }
}
