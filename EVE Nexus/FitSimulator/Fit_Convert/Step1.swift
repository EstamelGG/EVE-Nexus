import Foundation

/// Step1实现 - 物品、属性和效果的采集阶段
class Step1 {
    private let databaseManager: DatabaseManager
    
    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }
    
    /// 执行Step1处理 - 物品、属性和效果的采集
    /// - Parameter input: 模拟输入数据
    /// - Returns: 处理后的数据，包含物品属性和效果
    func process(input: SimulationInput) -> (itemAttributes: [Int: [Int: Double]], 
                                           itemAttributesByName: [Int: [String: Double]],
                                           itemEffects: [Int: [EffectDetail]]) {
        Logger.info("执行Step1 - 物品、属性和效果的采集阶段")
        
        // 1. 收集所有物品和技能的ID
        let (itemIds, skillIds, initialAttributes, initialAttributesByName, typeInfo) = collectIdsAndInitialAttributes(input: input)
        Logger.info("收集到\(itemIds.count)个物品和\(skillIds.count)个技能")
        
        // 记录植入体和增效剂的数量
        Logger.info("包含\(input.implants.count)个植入体和增效剂")
        
        // 2. 收集属性和效果
        let (attributes, attributesByName, effects) = collectAttributesAndEffects(
            itemIds: itemIds,
            skillIds: skillIds,
            initialAttributes: initialAttributes,
            initialAttributesByName: initialAttributesByName,
            typeInfo: typeInfo,
            characterSkills: input.characterSkills
        )
        
        Logger.info("Step1完成 - 物品、属性和效果采集完成，共\(attributes.count)个物品/技能")
        
        return (attributes, attributesByName, effects)
    }
    
    /// 收集所有物品和技能的ID以及初始属性
    /// - Parameter input: 模拟输入数据
    /// - Returns: (物品ID数组, 技能ID数组, 初始属性字典, 初始属性名称字典, 类型信息)
    private func collectIdsAndInitialAttributes(input: SimulationInput) -> (
        [Int],
        [Int],
        [Int: [Int: Double]],
        [Int: [String: Double]],
        [Int: (name: String, groupId: Int)]
    ) {
        var itemIds = Set<Int>()
        var initialAttributes: [Int: [Int: Double]] = [:]
        var initialAttributesByName: [Int: [String: Double]] = [:]
        var typeInfo: [Int: (name: String, groupId: Int)] = [:]
        
        // 添加飞船ID和属性
        let shipId = input.ship.typeId
        itemIds.insert(shipId)
        initialAttributes[shipId] = input.ship.baseAttributes
        initialAttributesByName[shipId] = input.ship.baseAttributesByName
        typeInfo[shipId] = (name: input.ship.name, groupId: input.ship.groupID)
        
        // 添加角色ID和属性
        let characterId = input.character.typeId
        itemIds.insert(characterId)
        initialAttributes[characterId] = input.character.baseAttributes
        initialAttributesByName[characterId] = input.character.baseAttributesByName
        typeInfo[characterId] = (name: "Character", groupId: 0)
        
        // 添加所有模块ID和属性
        for module in input.modules {
            let moduleId = module.typeId
            itemIds.insert(moduleId)
            initialAttributes[moduleId] = module.attributes
            initialAttributesByName[moduleId] = module.attributesByName
            typeInfo[moduleId] = (name: module.name, groupId: module.groupID)
            
            // 添加弹药ID和属性（如果有）
            if let charge = module.charge {
                let chargeId = charge.typeId
                itemIds.insert(chargeId)
                initialAttributes[chargeId] = charge.attributes
                initialAttributesByName[chargeId] = charge.attributesByName
                typeInfo[chargeId] = (name: charge.name, groupId: charge.groupID)
            }
        }
        
        // 添加所有无人机ID和属性
        for drone in input.drones {
            let droneId = drone.typeId
            itemIds.insert(droneId)
            initialAttributes[droneId] = drone.attributes
            initialAttributesByName[droneId] = drone.attributesByName
            typeInfo[droneId] = (name: drone.name, groupId: drone.groupID)
        }
        
        // 添加所有舰载机ID和属性
        if let fighters = input.fighters {
            for fighter in fighters {
                let fighterId = fighter.typeId
                itemIds.insert(fighterId)
                initialAttributes[fighterId] = fighter.attributes
                initialAttributesByName[fighterId] = fighter.attributesByName
                typeInfo[fighterId] = (name: fighter.name, groupId: fighter.groupID)
            }
        }
        
        // 添加所有植入体和增效剂的ID和属性
        for implant in input.implants {
            let implantId = implant.typeId
            itemIds.insert(implantId)
            initialAttributes[implantId] = implant.attributes
            initialAttributesByName[implantId] = implant.attributesByName
            typeInfo[implantId] = (name: implant.name, groupId: 0) // 植入体和增效剂的groupID可能需要从数据库获取
        }
        
        // 获取所有技能ID
        let skillIds = Array(input.characterSkills.keys)
        
        // 初始化技能的属性字典，并设置技能等级
        for skillId in skillIds {
            initialAttributes[skillId] = [:]
            initialAttributesByName[skillId] = [:]
            
            // 设置技能等级属性 (attribute_id=280)
            let level = input.characterSkills[skillId] ?? 0
            initialAttributes[skillId]?[280] = Double(level)
            initialAttributesByName[skillId]?["skillLevel"] = Double(level)
        }
        
        // 目前暂不包含货仓和环境效果
        
        return (Array(itemIds), skillIds, initialAttributes, initialAttributesByName, typeInfo)
    }
    
    /// 收集属性和效果
    /// - Parameters:
    ///   - itemIds: 物品ID数组
    ///   - skillIds: 技能ID数组
    ///   - initialAttributes: 初始属性字典
    ///   - initialAttributesByName: 初始属性名称字典
    ///   - typeInfo: 类型信息
    ///   - characterSkills: 角色技能等级
    /// - Returns: (属性字典, 属性名称字典, 效果字典)
    private func collectAttributesAndEffects(
        itemIds: [Int],
        skillIds: [Int],
        initialAttributes: [Int: [Int: Double]],
        initialAttributesByName: [Int: [String: Double]],
        typeInfo: [Int: (name: String, groupId: Int)],
        characterSkills: [Int: Int]
    ) -> (
        [Int: [Int: Double]],
        [Int: [String: Double]],
        [Int: [EffectDetail]]
    ) {
        // 复制初始属性字典
        var attributes = initialAttributes
        var attributesByName = initialAttributesByName
        var effects: [Int: [EffectDetail]] = [:]
        
        // 为所有物品和技能初始化效果数组
        for id in itemIds + skillIds {
            effects[id] = []
        }
        
        // 合并所有需要查询的ID
        let allIds = itemIds + skillIds
        
        if allIds.isEmpty {
            return (attributes, attributesByName, effects)
        }
        
        // 1. 收集缺失的类型信息和特殊属性
        var updatedTypeInfo = typeInfo
        let idsNeedingInfo = allIds.filter { id in
            let needsTypeInfo = !typeInfo.keys.contains(id)
            let needsSpecialAttributes = attributes[id]?[4] == nil || // mass
                                       attributes[id]?[38] == nil || // capacity
                                       attributes[id]?[161] == nil   // volume
            return needsTypeInfo || needsSpecialAttributes
        }
        
        if !idsNeedingInfo.isEmpty {
            collectTypeInfoAndSpecialAttributes(
                ids: idsNeedingInfo,
                typeInfo: &updatedTypeInfo,
                attributes: &attributes,
                attributesByName: &attributesByName
            )
        }
        
        // 2. 收集所有物品和技能的属性
        collectAttributes(
            ids: allIds,
            attributes: &attributes,
            attributesByName: &attributesByName
        )
        
        // 3. 收集所有物品和技能的效果
        collectEffects(
            ids: allIds,
            effects: &effects,
            typeInfo: updatedTypeInfo
        )
        
        // 4. 收集dbuffCollection表中的额外修饰器
        collectDbuffCollectionModifiers(
            ids: allIds,
            effects: &effects,
            typeInfo: updatedTypeInfo
        )
        
        Logger.info("完成\(allIds.count)个物品和技能的属性和效果采集")
        
        return (attributes, attributesByName, effects)
    }
    
    /// 收集类型信息和特殊属性（合并方法）
    /// - Parameters:
    ///   - ids: 需要收集信息的ID数组
    ///   - typeInfo: 类型信息字典（会被修改）
    ///   - attributes: 属性字典（会被修改）
    ///   - attributesByName: 属性名称字典（会被修改）
    private func collectTypeInfoAndSpecialAttributes(
        ids: [Int],
        typeInfo: inout [Int: (name: String, groupId: Int)],
        attributes: inout [Int: [Int: Double]],
        attributesByName: inout [Int: [String: Double]]
    ) {
        // 构建IN查询的占位符
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        
        // 收集类型信息和特殊属性（单次查询）
        let typeQuery = """
            SELECT type_id, name, groupID, mass, capacity, volume
            FROM types
            WHERE type_id IN (\(placeholders))
        """
        
        if case let .success(rows) = databaseManager.executeQuery(typeQuery, parameters: ids) {
            for row in rows {
                if let typeId = row["type_id"] as? Int {
                    // 收集类型信息
                    if let name = row["name"] as? String,
                       let groupId = row["groupID"] as? Int {
                        typeInfo[typeId] = (name: name, groupId: groupId)
                    }
                    
                    // 添加mass属性(id=4)，如果原先不存在
                    if attributes[typeId]?[4] == nil, let mass = row["mass"] as? Double {
                        attributes[typeId]?[4] = mass
                        attributesByName[typeId]?["mass"] = mass
                    }
                    
                    // 添加capacity属性(id=38)，如果原先不存在
                    if attributes[typeId]?[38] == nil, let capacity = row["capacity"] as? Double {
                        attributes[typeId]?[38] = capacity
                        attributesByName[typeId]?["capacity"] = capacity
                    }
                    
                    // 添加volume属性(id=161)，如果原先不存在
                    if attributes[typeId]?[161] == nil, let volume = row["volume"] as? Double {
                        attributes[typeId]?[161] = volume
                        attributesByName[typeId]?["volume"] = volume
                    }
                }
            }
        }
    }
    
    /// 收集属性
    /// - Parameters:
    ///   - ids: 需要收集属性的ID数组
    ///   - attributes: 属性字典（会被修改）
    ///   - attributesByName: 属性名称字典（会被修改）
    private func collectAttributes(
        ids: [Int],
        attributes: inout [Int: [Int: Double]],
        attributesByName: inout [Int: [String: Double]]
    ) {
        if ids.isEmpty {
            return
        }
        
        // 构建IN查询的占位符
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        
        // 查询属性 - 使用单个查询获取所有属性
        let attrQuery = """
            SELECT ta.type_id, ta.attribute_id, ta.value, da.name 
            FROM typeAttributes ta 
            JOIN dogmaAttributes da ON ta.attribute_id = da.attribute_id
            WHERE ta.type_id IN (\(placeholders))
        """
        
        if case let .success(rows) = databaseManager.executeQuery(attrQuery, parameters: ids) {
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                   let attrId = row["attribute_id"] as? Int,
                   let value = row["value"] as? Double,
                   let name = row["name"] as? String {
                    
                    // 保存属性值到属性字典
                    attributes[typeId]?[attrId] = value
                    attributesByName[typeId]?[name] = value
                }
            }
        }
    }
    
    /// 收集效果
    /// - Parameters:
    ///   - ids: 需要收集效果的ID数组
    ///   - effects: 效果字典（会被修改）
    ///   - typeInfo: 类型信息字典
    private func collectEffects(
        ids: [Int],
        effects: inout [Int: [EffectDetail]],
        typeInfo: [Int: (name: String, groupId: Int)]
    ) {
        // 构建IN查询的占位符
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        
        // 收集效果信息
        let effectQuery = """
            SELECT 
                te.type_id, 
                te.effect_id, 
                e.effect_name, 
                e.effect_category,
                e.description,
                e.modifier_info,
                e.is_offensive,
                e.is_assistance,
                te.is_default
            FROM typeEffects te
            JOIN dogmaEffects e ON te.effect_id = e.effect_id
            WHERE te.type_id IN (\(placeholders))
        """
        
        if case let .success(rows) = databaseManager.executeQuery(effectQuery, parameters: ids) {
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                   let effectId = row["effect_id"] as? Int,
                   let effectName = row["effect_name"] as? String {
                    
                    // 从typeInfo获取物品名称和分组ID
                    let (typeName, groupId) = typeInfo[typeId] ?? ("Unknown", 0)
                    
                    // 提取可选字段
                    let effectCategory = row["effect_category"] as? Int
                    let description = row["description"] as? String
                    let modifierInfo = row["modifier_info"] as? String
                    let isOffensive = (row["is_offensive"] as? Int ?? 0) == 1
                    let isAssistance = (row["is_assistance"] as? Int ?? 0) == 1
                    let isDefault = (row["is_default"] as? Int ?? 0) == 1
                    
                    // 创建效果详情对象
                    let effectDetail = EffectDetail(
                        effectId: effectId,
                        effectName: effectName,
                        effectCategory: effectCategory,
                        description: description,
                        
                        typeId: typeId,
                        typeName: typeName,
                        groupId: groupId,
                        
                        isDefault: isDefault,
                        isOffensive: isOffensive,
                        isAssistance: isAssistance,
                        modifierInfo: modifierInfo
                    )
                    
                    // 添加到对应物品的效果数组
                    effects[typeId]?.append(effectDetail)
                }
            }
        }
    }
    
    /// 收集dbuffCollection表中的修饰器
    /// - Parameters:
    ///   - ids: 需要收集修饰器的ID数组
    ///   - effects: 效果字典（会被修改）
    ///   - typeInfo: 类型信息字典
    private func collectDbuffCollectionModifiers(
        ids: [Int],
        effects: inout [Int: [EffectDetail]],
        typeInfo: [Int: (name: String, groupId: Int)]
    ) {
        if ids.isEmpty {
            return
        }
        
        // 构建IN查询的占位符
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        
        // 查询dbuffCollection表中的修饰器
        let dbuffQuery = """
            SELECT 
                dbuff_id, 
                type_id, 
                dbuff_name, 
                modifier_info
            FROM dbuffCollection
            WHERE type_id IN (\(placeholders))
        """
        
        if case let .success(rows) = databaseManager.executeQuery(dbuffQuery, parameters: ids) {
            for row in rows {
                if let dbuffId = row["dbuff_id"] as? Int,
                   let typeId = row["type_id"] as? Int,
                   let dbuffName = row["dbuff_name"] as? String,
                   let modifierInfo = row["modifier_info"] as? String {
                    
                    // 从typeInfo获取物品名称和分组ID
                    let (typeName, groupId) = typeInfo[typeId] ?? ("Unknown", 0)
                    
                    // 创建特殊的EffectDetail对象来表示dbuff修饰器
                    // 使用负数的effectId来区分dbuff修饰器和普通效果
                    let effectDetail = EffectDetail(
                        effectId: -dbuffId, // 使用负数来区分dbuff
                        effectName: dbuffName,
                        effectCategory: 1, // dbuff修饰器默认为主动效果
                        description: "DbuffCollection修饰器: \(dbuffName)",
                        
                        typeId: typeId,
                        typeName: typeName,
                        groupId: groupId,
                        
                        isDefault: false,
                        isOffensive: false,
                        isAssistance: false,
                        modifierInfo: modifierInfo
                    )
                    
                    // 添加到对应物品的效果数组
                    effects[typeId]?.append(effectDetail)
                }
            }
            
            Logger.info("从dbuffCollection表收集了\(rows.count)个额外修饰器")
        } else {
            Logger.warning("查询dbuffCollection表失败")
        }
    }
}
