import Foundation

// 解析器
class FitConvert {
    /// 创建一个新的本地配置
    static func createInitialFitting(shipTypeId: Int) -> LocalFitting {
        return LocalFitting(
            description: "",
            fitting_id: Int(Date().timeIntervalSince1970),
            items: [],
            name: "",
            ship_type_id: shipTypeId,
            drones: nil,
            fighters: nil,
            cargo: nil,
            implants: nil,
            environment_type_id: nil
        )
    }
    
    /// 从物品属性中提取所需技能ID
    static func extractRequiredSkills(attributes: [Int: Double]) -> [Int] {
        // 技能属性ID，用于识别所需技能
        let attributeSkills: [Int] = [182, 183, 184, 1285, 1289, 1290]
        
        var requiredSkills: [Int] = []
        
        // 遍历所有技能属性ID
        for attributeSkillId in attributeSkills {
            // 如果物品有这个属性，表示需要这个技能
            if let skillValue = attributes[attributeSkillId], skillValue > 0 {
                // 技能ID是属性值的整数部分
                let skillId = Int(skillValue)
                requiredSkills.append(skillId)
            }
        }
        
        return requiredSkills
    }
    
    /// 处理舰载机配置，根据飞船可用的发射筒配置舰载机
    static func processFighters(shipTypeId: Int, fighterBayItems: [FittingItem], databaseManager: DatabaseManager) -> [FighterSquad] {
        // 获取飞船的舰载机槽位信息
        var lightSlotsCount = 0
        var heavySlotsCount = 0
        var supportSlotsCount = 0
        var totalFighterTubes = 0
        
        // 查询飞船的舰载机槽位数
        let slotQuery = """
            SELECT da.name, ta.value
            FROM typeAttributes ta
            JOIN dogmaAttributes da ON ta.attribute_id = da.attribute_id
            WHERE ta.type_id = ? AND da.name IN ('fighterLightSlots', 'fighterHeavySlots', 'fighterSupportSlots', 'fighterTubes')
        """
        
        if case let .success(rows) = databaseManager.executeQuery(slotQuery, parameters: [shipTypeId]) {
            for row in rows {
                if let name = row["name"] as? String,
                   let value = row["value"] as? Double {
                    switch name {
                    case "fighterLightSlots":
                        lightSlotsCount = Int(value)
                    case "fighterHeavySlots":
                        heavySlotsCount = Int(value)
                    case "fighterSupportSlots":
                        supportSlotsCount = Int(value)
                    case "fighterTubes":
                        totalFighterTubes = Int(value)
                    default:
                        break
                    }
                }
            }
        }
        
        // 如果飞船不支持舰载机，直接返回空数组
        if totalFighterTubes <= 0 {
            return []
        }
        
        // 获取所有舰载机的ID列表
        let fighterTypeIds = fighterBayItems.map { $0.type_id }
        
        // 如果没有舰载机，直接返回空数组
        if fighterTypeIds.isEmpty {
            return []
        }
        
        // 使用IN语句一次性查询所有舰载机信息
        let placeholders = Array(repeating: "?", count: fighterTypeIds.count).joined(separator: ",")
        let groupQuery = """
            SELECT t.type_id, t.marketGroupID, t.name,
                  (SELECT ta.value 
                   FROM typeAttributes ta 
                   JOIN dogmaAttributes da ON ta.attribute_id = da.attribute_id 
                   WHERE ta.type_id = t.type_id AND da.name = 'fighterSquadronMaxSize') as maxSquadSize
            FROM types t
            WHERE t.type_id IN (\(placeholders))
        """
        
        // 存储舰载机信息
        var fighterInfoMap: [Int: (groupId: Int, name: String, maxSquadSize: Int)] = [:]
        
        if case let .success(rows) = databaseManager.executeQuery(groupQuery, parameters: fighterTypeIds) {
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                   let groupId = row["marketGroupID"] as? Int {
                    // 获取舰载机名称（用于日志）
                    let name = row["name"] as? String ?? "Unknown Fighter"
                    
                    // 获取最大中队大小，默认为1
                    var maxSquadSize = 1
                    if let squadSize = row["maxSquadSize"] as? Double, squadSize > 0 {
                        maxSquadSize = Int(squadSize)
                    }
                    
                    fighterInfoMap[typeId] = (groupId: groupId, name: name, maxSquadSize: maxSquadSize)
                }
            }
        }
        
        // 按类型分类舰载机
        var heavyFighters: [(typeId: Int, maxSquadSize: Int)] = []
        var supportFighters: [(typeId: Int, maxSquadSize: Int)] = []
        var lightFighters: [(typeId: Int, maxSquadSize: Int)] = []
        
        for (typeId, info) in fighterInfoMap {
            switch info.groupId {
            case 1310: // 重型舰载机
                heavyFighters.append((typeId: typeId, maxSquadSize: info.maxSquadSize))
                Logger.info("发现重型舰载机: \(info.name), 最大中队大小: \(info.maxSquadSize)")
            case 2239: // 辅助舰载机
                supportFighters.append((typeId: typeId, maxSquadSize: info.maxSquadSize))
                Logger.info("发现辅助舰载机: \(info.name), 最大中队大小: \(info.maxSquadSize)")
            case 840: // 轻型舰载机
                lightFighters.append((typeId: typeId, maxSquadSize: info.maxSquadSize))
                Logger.info("发现轻型舰载机: \(info.name), 最大中队大小: \(info.maxSquadSize)")
            default:
                Logger.warning("未知类型舰载机 groupId: \(info.groupId), typeId: \(typeId)")
            }
        }
        
        // 对舰载机按typeId排序（升序）
        heavyFighters.sort { $0.typeId < $1.typeId }
        supportFighters.sort { $0.typeId < $1.typeId }
        lightFighters.sort { $0.typeId < $1.typeId }
        
        // 结果数组
        var fighters: [FighterSquad] = []
        var usedTubes = 0
        
        // 按优先级添加舰载机（重型 > 辅助 > 轻型）
        
        // 1. 添加重型舰载机
        if !heavyFighters.isEmpty && heavySlotsCount > 0 {
            let fighter = heavyFighters.first!
            
            // 计算可添加的数量
            let availableTubes = min(heavySlotsCount, totalFighterTubes - usedTubes)
            
            for i in 0..<availableTubes {
                fighters.append(FighterSquad(
                    type_id: fighter.typeId,
                    quantity: fighter.maxSquadSize,
                    tubeId: 100 + i
                ))
                usedTubes += 1
            }
            
            Logger.info("添加重型舰载机: \(fighter.typeId), 数量: \(availableTubes), 中队大小: \(fighter.maxSquadSize)")
        }
        
        // 2. 添加辅助舰载机
        if !supportFighters.isEmpty && supportSlotsCount > 0 && usedTubes < totalFighterTubes {
            let fighter = supportFighters.first!
            
            // 计算可添加的数量
            let availableTubes = min(supportSlotsCount, totalFighterTubes - usedTubes)
            
            for i in 0..<availableTubes {
                fighters.append(FighterSquad(
                    type_id: fighter.typeId,
                    quantity: fighter.maxSquadSize,
                    tubeId: 200 + i
                ))
                usedTubes += 1
            }
            
            Logger.info("添加辅助舰载机: \(fighter.typeId), 数量: \(availableTubes), 中队大小: \(fighter.maxSquadSize)")
        }
        
        // 3. 添加轻型舰载机
        if !lightFighters.isEmpty && lightSlotsCount > 0 && usedTubes < totalFighterTubes {
            let fighter = lightFighters.first!
            
            // 计算可添加的数量
            let availableTubes = min(lightSlotsCount, totalFighterTubes - usedTubes)
            
            for i in 0..<availableTubes {
                fighters.append(FighterSquad(
                    type_id: fighter.typeId,
                    quantity: fighter.maxSquadSize,
                    tubeId: i
                ))
                usedTubes += 1
            }
            
            Logger.info("添加轻型舰载机: \(fighter.typeId), 数量: \(availableTubes), 中队大小: \(fighter.maxSquadSize)")
        }
        
        Logger.info("舰载机配置完成，总共添加了 \(fighters.count) 个舰载机，使用了 \(usedTubes) 个发射筒")
        return fighters
    }
    
    /// 将在线配置JSON数据解析为本地配置模型
    static func online2local(jsonData: Data) throws -> [LocalFitting] {
        let decoder = JSONDecoder()
        let onlineFittings = try decoder.decode([OnlineFitting].self, from: jsonData)
        let localFittings = onlineFittings.map { online in
            // 从items中提取无人机、货舱和舰载机信息
            let drones = online.items
                .filter { $0.flag == .droneBay }
                .map { Drone(type_id: $0.type_id, quantity: $0.quantity, active_count: 0) }
            
            let cargo = online.items
                .filter { $0.flag == .cargo }
                .map { CargoItem(type_id: $0.type_id, quantity: $0.quantity) }
            
            // 获取数据库管理器
            let databaseManager = DatabaseManager.shared
            
            // 从舰载机舱中筛选出舰载机
            let fighterBayItems = online.items.filter { $0.flag == .fighterBay }
            
            // 处理舰载机配置
            Logger.info("准备处理舰载机配置，找到 \(fighterBayItems.count) 个舰载机物品")
            let fighters = processFighters(
                shipTypeId: online.ship_type_id, 
                fighterBayItems: fighterBayItems, 
                databaseManager: databaseManager
            )
            Logger.info("舰载机处理完成，生成了 \(fighters.count) 个FighterSquad")
            
            // 过滤掉无人机、货舱和舰载机，只保留装备
            var equipmentItems = online.items.filter { 
                $0.flag != .droneBay && 
                $0.flag != .cargo && 
                $0.flag != .fighterBay 
            }
            
            // 检查是否为T3D战术驱逐舰（groupID=1305），如果是则添加默认模式
            let shipTypeId = online.ship_type_id
            
            // 1. 检查飞船是否为战术驱逐舰
            let shipQuery = "SELECT groupID FROM types WHERE type_id = ?"
            if case let .success(rows) = databaseManager.executeQuery(shipQuery, parameters: [shipTypeId]),
               let firstRow = rows.first,
               let groupId = firstRow["groupID"] as? Int,
               groupId == 1305 {
                
                // 2. 如果是T3D战术驱逐舰，查询默认模式
                let modeQuery = """
                    SELECT t.type_id
                    FROM types t
                    JOIN types s ON s.type_id = ?
                    WHERE t.groupID = 1306
                      AND t.en_name LIKE '%' || s.en_name || '%'
                    ORDER BY t.name
                    LIMIT 1
                """
                
                if case let .success(modeRows) = databaseManager.executeQuery(modeQuery, parameters: [shipTypeId]),
                   let firstModeRow = modeRows.first,
                   let defaultModeId = firstModeRow["type_id"] as? Int {
                    
                    // 3. 直接将T3D模式作为模块添加到装备列表中
                    let modeItem = FittingItem(
                        flag: .t3dModeSlot0,
                        quantity: 1,
                        type_id: defaultModeId
                    )
                    
                    // 添加模式到装备列表
                    equipmentItems.append(modeItem)
                    Logger.info("在线配置导入: 为战术驱逐舰(ID: \(shipTypeId))添加默认模式模块: \(defaultModeId)")
                }
            }
            
            return LocalFitting(
                description: online.description,
                fitting_id: online.fitting_id,
                items: equipmentItems.map { item in
                    LocalFittingItem(
                        flag: item.flag,
                        quantity: item.quantity,
                        type_id: item.type_id,
                        status: 1,  // 默认设置为在线状态(1)，原来是nil
                        charge_type_id: nil,  // 在线配置中没有弹药信息
                        charge_quantity: nil  // 在线配置中没有弹药数量信息
                    )
                },
                name: online.name,
                ship_type_id: online.ship_type_id,
                drones: drones.isEmpty ? nil : drones,           // 如果没有无人机则为nil
                fighters: fighters.isEmpty ? nil : fighters,     // 如果没有舰载机则为nil
                cargo: cargo.isEmpty ? nil : cargo,             // 如果没有货舱物品则为nil
                implants: nil,                                  // 在线配置中没有植入体信息
                environment_type_id: nil                        // 在线配置中没有环境信息
            )
        }
        return localFittings
    }
    
    /// 将本地配置保存为JSON文件
    static func saveLocalFitting(_ fitting: LocalFitting) throws {
        // 获取文档目录
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw NSError(domain: "FitConvert", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法访问文档目录"])
        }
        
        // 创建Fitting目录
        let fittingsDirectory = documentsDirectory.appendingPathComponent("Fitting")
        if !FileManager.default.fileExists(atPath: fittingsDirectory.path) {
            try FileManager.default.createDirectory(at: fittingsDirectory, withIntermediateDirectories: true)
        }
        
        // 创建文件路径
        let filePath = fittingsDirectory.appendingPathComponent("local_fitting_\(fitting.fitting_id).json")
        
        // 将配置转换为JSON数据
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted // 美化输出格式
        let jsonData = try encoder.encode(fitting)
        
        // 写入文件
        try jsonData.write(to: filePath)
        
        Logger.info("配置已保存到: \(filePath.path)")
    }
    
    /// 从JSON文件加载本地配置
    static func loadLocalFitting(fittingId: Int) throws -> LocalFitting {
        // 获取文档目录
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw NSError(domain: "FitConvert", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法访问文档目录"])
        }
        
        // 创建文件路径
        let filePath = documentsDirectory.appendingPathComponent("Fitting/local_fitting_\(fittingId).json")
        
        // 读取文件数据
        let jsonData = try Data(contentsOf: filePath)
        
        // 解码JSON数据
        let decoder = JSONDecoder()
        return try decoder.decode(LocalFitting.self, from: jsonData)
    }
    
    /// 从JSON文件加载所有本地配置
    static func loadAllLocalFittings() throws -> [LocalFitting] {
        // 获取文档目录
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw NSError(domain: "FitConvert", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法访问文档目录"])
        }
        
        // 创建Fitting目录路径
        let fittingsDirectory = documentsDirectory.appendingPathComponent("Fitting")
        
        // 检查目录是否存在
        guard FileManager.default.fileExists(atPath: fittingsDirectory.path) else {
            return []
        }
        
        // 获取目录中的所有文件
        let fileURLs = try FileManager.default.contentsOfDirectory(at: fittingsDirectory, includingPropertiesForKeys: nil)
        
        // 过滤出配置文件并加载
        var fittings: [LocalFitting] = []
        for fileURL in fileURLs where fileURL.lastPathComponent.hasPrefix("local_fitting_") && fileURL.pathExtension == "json" {
            do {
                let jsonData = try Data(contentsOf: fileURL)
                let decoder = JSONDecoder()
                let fitting = try decoder.decode(LocalFitting.self, from: jsonData)
                fittings.append(fitting)
            } catch {
                Logger.error("加载配置文件失败 \(fileURL.lastPathComponent): \(error)")
                continue
            }
        }
        
        return fittings
    }
    
    /// 将本地配置转为模拟器输入数据
    static func localFittingToSimulationInput(
        localFitting: LocalFitting,
        databaseManager: DatabaseManager,
        characterSkills: [Int: Int]
    ) -> SimulationInput {
        // 1. 飞船数据
        let shipTypeId = localFitting.ship_type_id
        var shipBaseAttributes: [Int: Double] = [:]
        var shipBaseAttributesByName: [String: Double] = [:]
        var shipEffects: [Int] = []
        var shipGroupID: Int = 0
        
        // 创建可变的modules数组副本
        var moduleItems = localFitting.items
        
        // 收集所有需要查询的typeId（飞船、装备、无人机和弹药）
        var allTypeIds = [shipTypeId] + 
                        localFitting.items.map { $0.type_id } + 
                        (localFitting.drones?.map { $0.type_id } ?? []) + 
                        (localFitting.fighters?.map { $0.type_id } ?? [])
        
        // 添加所有弹药的typeId
        let chargeTypeIds = localFitting.items.compactMap { $0.charge_type_id }
        allTypeIds.append(contentsOf: chargeTypeIds)
        
        let placeholders = Array(repeating: "?", count: allTypeIds.count).joined(separator: ",")
        let attrQuery = """
            SELECT ta.type_id, ta.attribute_id, ta.value, da.name 
            FROM typeAttributes ta 
            JOIN dogmaAttributes da ON ta.attribute_id = da.attribute_id 
            WHERE ta.type_id IN (\(placeholders))
        """
        var attrMap: [Int: ([Int: Double], [String: Double])] = [:]
        if case let .success(rows) = databaseManager.executeQuery(attrQuery, parameters: allTypeIds) {
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                   let attrId = row["attribute_id"] as? Int,
                   let value = row["value"] as? Double,
                   let name = row["name"] as? String {
                    if attrMap[typeId] == nil { attrMap[typeId] = ([:], [:]) }
                    attrMap[typeId]?.0[attrId] = value
                    attrMap[typeId]?.1[name] = value
                }
            }
        }
        
        // 查询所有效果（飞船、装备、无人机）
        let effectQuery = "SELECT type_id, effect_id FROM typeEffects WHERE type_id IN (\(placeholders))"
        var effectMap: [Int: [Int]] = [:]
        if case let .success(rows) = databaseManager.executeQuery(effectQuery, parameters: allTypeIds) {
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                   let effectId = row["effect_id"] as? Int {
                    if effectMap[typeId] == nil { effectMap[typeId] = [] }
                    effectMap[typeId]?.append(effectId)
                }
            }
        }
        
        // 查询所有groupID、名称和图标文件名
        let typeIdsForGroup = allTypeIds
        let groupPlaceholders = Array(repeating: "?", count: typeIdsForGroup.count).joined(separator: ",")
        let typeInfoQuery = "SELECT type_id, groupID, capacity, volume, mass, name, icon_filename FROM types WHERE type_id IN (\(groupPlaceholders))"
        var typeInfoMap: [Int: (groupID: Int, capacity: Double, volume: Double, mass: Double, name: String, iconFileName: String?)] = [:]
        if case let .success(rows) = databaseManager.executeQuery(typeInfoQuery, parameters: typeIdsForGroup) {
            for row in rows {
                if let typeId = row["type_id"] as? Int {
                    let groupID = row["groupID"] as? Int ?? 0
                    let capacity = row["capacity"] as? Double ?? 0
                    let volume = row["volume"] as? Double ?? 0
                    let mass = row["mass"] as? Double ?? 0
                    let name = row["name"] as? String ?? "Unknown"
                    let iconFileName = row["icon_filename"] as? String
                    typeInfoMap[typeId] = (groupID: groupID, capacity: capacity, volume: volume, mass: mass, name: name, iconFileName: iconFileName)
                }
            }
        }
        
        // 设置飞船数据
        if let shipAttr = attrMap[shipTypeId] {
            shipBaseAttributes = shipAttr.0
            shipBaseAttributesByName = shipAttr.1
        }
        shipEffects = effectMap[shipTypeId] ?? []
        
        // 获取飞船信息
        let shipInfo = typeInfoMap[shipTypeId] ?? (groupID: 0, capacity: 0, volume: 0, mass: 0, name: "Unknown Ship", iconFileName: nil)
        shipGroupID = shipInfo.groupID
        
        // 将types表中的物理属性添加到baseAttributes和baseAttributesByName中
        // 质量 (mass) - 属性ID 4
        shipBaseAttributes[4] = shipInfo.mass
        shipBaseAttributesByName["mass"] = shipInfo.mass
        
        // 容量 (capacity) - 属性ID 38
        shipBaseAttributes[38] = shipInfo.capacity
        shipBaseAttributesByName["capacity"] = shipInfo.capacity
        
        // 体积 (volume) - 属性ID 161
        shipBaseAttributes[161] = shipInfo.volume
        shipBaseAttributesByName["volume"] = shipInfo.volume
        
        // T3D模式处理 - 检查是否是战术驱逐舰
        // 查找当前模块列表中是否有T3D模式模块
        let t3dModeModule = localFitting.items.first { item in
            item.flag == .t3dModeSlot0
        }
        
        // 获取T3D模式ID（如果有）- 仅用于日志记录
        if let modeModule = t3dModeModule {
            Logger.info("从现有配置中检测到T3D模式模块: \(modeModule.type_id)")
        } else if shipGroupID == 1305 {
            // 是T3D战术驱逐舰但没有模式模块，尝试自动选择默认模式
            Logger.info("检测到战术驱逐舰(ID: \(shipTypeId))但未设置模式，尝试自动选择默认模式")
            
            // 查询该战术驱逐舰的模式选项
            let modeQuery = """
                SELECT t.type_id
                FROM types t
                JOIN types s ON s.type_id = ?
                WHERE t.groupID = 1306
                  AND t.en_name LIKE '%' || s.en_name || '%'
                ORDER BY t.name
                LIMIT 1
            """
            
            if case let .success(rows) = databaseManager.executeQuery(modeQuery, parameters: [shipTypeId]), 
               let firstRow = rows.first, 
               let defaultModeId = firstRow["type_id"] as? Int {
                Logger.info("为战术驱逐舰自动选择默认模式: \(defaultModeId)")
                
                // 添加模式模块到modules列表
                if let modeInfo = typeInfoMap[defaultModeId] {
                    // 创建模式模块项并添加到moduleItems数组
                    let modeItem = LocalFittingItem(
                        flag: .t3dModeSlot0,
                        quantity: 1,
                        type_id: defaultModeId,
                        status: 1,
                        charge_type_id: nil,
                        charge_quantity: nil
                    )
                    moduleItems.append(modeItem)
                    Logger.info("已添加T3D模式模块到配置项中: \(modeInfo.name)")
                }
            } else {
                Logger.error("无法为战术驱逐舰找到默认模式")
            }
        }
        
        let simShip = SimShip(
            typeId: shipTypeId, 
            baseAttributes: shipBaseAttributes, 
            baseAttributesByName: shipBaseAttributesByName, 
            effects: shipEffects, 
            groupID: shipGroupID,
            name: shipInfo.name, 
            iconFileName: shipInfo.iconFileName,
            requiredSkills: extractRequiredSkills(attributes: shipBaseAttributes)
        )
        
        // 2. 装备数据
        var modules: [SimModule] = []
        if !moduleItems.isEmpty {
            // 组装SimModule
            for item in moduleItems {
                let attr = attrMap[item.type_id]?.0 ?? [:]
                let attrName = attrMap[item.type_id]?.1 ?? [:]
                let effects = effectMap[item.type_id] ?? []
                
                // 获取装备信息
                let moduleInfo = typeInfoMap[item.type_id] ?? (groupID: 0, capacity: 0, volume: 0, mass: 0, name: "Unknown Module", iconFileName: nil)
                
                // 确保将capacity和volume添加到属性字典中
                var updatedAttr = attr
                var updatedAttrName = attrName
                
                // 容量 (capacity) - 属性ID 38
                if moduleInfo.capacity > 0 {
                    updatedAttr[38] = moduleInfo.capacity
                    updatedAttrName["capacity"] = moduleInfo.capacity
                }
                
                // 体积 (volume) - 属性ID 161
                updatedAttr[161] = moduleInfo.volume
                updatedAttrName["volume"] = moduleInfo.volume
                
                // 获取弹药信息（如有）
                var charge: SimCharge? = nil
                if let chargeTypeId = item.charge_type_id {
                    let chargeAttr = attrMap[chargeTypeId]?.0 ?? [:]
                    let chargeAttrName = attrMap[chargeTypeId]?.1 ?? [:]
                    let chargeEffects = effectMap[chargeTypeId] ?? []
                    
                    // 获取弹药信息
                    let chargeInfo = typeInfoMap[chargeTypeId] ?? (groupID: 0, capacity: 0, volume: 0, mass: 0, name: "Unknown Charge", iconFileName: nil)
                    
                    // 确保volume添加到弹药的属性字典中
                    var updatedChargeAttr = chargeAttr
                    var updatedChargeAttrName = chargeAttrName
                    
                    // 体积 (volume) - 属性ID 161
                    updatedChargeAttr[161] = chargeInfo.volume
                    updatedChargeAttrName["volume"] = chargeInfo.volume
                    
                    charge = SimCharge(
                        typeId: chargeTypeId, 
                        attributes: updatedChargeAttr, 
                        attributesByName: updatedChargeAttrName, 
                        effects: chargeEffects, 
                        groupID: chargeInfo.groupID,
                        chargeQuantity: item.charge_quantity,
                        requiredSkills: extractRequiredSkills(attributes: updatedChargeAttr),
                        name: chargeInfo.name,
                        iconFileName: chargeInfo.iconFileName
                    )
                }
                
                let simModule = SimModule(
                    typeId: item.type_id,
                    attributes: updatedAttr,
                    attributesByName: updatedAttrName,
                    effects: effects,
                    groupID: moduleInfo.groupID,
                    status: {
                        if let status = item.status {
                            return (0...3).contains(status) ? status : 1
                        } else {
                            return 1
                        }
                    }(),
                    charge: charge,
                    flag: item.flag,
                    quantity: item.quantity,
                    name: moduleInfo.name,
                    iconFileName: moduleInfo.iconFileName,
                    requiredSkills: extractRequiredSkills(attributes: updatedAttr)
                )
                
                modules.append(simModule)
            }
        }
        
        // 3. 无人机
        var drones: [SimDrone] = []
        if let droneList = localFitting.drones {
            for drone in droneList {
                let attr = attrMap[drone.type_id]?.0 ?? [:]
                let attrName = attrMap[drone.type_id]?.1 ?? [:]
                let effects = effectMap[drone.type_id] ?? []
                
                // 获取无人机信息
                let droneInfo = typeInfoMap[drone.type_id] ?? (groupID: 0, capacity: 0, volume: 0, mass: 0, name: "Unknown Drone", iconFileName: nil)
                
                // 确保volume添加到无人机的属性字典中
                var updatedAttr = attr
                var updatedAttrName = attrName
                
                // 体积 (volume) - 属性ID 161
                updatedAttr[161] = droneInfo.volume
                updatedAttrName["volume"] = droneInfo.volume
                
                let simDrone = SimDrone(
                    typeId: drone.type_id,
                    attributes: updatedAttr,
                    attributesByName: updatedAttrName,
                    effects: effects,
                    quantity: drone.quantity,
                    activeCount: drone.active_count,
                    groupID: droneInfo.groupID,
                    requiredSkills: extractRequiredSkills(attributes: updatedAttr),
                    name: droneInfo.name,
                    iconFileName: droneInfo.iconFileName
                )
                
                drones.append(simDrone)
            }
        }
        
        // 4. 货舱
        var cargoItems: [SimCargoItem] = []
        if let cargoList = localFitting.cargo {
            // 收集所有货舱物品的typeId
            let cargoTypeIds = cargoList.map { $0.type_id }
            
            // 为货舱物品单独查询最新信息
            var cargoItemInfoMap: [Int: (name: String, volume: Double, iconFileName: String?)] = [:]
            if !cargoTypeIds.isEmpty {
                let cargoPlaceholders = Array(repeating: "?", count: cargoTypeIds.count).joined(separator: ",")
                let cargoQuery = "SELECT type_id, name, volume, icon_filename FROM types WHERE type_id IN (\(cargoPlaceholders))"
                
                if case let .success(rows) = databaseManager.executeQuery(cargoQuery, parameters: cargoTypeIds) {
                    for row in rows {
                        if let typeId = row["type_id"] as? Int,
                           let name = row["name"] as? String {
                            let volume = row["volume"] as? Double ?? 0
                            let iconFileName = row["icon_filename"] as? String
                            cargoItemInfoMap[typeId] = (name: name, volume: volume, iconFileName: iconFileName)
                        }
                    }
                }
            }
            
            for item in cargoList {
                // 首先尝试从专门查询的货舱物品信息中获取
                if let cargoItemInfo = cargoItemInfoMap[item.type_id] {
                    cargoItems.append(SimCargoItem(
                        typeId: item.type_id, 
                        quantity: item.quantity,
                        volume: cargoItemInfo.volume,
                        name: cargoItemInfo.name,
                        iconFileName: cargoItemInfo.iconFileName
                    ))
                } else {
                    // 如果专门查询没有结果，再尝试从typeInfoMap获取
                    let itemInfo = typeInfoMap[item.type_id] ?? (groupID: 0, capacity: 0, volume: 0, mass: 0, name: "Unknown Item", iconFileName: nil)
                    
                    cargoItems.append(SimCargoItem(
                        typeId: item.type_id, 
                        quantity: item.quantity,
                        volume: itemInfo.volume,
                        name: itemInfo.name,
                        iconFileName: itemInfo.iconFileName
                    ))
                }
            }
        }
        let simCargo = SimCargo(items: cargoItems)
        
        // 5. 植入体、环境效果
        var implants: [SimImplant] = []
        let environmentEffects: [SimEnvironmentEffect] = []
        
        // 处理植入体数据
        if let implantTypeIds = localFitting.implants, !implantTypeIds.isEmpty {
            Logger.info("开始加载植入体数据，数量: \(implantTypeIds.count)")
            
            // 构建查询参数
            let placeholders = String(repeating: "?,", count: implantTypeIds.count).dropLast()
            
            // 查询植入体属性
            let attrQuery = """
                SELECT t.type_id, ta.attribute_id, ta.value, da.name, t.name as type_name, t.icon_filename
                FROM typeAttributes ta 
                JOIN dogmaAttributes da ON ta.attribute_id = da.attribute_id
                JOIN types t ON ta.type_id = t.type_id
                WHERE ta.type_id IN (\(placeholders))
            """
            
            var typeAttributes: [Int: [Int: Double]] = [:]
            var typeAttributesByName: [Int: [String: Double]] = [:]
            var typeNames: [Int: String] = [:]
            var typeIcons: [Int: String] = [:]
            
            if case let .success(rows) = databaseManager.executeQuery(attrQuery, parameters: implantTypeIds) {
                for row in rows {
                    if let typeId = row["type_id"] as? Int,
                       let attrId = row["attribute_id"] as? Int,
                       let value = row["value"] as? Double,
                       let name = row["name"] as? String {
                        
                        // 初始化字典
                        if typeAttributes[typeId] == nil {
                            typeAttributes[typeId] = [:]
                        }
                        if typeAttributesByName[typeId] == nil {
                            typeAttributesByName[typeId] = [:]
                        }
                        
                        // 添加属性
                        typeAttributes[typeId]?[attrId] = value
                        typeAttributesByName[typeId]?[name] = value
                        
                        // 保存物品名称和图标
                        if let typeName = row["type_name"] as? String {
                            typeNames[typeId] = typeName
                        }
                        if let iconFileName = row["icon_filename"] as? String {
                            typeIcons[typeId] = iconFileName
                        }
                    }
                }
            }
            
            // 查询植入体效果
            let effectQuery = """
                SELECT type_id, effect_id 
                FROM typeEffects 
                WHERE type_id IN (\(placeholders))
            """
            
            var typeEffects: [Int: [Int]] = [:]
            
            if case let .success(rows) = databaseManager.executeQuery(effectQuery, parameters: implantTypeIds) {
                for row in rows {
                    if let typeId = row["type_id"] as? Int,
                       let effectId = row["effect_id"] as? Int {
                        
                        // 初始化数组
                        if typeEffects[typeId] == nil {
                            typeEffects[typeId] = []
                        }
                        
                        // 添加效果
                        typeEffects[typeId]?.append(effectId)
                    }
                }
            }
            
            // 创建植入体对象
            for typeId in implantTypeIds {
                if let attributes = typeAttributes[typeId],
                   let attributesByName = typeAttributesByName[typeId] {
                    
                    let effects = typeEffects[typeId] ?? []
                    let name = typeNames[typeId] ?? "Unknown Implant"
                    let iconFileName = typeIcons[typeId]
                    
                    // 创建植入体对象
                    let implant = SimImplant(
                        typeId: typeId,
                        attributes: attributes,
                        attributesByName: attributesByName,
                        effects: effects,
                        requiredSkills: extractRequiredSkills(attributes: attributes),
                        name: name,
                        iconFileName: iconFileName
                    )
                    
                    implants.append(implant)
                    Logger.info("加载植入体: \(name), typeId: \(typeId)")
                }
            }
        }
        
        // 6. 组装SimulationInput（带上原始配置元数据）
        Logger.info("localFittingToSimulationInput 完成组装.")

        // 处理舰载机数据，将FighterSquad转换为SimFighterSquad
        Logger.info("开始将FighterSquad转换为SimFighterSquad，原始数量: \(localFitting.fighters?.count ?? 0)")
        // 检查FighterSquad数据完整性
        if let fighters = localFitting.fighters {
            for (index, fighter) in fighters.enumerated() {
                Logger.info("输入FighterSquad[\(index)]: type_id=\(fighter.type_id), tubeId=\(fighter.tubeId), quantity=\(fighter.quantity)")
            }
        }
        
        let simFighters: [SimFighterSquad]? = localFitting.fighters?.compactMap { fighter in
            Logger.info("处理舰载机: typeId=\(fighter.type_id), tubeId=\(fighter.tubeId), quantity=\(fighter.quantity)")
            // 获取舰载机属性和效果
            let attr = attrMap[fighter.type_id]?.0 ?? [:]
            let attrName = attrMap[fighter.type_id]?.1 ?? [:]
            let effects = effectMap[fighter.type_id] ?? []
            
            // 获取舰载机信息
            let fighterInfo = typeInfoMap[fighter.type_id] ?? (groupID: 0, capacity: 0, volume: 0, mass: 0, name: "Unknown Fighter", iconFileName: nil)
            Logger.info("舰载机信息: groupID=\(fighterInfo.groupID), name=\(fighterInfo.name)")
            
            // 确保volume添加到舰载机的属性字典中
            var updatedAttr = attr
            var updatedAttrName = attrName
            
            // 体积 (volume) - 属性ID 161
            updatedAttr[161] = fighterInfo.volume
            updatedAttrName["volume"] = fighterInfo.volume
            
            return SimFighterSquad(
                typeId: fighter.type_id,
                attributes: updatedAttr,
                attributesByName: updatedAttrName,
                effects: effects,
                quantity: fighter.quantity,
                tubeId: fighter.tubeId,
                groupID: fighterInfo.groupID,
                requiredSkills: extractRequiredSkills(attributes: updatedAttr),
                name: fighterInfo.name,
                iconFileName: fighterInfo.iconFileName
            )
        }
        Logger.info("完成SimFighterSquad转换，结果数量: \(simFighters?.count ?? 0)")

        return SimulationInput(
            fittingId: localFitting.fitting_id,
            name: localFitting.name,
            description: localFitting.description,
            fighters: simFighters,
            
            ship: simShip,
            modules: modules,
            drones: drones,
            cargo: simCargo,
            implants: implants,
            environmentEffects: environmentEffects,
            characterSkills: characterSkills
        )
    }
    
    /// 将模拟器输入数据转为本地配置
    static func simulationInputToLocalFitting(
        input: SimulationInput,
        customFittingId: Int? = nil // 可选参数，允许指定不同的fittingId
    ) -> LocalFitting {
        // 使用输入中的元数据或自定义值
        let fitId = customFittingId ?? input.fittingId
        
        // 如果有舰载机，先检查其完整性
        if let fighters = input.fighters {
            Logger.info("检查SimFighterSquad到FighterSquad转换前的数据: 数量 = \(fighters.count)")
            for (index, fighter) in fighters.enumerated() {
                Logger.info("SimFighterSquad[\(index)]: typeId=\(fighter.typeId), tubeId=\(fighter.tubeId), quantity=\(fighter.quantity)")
            }
        }
        
        // 从模块数据中恢复装备项
        let items = input.modules.map { module -> LocalFittingItem in
            return LocalFittingItem(
                flag: module.flag ?? .invalid,
                quantity: module.quantity,
                type_id: module.typeId,
                status: module.status,
                charge_type_id: module.charge?.typeId,
                charge_quantity: module.charge?.chargeQuantity
            )
        }
        
        // 从无人机数据中恢复无人机列表
        let drones = input.drones.isEmpty ? nil : input.drones.map { drone -> Drone in
            return Drone(
                type_id: drone.typeId,
                quantity: drone.quantity,
                active_count: drone.activeCount
            )
        }
        
        // 从SimFighterSquad转换为FighterSquad
        let fighters = input.fighters?.map { simFighter -> FighterSquad in
            return FighterSquad(
                type_id: simFighter.typeId,
                quantity: simFighter.quantity,
                tubeId: simFighter.tubeId
            )
        }
        
        // 检查转换后的舰载机数据
        if let fighters = fighters {
            Logger.info("检查转换后的FighterSquad数据: 数量 = \(fighters.count)")
            for (index, fighter) in fighters.enumerated() {
                Logger.info("FighterSquad[\(index)]: type_id=\(fighter.type_id), tubeId=\(fighter.tubeId), quantity=\(fighter.quantity)")
            }
        }
        
        // 从货舱数据中恢复货舱物品列表
        let cargo = input.cargo.items.isEmpty ? nil : input.cargo.items.map { item -> CargoItem in
            return CargoItem(
                type_id: item.typeId,
                quantity: item.quantity
            )
        }
        
        // 从植入体数据中提取typeId列表
        let implants = input.implants.isEmpty ? nil : input.implants.map { implant -> Int in
            return implant.typeId
        }
        
        // 创建并返回LocalFitting
        return LocalFitting(
            description: input.description,
            fitting_id: fitId,
            items: items,
            name: input.name,
            ship_type_id: input.ship.typeId,
            drones: drones,
            fighters: fighters,
            cargo: cargo,
            implants: implants, // 保存植入体typeId列表
            environment_type_id: nil // 暂不支持环境类型
        )
    }
} 
