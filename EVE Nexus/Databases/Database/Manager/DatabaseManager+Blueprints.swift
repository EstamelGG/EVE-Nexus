import Foundation
import SwiftUI

extension DatabaseManager {
    // MARK: - Blueprint Methods

    private func blueprintMaterialRows(from table: String, blueprintID: Int) -> [(
        typeID: Int, typeName: String, typeIcon: String, quantity: Int
    )] {
        let query = "SELECT typeID, typeName, typeIcon, quantity FROM \(table) WHERE blueprintTypeID = ?"
        guard case let .success(rows) = executeQuery(query, parameters: [blueprintID]) else { return [] }
        return rows.compactMap { row in
            guard let typeID = row["typeID"] as? Int,
                  let typeName = row["typeName"] as? String,
                  let typeIcon = row["typeIcon"] as? String,
                  let quantity = row["quantity"] as? Int else { return nil }
            return (typeID, typeName, typeIcon, quantity)
        }
    }

    private func blueprintSkillRows(from table: String, blueprintID: Int) -> [(
        typeID: Int, typeName: String, typeIcon: String, level: Int
    )] {
        let query = "SELECT typeID, typeName, typeIcon, level FROM \(table) WHERE blueprintTypeID = ?"
        guard case let .success(rows) = executeQuery(query, parameters: [blueprintID]) else { return [] }
        return rows.compactMap { row in
            guard let typeID = row["typeID"] as? Int,
                  let typeName = row["typeName"] as? String,
                  let typeIcon = row["typeIcon"] as? String,
                  let level = row["level"] as? Int else { return nil }
            return (typeID, typeName, typeIcon, level)
        }
    }

    func getBlueprintManufacturingMaterials(for blueprintID: Int) -> [(
        typeID: Int, typeName: String, typeIcon: String, quantity: Int
    )] {
        blueprintMaterialRows(from: "blueprint_manufacturing_materials", blueprintID: blueprintID)
    }

    func getBlueprintManufacturingOutput(for blueprintID: Int) -> [(
        typeID: Int, typeName: String, typeIcon: String, quantity: Int
    )] {
        blueprintMaterialRows(from: "blueprint_manufacturing_output", blueprintID: blueprintID)
    }

    func getBlueprintManufacturingSkills(for blueprintID: Int) -> [(
        typeID: Int, typeName: String, typeIcon: String, level: Int
    )] {
        blueprintSkillRows(from: "blueprint_manufacturing_skills", blueprintID: blueprintID)
    }

    func getBlueprintResearchMaterialMaterials(for blueprintID: Int) -> [(
        typeID: Int, typeName: String, typeIcon: String, quantity: Int
    )] {
        blueprintMaterialRows(from: "blueprint_research_material_materials", blueprintID: blueprintID)
    }

    func getBlueprintResearchMaterialSkills(for blueprintID: Int) -> [(
        typeID: Int, typeName: String, typeIcon: String, level: Int
    )] {
        blueprintSkillRows(from: "blueprint_research_material_skills", blueprintID: blueprintID)
    }

    func getBlueprintResearchTimeMaterials(for blueprintID: Int) -> [(
        typeID: Int, typeName: String, typeIcon: String, quantity: Int
    )] {
        blueprintMaterialRows(from: "blueprint_research_time_materials", blueprintID: blueprintID)
    }

    func getBlueprintResearchTimeSkills(for blueprintID: Int) -> [(
        typeID: Int, typeName: String, typeIcon: String, level: Int
    )] {
        blueprintSkillRows(from: "blueprint_research_time_skills", blueprintID: blueprintID)
    }

    func getBlueprintCopyingMaterials(for blueprintID: Int) -> [(
        typeID: Int, typeName: String, typeIcon: String, quantity: Int
    )] {
        blueprintMaterialRows(from: "blueprint_copying_materials", blueprintID: blueprintID)
    }

    func getBlueprintCopyingSkills(for blueprintID: Int) -> [(
        typeID: Int, typeName: String, typeIcon: String, level: Int
    )] {
        blueprintSkillRows(from: "blueprint_copying_skills", blueprintID: blueprintID)
    }

    func getBlueprintInventionMaterials(for blueprintID: Int) -> [(
        typeID: Int, typeName: String, typeIcon: String, quantity: Int
    )] {
        blueprintMaterialRows(from: "blueprint_invention_materials", blueprintID: blueprintID)
    }

    func getBlueprintInventionSkills(for blueprintID: Int) -> [(
        typeID: Int, typeName: String, typeIcon: String, level: Int
    )] {
        blueprintSkillRows(from: "blueprint_invention_skills", blueprintID: blueprintID)
    }

    func getBlueprintInventionProducts(for blueprintID: Int) -> [(
        typeID: Int, typeName: String, typeIcon: String, quantity: Int, probability: Double
    )] {
        let query = """
            SELECT typeID, typeName, typeIcon, quantity, probability
            FROM blueprint_invention_products
            WHERE blueprintTypeID = ?
        """
        guard case let .success(rows) = executeQuery(query, parameters: [blueprintID]) else { return [] }
        return rows.compactMap { row in
            guard let typeID = row["typeID"] as? Int,
                  let typeName = row["typeName"] as? String,
                  let typeIcon = row["typeIcon"] as? String,
                  let quantity = row["quantity"] as? Int,
                  let probability = row["probability"] as? Double else { return nil }
            return (typeID, typeName, typeIcon, quantity, probability)
        }
    }

    func getBlueprintProcessTime(for blueprintID: Int) -> (
        manufacturing_time: Int, research_material_time: Int, research_time_time: Int,
        copying_time: Int, invention_time: Int, maxRunsPerCopy: Int
    )? {
        let query = """
            SELECT manufacturing_time, research_material_time, research_time_time, copying_time, invention_time, maxRunsPerCopy
            FROM blueprint_process_time
            WHERE blueprintTypeID = ?
        """
        guard case let .success(rows) = executeQuery(query, parameters: [blueprintID]),
              let row = rows.first,
              let manufacturingTime = row["manufacturing_time"] as? Int,
              let researchMaterialTime = row["research_material_time"] as? Int,
              let researchTimeTime = row["research_time_time"] as? Int,
              let copyingTime = row["copying_time"] as? Int,
              let inventionTime = row["invention_time"] as? Int,
              let maxRunsPerCopy = row["maxRunsPerCopy"] as? Int else { return nil }
        return (
            manufacturing_time: manufacturingTime,
            research_material_time: researchMaterialTime,
            research_time_time: researchTimeTime,
            copying_time: copyingTime,
            invention_time: inventionTime,
            maxRunsPerCopy: maxRunsPerCopy
        )
    }

    func getBlueprintIDsForProduct(_ typeID: Int) -> [Int] {
        let query = """
            SELECT DISTINCT blueprintTypeID
            FROM blueprint_manufacturing_output
            WHERE typeID = ?
            UNION
            SELECT DISTINCT blueprintTypeID
            FROM blueprint_invention_products
            WHERE typeID = ?
        """

        let result = executeQuery(query, parameters: [typeID, typeID])
        var blueprintIDs: [Int] = []

        switch result {
        case let .success(rows):
            for row in rows {
                if let blueprintID = row["blueprintTypeID"] as? Int {
                    blueprintIDs.append(blueprintID)
                }
            }
        case let .error(error):
            Logger.error("Error getting blueprint IDs: \(error)")
        }

        return blueprintIDs
    }

    /// 批量获取多个产品的蓝图ID映射
    /// - Parameter typeIDs: 产品类型ID数组
    /// - Returns: 产品ID -> 蓝图ID数组的映射
    func getBlueprintIDsForProducts(_ typeIDs: [Int]) -> [Int: [Int]] {
        guard !typeIDs.isEmpty else { return [:] }

        let typeIDsString = typeIDs.map { String($0) }.joined(separator: ",")
        let query = """
            SELECT DISTINCT blueprintTypeID, typeID
            FROM blueprint_manufacturing_output
            WHERE typeID IN (\(typeIDsString))
            UNION
            SELECT DISTINCT blueprintTypeID, typeID
            FROM blueprint_invention_products
            WHERE typeID IN (\(typeIDsString))
        """

        let result = executeQuery(query)
        var blueprintMapping: [Int: [Int]] = [:]

        switch result {
        case let .success(rows):
            for row in rows {
                if let blueprintID = row["blueprintTypeID"] as? Int,
                   let typeID = row["typeID"] as? Int
                {
                    if blueprintMapping[typeID] == nil {
                        blueprintMapping[typeID] = []
                    }
                    blueprintMapping[typeID]?.append(blueprintID)
                }
            }
        case let .error(error):
            Logger.error("Error getting blueprint IDs for products: \(error)")
        }

        return blueprintMapping
    }

    /// 批量获取蓝图信息
    /// - Parameter blueprintIDs: 蓝图ID数组
    /// - Returns: 蓝图ID -> 蓝图信息的映射
    func getBlueprintInfos(_ blueprintIDs: [Int]) -> [Int: (name: String, iconFileName: String)] {
        guard !blueprintIDs.isEmpty else { return [:] }

        let blueprintIDsString = blueprintIDs.map { String($0) }.joined(separator: ",")
        let query = """
            SELECT type_id, name, icon_filename
            FROM types
            WHERE type_id IN (\(blueprintIDsString)) AND published = 1
        """

        let result = executeQuery(query)
        var blueprintInfos: [Int: (name: String, iconFileName: String)] = [:]

        switch result {
        case let .success(rows):
            for row in rows {
                if let blueprintID = row["type_id"] as? Int,
                   let name = row["name"] as? String
                {
                    let iconFileName = row["icon_filename"] as? String ?? ""
                    blueprintInfos[blueprintID] = (
                        name: name,
                        iconFileName: iconFileName.isEmpty
                            ? IconManager.defaultItemIcon : iconFileName
                    )
                }
            }
        case let .error(error):
            Logger.error("Error getting blueprint infos: \(error)")
        }

        return blueprintInfos
    }

    /// 获取蓝图源头
    func getBlueprintSource(for blueprintID: Int) -> [(
        typeID: Int, typeName: String, typeIcon: String
    )] {
        let query = """
            SELECT blueprintTypeID as type_id, 
                   blueprintTypeName as name, 
                   blueprintTypeIcon as icon_filename
            FROM blueprint_invention_products
            WHERE typeID = ?
        """

        let result = executeQuery(query, parameters: [blueprintID])
        var sources: [(typeID: Int, typeName: String, typeIcon: String)] = []

        switch result {
        case let .success(rows):
            for row in rows {
                if let typeID = row["type_id"] as? Int,
                   let typeName = row["name"] as? String
                {
                    let iconFileName = row["icon_filename"] as? String ?? ""
                    sources.append(
                        (
                            typeID: typeID,
                            typeName: typeName,
                            typeIcon: iconFileName.isEmpty
                                ? IconManager.defaultItemIcon : iconFileName
                        )
                    )
                }
            }
        case let .error(error):
            Logger.error("Error getting blueprint sources: \(error)")
        }

        return sources
    }

    /// 获取可以精炼/回收得到指定物品的源物品列表
    func getSourceMaterials(for itemID: Int, groupID: Int) -> [(
        typeID: Int, name: String, iconFileName: String, outputQuantityPerUnit: Double
    )]? {
        let filter: String
        switch groupID {
        case 18, 423, 427: // 矿物 / 同位素 / 元素 → 矿石
            filter = "AND tm.categoryid = 25"
        case 1996: // 突变残渣 → 装备
            filter = "AND tm.categoryid = 7 AND tm.output_material != 47975 AND tm.output_material != 48112"
        default:
            return nil
        }
        let query = """
            SELECT DISTINCT t.type_id, t.name, t.icon_filename,
                   CAST(tm.output_quantity AS FLOAT) / tm.process_size as output_per_unit
            FROM typeMaterials tm
            JOIN types t ON tm.typeid = t.type_id
            WHERE tm.output_material = ? \(filter)
            ORDER BY output_per_unit DESC
        """
        guard case let .success(rows) = executeQuery(query, parameters: [itemID]) else {
            return nil
        }
        let materials: [(typeID: Int, name: String, iconFileName: String, outputQuantityPerUnit: Double)] = rows.compactMap { row in
            guard let typeID = row["type_id"] as? Int,
                  let name = row["name"] as? String,
                  let outputPerUnit = row["output_per_unit"] as? Double else { return nil }
            let iconFileName = row["icon_filename"] as? String ?? ""
            return (
                typeID: typeID,
                name: name,
                iconFileName: iconFileName.isEmpty ? IconManager.defaultItemIcon : iconFileName,
                outputQuantityPerUnit: outputPerUnit
            )
        }
        return materials.isEmpty ? nil : materials
    }

    func getBlueprintDest(for typeID: Int) -> (
        blueprints: [(typeID: Int, name: String, iconFileName: String)],
        groups: [(groupID: Int, name: String, iconFileName: String)]
    ) {
        let query = """
            WITH blueprint_list AS (
                SELECT DISTINCT b.blueprintTypeID, b.blueprintTypeName, b.blueprintTypeIcon,
                       t.groupID, t.group_name
                FROM (
                    SELECT blueprintTypeID, blueprintTypeName, blueprintTypeIcon
                    FROM blueprint_manufacturing_materials
                    WHERE typeID = ?
                    UNION
                    SELECT blueprintTypeID, blueprintTypeName, blueprintTypeIcon
                    FROM blueprint_invention_materials
                    WHERE typeID = ?
                ) b
                LEFT JOIN types t ON b.blueprintTypeID = t.type_id AND t.published = 1
            )
            SELECT * FROM blueprint_list
            ORDER BY groupID, blueprintTypeID
        """

        var blueprints: [(typeID: Int, name: String, iconFileName: String)] = []
        var groups: [(groupID: Int, name: String, iconFileName: String)] = []
        var seenGroups = Set<Int>()

        if case let .success(rows) = executeQuery(query, parameters: [typeID, typeID]) {
            for row in rows {
                if let blueprintID = row["blueprintTypeID"] as? Int,
                   let blueprintName = row["blueprintTypeName"] as? String,
                   let blueprintIcon = row["blueprintTypeIcon"] as? String,
                   let groupID = row["groupID"] as? Int,
                   let groupName = row["group_name"] as? String
                {
                    // 添加蓝图
                    blueprints.append(
                        (
                            typeID: blueprintID,
                            name: blueprintName,
                            iconFileName: blueprintIcon.isEmpty
                                ? IconManager.defaultItemIcon : blueprintIcon
                        )
                    )

                    // 如果是新的组，添加到组列表
                    if !seenGroups.contains(groupID) {
                        groups.append(
                            (
                                groupID: groupID,
                                name: groupName,
                                iconFileName: blueprintIcon.isEmpty
                                    ? IconManager.defaultItemIcon : blueprintIcon
                            )
                        )
                        seenGroups.insert(groupID)
                    }
                }
            }
        }

        return (blueprints: blueprints, groups: groups)
    }
}
