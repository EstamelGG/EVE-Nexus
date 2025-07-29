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
                dbManager.loadVariations(for: typeID)  // 直接返回(items, metaGroupNames)元组
            },
            searchData: nil  // 变体列表不需要搜索功能
        )
    }
}

extension DatabaseManager {
    // 获取变体数量
    func getVariationsCount(for typeID: Int) -> Int {
        // 首先获取父物品ID（如果当前物品有父物品）或当前物品ID（如果当前物品就是父物品）
        let parentQuery = """
                WITH RECURSIVE parent AS (
                    -- 基础查询：获取当前物品
                    SELECT type_id, variationParentTypeID
                    FROM types
                    WHERE type_id = ?

                    UNION ALL

                    -- 递归查询：获取父物品
                    SELECT t.type_id, t.variationParentTypeID
                    FROM types t
                    JOIN parent p ON t.type_id = p.variationParentTypeID
                )
                -- 获取最顶层的父物品ID或当前物品ID
                SELECT COALESCE(
                    (SELECT type_id FROM parent WHERE variationParentTypeID IS NULL LIMIT 1),
                    ?
                ) as parent_id
            """

        let parentResult = executeQuery(parentQuery, parameters: [typeID, typeID])
        var parentID = typeID

        if case let .success(rows) = parentResult,
            let row = rows.first,
            let id = row["parent_id"] as? Int
        {
            parentID = id
        }

        // 然后计算这个父物品的所有变体数量
        let query = """
                SELECT COUNT(*) as count
                FROM types
                WHERE type_id = ? OR variationParentTypeID = ?
            """

        let result = executeQuery(query, parameters: [parentID, parentID])

        switch result {
        case let .success(rows):
            if let row = rows.first,
                let count = row["count"] as? Int
            {
                return count
            }
        case let .error(error):
            Logger.error("获取变体数量失败: \(error)")
        }

        return 0
    }

    // 加载变体列表
    func loadVariations(for typeID: Int) -> ([DatabaseListItem], [Int: String]) {
        // 首先获取父物品ID
        let parentQuery = """
                WITH RECURSIVE parent AS (
                    -- 基础查询：获取当前物品
                    SELECT type_id, variationParentTypeID
                    FROM types
                    WHERE type_id = ?

                    UNION ALL

                    -- 递归查询：获取父物品
                    SELECT t.type_id, t.variationParentTypeID
                    FROM types t
                    JOIN parent p ON t.type_id = p.variationParentTypeID
                )
                -- 获取最顶层的父物品ID或当前物品ID
                SELECT COALESCE(
                    (SELECT type_id FROM parent WHERE variationParentTypeID IS NULL LIMIT 1),
                    ?
                ) as parent_id
            """

        let parentResult = executeQuery(parentQuery, parameters: [typeID, typeID])
        var parentID = typeID

        if case let .success(rows) = parentResult,
            let row = rows.first,
            let id = row["parent_id"] as? Int
        {
            parentID = id
        }

        // 获取所有 metaGroups 的名称
        let metaQuery = """
                SELECT metagroup_id, name 
                FROM metaGroups 
                ORDER BY metagroup_id ASC
            """
        let metaResult = executeQuery(metaQuery)
        var metaGroupNames: [Int: String] = [:]

        if case let .success(metaRows) = metaResult {
            for row in metaRows {
                if let id = row["metagroup_id"] as? Int,
                    let name = row["name"] as? String
                {
                    metaGroupNames[id] = name
                }
            }
        }

        // 然后获取这个父物品的所有变体
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

        let result = executeQuery(query, parameters: [parentID, parentID])
        var items: [DatabaseListItem] = []

        switch result {
        case let .success(rows):
            for row in rows {
                guard let id = row["type_id"] as? Int,
                    let name = row["name"] as? String,
                    let enName = row["en_name"] as? String,
                    let iconFilename = row["icon_filename"] as? String,
                    let categoryId = row["categoryID"] as? Int,
                    let metaGroupId = row["metaGroupID"] as? Int
                else {
                    continue
                }

                let isPublished = (row["published"] as? Int ?? 0) != 0

                let item = DatabaseListItem(
                    id: id,
                    name: name,
                    enName: enName,
                    iconFileName: iconFilename.isEmpty
                        ? DatabaseConfig.defaultItemIcon : iconFilename,
                    published: isPublished,
                    categoryID: categoryId,
                    groupID: nil,
                    groupName: nil,
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
                    marketGroupID: nil,
                    navigationDestination: AnyView(
                        ItemInfoMap.getItemInfoView(
                            itemID: id,
                            databaseManager: self
                        )
                    )
                )

                items.append(item)
            }

        case let .error(error):
            Logger.error("加载变体失败: \(error)")
        }

        return (items, metaGroupNames)  // 返回物品列表和metaGroupNames
    }
}
