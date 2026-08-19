import SwiftUI

/// 植入体选择器
struct ImplantSelectorView: View {
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
                    format: NSLocalizedString("Implant_Slot_Num", comment: "植入体槽位 %d"), slotNumber
                ),
                logTag: "植入体",
                loadItems: { databaseManager in
                    // 获取指定槽位的植入体信息
                    let result = FlatItemSelectorQueries.loadSlottedItems(
                        databaseManager: databaseManager,
                        attributeID: 331,
                        slotValue: Double(slotNumber),
                        logTag: "植入体"
                    )
                    return (result.items, [:])
                },
                onSelect: { item, _ in onSelect(item) },
                removeLabel: hasExistingItem
                    ? NSLocalizedString("Remove_Current_Implant", comment: "移除现有植入体") : nil,
                onRemove: onRemove
            )
        )
    }
}
