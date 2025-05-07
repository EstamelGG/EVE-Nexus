import Foundation
import SwiftUI

class DatabaseManager: ObservableObject {
    static let shared = DatabaseManager()
    @Published var databaseUpdated = false
    private let sqliteManager = SQLiteManager.shared

    // 加载数据库
    func loadDatabase() {
        // 获取本地化的数据库名称
        guard let databaseName = getLocalizedDatabaseName() else {
            Logger.error("数据库名称未找到")
            return
        }

        // 使用 SQLiteManager 打开数据库
        if sqliteManager.openDatabase(withName: databaseName) {
            // 初始化技能树
            SkillTreeManager.shared.initialize(databaseManager: self)
            Logger.info("技能树初始化完成")

            // 初始化物品分类缓存
            ItemInfoMap.initializeCache(databaseManager: self)
            Logger.info("物品分类缓存初始化完成")

            databaseUpdated.toggle()
        }
    }

    // 获取本地化的数据库名称
    private func getLocalizedDatabaseName() -> String? {
        let dbLanguage = UserDefaults.standard.string(forKey: "selectedDatabaseLanguage") ?? "en"
        // 根据数据库语言选择相应的数据库文件
        switch dbLanguage {
        case "zh-Hans":
            return "item_db_zh"
        case "en":
            return "item_db_en"
        default:
            return "item_db_en"  // 默认使用英文数据库
        }
    }

    // 清除查询缓存
    func clearCache() {
        sqliteManager.clearCache()
    }

    // 执行查询
    func executeQuery(_ query: String, parameters: [Any] = [], useCache: Bool = true)
        -> SQLiteResult
    {
        return sqliteManager.executeQuery(query, parameters: parameters, useCache: useCache)
    }

    // 加载分类
    func loadCategories() -> ([Category], [Category]) {
        let query =
            "SELECT category_id, name, published, icon_filename FROM categories ORDER BY category_id"
        let result = executeQuery(query)

        var published: [Category] = []
        var unpublished: [Category] = []

        switch result {
        case let .success(rows):
            for (index, row) in rows.enumerated() {
                // Logger.debug("处理第 \(index + 1) 行: \(row)")

                // 确保所有必需的字段都存在且类型正确
                guard let categoryId = row["category_id"] as? Int,
                    let name = row["name"] as? String,
                    let iconFilename = row["icon_filename"] as? String
                else {
                    Logger.error("行 \(index + 1) 数据不完整或类型不正确: \(row)")
                    continue
                }

                let isPublished = (row["published"] as? Int ?? 0) != 0

                let category = Category(
                    id: categoryId,
                    name: name,
                    published: isPublished,
                    iconID: categoryId,  // 保持 iconID 为 categoryId
                    iconFileNew: iconFilename.isEmpty ? DatabaseConfig.defaultIcon : iconFilename
                )

                // Logger.debug("创建分类: id=\(category.id), name=\(category.name), published=\(category.published)")

                if category.published {
                    published.append(category)
                } else {
                    unpublished.append(category)
                }
            }

        // Logger.debug("处理完成 - 已发布: \(published.count), 未发布: \(unpublished.count)")

        case let .error(error):
            Logger.error("加载分类失败: \(error)")
        }

        return (published, unpublished)
    }

    // 加载组
    func loadGroups(for categoryID: Int) -> ([Group], [Group]) {
        let query = """
                SELECT g.group_id, g.name, g.categoryID, g.published, g.icon_filename
                FROM groups g
                WHERE g.categoryID = ?
            """

        let result = executeQuery(query, parameters: [categoryID])

        var published: [Group] = []
        var unpublished: [Group] = []

        switch result {
        case let .success(rows):
            for row in rows {
                guard let groupId = row["group_id"] as? Int,
                    let name = row["name"] as? String,
                    let catId = row["categoryID"] as? Int,
                    let iconFilename = row["icon_filename"] as? String
                else {
                    continue
                }

                let isPublished = (row["published"] as? Int ?? 0) != 0

                let group = Group(
                    id: groupId,
                    name: name,
                    iconID: groupId,  // 保持 iconID 为 groupId
                    categoryID: catId,
                    published: isPublished,
                    icon_filename: iconFilename.isEmpty ? DatabaseConfig.defaultIcon : iconFilename
                )

                if group.published {
                    published.append(group)
                } else {
                    unpublished.append(group)
                }
            }

        case let .error(error):
            Logger.error("加载组失败: \(error)")
        }

        return (published, unpublished)
    }

    // 加载物品
    func loadItems(for groupID: Int) -> ([DatabaseItem], [DatabaseItem], [Int: String]) {
        // 首先获取所有 metaGroups 的名称
        let metaQuery = """
                SELECT metagroup_id, name 
                FROM metaGroups 
                ORDER BY metagroup_id ASC
            """
        let metaResult = executeQuery(metaQuery, useCache: true)
        var metaGroupNames: [Int: String] = [:]

        if case let .success(metaRows) = metaResult {
            for row in metaRows {
                if let id = row["metagroup_id"] as? Int,
                    let name = row["name"] as? String
                {
                    metaGroupNames[id] = name
                } else {
                    Logger.warning("MetaGroup 行数据类型不正确: \(row)")
                }
            }
        } else {
            Logger.error("加载 metaGroups 失败")
        }

        // 查询物品
        let query = """
                SELECT t.type_id, t.name, t.icon_filename, t.published, t.metaGroupID, t.categoryID,
                       t.pg_need, t.cpu_need, t.rig_cost, 
                       t.em_damage, t.them_damage, t.kin_damage, t.exp_damage,
                       t.high_slot, t.mid_slot, t.low_slot, t.rig_slot, t.gun_slot, t.miss_slot
                FROM types t
                WHERE t.groupID = ?
                ORDER BY t.name ASC
            """

        let result = executeQuery(query, parameters: [groupID])

        var published: [DatabaseItem] = []
        var unpublished: [DatabaseItem] = []

        switch result {
        case let .success(rows):
            for row in rows {
                guard let typeId = row["type_id"] as? Int,
                    let name = row["name"] as? String,
                    let iconFilename = row["icon_filename"] as? String,
                    let metaGroupId = row["metaGroupID"] as? Int,
                    let categoryId = row["categoryID"] as? Int,
                    let isPublished = row["published"] as? Int
                else {
                    Logger.warning("物品基础数据不完整: \(row)")
                    continue
                }

                // 获取可选属性
                let pgNeed = row["pg_need"] as? Double
                let cpuNeed = row["cpu_need"] as? Double
                let rigCost = row["rig_cost"] as? Int
                let emDamage =
                    row["em_damage"] as? Double ?? (row["em_damage"] as? Int).map { Double($0) }
                let themDamage =
                    row["them_damage"] as? Double ?? (row["them_damage"] as? Int).map { Double($0) }
                let kinDamage =
                    row["kin_damage"] as? Double ?? (row["kin_damage"] as? Int).map { Double($0) }
                let expDamage =
                    row["exp_damage"] as? Double ?? (row["exp_damage"] as? Int).map { Double($0) }
                let highSlot = row["high_slot"] as? Int
                let midSlot = row["mid_slot"] as? Int
                let lowSlot = row["low_slot"] as? Int
                let rigSlot = row["rig_slot"] as? Int
                let gunSlot = row["gun_slot"] as? Int
                let missSlot = row["miss_slot"] as? Int

                // 打印调试信息
                Logger.debug("处理物品: ID=\(typeId), Name=\(name), MetaGroupID=\(metaGroupId)")

                let item = DatabaseItem(
                    id: typeId,
                    typeID: typeId,
                    name: name,
                    iconFileName: iconFilename.isEmpty
                        ? DatabaseConfig.defaultItemIcon : iconFilename,
                    categoryID: categoryId,
                    pgNeed: pgNeed,
                    cpuNeed: cpuNeed,
                    rigCost: rigCost,
                    emDamage: emDamage,
                    themDamage: themDamage,
                    kinDamage: kinDamage,
                    expDamage: expDamage,
                    highSlot: highSlot,
                    midSlot: midSlot,
                    lowSlot: lowSlot,
                    rigSlot: rigSlot,
                    gunSlot: gunSlot,
                    missSlot: missSlot,
                    metaGroupID: metaGroupId,
                    published: isPublished != 0
                )

                if isPublished != 0 {
                    published.append(item)
                } else {
                    unpublished.append(item)
                }
            }

        case let .error(error):
            Logger.error("加载物品失败: \(error)")
        }
        return (published, unpublished, metaGroupNames)
    }

    // 搜索物品 限制200个结果
    func searchItems(searchText: String, categoryID: Int? = nil, groupID: Int? = nil) -> (
        [DatabaseListItem], [Int: String], [Int: String]
    ) {
        Logger.info("Search: \(searchText)")
        var query = """
                SELECT t.type_id as id, t.name, t.published, t.icon_filename as iconFileName,
                       t.categoryID, t.groupID, t.metaGroupID, t.marketGroupID,
                       t.pg_need as pgNeed, t.cpu_need as cpuNeed, t.rig_cost as rigCost,
                       t.em_damage as emDamage, t.them_damage as themDamage, t.kin_damage as kinDamage, t.exp_damage as expDamage,
                       t.high_slot as highSlot, t.mid_slot as midSlot, t.low_slot as lowSlot,
                       t.rig_slot as rigSlot, t.gun_slot as gunSlot, t.miss_slot as missSlot,
                       t.group_name as groupName
                FROM types t
                WHERE t.name LIKE ? OR t.en_name LIKE ? OR t.zh_name LIKE ? OR t.de_name LIKE ? OR t.es_name LIKE ? OR t.fr_name LIKE ? OR t.ja_name LIKE ? OR t.ko_name LIKE ? OR t.ru_name LIKE ? OR t.type_id = ?
            """

        var parameters: [Any] = [
            "%\(searchText)%", "%\(searchText)%", "%\(searchText)%", "%\(searchText)%",
            "%\(searchText)%", "%\(searchText)%", "%\(searchText)%", "%\(searchText)%",
            "%\(searchText)%", "\(searchText)",
        ]

        if let categoryID = categoryID {
            query += " AND t.categoryID = ?"
            parameters.append(categoryID)
        }

        if let groupID = groupID {
            query += " AND t.groupID = ?"
            parameters.append(groupID)
        }

        query += " ORDER BY t.groupID, t.metaGroupID LIMIT 200"
        Logger.info(query)
        let result = executeQuery(query, parameters: parameters)
        var items: [DatabaseListItem] = []
        var groupNames: [Int: String] = [:]

        if case let .success(rows) = result {
            for row in rows {
                if let id = row["id"] as? Int,
                    let name = row["name"] as? String,
                    let categoryId = row["categoryID"] as? Int
                {
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
                            navigationDestination: ItemInfoMap.getItemInfoView(
                                itemID: id,
                                databaseManager: self
                            )
                        ))
                }
            }
        }

        // 获取 metaGroup 名称
        let metaGroupIDs = Set(items.compactMap { $0.metaGroupID })
        let metaGroupNames = loadMetaGroupNames(for: Array(metaGroupIDs))

        return (items, metaGroupNames, groupNames)
    }

    // 加载 MetaGroup 名称
    func loadMetaGroupNames(for metaGroupIDs: [Int]) -> [Int: String] {
        let placeholders = String(repeating: "?,", count: metaGroupIDs.count).dropLast()
        let query = """
                SELECT metagroup_id, name
                FROM metaGroups
                WHERE metagroup_id IN (\(placeholders))
            """

        let result = executeQuery(query, parameters: metaGroupIDs)
        var metaGroupNames: [Int: String] = [:]

        switch result {
        case let .success(rows):
            for row in rows {
                if let id = row["metagroup_id"] as? Int,
                    let name = row["name"] as? String
                {
                    metaGroupNames[id] = name
                }
            }
        case let .error(error):
            Logger.error("加载 MetaGroup 名称失败: \(error)")
        }

        return metaGroupNames
    }

    // 获取类型名称
    func getTypeName(for typeID: Int) -> String? {
        let query = "SELECT name FROM types WHERE type_id = ?"
        let result = executeQuery(query, parameters: [typeID])

        if case let .success(rows) = result,
            let row = rows.first,
            let name = row["name"] as? String
        {
            return name
        }
        return nil
    }

    // 获取属性名称
    func getAttributeName(for typeID: Int) -> String? {
        let query = "SELECT display_name FROM dogmaAttributes WHERE attribute_id = ?"
        let result = executeQuery(query, parameters: [typeID])

        if case let .success(rows) = result,
            let row = rows.first,
            let name = row["display_name"] as? String
        {
            return name
        }
        return nil
    }

    // 加载物品的所有属性组
    func loadAttributeGroups(for typeID: Int) -> [AttributeGroup] {
        // 1. 首先加载所有属性分类
        let categoryQuery = """
                SELECT attribute_category_id, name, description
                FROM dogmaAttributeCategories
                ORDER BY attribute_category_id
            """

        let categoryResult = executeQuery(categoryQuery)
        var categories: [Int: DogmaAttributeCategory] = [:]

        if case let .success(rows) = categoryResult {
            for row in rows {
                guard let id = row["attribute_category_id"] as? Int,
                    let name = row["name"] as? String,
                    let description = row["description"] as? String
                else {
                    continue
                }
                categories[id] = DogmaAttributeCategory(
                    id: id, name: name, description: description
                )
            }
        }

        // 2. 加载物品的所有属性值
        let attributeQuery = """
                SELECT da.attribute_id, da.categoryID, da.name, da.display_name, da.iconID, ta.value, da.unitID,
                       COALESCE(da.icon_filename, '') as icon_filename
                FROM typeAttributes ta
                JOIN dogmaAttributes da ON ta.attribute_id = da.attribute_id
                WHERE ta.type_id = ?
                ORDER BY da.categoryID, da.attribute_id
            """

        let attributeResult = executeQuery(attributeQuery, parameters: [typeID])
        var attributesByCategory: [Int: [DogmaAttribute]] = [:]

        if case let .success(rows) = attributeResult {
            for row in rows {
                guard let attributeId = row["attribute_id"] as? Int,
                    let categoryId = row["categoryID"] as? Int,
                    let name = row["name"] as? String,
                    let iconId = row["iconID"] as? Int,
                    let value = row["value"] as? Double
                else {
                    continue
                }

                let displayName = row["display_name"] as? String
                let iconFileName = (row["icon_filename"] as? String) ?? ""
                let unitID = row["unitID"] as? Int

                let attribute = DogmaAttribute(
                    id: attributeId,
                    categoryID: categoryId,
                    name: name,
                    displayName: displayName,
                    iconID: iconId,
                    iconFileName: iconFileName.isEmpty ? DatabaseConfig.defaultIcon : iconFileName,
                    value: value,
                    unitID: unitID
                )

                if attribute.shouldDisplay {
                    if attributesByCategory[categoryId] == nil {
                        attributesByCategory[categoryId] = []
                    }
                    attributesByCategory[categoryId]?.append(attribute)
                }
            }
        }

        // 3. 组合成最终的属性组列表
        return categories.sorted { $0.key < $1.key }  // 按 category_id 排序
            .compactMap { categoryId, category in
                if let attributes = attributesByCategory[categoryId], !attributes.isEmpty {
                    return AttributeGroup(
                        id: categoryId,
                        name: category.name,
                        attributes: attributes.sorted { $0.id < $1.id }  // 按 attribute_id 排序
                    )
                }
                return nil  // 如果这个分类没有属性，就不包含在结果中
            }
    }

    // 加载属性单位信息
    func loadAttributeUnits() -> [Int: String] {
        let query = """
                SELECT attribute_id, unitName
                FROM dogmaAttributes
                WHERE unitName IS NOT NULL AND unitName != ''
            """

        var units: [Int: String] = [:]

        if case let .success(rows) = executeQuery(query) {
            for row in rows {
                if let attributeId = row["attribute_id"] as? Int,
                    let unitName = row["unitName"] as? String
                {
                    units[attributeId] = unitName
                }
            }
        }

        return units
    }

    // 获取组名称（从 groups 表获取，用于其他场景）
    func getGroupName(for groupID: Int) -> String? {
        let query = "SELECT name FROM groups WHERE group_id = ?"

        if case let .success(rows) = executeQuery(query, parameters: [groupID]),
            let row = rows.first,
            let name = row["name"] as? String
        {
            return name
        }
        return nil
    }

    // 重新加工材料数据结构
    struct TypeMaterial {
        let process_size: Int
        let outputMaterial: Int
        let outputQuantity: Int
        let outputMaterialName: String
        let outputMaterialIcon: String
    }

    func getTypeMaterials(for typeID: Int) -> [TypeMaterial]? {
        let query = """
                SELECT process_size, output_material, output_quantity, output_material_name, output_material_icon
                FROM typeMaterials
                WHERE typeid = ?
                ORDER BY output_material
            """

        let result = sqliteManager.executeQuery(query, parameters: [typeID])
        var materials: [TypeMaterial] = []

        switch result {
        case let .success(rows):
            for row in rows {
                guard let process_size = row["process_size"] as? Int,
                    let outputMaterial = row["output_material"] as? Int,
                    let outputQuantity = row["output_quantity"] as? Int,
                    let outputMaterialName = row["output_material_name"] as? String,
                    let outputMaterialIcon = row["output_material_icon"] as? String
                else {
                    continue
                }

                let material = TypeMaterial(
                    process_size: process_size,
                    outputMaterial: outputMaterial,
                    outputQuantity: outputQuantity,
                    outputMaterialName: outputMaterialName,
                    outputMaterialIcon: outputMaterialIcon.isEmpty
                        ? DatabaseConfig.defaultItemIcon : outputMaterialIcon
                )
                materials.append(material)
            }

            return materials.isEmpty ? nil : materials

        case let .error(error):
            Logger.error("Error fetching type materials: \(error)")
            return nil
        }
    }

    // MARK: - Blueprint Methods

    // 获取蓝图制造材料
    func getBlueprintManufacturingMaterials(for blueprintID: Int) -> [(
        typeID: Int, typeName: String, typeIcon: String, quantity: Int
    )] {
        let query = """
                SELECT typeID, typeName, typeIcon, quantity
                FROM blueprint_manufacturing_materials
                WHERE blueprintTypeID = ?
            """
        let result = executeQuery(query, parameters: [blueprintID])
        var materials: [(typeID: Int, typeName: String, typeIcon: String, quantity: Int)] = []

        if case let .success(rows) = result {
            for row in rows {
                if let typeID = row["typeID"] as? Int,
                    let typeName = row["typeName"] as? String,
                    let typeIcon = row["typeIcon"] as? String,
                    let quantity = row["quantity"] as? Int
                {
                    materials.append(
                        (typeID: typeID, typeName: typeName, typeIcon: typeIcon, quantity: quantity)
                    )
                }
            }
        }
        return materials
    }

    // 获取蓝图制造产出
    func getBlueprintManufacturingOutput(for blueprintID: Int) -> [(
        typeID: Int, typeName: String, typeIcon: String, quantity: Int
    )] {
        let query = """
                SELECT typeID, typeName, typeIcon, quantity
                FROM blueprint_manufacturing_output
                WHERE blueprintTypeID = ?
            """
        let result = executeQuery(query, parameters: [blueprintID])
        var products: [(typeID: Int, typeName: String, typeIcon: String, quantity: Int)] = []

        if case let .success(rows) = result {
            for row in rows {
                if let typeID = row["typeID"] as? Int,
                    let typeName = row["typeName"] as? String,
                    let typeIcon = row["typeIcon"] as? String,
                    let quantity = row["quantity"] as? Int
                {
                    products.append(
                        (typeID: typeID, typeName: typeName, typeIcon: typeIcon, quantity: quantity)
                    )
                }
            }
        }
        return products
    }

    // 获取蓝图制造所需技能
    func getBlueprintManufacturingSkills(for blueprintID: Int) -> [(
        typeID: Int, typeName: String, typeIcon: String, level: Int
    )] {
        let query = """
                SELECT typeID, typeName, typeIcon, level
                FROM blueprint_manufacturing_skills
                WHERE blueprintTypeID = ?
            """
        let result = executeQuery(query, parameters: [blueprintID])
        var skills: [(typeID: Int, typeName: String, typeIcon: String, level: Int)] = []

        if case let .success(rows) = result {
            for row in rows {
                if let typeID = row["typeID"] as? Int,
                    let typeName = row["typeName"] as? String,
                    let typeIcon = row["typeIcon"] as? String,
                    let level = row["level"] as? Int
                {
                    skills.append(
                        (typeID: typeID, typeName: typeName, typeIcon: typeIcon, level: level))
                }
            }
        }
        return skills
    }

    // 获取蓝图材料研究材料
    func getBlueprintResearchMaterialMaterials(for blueprintID: Int) -> [(
        typeID: Int, typeName: String, typeIcon: String, quantity: Int
    )] {
        let query = """
                SELECT typeID, typeName, typeIcon, quantity
                FROM blueprint_research_material_materials
                WHERE blueprintTypeID = ?
            """
        let result = executeQuery(query, parameters: [blueprintID])
        var materials: [(typeID: Int, typeName: String, typeIcon: String, quantity: Int)] = []

        if case let .success(rows) = result {
            for row in rows {
                if let typeID = row["typeID"] as? Int,
                    let typeName = row["typeName"] as? String,
                    let typeIcon = row["typeIcon"] as? String,
                    let quantity = row["quantity"] as? Int
                {
                    materials.append(
                        (typeID: typeID, typeName: typeName, typeIcon: typeIcon, quantity: quantity)
                    )
                }
            }
        }
        return materials
    }

    // 获取蓝图材料研究技能
    func getBlueprintResearchMaterialSkills(for blueprintID: Int) -> [(
        typeID: Int, typeName: String, typeIcon: String, level: Int
    )] {
        let query = """
                SELECT typeID, typeName, typeIcon, level
                FROM blueprint_research_material_skills
                WHERE blueprintTypeID = ?
            """
        let result = executeQuery(query, parameters: [blueprintID])
        var skills: [(typeID: Int, typeName: String, typeIcon: String, level: Int)] = []

        if case let .success(rows) = result {
            for row in rows {
                if let typeID = row["typeID"] as? Int,
                    let typeName = row["typeName"] as? String,
                    let typeIcon = row["typeIcon"] as? String,
                    let level = row["level"] as? Int
                {
                    skills.append(
                        (typeID: typeID, typeName: typeName, typeIcon: typeIcon, level: level))
                }
            }
        }
        return skills
    }

    // 获取蓝图时间研究材料
    func getBlueprintResearchTimeMaterials(for blueprintID: Int) -> [(
        typeID: Int, typeName: String, typeIcon: String, quantity: Int
    )] {
        let query = """
                SELECT typeID, typeName, typeIcon, quantity
                FROM blueprint_research_time_materials
                WHERE blueprintTypeID = ?
            """
        let result = executeQuery(query, parameters: [blueprintID])
        var materials: [(typeID: Int, typeName: String, typeIcon: String, quantity: Int)] = []

        if case let .success(rows) = result {
            for row in rows {
                if let typeID = row["typeID"] as? Int,
                    let typeName = row["typeName"] as? String,
                    let typeIcon = row["typeIcon"] as? String,
                    let quantity = row["quantity"] as? Int
                {
                    materials.append(
                        (typeID: typeID, typeName: typeName, typeIcon: typeIcon, quantity: quantity)
                    )
                }
            }
        }
        return materials
    }

    // 获取蓝图时间研究技能
    func getBlueprintResearchTimeSkills(for blueprintID: Int) -> [(
        typeID: Int, typeName: String, typeIcon: String, level: Int
    )] {
        let query = """
                SELECT typeID, typeName, typeIcon, level
                FROM blueprint_research_time_skills
                WHERE blueprintTypeID = ?
            """
        let result = executeQuery(query, parameters: [blueprintID])
        var skills: [(typeID: Int, typeName: String, typeIcon: String, level: Int)] = []

        if case let .success(rows) = result {
            for row in rows {
                if let typeID = row["typeID"] as? Int,
                    let typeName = row["typeName"] as? String,
                    let typeIcon = row["typeIcon"] as? String,
                    let level = row["level"] as? Int
                {
                    skills.append(
                        (typeID: typeID, typeName: typeName, typeIcon: typeIcon, level: level))
                }
            }
        }
        return skills
    }

    // 获取蓝图复制材料
    func getBlueprintCopyingMaterials(for blueprintID: Int) -> [(
        typeID: Int, typeName: String, typeIcon: String, quantity: Int
    )] {
        let query = """
                SELECT typeID, typeName, typeIcon, quantity
                FROM blueprint_copying_materials
                WHERE blueprintTypeID = ?
            """
        let result = executeQuery(query, parameters: [blueprintID])
        var materials: [(typeID: Int, typeName: String, typeIcon: String, quantity: Int)] = []

        if case let .success(rows) = result {
            for row in rows {
                if let typeID = row["typeID"] as? Int,
                    let typeName = row["typeName"] as? String,
                    let typeIcon = row["typeIcon"] as? String,
                    let quantity = row["quantity"] as? Int
                {
                    materials.append(
                        (typeID: typeID, typeName: typeName, typeIcon: typeIcon, quantity: quantity)
                    )
                }
            }
        }
        return materials
    }

    // 获取蓝图复制技能
    func getBlueprintCopyingSkills(for blueprintID: Int) -> [(
        typeID: Int, typeName: String, typeIcon: String, level: Int
    )] {
        let query = """
                SELECT typeID, typeName, typeIcon, level
                FROM blueprint_copying_skills
                WHERE blueprintTypeID = ?
            """
        let result = executeQuery(query, parameters: [blueprintID])
        var skills: [(typeID: Int, typeName: String, typeIcon: String, level: Int)] = []

        if case let .success(rows) = result {
            for row in rows {
                if let typeID = row["typeID"] as? Int,
                    let typeName = row["typeName"] as? String,
                    let typeIcon = row["typeIcon"] as? String,
                    let level = row["level"] as? Int
                {
                    skills.append(
                        (typeID: typeID, typeName: typeName, typeIcon: typeIcon, level: level))
                }
            }
        }
        return skills
    }

    // 获取蓝图发明材料
    func getBlueprintInventionMaterials(for blueprintID: Int) -> [(
        typeID: Int, typeName: String, typeIcon: String, quantity: Int
    )] {
        let query = """
                SELECT typeID, typeName, typeIcon, quantity
                FROM blueprint_invention_materials
                WHERE blueprintTypeID = ?
            """
        let result = executeQuery(query, parameters: [blueprintID])
        var materials: [(typeID: Int, typeName: String, typeIcon: String, quantity: Int)] = []

        if case let .success(rows) = result {
            for row in rows {
                if let typeID = row["typeID"] as? Int,
                    let typeName = row["typeName"] as? String,
                    let typeIcon = row["typeIcon"] as? String,
                    let quantity = row["quantity"] as? Int
                {
                    materials.append(
                        (typeID: typeID, typeName: typeName, typeIcon: typeIcon, quantity: quantity)
                    )
                }
            }
        }
        return materials
    }

    // 获取蓝图发明技能
    func getBlueprintInventionSkills(for blueprintID: Int) -> [(
        typeID: Int, typeName: String, typeIcon: String, level: Int
    )] {
        let query = """
                SELECT typeID, typeName, typeIcon, level
                FROM blueprint_invention_skills
                WHERE blueprintTypeID = ?
            """
        let result = executeQuery(query, parameters: [blueprintID])
        var skills: [(typeID: Int, typeName: String, typeIcon: String, level: Int)] = []

        if case let .success(rows) = result {
            for row in rows {
                if let typeID = row["typeID"] as? Int,
                    let typeName = row["typeName"] as? String,
                    let typeIcon = row["typeIcon"] as? String,
                    let level = row["level"] as? Int
                {
                    skills.append(
                        (typeID: typeID, typeName: typeName, typeIcon: typeIcon, level: level))
                }
            }
        }
        return skills
    }

    // 获取蓝图发明产出
    func getBlueprintInventionProducts(for blueprintID: Int) -> [(
        typeID: Int, typeName: String, typeIcon: String, quantity: Int, probability: Double
    )] {
        let query = """
                SELECT typeID, typeName, typeIcon, quantity, probability
                FROM blueprint_invention_products
                WHERE blueprintTypeID = ?
            """
        let result = executeQuery(query, parameters: [blueprintID])
        var products:
            [(typeID: Int, typeName: String, typeIcon: String, quantity: Int, probability: Double)] =
                []

        if case let .success(rows) = result {
            for row in rows {
                if let typeID = row["typeID"] as? Int,
                    let typeName = row["typeName"] as? String,
                    let typeIcon = row["typeIcon"] as? String,
                    let quantity = row["quantity"] as? Int,
                    let probability = row["probability"] as? Double
                {
                    products.append(
                        (
                            typeID: typeID, typeName: typeName, typeIcon: typeIcon,
                            quantity: quantity, probability: probability
                        ))
                }
            }
        }
        return products
    }

    // 获取蓝图处理时间
    func getBlueprintProcessTime(for blueprintID: Int) -> (
        manufacturing_time: Int, research_material_time: Int, research_time_time: Int,
        copying_time: Int, invention_time: Int
    )? {
        let query = """
                SELECT manufacturing_time, research_material_time, research_time_time, copying_time, invention_time
                FROM blueprint_process_time
                WHERE blueprintTypeID = ?
            """
        let result = executeQuery(query, parameters: [blueprintID])

        if case let .success(rows) = result, let row = rows.first {
            if let manufacturingTime = row["manufacturing_time"] as? Int,
                let researchMaterialTime = row["research_material_time"] as? Int,
                let researchTimeTime = row["research_time_time"] as? Int,
                let copyingTime = row["copying_time"] as? Int,
                let inventionTime = row["invention_time"] as? Int
            {
                return (
                    manufacturing_time: manufacturingTime,
                    research_material_time: researchMaterialTime,
                    research_time_time: researchTimeTime,
                    copying_time: copyingTime,
                    invention_time: inventionTime
                )
            }
        }
        return nil
    }

    // 获取物品的分类ID
    func getCategoryID(for typeID: Int) -> Int? {
        Logger.debug("DatabaseManager - 获取物品分类ID，typeID: \(typeID)")

        let query = """
                SELECT categoryID
                FROM types
                WHERE type_id = ?
            """

        let result = executeQuery(query, parameters: [typeID])

        switch result {
        case let .success(rows):
            if let row = rows.first,
                let categoryID = row["categoryID"] as? Int
            {
                Logger.debug("DatabaseManager - 找到分类ID: \(categoryID)")
                return categoryID
            }
            Logger.debug("DatabaseManager - 未找到分类ID")
            return nil
        case let .error(error):
            Logger.error("DatabaseManager - 获取分类ID失败: \(error)")
            return nil
        }
    }

    // 获取物品详情
    func getItemDetails(for typeID: Int) -> ItemDetails? {
        let query = """
                SELECT name, description, icon_filename, groupID,
                       volume, repackaged_volume, capacity, mass, marketGroupID,
                       group_name, category_name, categoryID
                FROM types
                WHERE type_id = ?
            """

        let result = executeQuery(query, parameters: [typeID])

        if case let .success(rows) = result,
            let row = rows.first,
            let name = row["name"] as? String,
            let description = row["description"] as? String,
            let iconFileName = row["icon_filename"] as? String,
            let groupName = row["group_name"] as? String,
            let categoryID = row["categoryID"] as? Int,
            let categoryName = row["category_name"] as? String
        {
            let groupID = row["groupID"] as? Int
            let volume = row["volume"] as? Double
            let repackaged_volume = row["repackaged_volume"] as? Double
            let capacity = row["capacity"] as? Double
            let mass = row["mass"] as? Double
            let marketGroupID = row["marketGroupID"] as? Int

            return ItemDetails(
                name: name,
                description: description,
                iconFileName: iconFileName.isEmpty ? DatabaseConfig.defaultItemIcon : iconFileName,
                groupName: groupName,
                categoryID: categoryID,
                categoryName: categoryName,
                roleBonuses: nil,
                typeBonuses: nil,
                typeId: typeID,
                groupID: groupID,
                volume: volume,
                repackagedVolume: repackaged_volume,
                capacity: capacity,
                mass: mass,
                marketGroupID: marketGroupID
            )
        }
        return nil
    }

    // 根据物品ID获取对应的蓝图ID
    func getBlueprintIDForProduct(_ typeID: Int) -> Int? {
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

        switch result {
        case let .success(rows):
            if let row = rows.first,
                let blueprintID = row["blueprintTypeID"] as? Int
            {
                return blueprintID
            }
        case let .error(error):
            Logger.error("Error getting blueprint ID: \(error)")
        }

        return nil
    }

    // 获取蓝图源头
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
                    let typeName = row["name"] as? String,
                    let iconFileName = row["icon_filename"] as? String
                {
                    sources.append(
                        (
                            typeID: typeID,
                            typeName: typeName,
                            typeIcon: iconFileName.isEmpty
                                ? DatabaseConfig.defaultItemIcon : iconFileName
                        ))
                }
            }
        case let .error(error):
            Logger.error("Error getting blueprint sources: \(error)")
        }

        return sources
    }

    // 获取可以精炼/回收得到指定物品的源物品列表
    func getSourceMaterials(for itemID: Int, groupID: Int) -> [(
        typeID: Int, name: String, iconFileName: String, outputQuantityPerUnit: Double
    )]? {
        Logger.debug("DatabaseManager - 获取精炼来源，itemID: \(itemID), groupID: \(groupID)")

        let query: String
        if groupID == 18 {  // 矿物，只看矿石来源
            Logger.debug("DatabaseManager - 构建矿物查询")
            query = """
                    SELECT DISTINCT t.type_id, t.name, t.icon_filename,
                           CAST(tm.output_quantity AS FLOAT) / tm.process_size as output_per_unit
                    FROM typeMaterials tm 
                    JOIN types t ON tm.typeid = t.type_id 
                    WHERE tm.output_material = ? AND tm.categoryid = 25
                    ORDER BY output_per_unit DESC
                """
        } else if groupID == 1996 {  // 突变残渣，只看装备来源
            Logger.debug("DatabaseManager - 构建突变残渣查询")
            query = """
                    SELECT DISTINCT t.type_id, t.name, t.icon_filename,
                           CAST(tm.output_quantity AS FLOAT) / tm.process_size as output_per_unit
                    FROM typeMaterials tm 
                    JOIN types t ON tm.typeid = t.type_id 
                    WHERE tm.output_material = ? AND tm.categoryid = 7 AND tm.output_material != 47975 AND tm.output_material != 48112 
                    ORDER BY output_per_unit DESC
                """
        } else if groupID == 423 {  // 同位素，只看矿石来源
            Logger.debug("DatabaseManager - 构建同位素查询")
            query = """
                    SELECT DISTINCT t.type_id, t.name, t.icon_filename,
                           CAST(tm.output_quantity AS FLOAT) / tm.process_size as output_per_unit
                    FROM typeMaterials tm 
                    JOIN types t ON tm.typeid = t.type_id 
                    WHERE tm.output_material = ? AND tm.categoryid = 25
                    ORDER BY output_per_unit DESC
                """
        } else if groupID == 427 {  // 元素，只看石来源
            Logger.debug("DatabaseManager - 构建元素查询")
            query = """
                    SELECT DISTINCT t.type_id, t.name, t.icon_filename,
                           CAST(tm.output_quantity AS FLOAT) / tm.process_size as output_per_unit
                    FROM typeMaterials tm 
                    JOIN types t ON tm.typeid = t.type_id 
                    WHERE tm.output_material = ? AND tm.categoryid = 25
                    ORDER BY output_per_unit DESC
                """
        } else {
            Logger.debug("DatabaseManager - 不支持的物品组: \(groupID)")
            return nil
        }

        let result = executeQuery(query, parameters: [itemID])
        var materials:
            [(typeID: Int, name: String, iconFileName: String, outputQuantityPerUnit: Double)] = []

        switch result {
        case let .success(rows):
            Logger.debug("DatabaseManager - 查询成功，找到 \(rows.count) 条记录")
            for row in rows {
                if let typeID = row["type_id"] as? Int,
                    let name = row["name"] as? String,
                    let iconFileName = row["icon_filename"] as? String,
                    let outputPerUnit = row["output_per_unit"] as? Double
                {
                    materials.append(
                        (
                            typeID: typeID,
                            name: name,
                            iconFileName: iconFileName.isEmpty
                                ? DatabaseConfig.defaultItemIcon : iconFileName,
                            outputQuantityPerUnit: outputPerUnit
                        ))
                }
            }
            return materials.isEmpty ? nil : materials

        case let .error(error):
            Logger.error("DatabaseManager - 获取精炼来源失败: \(error)")
            return nil
        }
    }

    // 加载组名称
    func loadGroupNames(for groupIDs: [Int]) -> [Int: String] {
        let placeholders = String(repeating: "?,", count: groupIDs.count).dropLast()
        let query = """
                SELECT group_id, name
                FROM groups
                WHERE group_id IN (\(placeholders))
            """

        let result = executeQuery(query, parameters: groupIDs)
        var groupNames: [Int: String] = [:]

        switch result {
        case let .success(rows):
            for row in rows {
                if let id = row["group_id"] as? Int,
                    let name = row["name"] as? String
                {
                    groupNames[id] = name
                }
            }
        case let .error(error):
            Logger.error("加载组名称失败: \(error)")
        }

        return groupNames
    }

    // 获取物品的直接技能要求
    func getDirectSkillRequirements(for typeID: Int) -> [(skillID: Int, level: Int)] {
        let query = """
                SELECT DISTINCT required_skill_id, required_skill_level
                FROM typeSkillRequirement
                WHERE typeid = ?
                ORDER BY required_skill_level DESC
            """

        var requirements: [(skillID: Int, level: Int)] = []

        if case let .success(rows) = executeQuery(query, parameters: [typeID]) {
            for row in rows {
                if let skillID = row["required_skill_id"] as? Int,
                    let level = row["required_skill_level"] as? Int
                {
                    requirements.append((skillID: skillID, level: level))
                }
            }
        }

        return requirements
    }

    // 获取物品的图标文件名
    func getItemIconFileName(for typeID: Int) -> String? {
        let query = "SELECT icon_filename FROM types WHERE type_id = ?"

        if case let .success(rows) = executeQuery(query, parameters: [typeID]),
            let row = rows.first,
            let iconFileName = row["icon_filename"] as? String
        {
            return iconFileName.isEmpty ? DatabaseConfig.defaultItemIcon : iconFileName
        }
        return DatabaseConfig.defaultItemIcon
    }

    func getTraits(for typeID: Int) -> TraitGroup? {
        let roleQuery = """
                SELECT importance, content
                FROM traits
                WHERE typeid = ? AND bonus_type = 'roleBonuses'
                ORDER BY importance
            """

        let typeQuery = """
                SELECT importance, content, skill
                FROM traits
                WHERE typeid = ? AND bonus_type = 'typeBonuses'
                ORDER BY skill, importance
            """

        var roleBonuses: [Trait] = []
        var typeBonuses: [Trait] = []

        // 获取 Role Bonuses
        if case let .success(rows) = executeQuery(roleQuery, parameters: [typeID]) {
            for row in rows {
                if let importance = row["importance"] as? Int,
                    let content = row["content"] as? String
                {
                    roleBonuses.append(
                        Trait(
                            content: content,
                            importance: importance,
                            skill: nil,
                            bonusType: "roleBonuses"
                        ))
                }
            }
        }

        // 获取 Type Bonuses
        if case let .success(rows) = executeQuery(typeQuery, parameters: [typeID]) {
            for row in rows {
                if let importance = row["importance"] as? Int,
                    let content = row["content"] as? String,
                    let skill = row["skill"] as? Int
                {
                    typeBonuses.append(
                        Trait(
                            content: content,
                            importance: importance,
                            skill: skill,
                            bonusType: "typeBonuses"
                        ))
                }
            }
        }

        return TraitGroup(roleBonuses: roleBonuses, typeBonuses: typeBonuses)
    }

    // 获取所有需要特定技能的物品及其需求等级
    func getAllItemsRequiringSkill(skillID: Int) -> [Int: [(
        typeID: Int, name: String, iconFileName: String, categoryID: Int, categoryName: String
    )]] {
        let query = """
                SELECT DISTINCT typeid, typename, typeicon, required_skill_level, categoryID, category_name
                FROM typeSkillRequirement
                WHERE required_skill_id = ?
                AND published = 1
                ORDER BY required_skill_level, typename
            """

        var itemsByLevel:
            [Int: [(
                typeID: Int, name: String, iconFileName: String, categoryID: Int,
                categoryName: String
            )]] = [:]

        if case let .success(rows) = executeQuery(query, parameters: [skillID]) {
            for row in rows {
                if let typeID = row["typeid"] as? Int,
                    let name = row["typename"] as? String,
                    let iconFileName = row["typeicon"] as? String,
                    let level = row["required_skill_level"] as? Int,
                    let categoryID = row["categoryID"] as? Int,
                    let categoryName = row["category_name"] as? String
                {
                    let item = (
                        typeID: typeID,
                        name: name,
                        iconFileName: iconFileName.isEmpty
                            ? DatabaseConfig.defaultItemIcon : iconFileName,
                        categoryID: categoryID,
                        categoryName: categoryName
                    )

                    if itemsByLevel[level] == nil {
                        itemsByLevel[level] = []
                    }
                    // 避免重复添加相同的物品
                    if !itemsByLevel[level]!.contains(where: { $0.typeID == typeID }) {
                        itemsByLevel[level]?.append(item)
                    }
                }
            }
        }

        return itemsByLevel
    }

    // 加载市场物品的通用查询
    func loadMarketItems(whereClause: String, parameters: [Any]) -> [DatabaseListItem] {
        let query = """
                SELECT t.type_id as id, t.name, t.published, t.icon_filename as iconFileName,
                       t.categoryID, t.groupID, t.metaGroupID, t.marketGroupID,
                       t.pg_need as pgNeed, t.cpu_need as cpuNeed, t.rig_cost as rigCost,
                       t.em_damage as emDamage, t.them_damage as themDamage, t.kin_damage as kinDamage, t.exp_damage as expDamage,
                       t.high_slot as highSlot, t.mid_slot as midSlot, t.low_slot as lowSlot,
                       t.rig_slot as rigSlot, t.gun_slot as gunSlot, t.miss_slot as missSlot,
                       t.group_name as groupName
                FROM types t
                WHERE \(whereClause)
                ORDER BY t.metaGroupID
                LIMIT 100
            """

        if case let .success(rows) = executeQuery(query, parameters: parameters) {
            return rows.compactMap { row in
                guard let id = row["id"] as? Int,
                    let name = row["name"] as? String,
                    let categoryId = row["categoryID"] as? Int
                else { return nil }

                let iconFileName = (row["iconFileName"] as? String) ?? "not_found"
                let published = (row["published"] as? Int) ?? 0
                let groupID = row["groupID"] as? Int
                let groupName = row["groupName"] as? String

                return DatabaseListItem(
                    id: id,
                    name: name,
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
                    navigationDestination: ItemInfoMap.getItemInfoView(
                        itemID: id,
                        databaseManager: self
                    )
                )
            }
        }
        return []
    }

    // NPC浏览相关的数据结构
    struct NPCItem {
        let typeID: Int
        let name: String
        let iconFileName: String
    }

    // 获取所有NPC场景（一级目录）
    func getNPCScenes() -> [String] {
        let query = """
                SELECT DISTINCT npc_ship_scene 
                FROM types 
                WHERE npc_ship_scene IS NOT NULL 
                ORDER BY npc_ship_scene
            """

        var scenes: [String] = []
        if case let .success(rows) = executeQuery(query) {
            for row in rows {
                if let scene = row["npc_ship_scene"] as? String {
                    scenes.append(scene)
                }
            }
        }
        return scenes
    }

    // 获取特定场景下的所有阵营（二级目录）
    func getNPCFactions(for scene: String) -> [String] {
        let query = """
                SELECT DISTINCT npc_ship_faction 
                FROM types 
                WHERE npc_ship_scene = ? 
                AND npc_ship_faction IS NOT NULL 
                ORDER BY npc_ship_faction
            """

        var factions: [String] = []
        if case let .success(rows) = executeQuery(query, parameters: [scene]) {
            for row in rows {
                if let faction = row["npc_ship_faction"] as? String {
                    factions.append(faction)
                }
            }
        }
        return factions
    }

    // 获取特定场景和阵营下的所有类型（三级目录）
    func getNPCTypes(for scene: String, faction: String) -> [String] {
        let query = """
                SELECT DISTINCT npc_ship_type 
                FROM types 
                WHERE npc_ship_scene = ? 
                AND npc_ship_faction = ? 
                AND npc_ship_type IS NOT NULL 
                ORDER BY npc_ship_type
            """

        var types: [String] = []
        if case let .success(rows) = executeQuery(query, parameters: [scene, faction]) {
            for row in rows {
                if let type = row["npc_ship_type"] as? String {
                    types.append(type)
                }
            }
        }
        return types
    }

    // 获取特定场景、阵营和类型下的所有物品
    func getNPCItems(for scene: String, faction: String, type: String) -> [NPCItem] {
        let query = """
                SELECT type_id, name, icon_filename 
                FROM types 
                WHERE npc_ship_scene = ? 
                AND npc_ship_faction = ? 
                AND npc_ship_type = ?
                ORDER BY name
            """

        var items: [NPCItem] = []
        if case let .success(rows) = executeQuery(query, parameters: [scene, faction, type]) {
            for row in rows {
                if let typeID = row["type_id"] as? Int,
                    let name = row["name"] as? String,
                    let iconFileName = row["icon_filename"] as? String
                {
                    items.append(NPCItem(typeID: typeID, name: name, iconFileName: iconFileName))
                }
            }
        }
        return items
    }

    // 获取NPC阵营的图标
    func getNPCFactionIcon(for faction: String) -> String? {
        let query = """
                SELECT DISTINCT npc_ship_faction_icon 
                FROM types 
                WHERE npc_ship_faction = ? 
                AND npc_ship_faction_icon IS NOT NULL 
                LIMIT 1
            """

        if case let .success(rows) = executeQuery(query, parameters: [faction]),
            let row = rows.first,
            let iconFileName = row["npc_ship_faction_icon"] as? String
        {
            return iconFileName.isEmpty ? DatabaseConfig.defaultItemIcon : iconFileName
        }
        return DatabaseConfig.defaultItemIcon
    }

    // 在 DatabaseManager 类中添加
    func getItemDamages(for itemID: Int) -> (em: Double, therm: Double, kin: Double, exp: Double)? {
        var damages: (em: Double, therm: Double, kin: Double, exp: Double) = (0, 0, 0, 0)
        var hasData = false

        let query = """
                SELECT attribute_id, value 
                FROM typeAttributes 
                WHERE type_id = ? AND attribute_id IN (114, 116, 117, 118)
            """

        let result = executeQuery(query, parameters: [itemID])

        switch result {
        case let .success(rows):
            for row in rows {
                if let attributeID = row["attribute_id"] as? Int,
                    let value = row["value"] as? Double
                {
                    switch attributeID {
                    case 114: damages.em = value
                    case 118: damages.therm = value
                    case 117: damages.kin = value
                    case 116: damages.exp = value
                    default: break
                    }
                    hasData = true
                }
            }
        case let .error(error):
            Logger.error("Error fetching damages for item \(itemID): \(error)")
            return nil
        }

        return hasData ? damages : nil
    }

    // 获取具有特定属性值的物品
    func getItemsByAttributeValue(attributeID: Int, value: Double) -> [(
        typeID: Int, name: String, iconFileName: String
    )] {
        let query = """
                SELECT t.type_id, t.name, t.icon_filename
                FROM typeAttributes ta
                JOIN types t ON ta.type_id = t.type_id
                WHERE ta.attribute_id = ? AND ta.value = ?
                ORDER BY t.type_id
            """

        var items: [(typeID: Int, name: String, iconFileName: String)] = []

        if case let .success(rows) = executeQuery(query, parameters: [attributeID, value]) {
            for row in rows {
                if let typeID = row["type_id"] as? Int,
                    let name = row["name"] as? String,
                    let iconFileName = row["icon_filename"] as? String
                {
                    items.append(
                        (
                            typeID: typeID,
                            name: name,
                            iconFileName: iconFileName.isEmpty
                                ? DatabaseConfig.defaultItemIcon : iconFileName
                        ))
                }
            }
        }

        return items
    }
    /// 获取物品可以突变的结果
    /// - Parameter typeID: 物品ID
    /// - Returns: 突变结果列表，每个结果包含 typeID、name 和 iconFileName
    func getMutationResults(for typeID: Int) -> [(typeID: Int, name: String, iconFileName: String)]
    {
        let query = """
                SELECT DISTINCT m.resulting_type as type_id, t.name, t.icon_filename
                FROM dynamic_item_mappings m
                LEFT JOIN types t ON m.resulting_type = t.type_id
                WHERE m.applicable_type = ?
                ORDER BY t.name
            """

        if case let .success(rows) = executeQuery(query, parameters: [typeID]) {
            return rows.compactMap { row in
                guard let typeID = row["type_id"] as? Int,
                    let name = row["name"] as? String,
                    let iconFileName = row["icon_filename"] as? String
                else { return nil }
                return (typeID: typeID, name: name, iconFileName: iconFileName)
            }
        }
        return []
    }

    /// 获取用于突变该物品的突变体列表
    /// - Parameter typeID: 物品ID
    /// - Returns: 突变体列表，每个突变体包含 typeID、name 和 iconFileName
    func getRequiredMutaplasmids(for typeID: Int) -> [(
        typeID: Int, name: String, iconFileName: String
    )] {
        let query = """
                SELECT DISTINCT m.type_id, t.name, t.icon_filename
                FROM dynamic_item_mappings m
                LEFT JOIN types t ON m.type_id = t.type_id
                WHERE m.applicable_type = ?
                ORDER BY t.name
            """

        if case let .success(rows) = executeQuery(query, parameters: [typeID]) {
            return rows.compactMap { row in
                guard let typeID = row["type_id"] as? Int,
                    let name = row["name"] as? String,
                    let iconFileName = row["icon_filename"] as? String
                else { return nil }
                return (typeID: typeID, name: name, iconFileName: iconFileName)
            }
        }
        return []
    }

    // 获取突变来源信息
    func getMutationSource(for itemID: Int) -> (
        sourceItems: [(typeID: Int, name: String, iconFileName: String)],
        mutaplasmids: [(typeID: Int, name: String, iconFileName: String)]
    ) {
        let query = """
                SELECT 
                    t1.type_id as source_type_id, 
                    t1.name as source_name, 
                    t1.icon_filename as source_icon,
                    t1.metaGroupID as source_meta,
                    t2.type_id as muta_type_id,
                    t2.name as muta_name,
                    t2.icon_filename as muta_icon,
                    t2.metaGroupID as muta_meta
                FROM dynamic_item_mappings m
                JOIN types t1 ON m.applicable_type = t1.type_id
                JOIN types t2 ON m.type_id = t2.type_id
                WHERE m.resulting_type = ?
                ORDER BY t1.metaGroupID ASC, t1.type_id ASC, t2.metaGroupID ASC, t2.type_id ASC
            """

        var sourceItems: [(typeID: Int, name: String, iconFileName: String)] = []
        var mutaplasmids: [(typeID: Int, name: String, iconFileName: String)] = []
        var seenSourceItems = Set<Int>()
        var seenMutaplasmids = Set<Int>()

        if case let .success(rows) = executeQuery(query, parameters: [itemID]) {
            for row in rows {
                if let sourceTypeID = row["source_type_id"] as? Int,
                    let sourceName = row["source_name"] as? String,
                    let sourceIcon = row["source_icon"] as? String,
                    let mutaTypeID = row["muta_type_id"] as? Int,
                    let mutaName = row["muta_name"] as? String,
                    let mutaIcon = row["muta_icon"] as? String
                {

                    // 添加源装备（如果还没有添加过）
                    if !seenSourceItems.contains(sourceTypeID) {
                        sourceItems.append(
                            (
                                typeID: sourceTypeID,
                                name: sourceName,
                                iconFileName: sourceIcon.isEmpty
                                    ? DatabaseConfig.defaultItemIcon : sourceIcon
                            ))
                        seenSourceItems.insert(sourceTypeID)
                    }

                    // 添加突变质体（如果还没有添加过）
                    if !seenMutaplasmids.contains(mutaTypeID) {
                        mutaplasmids.append(
                            (
                                typeID: mutaTypeID,
                                name: mutaName,
                                iconFileName: mutaIcon.isEmpty
                                    ? DatabaseConfig.defaultItemIcon : mutaIcon
                            ))
                        seenMutaplasmids.insert(mutaTypeID)
                    }
                }
            }
        }

        return (sourceItems: sourceItems, mutaplasmids: mutaplasmids)
    }

    // 获取可以制造指定物品的蓝图列表
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
                                ? DatabaseConfig.defaultItemIcon : blueprintIcon
                        ))

                    // 如果是新的组，添加到组列表
                    if !seenGroups.contains(groupID) {
                        groups.append(
                            (
                                groupID: groupID,
                                name: groupName,
                                iconFileName: blueprintIcon.isEmpty
                                    ? DatabaseConfig.defaultItemIcon : blueprintIcon
                            ))
                        seenGroups.insert(groupID)
                    }
                }
            }
        }

        return (blueprints: blueprints, groups: groups)
    }
}

// 虫洞信息结构体
public struct WormholeInfo: Identifiable {
    public let id: Int
    public let name: String
    public let description: String
    public let icon: String
    public let target: String
    public let stableTime: String
    public let maxStableMass: String
    public let maxJumpMass: String
    public let sizeType: String
}

extension DatabaseManager {
    // 加载虫洞数据
    func loadWormholes() -> [WormholeInfo] {
        let query = """
                SELECT type_id, name, description, icon, target_value, target, stable_time, max_stable_mass, max_jump_mass, size_type
                FROM wormholes
                ORDER BY target_value
            """

        let result = executeQuery(query)
        var wormholes: [WormholeInfo] = []

        switch result {
        case let .success(rows):
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                    let name = row["name"] as? String,
                    let description = row["description"] as? String,
                    let icon = row["icon"] as? String,
                    let target = row["target"] as? String,
                    let stableTime = row["stable_time"] as? String,
                    let maxStableMass = row["max_stable_mass"] as? String,
                    let maxJumpMass = row["max_jump_mass"] as? String,
                    let sizeType = row["size_type"] as? String
                {
                    let wormhole = WormholeInfo(
                        id: typeId,
                        name: name,
                        description: description,
                        icon: icon.isEmpty ? "not_found" : icon,
                        target: target,
                        stableTime: stableTime,
                        maxStableMass: maxStableMass,
                        maxJumpMass: maxJumpMass,
                        sizeType: sizeType
                    )
                    wormholes.append(wormhole)
                }
            }
        case let .error(error):
            Logger.error("加载虫洞数据失败: \(error)")
        }

        return wormholes
    }
}
