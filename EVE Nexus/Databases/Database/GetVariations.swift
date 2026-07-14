import Foundation
import SwiftUI

struct VariationsView: View {
    @ObservedObject var databaseManager: DatabaseManager
    let typeID: Int

    var body: some View {
        DatabaseListView(
            databaseManager: databaseManager,
            title: NSLocalizedString("Main_Database_Variations", comment: ""),
            groupingType: .metaGroups,
            loadData: { dbManager in
                dbManager.loadVariations(for: typeID)
            },
            searchData: nil
        )
    }
}

extension DatabaseManager {
    /// 解析变体树顶层父物品 ID（无父物品时返回自身）
    private func resolveVariationParentID(for typeID: Int) -> Int {
        SDEMemoryStore.resolveVariationParent(for: typeID)
    }

    /// 获取变体数量
    func getVariationsCount(for typeID: Int) -> Int {
        SDEMemoryStore.variationsCount(for: typeID)
    }

    /// 加载变体列表
    func loadVariations(for typeID: Int) -> ([DatabaseListItem], [Int: String]) {
        let parentID = resolveVariationParentID(for: typeID)

        let metaGroupNames = SDEMemoryStore.localizedMetaGroupNames

        let query = """
            SELECT type_id, name, en_name, icon_filename, published, categoryID,
                   pg_need, cpu_need, rig_cost,
                   em_damage, them_damage, kin_damage, exp_damage,
                   high_slot, mid_slot, low_slot, rig_slot,
                   gun_slot, miss_slot, metaGroupID
            FROM types
            WHERE type_id = ? OR variationParentTypeID = ?
            ORDER BY metaGroupID, name
        """

        var items: [DatabaseListItem] = []
        switch executeQuery(query, parameters: [parentID, parentID]) {
        case let .success(rows):
            for row in rows {
                guard let id = row["type_id"] as? Int,
                      let name = row["name"] as? String,
                      let enName = row["en_name"] as? String,
                      let iconFilename = row["icon_filename"] as? String,
                      let categoryId = row["categoryID"] as? Int,
                      let metaGroupId = row["metaGroupID"] as? Int
                else { continue }

                items.append(
                    DatabaseListItem(
                        id: id,
                        name: name,
                        enName: enName,
                        iconFileName: iconFilename.isEmpty
                            ? IconManager.defaultItemIcon : iconFilename,
                        published: (row["published"] as? Int ?? 0) != 0,
                        categoryID: categoryId,
                        pgNeed: row["pg_need"] as? Double,
                        cpuNeed: row["cpu_need"] as? Double,
                        rigCost: row["rig_cost"] as? Int,
                        emDamage: row["em_damage"] as? Double,
                        themDamage: row["them_damage"] as? Double,
                        kinDamage: row["kin_damage"] as? Double,
                        expDamage: row["exp_damage"] as? Double,
                        highSlot: row["high_slot"] as? Int,
                        midSlot: row["mid_slot"] as? Int,
                        lowSlot: row["low_slot"] as? Int,
                        rigSlot: row["rig_slot"] as? Int,
                        gunSlot: row["gun_slot"] as? Int,
                        missSlot: row["miss_slot"] as? Int,
                        metaGroupID: metaGroupId,
                        navigationDestination: AnyView(
                            ItemInfoMap.getItemInfoView(itemID: id, databaseManager: self)
                        )
                    )
                )
            }

        case let .error(error):
            Logger.error("加载变体失败: \(error)")
        }

        return (items, metaGroupNames)
    }
}
