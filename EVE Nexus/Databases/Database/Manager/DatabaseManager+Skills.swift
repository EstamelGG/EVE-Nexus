import Foundation
import SwiftUI

extension DatabaseManager {
    func getDirectSkillRequirements(for typeID: Int) -> [(skillID: Int, level: Int)] {
        // 内存索引；去重并按等级降序（与旧 SQL DISTINCT + ORDER BY 一致）
        var seen = Set<Int>()
        var requirements: [(skillID: Int, level: Int)] = []
        for requirement in SDEMemoryStore.requiredSkills(for: typeID) {
            guard !seen.contains(requirement.skillID) else { continue }
            seen.insert(requirement.skillID)
            requirements.append((skillID: requirement.skillID, level: requirement.level))
        }
        requirements.sort { $0.level > $1.level }
        return requirements
    }

    func getTraits(for typeID: Int) -> TraitGroup? {
        let query = """
            SELECT importance, content, skill, bonus_type
            FROM traits
            WHERE typeid = ? AND bonus_type IN ('roleBonuses', 'typeBonuses', 'miscBonuses')
            ORDER BY bonus_type, skill, importance
        """

        var roleBonuses: [Trait] = []
        var typeBonuses: [Trait] = []
        var miscBonuses: [Trait] = []

        if case let .success(rows) = executeQuery(query, parameters: [typeID]) {
            for row in rows {
                if let importance = row["importance"] as? Int,
                   let content = row["content"] as? String,
                   let bonusType = row["bonus_type"] as? String
                {
                    switch bonusType {
                    case "roleBonuses":
                        roleBonuses.append(
                            Trait(
                                content: content,
                                importance: importance,
                                skill: nil,
                                bonusType: bonusType
                            )
                        )
                    case "typeBonuses":
                        if let skill = row["skill"] as? Int, skill > 0 {
                            typeBonuses.append(
                                Trait(
                                    content: content,
                                    importance: importance,
                                    skill: skill,
                                    bonusType: bonusType
                                )
                            )
                        }
                    case "miscBonuses":
                        miscBonuses.append(
                            Trait(
                                content: content,
                                importance: importance,
                                skill: nil,
                                bonusType: bonusType
                            )
                        )
                    default:
                        break
                    }
                }
            }
        }

        return TraitGroup(
            roleBonuses: roleBonuses, typeBonuses: typeBonuses, miscBonuses: miscBonuses
        )
    }

    /// 获取所有需要特定技能的物品及其需求等级
    func getAllItemsRequiringSkill(skillID: Int) -> [Int: [(
        typeID: Int, name: String, iconFileName: String, categoryID: Int, categoryName: String
    )]] {
        // 获取物品依赖
        let itemsQuery = """
            SELECT typeid, typename, typeicon, required_skill_level, categoryID, category_name
            FROM typeSkillRequirement
            WHERE required_skill_id = ?
            AND published = 1
        """

        var itemsByLevel:
            [Int: [(
                typeID: Int, name: String, iconFileName: String, categoryID: Int,
                categoryName: String
            )]] = [:]

        // 在内存中收集物品数据并去重
        var processedItems = Set<Int>()

        if case let .success(rows) = executeQuery(itemsQuery, parameters: [skillID]) {
            for row in rows {
                if let typeID = row["typeid"] as? Int,
                   let name = row["typename"] as? String,
                   let iconFileName = row["typeicon"] as? String,
                   let level = row["required_skill_level"] as? Int,
                   let categoryID = row["categoryID"] as? Int,
                   let categoryName = row["category_name"] as? String
                {
                    // 跳过已处理的物品
                    guard !processedItems.contains(typeID) else { continue }

                    let item = (
                        typeID: typeID,
                        name: name,
                        iconFileName: iconFileName.isEmpty
                            ? IconManager.defaultItemIcon : iconFileName,
                        categoryID: categoryID,
                        categoryName: categoryName
                    )

                    if itemsByLevel[level] == nil {
                        itemsByLevel[level] = []
                    }
                    itemsByLevel[level]?.append(item)
                    processedItems.insert(typeID)
                }
            }
        }

        // 获取蓝图依赖
        let blueprintsByLevel = getAllBlueprintsRequiringSkill(skillID: skillID)

        // 合并物品和蓝图结果
        for (level, blueprints) in blueprintsByLevel {
            if itemsByLevel[level] == nil {
                itemsByLevel[level] = []
            }
            itemsByLevel[level]?.append(contentsOf: blueprints)
        }

        // 对每个等级内的物品按名称排序
        for level in itemsByLevel.keys {
            itemsByLevel[level]?.sort { $0.name < $1.name }
        }

        return itemsByLevel
    }

    /// 获取所有需要特定技能的蓝图及其需求等级
    private func getAllBlueprintsRequiringSkill(skillID: Int) -> [Int: [(
        typeID: Int, name: String, iconFileName: String, categoryID: Int, categoryName: String
    )]] {
        // 获取所有蓝图技能要求数据
        let blueprintSkillsQuery = """
            SELECT 
                blueprintTypeID,
                level as required_skill_level
            FROM (
                SELECT blueprintTypeID, typeID, level FROM blueprint_manufacturing_skills WHERE typeID = ?
                UNION ALL
                SELECT blueprintTypeID, typeID, level FROM blueprint_copying_skills WHERE typeID = ?
                UNION ALL
                SELECT blueprintTypeID, typeID, level FROM blueprint_invention_skills WHERE typeID = ?
                UNION ALL
                SELECT blueprintTypeID, typeID, level FROM blueprint_research_material_skills WHERE typeID = ?
                UNION ALL
                SELECT blueprintTypeID, typeID, level FROM blueprint_research_time_skills WHERE typeID = ?
            )
        """

        // 在内存中收集所有蓝图ID和等级要求
        var blueprintRequirements: [(blueprintID: Int, level: Int)] = []
        var blueprintIDs = Set<Int>()

        if case let .success(rows) = executeQuery(
            blueprintSkillsQuery, parameters: [skillID, skillID, skillID, skillID, skillID]
        ) {
            for row in rows {
                if let blueprintID = row["blueprintTypeID"] as? Int,
                   let level = row["required_skill_level"] as? Int
                {
                    blueprintRequirements.append((blueprintID: blueprintID, level: level))
                    blueprintIDs.insert(blueprintID)
                }
            }
        }

        // 如果没有找到蓝图，直接返回空结果
        if blueprintIDs.isEmpty {
            return [:]
        }

        // 从types表获取蓝图的详细信息
        let placeholders = String(repeating: "?,", count: blueprintIDs.count).dropLast()
        let blueprintDetailsQuery = """
            SELECT 
                t.type_id,
                t.name,
                t.icon_filename,
                t.categoryID,
                t.published,
                c.name as category_name
            FROM types t
            LEFT JOIN categories c ON t.categoryID = c.category_id
            WHERE t.type_id IN (\(placeholders))
            AND t.published = 1
        """

        var blueprintDetails:
            [Int: (name: String, iconFileName: String, categoryID: Int, categoryName: String)] = [:]

        if case let .success(rows) = executeQuery(
            blueprintDetailsQuery, parameters: Array(blueprintIDs)
        ) {
            for row in rows {
                if let typeID = row["type_id"] as? Int,
                   let name = row["name"] as? String,
                   let categoryID = row["categoryID"] as? Int,
                   let categoryName = row["category_name"] as? String
                {
                    let iconFileName = row["icon_filename"] as? String ?? ""
                    blueprintDetails[typeID] = (
                        name: name,
                        iconFileName: iconFileName.isEmpty
                            ? IconManager.defaultItemIcon : iconFileName,
                        categoryID: categoryID,
                        categoryName: categoryName
                    )
                }
            }
        }

        // 在内存中按等级分组并去重
        var blueprintsByLevel:
            [Int: [(
                typeID: Int, name: String, iconFileName: String, categoryID: Int,
                categoryName: String
            )]] = [:]

        // 用于去重的Set
        var processedBlueprints = Set<Int>()

        for requirement in blueprintRequirements {
            let blueprintID = requirement.blueprintID
            let level = requirement.level

            // 跳过已处理的蓝图
            guard !processedBlueprints.contains(blueprintID),
                  let details = blueprintDetails[blueprintID]
            else {
                continue
            }

            let blueprint = (
                typeID: blueprintID,
                name: details.name,
                iconFileName: details.iconFileName,
                categoryID: details.categoryID,
                categoryName: details.categoryName
            )

            if blueprintsByLevel[level] == nil {
                blueprintsByLevel[level] = []
            }

            blueprintsByLevel[level]?.append(blueprint)
            processedBlueprints.insert(blueprintID)
        }

        // 对每个等级内的蓝图按名称排序
        for level in blueprintsByLevel.keys {
            blueprintsByLevel[level]?.sort { $0.name < $1.name }
        }

        return blueprintsByLevel
    }
}
