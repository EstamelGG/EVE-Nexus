import SwiftUI

/// 全部增效剂选择器
struct AllBoosterSelector: View {
    @ObservedObject var databaseManager: DatabaseManager

    let onSelect: (DatabaseListItem, Int) -> Void // 选择回调，包含物品和槽位号

    var body: some View {
        FlatItemSelectorView(
            databaseManager: databaseManager,
            config: FlatItemSelectorConfig(
                title: NSLocalizedString("Implant_Select_Boosters", comment: "选择增效剂"),
                logTag: "增效剂",
                loadItems: { databaseManager in
                    // 获取所有增效剂信息，包含槽位号
                    FlatItemSelectorQueries.loadSlottedItems(
                        databaseManager: databaseManager,
                        attributeID: 1087,
                        logTag: "增效剂"
                    )
                },
                onSelect: { item, slotNumber in
                    if let slotNumber = slotNumber {
                        onSelect(item, slotNumber)
                    }
                },
                groupTitle: { slotNumber in
                    String(
                        format: NSLocalizedString("Booster_Slot_Num", comment: "增效剂槽位 %d"),
                        slotNumber
                    )
                }
            )
        )
    }
}
