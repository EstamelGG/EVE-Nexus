import SwiftUI

/// 全部植入体选择器
struct AllImplantsSelector: View {
    @ObservedObject var databaseManager: DatabaseManager

    let onSelect: (DatabaseListItem, Int) -> Void // 选择回调，包含物品和槽位号

    var body: some View {
        FlatItemSelectorView(
            databaseManager: databaseManager,
            config: FlatItemSelectorConfig(
                title: NSLocalizedString("Implant_Select_Implants", comment: "选择植入体"),
                logTag: "植入体",
                loadItems: { databaseManager in
                    // 获取所有植入体信息和槽位号
                    FlatItemSelectorQueries.loadItemsWithGroup(
                        databaseManager: databaseManager,
                        query: """
                            SELECT t.type_id as id, t.name, t.published, t.icon_filename as iconFileName,
                                   t.categoryID, t.groupID, t.group_name as groupName,
                                   ta.value as slotNumber,
                                   t.en_name
                            FROM types t
                            JOIN typeAttributes ta ON t.type_id = ta.type_id
                            WHERE ta.attribute_id = 331
                            AND t.published = 1
                            AND t.marketGroupID IS NOT NULL
                            ORDER BY t.name
                        """,
                        logTag: "植入体"
                    )
                },
                onSelect: { item, slotNumber in
                    if let slotNumber = slotNumber {
                        onSelect(item, slotNumber)
                    }
                },
                groupTitle: { slotNumber in
                    String(
                        format: NSLocalizedString("Implant_Slot_Num", comment: "植入体槽位 %d"),
                        slotNumber
                    )
                }
            )
        )
    }
}
