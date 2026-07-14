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
                    (
                        FlatItemSelectorQueries.loadItems(
                            databaseManager: databaseManager,
                            query: """
                                SELECT t.type_id as id, t.name, t.en_name, t.published, t.icon_filename as iconFileName,
                                       t.categoryID, t.groupID, t.group_name as groupName
                                FROM types t
                                JOIN typeAttributes ta ON t.type_id = ta.type_id
                                WHERE ta.attribute_id = 331
                                AND ta.value = ?
                                AND t.published = 1
                                AND t.marketGroupID IS NOT NULL
                                ORDER BY t.name
                            """,
                            parameters: [slotNumber],
                            logTag: "植入体"
                        ),
                        [:]
                    )
                },
                onSelect: { item, _ in onSelect(item) },
                removeLabel: hasExistingItem
                    ? NSLocalizedString("Remove_Current_Implant", comment: "移除现有植入体") : nil,
                onRemove: onRemove
            )
        )
    }
}
