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
                    (
                        FlatItemSelectorQueries.loadItems(
                            databaseManager: databaseManager,
                            query: """
                                SELECT t.type_id as id, t.name, t.en_name, t.published, t.icon_filename as iconFileName,
                                       t.categoryID, t.groupID, t.group_name as groupName
                                FROM types t
                                JOIN typeAttributes ta ON t.type_id = ta.type_id
                                WHERE ta.attribute_id = 1087
                                AND ta.value = ?
                                AND t.published = 1
                                AND t.marketGroupID IS NOT NULL
                                ORDER BY t.name
                            """,
                            parameters: [slotNumber],
                            logTag: "增效剂"
                        ),
                        [:]
                    )
                },
                onSelect: { item, _ in onSelect(item) },
                removeLabel: hasExistingItem
                    ? NSLocalizedString("Remove_Current_Booster", comment: "移除现有增效剂") : nil,
                onRemove: onRemove
            )
        )
    }
}
