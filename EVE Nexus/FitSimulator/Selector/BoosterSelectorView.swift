import SwiftUI

/// 增效剂选择器
struct BoosterSelectorView: View {
    @ObservedObject var databaseManager: DatabaseManager
    let slotNumber: Int
    let hasExistingItem: Bool

    let onSelect: (DatabaseListItem) -> Void
    let onRemove: (() -> Void)?

    var body: some View {
        FlatItemSelectorView(
            databaseManager: databaseManager,
            config: FlatItemSelectorConfig(
                title: String(
                    format: NSLocalizedString("Booster_Slot_Num", comment: "增效剂槽位 %d"), slotNumber
                ),
                logTag: "增效剂",
                loadItems: { databaseManager in
                    // 获取指定槽位的增效剂信息
                    let result = FlatItemSelectorQueries.loadSlottedItems(
                        databaseManager: databaseManager,
                        attributeID: 1087,
                        slotValue: Double(slotNumber),
                        logTag: "增效剂"
                    )
                    return (result.items, [:])
                },
                onSelect: { item, _ in onSelect(item) },
                removeLabel: hasExistingItem
                    ? NSLocalizedString("Remove_Current_Booster", comment: "移除现有增效剂") : nil,
                onRemove: onRemove
            )
        )
    }
}
