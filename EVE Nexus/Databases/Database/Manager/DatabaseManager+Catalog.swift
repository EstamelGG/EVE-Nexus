import Foundation
import SwiftUI

extension DatabaseManager {
    func loadCategories() -> ([Category], [Category]) {
        var published: [Category] = []
        var unpublished: [Category] = []
        for category in SDEMemoryStore.categories.values.sorted(by: { $0.id < $1.id }) {
            let item = Category(
                id: category.id,
                name: category.name,
                enName: category.enName,
                published: category.published,
                iconID: category.id,
                iconFileNew: category.iconFilename
            )
            if category.published {
                published.append(item)
            } else {
                unpublished.append(item)
            }
        }
        return (published, unpublished)
    }

    /// 加载组
    func loadGroups(for categoryID: Int) -> ([TypeGroup], [TypeGroup]) {
        var published: [TypeGroup] = []
        var unpublished: [TypeGroup] = []
        for group in SDEMemoryStore.groups(inCategory: categoryID) {
            let item = TypeGroup(
                id: group.id,
                name: group.name,
                enName: group.enName,
                iconID: group.id,
                categoryID: group.categoryID,
                published: group.published,
                icon_filename: group.iconFilename
            )
            if group.published {
                published.append(item)
            } else {
                unpublished.append(item)
            }
        }
        return (published, unpublished)
    }

    /// 加载物品（按 metaGroupID、名称排序）
    func loadItems(for groupID: Int, groupName: String) -> ([DatabaseListItem], [Int: String]) {
        let metaGroupNames = SDEMemoryStore.localizedMetaGroupNames

        let query = """
            SELECT t.type_id, t.name, t.en_name, t.icon_filename, t.published, t.metaGroupID, t.categoryID,
                   t.pg_need, t.cpu_need, t.rig_cost, 
                   t.em_damage, t.them_damage, t.kin_damage, t.exp_damage,
                   t.high_slot, t.mid_slot, t.low_slot, t.rig_slot, t.gun_slot, t.miss_slot
            FROM types t
            WHERE t.groupID = ?
            ORDER BY t.name ASC
        """

        let result = executeQuery(query, parameters: [groupID])

        var items: [DatabaseListItem] = []

        switch result {
        case let .success(rows):
            for row in rows {
                guard let typeId = row["type_id"] as? Int,
                      let name = row["name"] as? String,
                      let enName = row["en_name"] as? String,
                      let metaGroupId = row["metaGroupID"] as? Int,
                      let categoryId = row["categoryID"] as? Int,
                      let isPublished = row["published"] as? Int
                else {
                    Logger.warning("物品基础数据不完整: \(row)")
                    continue
                }

                let iconFilename = (row["icon_filename"] as? String) ?? ""

                items.append(
                    DatabaseListItem(
                        id: typeId,
                        name: name,
                        enName: enName,
                        iconFileName: iconFilename.isEmpty
                            ? IconManager.defaultItemIcon : iconFilename,
                        published: isPublished != 0,
                        categoryID: categoryId,
                        groupID: groupID,
                        groupName: groupName,
                        pgNeed: row["pg_need"] as? Double,
                        cpuNeed: row["cpu_need"] as? Double,
                        rigCost: row["rig_cost"] as? Int,
                        emDamage: row["em_damage"] as? Double
                            ?? (row["em_damage"] as? Int).map { Double($0) },
                        themDamage: row["them_damage"] as? Double
                            ?? (row["them_damage"] as? Int).map { Double($0) },
                        kinDamage: row["kin_damage"] as? Double
                            ?? (row["kin_damage"] as? Int).map { Double($0) },
                        expDamage: row["exp_damage"] as? Double
                            ?? (row["exp_damage"] as? Int).map { Double($0) },
                        highSlot: row["high_slot"] as? Int,
                        midSlot: row["mid_slot"] as? Int,
                        lowSlot: row["low_slot"] as? Int,
                        rigSlot: row["rig_slot"] as? Int,
                        gunSlot: row["gun_slot"] as? Int,
                        missSlot: row["miss_slot"] as? Int,
                        metaGroupID: metaGroupId,
                        navigationDestination: ItemInfoMap.getItemInfoView(
                            itemID: typeId,
                            databaseManager: self
                        )
                    )
                )
            }

        case let .error(error):
            Logger.error("加载物品失败: \(error)")
        }

        // 按 metaGroupID、名称排序
        items.sort {
            if $0.metaGroupID != $1.metaGroupID {
                return ($0.metaGroupID ?? -1) < ($1.metaGroupID ?? -1)
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        return (items, metaGroupNames)
    }

    /// 搜索物品（无数量上限，由展示层按目录树承载索引）
    func searchItems(searchText: String, categoryID: Int? = nil, groupID: Int? = nil) -> (
        [DatabaseListItem], [Int: String], [Int: String]
    ) {
        Logger.info("Search: \(searchText)")
        var query = """
            SELECT t.type_id as id, t.name, t.en_name, t.published, t.icon_filename as iconFileName,
                   t.categoryID, t.groupID, t.metaGroupID, t.marketGroupID,
                   t.pg_need as pgNeed, t.cpu_need as cpuNeed, t.rig_cost as rigCost,
                   t.em_damage as emDamage, t.them_damage as themDamage, t.kin_damage as kinDamage, t.exp_damage as expDamage,
                   t.high_slot as highSlot, t.mid_slot as midSlot, t.low_slot as lowSlot,
                   t.rig_slot as rigSlot, t.gun_slot as gunSlot, t.miss_slot as missSlot,
                   t.group_name as groupName
            FROM types t
            WHERE \(LocalizedText.typeLangNameLikeSQL) OR t.type_id = ?
        """

        var parameters: [Any] = LocalizedText.typeLangNameLikeParams(searchText) + ["\(searchText)"]

        if let categoryID = categoryID {
            query += " AND t.categoryID = ?"
            parameters.append(categoryID)
        }

        if let groupID = groupID {
            query += " AND t.groupID = ?"
            parameters.append(groupID)
        }

        // 精确匹配（分隔符夹逼全等）排在最前
        query += " ORDER BY CASE WHEN \(LocalizedText.typeLangNameExactSQL) THEN 0 ELSE 1 END, t.groupID, t.metaGroupID"
        parameters.append(contentsOf: LocalizedText.typeLangNameExactParams(searchText))
        let result = executeQuery(query, parameters: parameters)
        var items: [DatabaseListItem] = []
        var groupNames: [Int: String] = [:]

        if case let .success(rows) = result {
            for row in rows {
                if let id = row["id"] as? Int,
                   let name = row["name"] as? String,
                   let categoryId = row["categoryID"] as? Int
                {
                    let enName = row["en_name"] as? String
                    let iconFileName = (row["iconFileName"] as? String) ?? "not_found"
                    let published = (row["published"] as? Int) ?? 0
                    let groupID = row["groupID"] as? Int
                    let groupName = row["groupName"] as? String

                    // 保存组名到字典中
                    if let gID = groupID, let gName = groupName {
                        groupNames[gID] = gName
                    }

                    items.append(
                        DatabaseListItem(
                            id: id,
                            name: name,
                            enName: enName,
                            iconFileName: iconFileName,
                            published: published == 1,
                            categoryID: categoryId,
                            groupID: groupID,
                            groupName: groupName,
                            pgNeed: row["pgNeed"] as? Double,
                            cpuNeed: row["cpuNeed"] as? Double,
                            rigCost: row["rigCost"] as? Int,
                            emDamage: row["emDamage"] as? Double,
                            themDamage: row["themDamage"] as? Double,
                            kinDamage: row["kinDamage"] as? Double,
                            expDamage: row["expDamage"] as? Double,
                            highSlot: row["highSlot"] as? Int,
                            midSlot: row["midSlot"] as? Int,
                            lowSlot: row["lowSlot"] as? Int,
                            rigSlot: row["rigSlot"] as? Int,
                            gunSlot: row["gunSlot"] as? Int,
                            missSlot: row["missSlot"] as? Int,
                            metaGroupID: row["metaGroupID"] as? Int,
                            marketGroupID: row["marketGroupID"] as? Int,
                            attributeCompareEligible: false,
                            navigationDestination: ItemInfoMap.getItemInfoView(
                                itemID: id,
                                databaseManager: self
                            )
                        )
                    )
                }
            }
        }

        // 获取 metaGroup 名称
        let metaGroupIDs = Set(items.compactMap { $0.metaGroupID })
        let metaGroupNames = loadMetaGroupNames(for: Array(metaGroupIDs))

        return (items, metaGroupNames, groupNames)
    }

    /// 加载 MetaGroup 名称
    func loadMetaGroupNames(for metaGroupIDs: [Int]) -> [Int: String] {
        if metaGroupIDs.isEmpty { return [:] }
        var names: [Int: String] = [:]
        for id in metaGroupIDs {
            if let name = SDEMemoryStore.metaGroupName(for: id) {
                names[id] = name
            }
        }
        return names
    }

    func getCategoryID(for typeID: Int) -> Int? {
        SDEMemoryStore.type(for: typeID)?.categoryID
    }

    /// 获取物品详情（描述文本来自 texts.zip / ItemTextStore）
    func getItemDetails(for typeID: Int) -> ItemDetails? {
        // 从 SDEMemoryStore 内存索引获取，避免每次打开物品详情都执行一次重 SQL
        guard let info = SDEMemoryStore.type(for: typeID) else { return nil }
        let groupName = info.groupID.flatMap { SDEMemoryStore.group(for: $0)?.name } ?? ""
        let categoryName = SDEMemoryStore.category(for: info.categoryID)?.name ?? ""
        let description = ItemTextStore.shared.text(for: info.descID)

        return ItemDetails(
            name: info.name,
            en_name: info.enName,
            description: description,
            iconFileName: info.iconFilename,
            groupName: groupName,
            categoryID: info.categoryID,
            categoryName: categoryName,
            roleBonuses: nil,
            typeBonuses: nil,
            typeId: typeID,
            groupID: info.groupID,
            volume: info.volume,
            repackagedVolume: info.repackagedVolume,
            capacity: info.capacity,
            mass: info.mass,
            marketGroupID: info.marketGroupID
        )
    }

    func loadGroupNames(for groupIDs: [Int]) -> [Int: String] {
        var groupNames: [Int: String] = [:]
        for id in groupIDs {
            if let name = SDEMemoryStore.group(for: id)?.name {
                groupNames[id] = name
            }
        }
        return groupNames
    }

    func getItemIconFileName(for typeID: Int) -> String? {
        ItemInfoMap.iconFilename(for: typeID)
    }

    func loadMarketItems(
        whereClause: String, parameters: [Any], limit: Int = 0,
        eligibleMarketGroupIDs: Set<Int>? = nil, exactMatchText: String? = nil
    ) -> [DatabaseListItem] {
        // 传入搜索词时，精确匹配（任意语种全等）排在最前，保证结果数触达上限时精确项仍在结果集内
        let orderBy: String
        var allParameters = parameters
        if let exactMatchText, !exactMatchText.isEmpty {
            orderBy =
                "ORDER BY CASE WHEN \(LocalizedText.typeLangNameExactSQL) THEN 0 ELSE 1 END, t.metaGroupID"
            allParameters.append(contentsOf: LocalizedText.typeLangNameExactParams(exactMatchText))
        } else {
            orderBy = "ORDER BY t.metaGroupID"
        }

        var query = """
            SELECT t.type_id as id, t.name, t.en_name, t.published, t.icon_filename as iconFileName,
                   t.categoryID, t.groupID, t.metaGroupID, t.marketGroupID,
                   t.pg_need as pgNeed, t.cpu_need as cpuNeed, t.rig_cost as rigCost,
                   t.em_damage as emDamage, t.them_damage as themDamage, t.kin_damage as kinDamage, t.exp_damage as expDamage,
                   t.high_slot as highSlot, t.mid_slot as midSlot, t.low_slot as lowSlot,
                   t.rig_slot as rigSlot, t.gun_slot as gunSlot, t.miss_slot as missSlot,
                   t.group_name as groupName
            FROM types t
            WHERE \(whereClause)
            \(orderBy)
        """
        if limit > 0 {
            query.append(" LIMIT \(limit)")
        }
        if case let .success(rows) = executeQuery(query, parameters: allParameters) {
            return rows.compactMap { mapMarketItemRow($0, eligibleMarketGroupIDs: eligibleMarketGroupIDs) }
        }
        return []
    }

    /// 市场物品行 → DatabaseListItem（含属性对比资格判定）
    private func mapMarketItemRow(
        _ row: [String: Any], eligibleMarketGroupIDs: Set<Int>?
    ) -> DatabaseListItem? {
        guard let id = row["id"] as? Int,
              let name = row["name"] as? String,
              let categoryId = row["categoryID"] as? Int
        else { return nil }

        let enName = row["en_name"] as? String
        let iconFileName = (row["iconFileName"] as? String) ?? "not_found"
        let published = (row["published"] as? Int) ?? 0
        let groupID = row["groupID"] as? Int
        let groupName = row["groupName"] as? String
        let marketGroupID = row["marketGroupID"] as? Int

        // 加载期一次性判定属性对比资格，避免渲染期每行重复查 Set
        let isEligible: Bool = {
            guard let mgID = marketGroupID, let eligible = eligibleMarketGroupIDs else { return false }
            return eligible.contains(mgID)
        }()

        return DatabaseListItem(
            id: id,
            name: name,
            enName: enName,
            iconFileName: iconFileName,
            published: published == 1,
            categoryID: categoryId,
            groupID: groupID,
            groupName: groupName,
            pgNeed: row["pgNeed"] as? Double,
            cpuNeed: row["cpuNeed"] as? Double,
            rigCost: row["rigCost"] as? Int,
            emDamage: row["emDamage"] as? Double,
            themDamage: row["themDamage"] as? Double,
            kinDamage: row["kinDamage"] as? Double,
            expDamage: row["expDamage"] as? Double,
            highSlot: row["highSlot"] as? Int,
            midSlot: row["midSlot"] as? Int,
            lowSlot: row["lowSlot"] as? Int,
            rigSlot: row["rigSlot"] as? Int,
            gunSlot: row["gunSlot"] as? Int,
            missSlot: row["missSlot"] as? Int,
            metaGroupID: row["metaGroupID"] as? Int,
            marketGroupID: marketGroupID,
            attributeCompareEligible: isEligible,
            navigationDestination: ItemInfoMap.getItemInfoView(
                itemID: id,
                databaseManager: self
            )
        )
    }
}
