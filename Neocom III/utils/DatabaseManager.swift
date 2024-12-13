import Foundation
import SQLite3
import SwiftUI

class DatabaseManager: ObservableObject {
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
            self.databaseUpdated.toggle()
        }
    }
    
    // 获取本地化的数据库名称
    private func getLocalizedDatabaseName() -> String? {
        return NSLocalizedString("DatabaseName", comment: "数据库文件名基于语言")
    }
    
    // 当应用结束时关闭数据库
    func closeDatabase() {
        sqliteManager.closeDatabase()
    }
    
    // 清除查询缓存
    func clearCache() {
        sqliteManager.clearCache()
    }
    
    // 获取查询日志
    func getQueryLogs() -> [(query: String, parameters: [Any], timestamp: Date)] {
        return sqliteManager.getQueryLogs()
    }
    
    // 执行查询
    func executeQuery(_ query: String, parameters: [Any] = [], useCache: Bool = true) -> SQLiteResult {
        return sqliteManager.executeQuery(query, parameters: parameters, useCache: useCache)
    }
    
    // 加载分类
    func loadCategories() -> ([Category], [Category]) {
        let query = "SELECT category_id, name, published, icon_filename FROM categories ORDER BY category_id"
        let result = executeQuery(query)
        
        var published: [Category] = []
        var unpublished: [Category] = []
        
        switch result {
        case .success(let rows):
            for (index, row) in rows.enumerated() {
                Logger.debug("处理第 \(index + 1) 行: \(row)")
                
                // 确保所有必需的字段都存在且类型正确
                guard let categoryId = row["category_id"] as? Int,
                      let name = row["name"] as? String,
                      let iconFilename = row["icon_filename"] as? String else {
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
                
                Logger.debug("创建分类: id=\(category.id), name=\(category.name), published=\(category.published)")
                
                if category.published {
                    published.append(category)
                } else {
                    unpublished.append(category)
                }
            }
            
            Logger.debug("处理完成 - 已发布: \(published.count), 未发布: \(unpublished.count)")
            
        case .error(let error):
            Logger.error("加载分类失败: \(error)")
        }
        
        return (published, unpublished)
    }
    
    // 加载组
    func loadGroups(for categoryID: Int) -> ([Group], [Group]) {
        let query = """
            SELECT group_id, name, categoryID, published, icon_filename
            FROM groups
            WHERE categoryID = ?
        """
        
        let result = executeQuery(query, parameters: [categoryID])
        
        var published: [Group] = []
        var unpublished: [Group] = []
        
        switch result {
        case .success(let rows):
            for row in rows {
                guard let groupId = row["group_id"] as? Int,
                      let name = row["name"] as? String,
                      let catId = row["categoryID"] as? Int,
                      let iconFilename = row["icon_filename"] as? String else {
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
        case .error(let error):
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
        
        if case .success(let metaRows) = metaResult {
            Logger.debug("加载 metaGroups - 获取到 \(metaRows.count) 行数据")
            for row in metaRows {
                if let id = row["metagroup_id"] as? Int,
                   let name = row["name"] as? String {
                    metaGroupNames[id] = name
                    Logger.debug("加载 MetaGroup: ID=\(id), Name=\(name)")
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
        case .success(let rows):
            for row in rows {
                guard let typeId = row["type_id"] as? Int,
                      let name = row["name"] as? String,
                      let iconFilename = row["icon_filename"] as? String,
                      let metaGroupId = row["metaGroupID"] as? Int,
                      let categoryId = row["categoryID"] as? Int,
                      let isPublished = row["published"] as? Int else {
                    Logger.warning("物品基础数据不完整: \(row)")
                    continue
                }
                
                // 获取可选属性
                let pgNeed = row["pg_need"] as? Int
                let cpuNeed = row["cpu_need"] as? Int
                let rigCost = row["rig_cost"] as? Int
                let emDamage = row["em_damage"] as? Double ??
                (row["em_damage"] as? Int).map { Double($0) }
                let themDamage = row["them_damage"] as? Double ??
                (row["them_damage"] as? Int).map { Double($0) }
                let kinDamage = row["kin_damage"] as? Double ??
                (row["kin_damage"] as? Int).map { Double($0) }
                let expDamage = row["exp_damage"] as? Double ??
                (row["exp_damage"] as? Int).map { Double($0) }
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
                    iconFileName: iconFilename.isEmpty ? DatabaseConfig.defaultItemIcon : iconFilename,
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
            
        case .error(let error):
            Logger.error("加载物品失败: \(error)")
        }
        
        // 打印最终的 metaGroupNames 内容
        Logger.debug("最终的 metaGroupNames 内容:")
        for (id, name) in metaGroupNames.sorted(by: { $0.key < $1.key }) {
            Logger.debug("ID: \(id) -> Name: \(name)")
        }
        
        return (published, unpublished, metaGroupNames)
    }
    
    // 加载物品详情
    func loadItemDetails(for itemID: Int) -> ItemDetails? {
        let query = """
            SELECT t.name, t.description, t.icon_filename, t.groupID,
                   t.volume, t.capacity, t.mass,
                   g.name as group_name, c.name as category_name
            FROM types t
            LEFT JOIN groups g ON t.groupID = g.group_id
            LEFT JOIN categories c ON g.categoryID = c.category_id
            WHERE t.type_id = ?
        """
        
        let result = executeQuery(query, parameters: [itemID])
        
        switch result {
        case .success(let rows):
            guard let row = rows.first,
                  let name = row["name"] as? String,
                  let description = row["description"] as? String,
                  let iconFilename = row["icon_filename"] as? String,
                  let groupName = row["group_name"] as? String,
                  let categoryName = row["category_name"] as? String else {
                return nil
            }
            
            let groupID = row["groupID"] as? Int
            let volume = row["volume"] as? Int
            let capacity = row["capacity"] as? Int
            let mass = row["mass"] as? Int
            
            return ItemDetails(
                name: name,
                description: description,
                iconFileName: iconFilename.isEmpty ? DatabaseConfig.defaultItemIcon : iconFilename,
                groupName: groupName,
                categoryName: categoryName,
                roleBonuses: nil,
                typeBonuses: nil,
                typeId: itemID,
                groupID: groupID,
                volume: volume,
                capacity: capacity,
                mass: mass
            )
            
        case .error(let error):
            Logger.error("Error loading item details: \(error)")
            return nil
        }
    }
    
    // 搜索物品
    func searchItems(searchText: String, categoryID: Int? = nil, groupID: Int? = nil) -> ([DatabaseListItem], [Int: String]) {
        var query = """
            SELECT t.type_id, t.name, t.icon_filename, t.published, t.categoryID,
                   t.pg_need, t.cpu_need, t.rig_cost,
                   t.em_damage, t.them_damage, t.kin_damage, t.exp_damage,
                   t.high_slot, t.mid_slot, t.low_slot, t.rig_slot,
                   t.gun_slot, t.miss_slot, t.metaGroupID
            FROM types t
            WHERE t.name LIKE ?
        """
        
        var parameters: [Any] = ["%\(searchText)%"]
        
        if let categoryID = categoryID {
            query += " AND t.categoryID = ?"
            parameters.append(categoryID)
        }
        
        if let groupID = groupID {
            query += " AND t.groupID = ?"
            parameters.append(groupID)
        }
        
        query += " ORDER BY t.name"
        
        let result = executeQuery(query, parameters: parameters)
        var items: [DatabaseListItem] = []
        
        if case .success(let rows) = result {
            for row in rows {
                if let id = row["type_id"] as? Int,
                   let name = row["name"] as? String,
                   let iconFilename = row["icon_filename"] as? String,
                   let categoryId = row["categoryID"] as? Int,
                   let isPublished = row["published"] as? Int {
                    
                    items.append(DatabaseListItem(
                        id: id,
                        name: name,
                        iconFileName: iconFilename.isEmpty ? DatabaseConfig.defaultItemIcon : iconFilename,
                        published: isPublished != 0,
                        categoryID: categoryId,
                        pgNeed: row["pg_need"] as? Int,
                        cpuNeed: row["cpu_need"] as? Int,
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
                        metaGroupID: row["metaGroupID"] as? Int,
                        navigationDestination: ItemInfoMap.getItemInfoView(
                            itemID: id,
                            categoryID: categoryId,
                            databaseManager: self
                        )
                    ))
                }
            }
        }
        
        // 获取 metaGroup 名称
        let metaGroupIDs = Set(items.compactMap { $0.metaGroupID })
        let metaGroupNames = loadMetaGroupNames(for: Array(metaGroupIDs))
        
        return (items, metaGroupNames)
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
        case .success(let rows):
            for row in rows {
                if let id = row["metagroup_id"] as? Int,
                   let name = row["name"] as? String {
                    metaGroupNames[id] = name
                }
            }
        case .error(let error):
            Logger.error("加载 MetaGroup 名称失败: \(error)")
        }
        
        return metaGroupNames
    }
    
    // 获取类型名称
    func getTypeName(for typeID: Int) -> String? {
        let query = "SELECT name FROM types WHERE type_id = ?"
        let result = executeQuery(query, parameters: [typeID])
        
        if case .success(let rows) = result,
           let row = rows.first,
           let name = row["name"] as? String {
            return name
        }
        return nil
    }
    
    // 获取属性名称
    func getAttributeName(for typeID: Int) -> String? {
        let query = "SELECT display_name FROM dogmaAttributes WHERE attribute_id = ?"
        let result = executeQuery(query, parameters: [typeID])
        
        if case .success(let rows) = result,
           let row = rows.first,
           let name = row["display_name"] as? String {
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
        
        if case .success(let rows) = categoryResult {
            for row in rows {
                guard let id = row["attribute_category_id"] as? Int,
                      let name = row["name"] as? String,
                      let description = row["description"] as? String else {
                    continue
                }
                categories[id] = DogmaAttributeCategory(id: id, name: name, description: description)
            }
        }
        
        // 2. 加载物品的所有属性值
        let attributeQuery = """
            SELECT da.attribute_id, da.categoryID, da.name, da.display_name, da.iconID, ta.value, da.unitID,
                   COALESCE(i.iconFile_new, '') as icon_filename
            FROM typeAttributes ta
            JOIN dogmaAttributes da ON ta.attribute_id = da.attribute_id
            LEFT JOIN iconIDs i ON da.iconID = i.icon_id
            WHERE ta.type_id = ?
            ORDER BY da.categoryID, da.attribute_id
        """
        
        let attributeResult = executeQuery(attributeQuery, parameters: [typeID])
        var attributesByCategory: [Int: [DogmaAttribute]] = [:]
        
        if case .success(let rows) = attributeResult {
            for row in rows {
                guard let attributeId = row["attribute_id"] as? Int,
                      let categoryId = row["categoryID"] as? Int,
                      let name = row["name"] as? String,
                      let iconId = row["iconID"] as? Int,
                      let value = row["value"] as? Double else {
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
        
        if case .success(let rows) = executeQuery(query) {
            for row in rows {
                if let attributeId = row["attribute_id"] as? Int,
                   let unitName = row["unitName"] as? String {
                    units[attributeId] = unitName
                }
            }
        }
        
        return units
    }
    
    // 获取组名
    func getGroupName(for groupID: Int) -> String? {
        let query = "SELECT name FROM groups WHERE group_id = ?"
        let result = executeQuery(query, parameters: [groupID])
        
        if case .success(let rows) = result,
           let row = rows.first,
           let name = row["name"] as? String {
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
        case .success(let rows):
            for row in rows {
                guard let process_size = row["process_size"] as? Int,
                      let outputMaterial = row["output_material"] as? Int,
                      let outputQuantity = row["output_quantity"] as? Int,
                      let outputMaterialName = row["output_material_name"] as? String,
                      let outputMaterialIcon = row["output_material_icon"] as? String else {
                    continue
                }
                
                let material = TypeMaterial(
                    process_size: process_size,
                    outputMaterial: outputMaterial,
                    outputQuantity: outputQuantity,
                    outputMaterialName: outputMaterialName,
                    outputMaterialIcon: outputMaterialIcon.isEmpty ? DatabaseConfig.defaultItemIcon : outputMaterialIcon
                )
                materials.append(material)
            }
            
            return materials.isEmpty ? nil : materials
            
        case .error(let error):
            Logger.error("Error fetching type materials: \(error)")
            return nil
        }
    }
    
    // MARK: - Blueprint Methods
    // 获取蓝图制造材料
    func getBlueprintManufacturingMaterials(for blueprintID: Int) -> [(typeID: Int, typeName: String, typeIcon: String, quantity: Int)] {
        let query = """
            SELECT typeID, typeName, typeIcon, quantity
            FROM blueprint_manufacturing_materials
            WHERE blueprintTypeID = ?
        """
        let result = executeQuery(query, parameters: [blueprintID])
        var materials: [(typeID: Int, typeName: String, typeIcon: String, quantity: Int)] = []
        
        if case .success(let rows) = result {
            for row in rows {
                if let typeID = row["typeID"] as? Int,
                   let typeName = row["typeName"] as? String,
                   let typeIcon = row["typeIcon"] as? String,
                   let quantity = row["quantity"] as? Int {
                    materials.append((typeID: typeID, typeName: typeName, typeIcon: typeIcon, quantity: quantity))
                }
            }
        }
        return materials
    }
    
    // 获取蓝图制造产出
    func getBlueprintManufacturingOutput(for blueprintID: Int) -> [(typeID: Int, typeName: String, typeIcon: String, quantity: Int)] {
        let query = """
            SELECT typeID, typeName, typeIcon, quantity
            FROM blueprint_manufacturing_output
            WHERE blueprintTypeID = ?
        """
        let result = executeQuery(query, parameters: [blueprintID])
        var products: [(typeID: Int, typeName: String, typeIcon: String, quantity: Int)] = []
        
        if case .success(let rows) = result {
            for row in rows {
                if let typeID = row["typeID"] as? Int,
                   let typeName = row["typeName"] as? String,
                   let typeIcon = row["typeIcon"] as? String,
                   let quantity = row["quantity"] as? Int {
                    products.append((typeID: typeID, typeName: typeName, typeIcon: typeIcon, quantity: quantity))
                }
            }
        }
        return products
    }
    
    // 获取蓝图制造所需技能
    func getBlueprintManufacturingSkills(for blueprintID: Int) -> [(typeID: Int, typeName: String, typeIcon: String, level: Int)] {
        let query = """
            SELECT typeID, typeName, typeIcon, level
            FROM blueprint_manufacturing_skills
            WHERE blueprintTypeID = ?
        """
        let result = executeQuery(query, parameters: [blueprintID])
        var skills: [(typeID: Int, typeName: String, typeIcon: String, level: Int)] = []
        
        if case .success(let rows) = result {
            for row in rows {
                if let typeID = row["typeID"] as? Int,
                   let typeName = row["typeName"] as? String,
                   let typeIcon = row["typeIcon"] as? String,
                   let level = row["level"] as? Int {
                    skills.append((typeID: typeID, typeName: typeName, typeIcon: typeIcon, level: level))
                }
            }
        }
        return skills
    }
    
    // 获取蓝图材料研究材料
    func getBlueprintResearchMaterialMaterials(for blueprintID: Int) -> [(typeID: Int, typeName: String, typeIcon: String, quantity: Int)] {
        let query = """
            SELECT typeID, typeName, typeIcon, quantity
            FROM blueprint_research_material_materials
            WHERE blueprintTypeID = ?
        """
        let result = executeQuery(query, parameters: [blueprintID])
        var materials: [(typeID: Int, typeName: String, typeIcon: String, quantity: Int)] = []
        
        if case .success(let rows) = result {
            for row in rows {
                if let typeID = row["typeID"] as? Int,
                   let typeName = row["typeName"] as? String,
                   let typeIcon = row["typeIcon"] as? String,
                   let quantity = row["quantity"] as? Int {
                    materials.append((typeID: typeID, typeName: typeName, typeIcon: typeIcon, quantity: quantity))
                }
            }
        }
        return materials
    }
    
    // 获取蓝图材料研究技能
    func getBlueprintResearchMaterialSkills(for blueprintID: Int) -> [(typeID: Int, typeName: String, typeIcon: String, level: Int)] {
        let query = """
            SELECT typeID, typeName, typeIcon, level
            FROM blueprint_research_material_skills
            WHERE blueprintTypeID = ?
        """
        let result = executeQuery(query, parameters: [blueprintID])
        var skills: [(typeID: Int, typeName: String, typeIcon: String, level: Int)] = []
        
        if case .success(let rows) = result {
            for row in rows {
                if let typeID = row["typeID"] as? Int,
                   let typeName = row["typeName"] as? String,
                   let typeIcon = row["typeIcon"] as? String,
                   let level = row["level"] as? Int {
                    skills.append((typeID: typeID, typeName: typeName, typeIcon: typeIcon, level: level))
                }
            }
        }
        return skills
    }
    
    // 获取蓝图时间研究材料
    func getBlueprintResearchTimeMaterials(for blueprintID: Int) -> [(typeID: Int, typeName: String, typeIcon: String, quantity: Int)] {
        let query = """
            SELECT typeID, typeName, typeIcon, quantity
            FROM blueprint_research_time_materials
            WHERE blueprintTypeID = ?
        """
        let result = executeQuery(query, parameters: [blueprintID])
        var materials: [(typeID: Int, typeName: String, typeIcon: String, quantity: Int)] = []
        
        if case .success(let rows) = result {
            for row in rows {
                if let typeID = row["typeID"] as? Int,
                   let typeName = row["typeName"] as? String,
                   let typeIcon = row["typeIcon"] as? String,
                   let quantity = row["quantity"] as? Int {
                    materials.append((typeID: typeID, typeName: typeName, typeIcon: typeIcon, quantity: quantity))
                }
            }
        }
        return materials
    }
    
    // 获取蓝图时间研究技能
    func getBlueprintResearchTimeSkills(for blueprintID: Int) -> [(typeID: Int, typeName: String, typeIcon: String, level: Int)] {
        let query = """
            SELECT typeID, typeName, typeIcon, level
            FROM blueprint_research_time_skills
            WHERE blueprintTypeID = ?
        """
        let result = executeQuery(query, parameters: [blueprintID])
        var skills: [(typeID: Int, typeName: String, typeIcon: String, level: Int)] = []
        
        if case .success(let rows) = result {
            for row in rows {
                if let typeID = row["typeID"] as? Int,
                   let typeName = row["typeName"] as? String,
                   let typeIcon = row["typeIcon"] as? String,
                   let level = row["level"] as? Int {
                    skills.append((typeID: typeID, typeName: typeName, typeIcon: typeIcon, level: level))
                }
            }
        }
        return skills
    }
    
    // 获取蓝图复制材料
    func getBlueprintCopyingMaterials(for blueprintID: Int) -> [(typeID: Int, typeName: String, typeIcon: String, quantity: Int)] {
        let query = """
            SELECT typeID, typeName, typeIcon, quantity
            FROM blueprint_copying_materials
            WHERE blueprintTypeID = ?
        """
        let result = executeQuery(query, parameters: [blueprintID])
        var materials: [(typeID: Int, typeName: String, typeIcon: String, quantity: Int)] = []
        
        if case .success(let rows) = result {
            for row in rows {
                if let typeID = row["typeID"] as? Int,
                   let typeName = row["typeName"] as? String,
                   let typeIcon = row["typeIcon"] as? String,
                   let quantity = row["quantity"] as? Int {
                    materials.append((typeID: typeID, typeName: typeName, typeIcon: typeIcon, quantity: quantity))
                }
            }
        }
        return materials
    }
    
    // 获取蓝图复制技能
    func getBlueprintCopyingSkills(for blueprintID: Int) -> [(typeID: Int, typeName: String, typeIcon: String, level: Int)] {
        let query = """
            SELECT typeID, typeName, typeIcon, level
            FROM blueprint_copying_skills
            WHERE blueprintTypeID = ?
        """
        let result = executeQuery(query, parameters: [blueprintID])
        var skills: [(typeID: Int, typeName: String, typeIcon: String, level: Int)] = []
        
        if case .success(let rows) = result {
            for row in rows {
                if let typeID = row["typeID"] as? Int,
                   let typeName = row["typeName"] as? String,
                   let typeIcon = row["typeIcon"] as? String,
                   let level = row["level"] as? Int {
                    skills.append((typeID: typeID, typeName: typeName, typeIcon: typeIcon, level: level))
                }
            }
        }
        return skills
    }
    
    // 获取蓝图发明材料
    func getBlueprintInventionMaterials(for blueprintID: Int) -> [(typeID: Int, typeName: String, typeIcon: String, quantity: Int)] {
        let query = """
            SELECT typeID, typeName, typeIcon, quantity
            FROM blueprint_invention_materials
            WHERE blueprintTypeID = ?
        """
        let result = executeQuery(query, parameters: [blueprintID])
        var materials: [(typeID: Int, typeName: String, typeIcon: String, quantity: Int)] = []
        
        if case .success(let rows) = result {
            for row in rows {
                if let typeID = row["typeID"] as? Int,
                   let typeName = row["typeName"] as? String,
                   let typeIcon = row["typeIcon"] as? String,
                   let quantity = row["quantity"] as? Int {
                    materials.append((typeID: typeID, typeName: typeName, typeIcon: typeIcon, quantity: quantity))
                }
            }
        }
        return materials
    }
    
    // 获取蓝图发明技能
    func getBlueprintInventionSkills(for blueprintID: Int) -> [(typeID: Int, typeName: String, typeIcon: String, level: Int)] {
        let query = """
            SELECT typeID, typeName, typeIcon, level
            FROM blueprint_invention_skills
            WHERE blueprintTypeID = ?
        """
        let result = executeQuery(query, parameters: [blueprintID])
        var skills: [(typeID: Int, typeName: String, typeIcon: String, level: Int)] = []
        
        if case .success(let rows) = result {
            for row in rows {
                if let typeID = row["typeID"] as? Int,
                   let typeName = row["typeName"] as? String,
                   let typeIcon = row["typeIcon"] as? String,
                   let level = row["level"] as? Int {
                    skills.append((typeID: typeID, typeName: typeName, typeIcon: typeIcon, level: level))
                }
            }
        }
        return skills
    }
    
    // 获取蓝图发明产出
    func getBlueprintInventionProducts(for blueprintID: Int) -> [(typeID: Int, typeName: String, typeIcon: String, quantity: Int, probability: Double)] {
        let query = """
            SELECT typeID, typeName, typeIcon, quantity, probability
            FROM blueprint_invention_products
            WHERE blueprintTypeID = ?
        """
        let result = executeQuery(query, parameters: [blueprintID])
        var products: [(typeID: Int, typeName: String, typeIcon: String, quantity: Int, probability: Double)] = []
        
        if case .success(let rows) = result {
            for row in rows {
                if let typeID = row["typeID"] as? Int,
                   let typeName = row["typeName"] as? String,
                   let typeIcon = row["typeIcon"] as? String,
                   let quantity = row["quantity"] as? Int,
                   let probability = row["probability"] as? Double {
                    products.append((typeID: typeID, typeName: typeName, typeIcon: typeIcon, quantity: quantity, probability: probability))
                }
            }
        }
        return products
    }
    
    // 获取蓝图处理时间
    func getBlueprintProcessTime(for blueprintID: Int) -> (manufacturing_time: Int, research_material_time: Int, research_time_time: Int, copying_time: Int, invention_time: Int)? {
        let query = """
            SELECT manufacturing_time, research_material_time, research_time_time, copying_time, invention_time
            FROM blueprint_process_time
            WHERE blueprintTypeID = ?
        """
        let result = executeQuery(query, parameters: [blueprintID])
        
        if case .success(let rows) = result, let row = rows.first {
            if let manufacturingTime = row["manufacturing_time"] as? Int,
               let researchMaterialTime = row["research_material_time"] as? Int,
               let researchTimeTime = row["research_time_time"] as? Int,
               let copyingTime = row["copying_time"] as? Int,
               let inventionTime = row["invention_time"] as? Int {
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
    
    // 获取物品的categoryID
    func getCategoryID(for typeID: Int) -> Int? {
        let query = "SELECT categoryID FROM types WHERE type_id = ?"
        let result = executeQuery(query, parameters: [typeID])
        
        if case .success(let rows) = result,
           let row = rows.first,
           let categoryID = row["categoryID"] as? Int {
            return categoryID
        }
        return nil
    }
    
    // 获取物品详情
    func getItemDetails(for typeID: Int) -> ItemDetails? {
        let query = """
            SELECT t.name, t.description, t.icon_filename, t.groupID,
                   t.volume, t.capacity, t.mass,
                   g.name as group_name, c.name as category_name
            FROM types t
            LEFT JOIN groups g ON t.groupID = g.group_id
            LEFT JOIN categories c ON g.categoryID = c.category_id
            WHERE t.type_id = ?
        """
        
        let result = executeQuery(query, parameters: [typeID])
        
        if case .success(let rows) = result,
           let row = rows.first,
           let name = row["name"] as? String,
           let description = row["description"] as? String,
           let iconFileName = row["icon_filename"] as? String,
           let groupName = row["group_name"] as? String,
           let categoryName = row["category_name"] as? String {
            
            let groupID = row["groupID"] as? Int
            let volume = row["volume"] as? Int
            let capacity = row["capacity"] as? Int
            let mass = row["mass"] as? Int
            
            return ItemDetails(
                name: name,
                description: description,
                iconFileName: iconFileName.isEmpty ? DatabaseConfig.defaultItemIcon : iconFileName,
                groupName: groupName,
                categoryName: categoryName,
                roleBonuses: nil,
                typeBonuses: nil,
                typeId: typeID,
                groupID: groupID,
                volume: volume,
                capacity: capacity,
                mass: mass
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
        case .success(let rows):
            if let row = rows.first,
               let blueprintID = row["blueprintTypeID"] as? Int {
                return blueprintID
            }
        case .error(let error):
            Logger.error("Error getting blueprint ID: \(error)")
        }
        
        return nil
    }
    
    // 获取蓝图的图标文件名
    func getBlueprintIconFileName(_ blueprintID: Int) -> String? {
        let query = """
            SELECT icon_filename
            FROM types
            WHERE type_id = ?
        """
        
        let result = executeQuery(query, parameters: [blueprintID])
        
        switch result {
        case .success(let rows):
            if let row = rows.first,
               let iconFileName = row["icon_filename"] as? String {
                return iconFileName.isEmpty ? DatabaseConfig.defaultItemIcon : iconFileName
            }
        case .error(let error):
            Logger.error("Error getting blueprint icon: \(error)")
        }
        
        return nil
    }
    
    // 获取蓝图源头
    func getBlueprintSource(for blueprintID: Int) -> [(typeID: Int, typeName: String, typeIcon: String)] {
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
        case .success(let rows):
            for row in rows {
                if let typeID = row["type_id"] as? Int,
                   let typeName = row["name"] as? String,
                   let iconFileName = row["icon_filename"] as? String {
                    sources.append((
                        typeID: typeID,
                        typeName: typeName,
                        typeIcon: iconFileName.isEmpty ? DatabaseConfig.defaultItemIcon : iconFileName
                    ))
                }
            }
        case .error(let error):
            Logger.error("Error getting blueprint sources: \(error)")
        }
        
        return sources
    }
    
    // 获取可以精炼/回收得到指定物品的源物品列表
    func getSourceMaterials(for itemID: Int, groupID: Int) -> [(typeID: Int, name: String, iconFileName: String, outputQuantityPerUnit: Double)]? {
        let query: String
        if groupID == 18 { // 矿物，只看矿石来源
            query = """
                SELECT DISTINCT t.type_id, t.name, t.icon_filename,
                       CAST(tm.output_quantity AS FLOAT) / tm.process_size as output_per_unit
                FROM typeMaterials tm 
                JOIN types t ON tm.typeid = t.type_id 
                WHERE tm.output_material = ? AND tm.categoryid = 25
                ORDER BY output_per_unit DESC
            """
        } else if groupID == 1996 { // 突变残渣，只看装备来源
            query = """
                SELECT DISTINCT t.type_id, t.name, t.icon_filename,
                       CAST(tm.output_quantity AS FLOAT) / tm.process_size as output_per_unit
                FROM typeMaterials tm 
                JOIN types t ON tm.typeid = t.type_id 
                WHERE tm.output_material = ? AND tm.categoryid = 7 AND tm.output_material != 47975 AND tm.output_material != 48112 
                ORDER BY output_per_unit DESC
            """
        } else if groupID == 423 { // 同位素，只看矿石来源
            query = """
                SELECT DISTINCT t.type_id, t.name, t.icon_filename,
                       CAST(tm.output_quantity AS FLOAT) / tm.process_size as output_per_unit
                FROM typeMaterials tm 
                JOIN types t ON tm.typeid = t.type_id 
                WHERE tm.output_material = ? AND tm.categoryid = 25
                ORDER BY output_per_unit DESC
            """
        } else if groupID == 427 { //元素，只看矿石来源
            query = """
                SELECT DISTINCT t.type_id, t.name, t.icon_filename,
                       CAST(tm.output_quantity AS FLOAT) / tm.process_size as output_per_unit
                FROM typeMaterials tm 
                JOIN types t ON tm.typeid = t.type_id 
                WHERE tm.output_material = ? AND tm.categoryid = 25
                ORDER BY output_per_unit DESC
            """
        } else {
            return nil
        }
        
        let result = executeQuery(query, parameters: [itemID])
        var materials: [(typeID: Int, name: String, iconFileName: String, outputQuantityPerUnit: Double)] = []
        
        switch result {
        case .success(let rows):
            for row in rows {
                if let typeID = row["type_id"] as? Int,
                   let name = row["name"] as? String,
                   let iconFileName = row["icon_filename"] as? String,
                   let outputPerUnit = row["output_per_unit"] as? Double {
                    materials.append((
                        typeID: typeID,
                        name: name,
                        iconFileName: iconFileName.isEmpty ? DatabaseConfig.defaultItemIcon : iconFileName,
                        outputQuantityPerUnit: outputPerUnit
                    ))
                }
            }
            return materials.isEmpty ? nil : materials
            
        case .error(let error):
            Logger.error("Error getting source materials: \(error)")
            return nil
        }
    }
}
