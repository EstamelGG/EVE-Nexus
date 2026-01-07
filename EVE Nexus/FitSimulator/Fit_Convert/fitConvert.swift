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
    static func processFighters(
        shipTypeId: Int, fighterBayItems: [FittingItem], databaseManager: DatabaseManager
    ) -> [FighterSquad] {
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

        if case let .success(rows) = databaseManager.executeQuery(
            slotQuery, parameters: [shipTypeId]
        ) {
            for row in rows {
                if let name = row["name"] as? String,
                   let value = row["value"] as? Double
                {
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
        var fighterInfoMap: [Int: (marketGroupId: Int, name: String, maxSquadSize: Int)] = [:]

        if case let .success(rows) = databaseManager.executeQuery(
            groupQuery, parameters: fighterTypeIds
        ) {
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                   let marketGroupId = row["marketGroupID"] as? Int
                {
                    // 获取舰载机名称（用于日志）
                    let name = row["name"] as? String ?? "Unknown Fighter"

                    // 获取最大中队大小，默认为1
                    var maxSquadSize = 1
                    if let squadSize = row["maxSquadSize"] as? Double, squadSize > 0 {
                        maxSquadSize = Int(squadSize)
                    }

                    fighterInfoMap[typeId] = (
                        marketGroupId: marketGroupId, name: name, maxSquadSize: maxSquadSize
                    )
                }
            }
        }

        // 按类型分类舰载机
        var heavyFighters: [(typeId: Int, maxSquadSize: Int)] = []
        var supportFighters: [(typeId: Int, maxSquadSize: Int)] = []
        var lightFighters: [(typeId: Int, maxSquadSize: Int)] = []

        for (typeId, info) in fighterInfoMap {
            switch info.marketGroupId {
            case 1310: // 重型舰载机
                heavyFighters.append((typeId: typeId, maxSquadSize: info.maxSquadSize))
                if AppConfiguration.Fitting.showDebug {
                    Logger.info("发现重型舰载机: \(info.name), 最大中队大小: \(info.maxSquadSize)")
                }
            case 2239: // 辅助舰载机
                supportFighters.append((typeId: typeId, maxSquadSize: info.maxSquadSize))
                if AppConfiguration.Fitting.showDebug {
                    Logger.info("发现辅助舰载机: \(info.name), 最大中队大小: \(info.maxSquadSize)")
                }
            case 840: // 轻型舰载机
                lightFighters.append((typeId: typeId, maxSquadSize: info.maxSquadSize))
                if AppConfiguration.Fitting.showDebug {
                    Logger.info("发现轻型舰载机: \(info.name), 最大中队大小: \(info.maxSquadSize)")
                }
            default:
                Logger.warning("未知类型舰载机 marketGroupId: \(info.marketGroupId), typeId: \(typeId)")
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
        if !heavyFighters.isEmpty, heavySlotsCount > 0 {
            let fighter = heavyFighters.first!

            // 计算可添加的数量
            let availableTubes = min(heavySlotsCount, totalFighterTubes - usedTubes)

            for i in 0 ..< availableTubes {
                fighters.append(
                    FighterSquad(
                        type_id: fighter.typeId,
                        quantity: fighter.maxSquadSize,
                        tubeId: 100 + i
                    ))
                usedTubes += 1
            }

            if AppConfiguration.Fitting.showDebug {
                Logger.info(
                    "添加重型舰载机: \(fighter.typeId), 数量: \(availableTubes), 中队大小: \(fighter.maxSquadSize)")
            }
        }

        // 2. 添加辅助舰载机
        if !supportFighters.isEmpty, supportSlotsCount > 0, usedTubes < totalFighterTubes {
            let fighter = supportFighters.first!

            // 计算可添加的数量
            let availableTubes = min(supportSlotsCount, totalFighterTubes - usedTubes)

            for i in 0 ..< availableTubes {
                fighters.append(
                    FighterSquad(
                        type_id: fighter.typeId,
                        quantity: fighter.maxSquadSize,
                        tubeId: 200 + i
                    ))
                usedTubes += 1
            }

            if AppConfiguration.Fitting.showDebug {
                Logger.info(
                    "添加辅助舰载机: \(fighter.typeId), 数量: \(availableTubes), 中队大小: \(fighter.maxSquadSize)")
            }
        }

        // 3. 添加轻型舰载机
        if !lightFighters.isEmpty, lightSlotsCount > 0, usedTubes < totalFighterTubes {
            let fighter = lightFighters.first!

            // 计算可添加的数量
            let availableTubes = min(lightSlotsCount, totalFighterTubes - usedTubes)

            for i in 0 ..< availableTubes {
                fighters.append(
                    FighterSquad(
                        type_id: fighter.typeId,
                        quantity: fighter.maxSquadSize,
                        tubeId: i
                    ))
                usedTubes += 1
            }

            if AppConfiguration.Fitting.showDebug {
                Logger.info(
                    "添加轻型舰载机: \(fighter.typeId), 数量: \(availableTubes), 中队大小: \(fighter.maxSquadSize)")
            }
        }

        if AppConfiguration.Fitting.showDebug {
            Logger.info("舰载机配置完成，总共添加了 \(fighters.count) 个舰载机，使用了 \(usedTubes) 个发射筒")
        }
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
                .map { Drone(type_id: $0.type_id, quantity: $0.quantity, active_count: 0, muta: nil) }

            let cargo = online.items
                .filter { $0.flag == .cargo }
                .map { CargoItem(type_id: $0.type_id, quantity: $0.quantity) }

            // 获取数据库管理器
            let databaseManager = DatabaseManager.shared

            // 从舰载机舱中筛选出舰载机
            let fighterBayItems = online.items.filter { $0.flag == .fighterBay }

            // 处理舰载机配置
            if AppConfiguration.Fitting.showDebug {
                Logger.info("准备处理舰载机配置，找到 \(fighterBayItems.count) 个舰载机物品")
            }
            let fighters = processFighters(
                shipTypeId: online.ship_type_id,
                fighterBayItems: fighterBayItems,
                databaseManager: databaseManager
            )
            if AppConfiguration.Fitting.showDebug {
                Logger.info("舰载机处理完成，生成了 \(fighters.count) 个FighterSquad")
            }

            // 过滤掉无人机、货舱和舰载机，只保留装备
            var equipmentItems = online.items.filter {
                $0.flag != .droneBay && $0.flag != .cargo && $0.flag != .fighterBay
            }

            // 检查是否为模式切换飞船，如果是则添加默认模式
            let shipTypeId = online.ship_type_id

            // 使用新的工具函数检查飞船是否支持模式切换
            if ModeSwitchingUtils.isModeSwitchingShip(
                shipTypeId: shipTypeId,
                databaseManager: databaseManager
            ) {
                // 获取默认模式ID
                if let defaultModeId = ModeSwitchingUtils.getDefaultModeId(
                    for: shipTypeId,
                    databaseManager: databaseManager
                ) {
                    // 将模式作为模块添加到装备列表中
                    let modeItem = FittingItem(
                        flag: .t3dModeSlot0,
                        quantity: 1,
                        type_id: defaultModeId
                    )

                    // 添加模式到装备列表
                    equipmentItems.append(modeItem)
                    if AppConfiguration.Fitting.showDebug {
                        Logger.info("在线配置导入: 为模式切换飞船(ID: \(shipTypeId))添加默认模式模块: \(defaultModeId)")
                    }
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
                        status: 1, // 默认设置为在线状态(1)，原来是nil
                        charge_type_id: nil, // 在线配置中没有弹药信息
                        charge_quantity: nil, // 在线配置中没有弹药数量信息
                        muta: nil
                    )
                },
                name: online.name,
                ship_type_id: online.ship_type_id,
                drones: drones.isEmpty ? nil : drones, // 如果没有无人机则为nil
                fighters: fighters.isEmpty ? nil : fighters, // 如果没有舰载机则为nil
                cargo: cargo.isEmpty ? nil : cargo, // 如果没有货舱物品则为nil
                implants: nil, // 在线配置中没有植入体信息
                environment_type_id: nil // 在线配置中没有环境信息
            )
        }
        return localFittings
    }

    /// 将本地配置保存为JSON文件
    static func saveLocalFitting(_ fitting: LocalFitting) throws {
        // 获取文档目录
        guard
            let documentsDirectory = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask
            ).first
        else {
            throw NSError(
                domain: "FitConvert", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法访问文档目录"]
            )
        }

        // 创建Fitting目录
        let fittingsDirectory = documentsDirectory.appendingPathComponent("Fitting")
        if !FileManager.default.fileExists(atPath: fittingsDirectory.path) {
            try FileManager.default.createDirectory(
                at: fittingsDirectory, withIntermediateDirectories: true
            )
        }

        // 创建文件路径
        let filePath = fittingsDirectory.appendingPathComponent(
            "local_fitting_\(fitting.fitting_id).json")

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
        guard
            let documentsDirectory = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask
            ).first
        else {
            throw NSError(
                domain: "FitConvert", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法访问文档目录"]
            )
        }

        // 创建文件路径
        let filePath = documentsDirectory.appendingPathComponent(
            "Fitting/local_fitting_\(fittingId).json")

        // 读取文件数据
        let jsonData = try Data(contentsOf: filePath)

        // 解码JSON数据
        let decoder = JSONDecoder()
        return try decoder.decode(LocalFitting.self, from: jsonData)
    }

    /// 从JSON文件加载所有本地配置
    static func loadAllLocalFittings() throws -> [LocalFitting] {
        // 获取文档目录
        guard
            let documentsDirectory = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask
            ).first
        else {
            throw NSError(
                domain: "FitConvert", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法访问文档目录"]
            )
        }

        // 创建Fitting目录路径
        let fittingsDirectory = documentsDirectory.appendingPathComponent("Fitting")

        // 检查目录是否存在
        guard FileManager.default.fileExists(atPath: fittingsDirectory.path) else {
            return []
        }

        // 获取目录中的所有文件
        let fileURLs = try FileManager.default.contentsOfDirectory(
            at: fittingsDirectory, includingPropertiesForKeys: nil
        )

        // 过滤出配置文件并加载
        var fittings: [LocalFitting] = []
        for fileURL in fileURLs
            where fileURL.lastPathComponent.hasPrefix("local_fitting_")
            && fileURL.pathExtension == "json"
        {
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
        var shipGroupID = 0

        // 创建可变的modules数组副本
        var moduleItems = localFitting.items

        // 收集所有需要查询的typeId（飞船、装备、无人机和弹药）
        var allTypeIds =
            [shipTypeId] + localFitting.items.map { $0.type_id }
                + (localFitting.drones?.map { $0.type_id } ?? [])
                + (localFitting.fighters?.map { $0.type_id } ?? [])

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
                   let name = row["name"] as? String
                {
                    if attrMap[typeId] == nil { attrMap[typeId] = ([:], [:]) }
                    attrMap[typeId]?.0[attrId] = value
                    attrMap[typeId]?.1[name] = value
                }
            }
        }

        // 查询所有效果（飞船、装备、无人机）
        let effectQuery =
            "SELECT type_id, effect_id FROM typeEffects WHERE type_id IN (\(placeholders))"
        var effectMap: [Int: [Int]] = [:]
        if case let .success(rows) = databaseManager.executeQuery(
            effectQuery, parameters: allTypeIds
        ) {
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                   let effectId = row["effect_id"] as? Int
                {
                    if effectMap[typeId] == nil { effectMap[typeId] = [] }
                    effectMap[typeId]?.append(effectId)
                }
            }
        }

        // 查询所有groupID、名称和图标文件名
        let typeIdsForGroup = allTypeIds
        let groupPlaceholders = Array(repeating: "?", count: typeIdsForGroup.count).joined(
            separator: ",")
        let typeInfoQuery =
            "SELECT type_id, groupID, capacity, volume, mass, name, icon_filename FROM types WHERE type_id IN (\(groupPlaceholders))"
        var typeInfoMap:
            [Int: (
                groupID: Int, capacity: Double, volume: Double, mass: Double, name: String,
                iconFileName: String?
            )] = [:]
        if case let .success(rows) = databaseManager.executeQuery(
            typeInfoQuery, parameters: typeIdsForGroup
        ) {
            for row in rows {
                if let typeId = row["type_id"] as? Int {
                    let groupID = row["groupID"] as? Int ?? 0
                    let capacity = row["capacity"] as? Double ?? 0
                    let volume = row["volume"] as? Double ?? 0
                    let mass = row["mass"] as? Double ?? 0
                    let name = row["name"] as? String ?? "Unknown"
                    let iconFileName = row["icon_filename"] as? String
                    typeInfoMap[typeId] = (
                        groupID: groupID, capacity: capacity, volume: volume, mass: mass,
                        name: name, iconFileName: iconFileName
                    )
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
        let shipInfo =
            typeInfoMap[shipTypeId] ?? (
                groupID: 0, capacity: 0, volume: 0, mass: 0, name: "Unknown Ship", iconFileName: nil
            )
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

        // 模式切换处理 - 检查是否是模式切换飞船
        // 查找当前模块列表中是否有模式模块
        let modeModule = localFitting.items.first { item in
            item.flag == .t3dModeSlot0
        }

        // 获取模式ID（如果有）- 仅用于日志记录
        if let modeModule = modeModule {
            if AppConfiguration.Fitting.showDebug {
                Logger.info("从现有配置中检测到模式模块: \(modeModule.type_id)")
            }
        } else if ModeSwitchingUtils.isModeSwitchingShip(
            shipTypeId: shipTypeId,
            databaseManager: databaseManager
        ) {
            // 是模式切换飞船但没有模式模块，尝试自动选择默认模式
            if AppConfiguration.Fitting.showDebug {
                Logger.info("检测到模式切换飞船(ID: \(shipTypeId))但未设置模式，尝试自动选择默认模式")
            }

            // 获取默认模式ID
            if let defaultModeId = ModeSwitchingUtils.getDefaultModeId(
                for: shipTypeId,
                databaseManager: databaseManager
            ) {
                if AppConfiguration.Fitting.showDebug {
                    Logger.info("为模式切换飞船自动选择默认模式: \(defaultModeId)")
                }

                // 添加模式模块到modules列表
                if let modeInfo = typeInfoMap[defaultModeId] {
                    // 创建模式模块项并添加到moduleItems数组
                    let modeItem = LocalFittingItem(
                        flag: .t3dModeSlot0,
                        quantity: 1,
                        type_id: defaultModeId,
                        status: 1,
                        charge_type_id: nil,
                        charge_quantity: nil,
                        muta: nil
                    )
                    moduleItems.append(modeItem)
                    if AppConfiguration.Fitting.showDebug {
                        Logger.info("已添加模式模块到配置项中: \(modeInfo.name)")
                    }
                }
            } else {
                Logger.error("无法为模式切换飞船找到默认模式")
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
                let moduleInfo =
                    typeInfoMap[item.type_id] ?? (
                        groupID: 0, capacity: 0, volume: 0, mass: 0, name: "Unknown Module",
                        iconFileName: nil
                    )

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
                    let chargeInfo =
                        typeInfoMap[chargeTypeId] ?? (
                            groupID: 0, capacity: 0, volume: 0, mass: 0, name: "Unknown Charge",
                            iconFileName: nil
                        )

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

                // 加载突变数据（直接使用倍数：1.15表示+15%，0.8表示-20%）
                var selectedMutaplasmidID: Int? = nil
                var mutatedAttributes: [Int: Double] = [:]
                var mutatedTypeId: Int? = nil
                var mutatedName: String? = nil
                var mutatedIconFileName: String? = nil

                if let mutaData = item.muta, !mutaData.isEmpty {
                    // 取第一个突变数据的mutaplasmid_id（所有突变数据应该来自同一个突变质体）
                    selectedMutaplasmidID = mutaData.first?.mutaplasmid_id
                    // 直接使用倍数（value已经是倍数）
                    for mutation in mutaData {
                        mutatedAttributes[mutation.attribute_id] = mutation.value
                    }

                    // 查询突变后的typeID、名称和图标
                    if let mutaplasmidID = selectedMutaplasmidID {
                        if let resultingTypeId = databaseManager.getMutatedTypeID(
                            applicableTypeID: item.type_id,
                            mutaplasmidID: mutaplasmidID
                        ) {
                            mutatedTypeId = resultingTypeId

                            // 查询突变后的名称和图标
                            let typeQuery = "SELECT name, icon_filename FROM types WHERE type_id = ?"
                            if case let .success(rows) = databaseManager.executeQuery(
                                typeQuery, parameters: [resultingTypeId]
                            ), let row = rows.first {
                                mutatedName = row["name"] as? String
                                mutatedIconFileName = row["icon_filename"] as? String
                            }
                        }
                    }
                }

                let simModule = SimModule(
                    typeId: item.type_id,
                    attributes: updatedAttr,
                    attributesByName: updatedAttrName,
                    effects: effects,
                    groupID: moduleInfo.groupID,
                    status: {
                        if let status = item.status {
                            return (0 ... 3).contains(status) ? status : 1
                        } else {
                            return 1
                        }
                    }(),
                    charge: charge,
                    flag: item.flag,
                    quantity: item.quantity,
                    name: moduleInfo.name,
                    iconFileName: moduleInfo.iconFileName,
                    requiredSkills: extractRequiredSkills(attributes: updatedAttr),
                    selectedMutaplasmidID: selectedMutaplasmidID,
                    mutatedAttributes: mutatedAttributes,
                    mutatedTypeId: mutatedTypeId,
                    mutatedName: mutatedName,
                    mutatedIconFileName: mutatedIconFileName
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
                let droneInfo =
                    typeInfoMap[drone.type_id] ?? (
                        groupID: 0, capacity: 0, volume: 0, mass: 0, name: "Unknown Drone",
                        iconFileName: nil
                    )

                // 确保volume添加到无人机的属性字典中
                var updatedAttr = attr
                var updatedAttrName = attrName

                // 体积 (volume) - 属性ID 161
                updatedAttr[161] = droneInfo.volume
                updatedAttrName["volume"] = droneInfo.volume

                // 加载突变数据（直接使用倍数：1.15表示+15%，0.8表示-20%）
                var selectedMutaplasmidID: Int? = nil
                var mutatedAttributes: [Int: Double] = [:]
                var mutatedTypeId: Int? = nil
                var mutatedName: String? = nil
                var mutatedIconFileName: String? = nil

                if let mutaData = drone.muta, !mutaData.isEmpty {
                    // 取第一个突变数据的mutaplasmid_id（所有突变数据应该来自同一个突变质体）
                    selectedMutaplasmidID = mutaData.first?.mutaplasmid_id
                    // 直接使用倍数（value已经是倍数）
                    for mutation in mutaData {
                        mutatedAttributes[mutation.attribute_id] = mutation.value
                    }

                    // 查询突变后的typeID、名称和图标
                    if let mutaplasmidID = selectedMutaplasmidID {
                        if let resultingTypeId = databaseManager.getMutatedTypeID(
                            applicableTypeID: drone.type_id,
                            mutaplasmidID: mutaplasmidID
                        ) {
                            mutatedTypeId = resultingTypeId

                            // 查询突变后的名称和图标
                            let typeQuery = "SELECT name, icon_filename FROM types WHERE type_id = ?"
                            if case let .success(rows) = databaseManager.executeQuery(
                                typeQuery, parameters: [resultingTypeId]
                            ), let row = rows.first {
                                mutatedName = row["name"] as? String
                                mutatedIconFileName = row["icon_filename"] as? String
                            }
                        }
                    }
                }

                var simDrone = SimDrone(
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
                // 设置突变数据
                simDrone.selectedMutaplasmidID = selectedMutaplasmidID
                simDrone.mutatedAttributes = mutatedAttributes
                simDrone.mutatedTypeId = mutatedTypeId
                simDrone.mutatedName = mutatedName
                simDrone.mutatedIconFileName = mutatedIconFileName

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
                let cargoPlaceholders = Array(repeating: "?", count: cargoTypeIds.count).joined(
                    separator: ",")
                let cargoQuery =
                    "SELECT type_id, name, volume, icon_filename FROM types WHERE type_id IN (\(cargoPlaceholders))"

                if case let .success(rows) = databaseManager.executeQuery(
                    cargoQuery, parameters: cargoTypeIds
                ) {
                    for row in rows {
                        if let typeId = row["type_id"] as? Int,
                           let name = row["name"] as? String
                        {
                            let volume = row["volume"] as? Double ?? 0
                            let iconFileName = row["icon_filename"] as? String
                            cargoItemInfoMap[typeId] = (
                                name: name, volume: volume, iconFileName: iconFileName
                            )
                        }
                    }
                }
            }

            for item in cargoList {
                // 首先尝试从专门查询的货舱物品信息中获取
                if let cargoItemInfo = cargoItemInfoMap[item.type_id] {
                    cargoItems.append(
                        SimCargoItem(
                            typeId: item.type_id,
                            quantity: item.quantity,
                            volume: cargoItemInfo.volume,
                            name: cargoItemInfo.name,
                            iconFileName: cargoItemInfo.iconFileName
                        ))
                } else {
                    // 如果专门查询没有结果，再尝试从typeInfoMap获取
                    let itemInfo =
                        typeInfoMap[item.type_id] ?? (
                            groupID: 0, capacity: 0, volume: 0, mass: 0, name: "Unknown Item",
                            iconFileName: nil
                        )

                    cargoItems.append(
                        SimCargoItem(
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
            if AppConfiguration.Fitting.showDebug {
                Logger.info("开始加载植入体数据，数量: \(implantTypeIds.count)")
            }

            // 构建查询参数
            let placeholders = String(repeating: "?,", count: implantTypeIds.count).dropLast()

            // 查询植入体属性
            let attrQuery = """
                SELECT t.type_id, ta.attribute_id, ta.value, da.name, t.name as type_name, t.icon_filename, t.groupID
                FROM typeAttributes ta
                JOIN dogmaAttributes da ON ta.attribute_id = da.attribute_id
                JOIN types t ON ta.type_id = t.type_id
                WHERE ta.type_id IN (\(placeholders))
            """

            var typeAttributes: [Int: [Int: Double]] = [:]
            var typeAttributesByName: [Int: [String: Double]] = [:]
            var typeNames: [Int: String] = [:]
            var typeIcons: [Int: String] = [:]
            var typeGroupIDs: [Int: Int] = [:]

            if case let .success(rows) = databaseManager.executeQuery(
                attrQuery, parameters: implantTypeIds
            ) {
                for row in rows {
                    if let typeId = row["type_id"] as? Int,
                       let attrId = row["attribute_id"] as? Int,
                       let value = row["value"] as? Double,
                       let name = row["name"] as? String
                    {
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

                        // 保存物品名称、图标和分组ID
                        if let typeName = row["type_name"] as? String {
                            typeNames[typeId] = typeName
                        }
                        if let iconFileName = row["icon_filename"] as? String {
                            typeIcons[typeId] = iconFileName
                        }
                        if let groupID = row["groupID"] as? Int {
                            typeGroupIDs[typeId] = groupID
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

            if case let .success(rows) = databaseManager.executeQuery(
                effectQuery, parameters: implantTypeIds
            ) {
                for row in rows {
                    if let typeId = row["type_id"] as? Int,
                       let effectId = row["effect_id"] as? Int
                    {
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
                   let attributesByName = typeAttributesByName[typeId]
                {
                    let effects = typeEffects[typeId] ?? []
                    let name = typeNames[typeId] ?? "Unknown Implant"
                    let iconFileName = typeIcons[typeId]
                    let groupID = typeGroupIDs[typeId] ?? 0

                    // 创建植入体对象
                    let implant = SimImplant(
                        typeId: typeId,
                        attributes: attributes,
                        attributesByName: attributesByName,
                        effects: effects,
                        requiredSkills: extractRequiredSkills(attributes: attributes),
                        groupID: groupID,
                        name: name,
                        iconFileName: iconFileName
                    )

                    implants.append(implant)
                    if AppConfiguration.Fitting.showDebug {
                        Logger.info("加载植入体: \(name), typeId: \(typeId), groupID: \(groupID)")
                    }
                }
            }
        }

        // 6. 组装SimulationInput（带上原始配置元数据）
        if AppConfiguration.Fitting.showDebug {
            Logger.info("localFittingToSimulationInput 完成组装.")
        }

        // 处理舰载机数据，将FighterSquad转换为SimFighterSquad
        if AppConfiguration.Fitting.showDebug {
            Logger.info("开始将FighterSquad转换为SimFighterSquad，原始数量: \(localFitting.fighters?.count ?? 0)")
        }
        // 检查FighterSquad数据完整性
        if AppConfiguration.Fitting.showDebug, let fighters = localFitting.fighters {
            for (index, fighter) in fighters.enumerated() {
                Logger.info(
                    "输入FighterSquad[\(index)]: type_id=\(fighter.type_id), tubeId=\(fighter.tubeId), quantity=\(fighter.quantity)"
                )
            }
        }

        let simFighters: [SimFighterSquad]? = localFitting.fighters?.compactMap { fighter in
            if AppConfiguration.Fitting.showDebug {
                Logger.info(
                    "处理舰载机: typeId=\(fighter.type_id), tubeId=\(fighter.tubeId), quantity=\(fighter.quantity)"
                )
            }
            // 获取舰载机属性和效果
            let attr = attrMap[fighter.type_id]?.0 ?? [:]
            let attrName = attrMap[fighter.type_id]?.1 ?? [:]
            let effects = effectMap[fighter.type_id] ?? []

            // 获取舰载机信息
            let fighterInfo =
                typeInfoMap[fighter.type_id] ?? (
                    groupID: 0, capacity: 0, volume: 0, mass: 0, name: "Unknown Fighter",
                    iconFileName: nil
                )
            if AppConfiguration.Fitting.showDebug {
                Logger.info("舰载机信息: groupID=\(fighterInfo.groupID), name=\(fighterInfo.name)")
            }

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
        if AppConfiguration.Fitting.showDebug {
            Logger.info("完成SimFighterSquad转换，结果数量: \(simFighters?.count ?? 0)")
        }

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
        if AppConfiguration.Fitting.showDebug, let fighters = input.fighters {
            Logger.info("检查SimFighterSquad到FighterSquad转换前的数据: 数量 = \(fighters.count)")
            for (index, fighter) in fighters.enumerated() {
                Logger.info(
                    "SimFighterSquad[\(index)]: typeId=\(fighter.typeId), tubeId=\(fighter.tubeId), quantity=\(fighter.quantity)"
                )
            }
        }

        // 从模块数据中恢复装备项
        let items = input.modules.map { module -> LocalFittingItem in
            // 添加调试日志，记录弹药信息
            if AppConfiguration.Fitting.showDebug, let charge = module.charge {
                Logger.info(
                    "转换装备弹药: 装备=\(module.name), 弹药=\(charge.name), 弹药数量=\(charge.chargeQuantity ?? -1)"
                )
            }

            // 构建突变数据（直接存储倍数：+15%就是1.15，-20%是0.8）
            var mutaData: [MutationData]? = nil
            if let mutaplasmidID = module.selectedMutaplasmidID, !module.mutatedAttributes.isEmpty {
                mutaData = module.mutatedAttributes.map { attributeID, multiplier in
                    // 直接存储倍数（不带百分号）
                    MutationData(
                        mutaplasmid_id: mutaplasmidID,
                        attribute_id: attributeID,
                        value: multiplier
                    )
                }
            }

            return LocalFittingItem(
                flag: module.flag ?? .invalid,
                quantity: module.quantity,
                type_id: module.typeId,
                status: module.status,
                charge_type_id: module.charge?.typeId,
                charge_quantity: module.charge?.chargeQuantity,
                muta: mutaData
            )
        }

        // 从无人机数据中恢复无人机列表
        let drones =
            input.drones.isEmpty
                ? nil
                : input.drones.map { drone -> Drone in
                    // 构建突变数据（直接存储倍数：+15%就是1.15，-20%是0.8）
                    var mutaData: [MutationData]? = nil
                    if let mutaplasmidID = drone.selectedMutaplasmidID, !drone.mutatedAttributes.isEmpty {
                        mutaData = drone.mutatedAttributes.map { attributeID, multiplier in
                            // 直接存储倍数（不带百分号）
                            MutationData(
                                mutaplasmid_id: mutaplasmidID,
                                attribute_id: attributeID,
                                value: multiplier
                            )
                        }
                    }

                    return Drone(
                        type_id: drone.typeId,
                        quantity: drone.quantity,
                        active_count: drone.activeCount,
                        muta: mutaData
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
        if AppConfiguration.Fitting.showDebug, let fighters = fighters {
            Logger.info("检查转换后的FighterSquad数据: 数量 = \(fighters.count)")
            for (index, fighter) in fighters.enumerated() {
                Logger.info(
                    "FighterSquad[\(index)]: type_id=\(fighter.type_id), tubeId=\(fighter.tubeId), quantity=\(fighter.quantity)"
                )
            }
        }

        // 从货舱数据中恢复货舱物品列表
        let cargo =
            input.cargo.items.isEmpty
                ? nil
                : input.cargo.items.map { item -> CargoItem in
                    return CargoItem(
                        type_id: item.typeId,
                        quantity: item.quantity
                    )
                }

        // 从植入体数据中提取typeId列表
        let implants =
            input.implants.isEmpty
                ? nil
                : input.implants.map { implant -> Int in
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

    /// 将模拟器输入数据直接转换为在线配置格式
    /// - Parameter input: 模拟器输入数据
    /// - Returns: 在线配置数据，适用于上传到EVE服务器
    static func simulationInputToCharacterFitting(input: SimulationInput) -> CharacterFitting {
        if AppConfiguration.Fitting.showDebug {
            Logger.info("开始将SimulationInput转换为CharacterFitting - 配置名称: \(input.name)")
        }

        // 创建装备项列表，只包含安装在飞船上的装备（排除货舱、无人机舱等）
        var items: [FittingItem] = []

        // 1. 添加模块装备
        for module in input.modules {
            if let flag = module.flag, flag != .cargo && flag != .droneBay && flag != .fighterBay {
                let item = FittingItem(
                    flag: flag,
                    quantity: module.quantity,
                    type_id: module.typeId
                )
                items.append(item)
                if AppConfiguration.Fitting.showDebug {
                    Logger.debug("添加模块: \(module.name), flag: \(flag), typeId: \(module.typeId)")
                }
            }
        }

        // 2. 添加无人机到无人机舱
        for drone in input.drones {
            let item = FittingItem(
                flag: .droneBay,
                quantity: drone.quantity,
                type_id: drone.typeId
            )
            items.append(item)
            if AppConfiguration.Fitting.showDebug {
                Logger.debug("添加无人机: \(drone.name), 数量: \(drone.quantity)")
            }
        }

        // 3. 添加舰载机到舰载机舱
        if let fighters = input.fighters {
            for fighter in fighters {
                let item = FittingItem(
                    flag: .fighterBay,
                    quantity: fighter.quantity,
                    type_id: fighter.typeId
                )
                items.append(item)
                if AppConfiguration.Fitting.showDebug {
                    Logger.debug("添加舰载机: \(fighter.name), 数量: \(fighter.quantity)")
                }
            }
        }

        // 4. 添加货舱物品
        for cargoItem in input.cargo.items {
            let item = FittingItem(
                flag: .cargo,
                quantity: cargoItem.quantity,
                type_id: cargoItem.typeId
            )
            items.append(item)
            if AppConfiguration.Fitting.showDebug {
                Logger.debug("添加货舱物品: \(cargoItem.name), 数量: \(cargoItem.quantity)")
            }
        }

        // 创建在线配置对象
        let characterFitting = CharacterFitting(
            description: input.description.isEmpty ? nil : input.description,
            fitting_id: 0, // 新上传的配置ID为0
            items: items,
            name: input.name.isEmpty ? "Untitled Fitting" : input.name,
            ship_type_id: input.ship.typeId
        )

        if AppConfiguration.Fitting.showDebug {
            Logger.info("SimulationInput转换完成 - 总装备数: \(items.count), 飞船ID: \(input.ship.typeId)")
        }
        return characterFitting
    }

    /// 将本地配置转换为EFT格式的剪贴板文本
    /// - Parameters:
    ///   - localFitting: 本地配置对象
    ///   - databaseManager: 数据库管理器，用于查询物品名称
    /// - Returns: EFT格式的配置文本
    static func localFittingToEFT(localFitting: LocalFitting, databaseManager: DatabaseManager)
        -> String
    {
        if AppConfiguration.Fitting.showDebug {
            Logger.info("开始将本地配置转换为EFT格式 - 配置名称: \(localFitting.name)")
        }

        var lines: [String] = []

        // 1. 获取飞船名称（使用标准name字段以保持EFT格式兼容性）
        var shipName = "Unknown Ship"
        let shipQuery = "SELECT name FROM types WHERE type_id = ?"
        if case let .success(rows) = databaseManager.executeQuery(
            shipQuery, parameters: [localFitting.ship_type_id]
        ),
            let row = rows.first,
            let name = row["name"] as? String
        {
            shipName = name
        }

        // 第一行：飞船和配置名称
        let fittingName = localFitting.name.isEmpty ? "Unnamed Fitting" : localFitting.name
        lines.append("[\(shipName), \(fittingName)]")

        // 2. 收集所有需要查询的typeId
        var allTypeIds = localFitting.items.map { $0.type_id }

        // 添加弹药typeId
        let chargeTypeIds = localFitting.items.compactMap { $0.charge_type_id }
        allTypeIds.append(contentsOf: chargeTypeIds)

        // 添加无人机typeId
        if let drones = localFitting.drones {
            allTypeIds.append(contentsOf: drones.map { $0.type_id })
        }

        // 添加舰载机typeId
        if let fighters = localFitting.fighters {
            allTypeIds.append(contentsOf: fighters.map { $0.type_id })
        }

        // 添加货舱物品typeId
        if let cargo = localFitting.cargo {
            allTypeIds.append(contentsOf: cargo.map { $0.type_id })
        }

        // 添加植入体typeId
        if let implants = localFitting.implants {
            allTypeIds.append(contentsOf: implants)
        }

        // 3. 批量查询所有物品名称（使用标准name字段以保持EFT格式兼容性）
        var itemNames: [Int: String] = [:]
        if !allTypeIds.isEmpty {
            let placeholders = Array(repeating: "?", count: allTypeIds.count).joined(separator: ",")
            let nameQuery = "SELECT type_id, name FROM types WHERE type_id IN (\(placeholders))"

            if case let .success(rows) = databaseManager.executeQuery(
                nameQuery, parameters: allTypeIds
            ) {
                for row in rows {
                    if let typeId = row["type_id"] as? Int,
                       let name = row["name"] as? String
                    {
                        itemNames[typeId] = name
                    }
                }
            }
        }

        // 4. 按槽位分组模块
        let modulesBySlot = groupModulesBySlot(items: localFitting.items)

        // 5. 按顺序添加各槽位模块

        // 低槽模块
        if !modulesBySlot.lowSlots.isEmpty {
            lines.append("") // 空行分隔
            for item in modulesBySlot.lowSlots {
                lines.append(formatModuleLine(item: item, itemNames: itemNames))
            }
        }

        // 中槽模块
        if !modulesBySlot.medSlots.isEmpty {
            lines.append("") // 空行分隔
            for item in modulesBySlot.medSlots {
                lines.append(formatModuleLine(item: item, itemNames: itemNames))
            }
        }

        // 高槽模块
        if !modulesBySlot.hiSlots.isEmpty {
            lines.append("") // 空行分隔
            for item in modulesBySlot.hiSlots {
                lines.append(formatModuleLine(item: item, itemNames: itemNames))
            }
        }

        // 改装件
        if !modulesBySlot.rigs.isEmpty {
            lines.append("") // 空行分隔
            for item in modulesBySlot.rigs {
                lines.append(formatModuleLine(item: item, itemNames: itemNames))
            }
        }

        // 子系统
        if !modulesBySlot.subsystems.isEmpty {
            lines.append("") // 空行分隔
            for item in modulesBySlot.subsystems {
                lines.append(formatModuleLine(item: item, itemNames: itemNames))
            }
        }

        // 服务槽（如果有）
        if !modulesBySlot.services.isEmpty {
            lines.append("") // 空行分隔
            for item in modulesBySlot.services {
                lines.append(formatModuleLine(item: item, itemNames: itemNames))
            }
        }

        // 6. 无人机（两个空行分隔）
        if let drones = localFitting.drones, !drones.isEmpty {
            lines.append("")
            lines.append("")
            for drone in drones {
                if drone.quantity > 0 {
                    let droneName = itemNames[drone.type_id] ?? "Unknown Drone"
                    lines.append("\(droneName) x\(drone.quantity)")
                }
            }
        }

        // 7. 舰载机（如果有）
        if let fighters = localFitting.fighters, !fighters.isEmpty {
            if localFitting.drones?.isEmpty ?? true {
                lines.append("")
                lines.append("")
            }
            for fighter in fighters {
                if fighter.quantity > 0 {
                    let fighterName = itemNames[fighter.type_id] ?? "Unknown Fighter"
                    lines.append("\(fighterName) x\(fighter.quantity)")
                }
            }
        }

        // 8. 货舱物品（排除无人机和舰载机）
        if let cargo = localFitting.cargo, !cargo.isEmpty {
            if (localFitting.drones?.isEmpty ?? true) && (localFitting.fighters?.isEmpty ?? true) {
                lines.append("")
                lines.append("")
            }

            // 使用装备分类器过滤货舱物品，排除无人机和舰载机
            let classifier = EquipmentClassifier(databaseManager: databaseManager)
            let cargoTypeIds = cargo.map { $0.type_id }
            let cargoClassifications = classifier.classifyEquipments(typeIds: cargoTypeIds)

            for cargoItem in cargo {
                if cargoItem.quantity > 0 {
                    // 检查物品类型，排除无人机和舰载机
                    let classification = cargoClassifications[cargoItem.type_id]
                    if classification?.category != .drone && classification?.category != .fighter {
                        let itemName = itemNames[cargoItem.type_id] ?? "Unknown Item"
                        lines.append("\(itemName) x\(cargoItem.quantity)")
                    } else {
                        Logger.debug(
                            "跳过货舱中的无人机/舰载机: \(itemNames[cargoItem.type_id] ?? "Unknown") (类型: \(classification?.category.rawValue ?? "unknown"))"
                        )
                    }
                }
            }
        }

        // 9. 植入体（作为货舱物品导出）
        if let implants = localFitting.implants, !implants.isEmpty {
            // 检查是否需要添加空行分隔
            let needsEmptyLines =
                (localFitting.drones?.isEmpty ?? true) && (localFitting.fighters?.isEmpty ?? true)
                    && (localFitting.cargo?.isEmpty ?? true)
            if needsEmptyLines {
                lines.append("")
                lines.append("")
            }

            for implantTypeId in implants {
                let implantName = itemNames[implantTypeId] ?? "Unknown Implant"
                lines.append("\(implantName) x1")
            }

            if AppConfiguration.Fitting.showDebug {
                Logger.info("导出了 \(implants.count) 个植入体到EFT格式")
            }
        }

        let result = lines.joined(separator: "\n")

        // 统计导出内容
        let implantCount = localFitting.implants?.count ?? 0
        let totalLines = lines.count

        if AppConfiguration.Fitting.showDebug {
            if implantCount > 0 {
                Logger.info("EFT格式转换完成，总行数: \(totalLines)，包含 \(implantCount) 个植入体（作为货舱物品导出）")
            } else {
                Logger.info("EFT格式转换完成，总行数: \(totalLines)")
            }
        }

        return result
    }

    /// 按槽位分组模块（私有辅助方法）
    private static func groupModulesBySlot(items: [LocalFittingItem]) -> (
        lowSlots: [LocalFittingItem],
        medSlots: [LocalFittingItem],
        hiSlots: [LocalFittingItem],
        rigs: [LocalFittingItem],
        subsystems: [LocalFittingItem],
        services: [LocalFittingItem]
    ) {
        var lowSlots: [LocalFittingItem] = []
        var medSlots: [LocalFittingItem] = []
        var hiSlots: [LocalFittingItem] = []
        var rigs: [LocalFittingItem] = []
        var subsystems: [LocalFittingItem] = []
        var services: [LocalFittingItem] = []

        for item in items {
            switch item.flag {
            case .loSlot0, .loSlot1, .loSlot2, .loSlot3, .loSlot4, .loSlot5, .loSlot6, .loSlot7:
                lowSlots.append(item)
            case .medSlot0, .medSlot1, .medSlot2, .medSlot3, .medSlot4, .medSlot5, .medSlot6,
                 .medSlot7:
                medSlots.append(item)
            case .hiSlot0, .hiSlot1, .hiSlot2, .hiSlot3, .hiSlot4, .hiSlot5, .hiSlot6, .hiSlot7:
                hiSlots.append(item)
            case .rigSlot0, .rigSlot1, .rigSlot2:
                rigs.append(item)
            case .subSystemSlot0, .subSystemSlot1, .subSystemSlot2, .subSystemSlot3:
                subsystems.append(item)
            case .serviceSlot0, .serviceSlot1, .serviceSlot2, .serviceSlot3, .serviceSlot4,
                 .serviceSlot5, .serviceSlot6, .serviceSlot7:
                services.append(item)
            default:
                break
            }
        }

        // 按槽位索引排序
        lowSlots.sort { getSlotIndex(from: $0.flag) < getSlotIndex(from: $1.flag) }
        medSlots.sort { getSlotIndex(from: $0.flag) < getSlotIndex(from: $1.flag) }
        hiSlots.sort { getSlotIndex(from: $0.flag) < getSlotIndex(from: $1.flag) }
        rigs.sort { getSlotIndex(from: $0.flag) < getSlotIndex(from: $1.flag) }
        subsystems.sort { getSlotIndex(from: $0.flag) < getSlotIndex(from: $1.flag) }
        services.sort { getSlotIndex(from: $0.flag) < getSlotIndex(from: $1.flag) }

        return (lowSlots, medSlots, hiSlots, rigs, subsystems, services)
    }

    /// 格式化模块行（包含弹药信息）（私有辅助方法）
    private static func formatModuleLine(item: LocalFittingItem, itemNames: [Int: String]) -> String {
        let moduleName = itemNames[item.type_id] ?? "Unknown Module"

        if let chargeTypeId = item.charge_type_id {
            let chargeName = itemNames[chargeTypeId] ?? "Unknown Charge"
            return "\(moduleName), \(chargeName)"
        } else {
            return moduleName
        }
    }

    /// 从槽位标识获取槽位索引（私有辅助方法）
    private static func getSlotIndex(from flag: FittingFlag) -> Int {
        switch flag {
        case .loSlot0, .medSlot0, .hiSlot0, .rigSlot0, .subSystemSlot0, .serviceSlot0:
            return 0
        case .loSlot1, .medSlot1, .hiSlot1, .rigSlot1, .subSystemSlot1, .serviceSlot1:
            return 1
        case .loSlot2, .medSlot2, .hiSlot2, .rigSlot2, .subSystemSlot2, .serviceSlot2:
            return 2
        case .loSlot3, .medSlot3, .hiSlot3, .subSystemSlot3, .serviceSlot3:
            return 3
        case .loSlot4, .medSlot4, .hiSlot4, .serviceSlot4:
            return 4
        case .loSlot5, .medSlot5, .hiSlot5, .serviceSlot5:
            return 5
        case .loSlot6, .medSlot6, .hiSlot6, .serviceSlot6:
            return 6
        case .loSlot7, .medSlot7, .hiSlot7, .serviceSlot7:
            return 7
        default:
            return 999
        }
    }

    /// 将EFT格式文本转换为LocalFitting（带飞船选择）
    /// - Parameters:
    ///   - eftText: EFT格式的配置文本
    ///   - databaseManager: 数据库管理器，用于查询物品ID
    ///   - selectedShipTypeId: 当有多个同名飞船时，用户选择的飞船ID
    /// - Returns: LocalFitting对象
    /// - Throws: 转换过程中的错误
    static func eftToLocalFitting(
        eftText: String, databaseManager: DatabaseManager, selectedShipTypeId: Int
    ) throws -> LocalFitting {
        return try eftToLocalFittingInternal(
            eftText: eftText, databaseManager: databaseManager,
            selectedShipTypeId: selectedShipTypeId
        )
    }

    /// 将EFT格式文本转换为LocalFitting
    /// - Parameters:
    ///   - eftText: EFT格式的配置文本
    ///   - databaseManager: 数据库管理器，用于查询物品ID
    /// - Returns: LocalFitting对象
    /// - Throws: 转换过程中的错误
    static func eftToLocalFitting(eftText: String, databaseManager: DatabaseManager) throws
        -> LocalFitting
    {
        return try eftToLocalFittingInternal(
            eftText: eftText, databaseManager: databaseManager, selectedShipTypeId: nil
        )
    }

    /// 内部EFT转换方法
    private static func eftToLocalFittingInternal(
        eftText: String, databaseManager: DatabaseManager, selectedShipTypeId: Int?
    ) throws -> LocalFitting {
        if AppConfiguration.Fitting.showDebug {
            Logger.info("开始将EFT格式转换为LocalFitting")
        }

        let lines = eftText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        // 找到第一个非空行
        guard let firstLineIndex = lines.firstIndex(where: { !$0.isEmpty }),
              firstLineIndex < lines.count
        else {
            throw NSError(
                domain: "EFTConvert", code: 1, userInfo: [NSLocalizedDescriptionKey: "EFT文本为空"]
            )
        }

        // 解析第一行：[飞船名称, 配置名称]
        let firstLine = lines[firstLineIndex]
        guard firstLine.hasPrefix("[") && firstLine.hasSuffix("]") else {
            throw NSError(
                domain: "EFTConvert", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "EFT格式错误：第一行应为 [飞船名称, 配置名称]"]
            )
        }

        let headerContent = String(firstLine.dropFirst().dropLast())
        let headerParts = headerContent.components(separatedBy: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard headerParts.count >= 2 else {
            throw NSError(
                domain: "EFTConvert", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "EFT格式错误：无法解析飞船和配置名称"]
            )
        }

        let shipName = headerParts[0]
        let fittingName = headerParts[1]

        // 第一步：收集所有物品名称并批量查询typeId
        var allItemNames = collectAllItemNames(lines: lines, startIndex: firstLineIndex + 1)
        allItemNames.insert(shipName)
        if AppConfiguration.Fitting.showDebug {
            Logger.info("收集到 \(allItemNames.count) 个不重复的物品名称")
        }

        // 批量查询所有物品的typeId
        let nameToTypeIdMap = try batchQueryTypeIds(
            itemNames: allItemNames, databaseManager: databaseManager
        )
        if AppConfiguration.Fitting.showDebug {
            Logger.success("成功查询到 \(nameToTypeIdMap.count) 个物品的typeId")
        }

        // 查找飞船ID（初始查找，后续会通过验证查询确认）
        guard let initialShipTypeId = nameToTypeIdMap[shipName] else {
            throw NSError(
                domain: "EFTConvert", code: 4,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "\(NSLocalizedString("Fitting_Import_Ship_notfound", comment: "")): \(shipName)",
                ]
            )
        }

        // 声明可变的飞船ID变量
        var shipTypeId = initialShipTypeId

        // 验证是否为飞船类型并查询飞船信息
        let shipValidationQuery = """
            SELECT t.type_id, t.en_name, t.zh_name, t.icon_filename
            FROM types t
            WHERE (t.en_name = ? OR t.zh_name = ?) AND t.categoryID = 6
        """

        guard
            case let .success(rows) = databaseManager.executeQuery(
                shipValidationQuery, parameters: [shipName, shipName]
            )
        else {
            throw NSError(
                domain: "EFTConvert", code: 5,
                userInfo: [
                    NSLocalizedDescriptionKey: String(
                        format: NSLocalizedString(
                            "Fitting_Import_Validation_Failed_Error", comment: "验证物品类型失败"
                        ), shipName
                    ),
                ]
            )
        }

        // 根据查询结果行数处理不同情况
        if rows.isEmpty {
            // 查无此飞船
            throw NSError(
                domain: "EFTConvert", code: 6,
                userInfo: [
                    NSLocalizedDescriptionKey: String(
                        format: NSLocalizedString(
                            "Fitting_Import_Not_Ship_Error", comment: "导入错误：不是飞船"
                        ), shipName
                    ),
                ]
            )
        } else if rows.count == 1 {
            // 正常情况：找到唯一的飞船
            guard let row = rows.first,
                  let validatedShipTypeId = row["type_id"] as? Int
            else {
                throw NSError(
                    domain: "EFTConvert", code: 5,
                    userInfo: [
                        NSLocalizedDescriptionKey: String(
                            format: NSLocalizedString(
                                "Fitting_Import_Validation_Failed_Error", comment: "验证物品类型失败"
                            ),
                            shipName
                        ),
                    ]
                )
            }

            // 使用验证过的飞船ID（可能与之前查询的不同）
            shipTypeId = validatedShipTypeId
            if AppConfiguration.Fitting.showDebug {
                Logger.info("验证通过：\(shipName) 是有效的飞船 (ID: \(shipTypeId))")
            }
        } else {
            // 多个同名飞船，需要用户选择
            if AppConfiguration.Fitting.showDebug {
                Logger.info("发现多个同名飞船：\(shipName)，数量：\(rows.count)")
            }

            // 如果提供了选择的飞船ID，验证并使用它
            if let selectedId = selectedShipTypeId {
                // 验证选择的飞船ID是否在查询结果中
                if rows.first(where: { ($0["type_id"] as? Int) == selectedId }) != nil {
                    shipTypeId = selectedId
                    if AppConfiguration.Fitting.showDebug {
                        Logger.info("使用用户选择的飞船：\(shipName) (ID: \(shipTypeId))")
                    }
                } else {
                    // 选择的飞船ID不在结果中，可能是无效的选择
                    throw NSError(
                        domain: "EFTConvert", code: 8,
                        userInfo: [NSLocalizedDescriptionKey: "选择的飞船ID无效"]
                    )
                }
            } else {
                // 没有提供选择，构建飞船选择信息并抛出错误
                var shipOptions: [(typeId: Int, name: String, iconFileName: String?)] = []
                for row in rows {
                    if let typeId = row["type_id"] as? Int {
                        let iconFileName = row["icon_filename"] as? String

                        // 这里需要显示给用户选择，所以需要考虑本地化
                        // 优先使用中文名称，如果没有则使用英文名称
                        var displayName = "Unknown Ship"
                        if let zhName = row["zh_name"] as? String, !zhName.isEmpty {
                            displayName = zhName
                        } else if let enName = row["en_name"] as? String, !enName.isEmpty {
                            displayName = enName
                        }

                        shipOptions.append(
                            (typeId: typeId, name: displayName, iconFileName: iconFileName))
                    }
                }

                // 这里需要抛出一个特殊的错误，包含飞船选择信息
                // 调用方需要处理这个错误并显示选择界面
                let userInfo: [String: Any] = [
                    NSLocalizedDescriptionKey: String(
                        format: NSLocalizedString(
                            "Fitting_Import_Multiple_Ships_Error", comment: "发现多个同名飞船，请选择"
                        ),
                        shipName
                    ),
                    "shipOptions": shipOptions,
                    "shipName": shipName,
                ]
                throw NSError(domain: "EFTConvert", code: 7, userInfo: userInfo)
            }
        }

        // 第二步：使用装备分类器对所有typeId进行批量分类
        let allTypeIds = Array(nameToTypeIdMap.values)
        let classifier = EquipmentClassifier(databaseManager: databaseManager)
        let classifications = classifier.classifyEquipments(typeIds: allTypeIds)
        if AppConfiguration.Fitting.showDebug {
            Logger.info("完成 \(allTypeIds.count) 个物品的分类")
        }

        // 解析装备、无人机、舰载机和货舱物品
        var items: [LocalFittingItem] = []
        var drones: [Drone] = []
        var cargo: [CargoItem] = []

        // 临时存储舰载机物品，稍后统一处理
        var tempFighterBayItems: [FittingItem] = []

        // 槽位计数器
        var slotCounters = SlotCounters()

        // 跳过第一行（飞船和配置名称），从下一行开始解析
        let startIndex = firstLineIndex + 1

        for index in startIndex ..< lines.count {
            let line = lines[index]
            let lineNumber = index + 1 // 实际行号（从1开始计数）

            // 跳过空行和空槽位标记
            if line.isEmpty || (line.hasPrefix("[") && line.hasSuffix("]")) {
                continue
            }

            do {
                // 检查是否为数量格式
                if isQuantityFormat(line: line) {
                    // 所有数量格式的物品都按货舱物品处理，然后根据分类决定最终归属
                    if let result = try parseQuantityItemWithClassification(
                        line: line, nameToTypeIdMap: nameToTypeIdMap,
                        classifications: classifications
                    ) {
                        switch result.category {
                        case .drone:
                            let drone = Drone(
                                type_id: result.typeId,
                                quantity: result.quantity,
                                active_count: 0,
                                muta: nil
                            )
                            drones.append(drone)
                            if AppConfiguration.Fitting.showDebug {
                                Logger.debug("数量物品归类为无人机: \(result.itemName) x\(result.quantity)")
                            }
                        case .fighter:
                            // 暂存舰载机信息，稍后统一处理
                            let fighterItem = FittingItem(
                                flag: .fighterBay,
                                quantity: result.quantity,
                                type_id: result.typeId
                            )
                            tempFighterBayItems.append(fighterItem)
                            if AppConfiguration.Fitting.showDebug {
                                Logger.debug("数量物品归类为舰载机: \(result.itemName) x\(result.quantity)")
                            }
                        default:
                            let cargoItem = CargoItem(
                                type_id: result.typeId,
                                quantity: result.quantity
                            )
                            cargo.append(cargoItem)
                            if AppConfiguration.Fitting.showDebug {
                                Logger.debug("数量物品归类为货舱: \(result.itemName) x\(result.quantity)")
                            }
                        }
                    }
                } else {
                    // 非数量格式的物品，根据分类器结果确定装备类型
                    if let item = try parseEquipmentLineWithClassification(
                        line: line, slotCounters: &slotCounters, nameToTypeIdMap: nameToTypeIdMap,
                        classifications: classifications
                    ) {
                        items.append(item)
                    }
                }
            } catch {
                Logger.warning("解析第\(lineNumber)行失败：\(line) - \(error.localizedDescription)")
                // 继续解析其他行，不因单行错误而中断
            }
        }

        // 使用智能舰载机处理逻辑
        if AppConfiguration.Fitting.showDebug {
            Logger.info("EFT导入: 准备处理舰载机配置，找到 \(tempFighterBayItems.count) 个舰载机物品")
        }
        let fighters = processFighters(
            shipTypeId: shipTypeId,
            fighterBayItems: tempFighterBayItems,
            databaseManager: databaseManager
        )
        if AppConfiguration.Fitting.showDebug {
            Logger.info("EFT导入: 舰载机处理完成，生成了 \(fighters.count) 个FighterSquad")
        }

        // 创建LocalFitting对象
        let localFitting = LocalFitting(
            description: "",
            fitting_id: Int(Date().timeIntervalSince1970), // 使用时间戳作为ID
            items: items,
            name: fittingName,
            ship_type_id: shipTypeId,
            drones: drones.isEmpty ? nil : drones,
            fighters: fighters.isEmpty ? nil : fighters,
            cargo: cargo.isEmpty ? nil : cargo,
            implants: nil,
            environment_type_id: nil
        )

        // 打印详细的解析结果
        if AppConfiguration.Fitting.showDebug {
            Logger.info("=== EFT解析结果详情 ===")
            Logger.info("Ship: \(shipName)")
            Logger.info("Fitting Name: \(fittingName)")

            // 获取所有装备的名称（用于调试日志）
            let allEquipmentTypeIds = items.map { $0.type_id }
            var equipmentNames: [Int: String] = [:]
            if !allEquipmentTypeIds.isEmpty {
                let placeholders = Array(repeating: "?", count: allEquipmentTypeIds.count).joined(
                    separator: ",")
                let nameQuery = "SELECT type_id, name FROM types WHERE type_id IN (\(placeholders))"
                if case let .success(rows) = databaseManager.executeQuery(
                    nameQuery, parameters: allEquipmentTypeIds
                ) {
                    for row in rows {
                        if let typeId = row["type_id"] as? Int,
                           let name = row["name"] as? String
                        {
                            equipmentNames[typeId] = name
                        }
                    }
                }
            }

            // 打印装备详情
            for item in items {
                let equipmentName = equipmentNames[item.type_id] ?? "Unknown Equipment"
                let category = classifications[item.type_id]?.category.rawValue ?? "unknown"
                Logger.info("\(item.flag): \(equipmentName) (category: \(category))")
            }

            // 打印无人机详情
            if !drones.isEmpty {
                Logger.info("=== 无人机 ===")
                for drone in drones {
                    if let droneName = nameToTypeIdMap.first(where: { $0.value == drone.type_id })?.key {
                        let category = classifications[drone.type_id]?.category.rawValue ?? "unknown"
                        Logger.info("Drone: \(droneName) x\(drone.quantity) (category: \(category))")
                    }
                }
            }

            // 打印舰载机详情
            if !fighters.isEmpty {
                Logger.info("=== 舰载机 ===")

                // 获取舰载机名称
                let fighterTypeIds = fighters.map { $0.type_id }
                var fighterNames: [Int: String] = [:]
                if !fighterTypeIds.isEmpty {
                    let placeholders = Array(repeating: "?", count: fighterTypeIds.count).joined(
                        separator: ",")
                    let fighterNameQuery =
                        "SELECT type_id, name FROM types WHERE type_id IN (\(placeholders))"
                    if case let .success(rows) = databaseManager.executeQuery(
                        fighterNameQuery, parameters: fighterTypeIds
                    ) {
                        for row in rows {
                            if let typeId = row["type_id"] as? Int,
                               let name = row["name"] as? String
                            {
                                fighterNames[typeId] = name
                            }
                        }
                    }
                }

                for fighter in fighters {
                    let fighterName = fighterNames[fighter.type_id] ?? "Unknown Fighter"
                    let category = classifications[fighter.type_id]?.category.rawValue ?? "fighter"
                    Logger.info(
                        "Fighter: \(fighterName) x\(fighter.quantity) (tubeId: \(fighter.tubeId), category: \(category))"
                    )
                }
            }

            // 打印货舱物品详情
            if !cargo.isEmpty {
                Logger.info("=== 货舱物品 ===")
                for cargoItem in cargo {
                    if let itemName = nameToTypeIdMap.first(where: { $0.value == cargoItem.type_id })?
                        .key
                    {
                        let category =
                            classifications[cargoItem.type_id]?.category.rawValue ?? "unknown"
                        Logger.info("Cargo: \(itemName) x\(cargoItem.quantity) (category: \(category))")
                    }
                }
            }

            Logger.info("=== 解析统计 ===")
            Logger.info(
                "EFT转换完成 - 装备: \(items.count), 无人机: \(drones.count), 舰载机: \(fighters.count), 货舱: \(cargo.count)"
            )
            Logger.info(
                "装备分布 - 低槽: \(slotCounters.lowSlot), 中槽: \(slotCounters.medSlot), 高槽: \(slotCounters.hiSlot), 改装件: \(slotCounters.rigSlot), 子系统: \(slotCounters.subSystemSlot), 服务槽: \(slotCounters.serviceSlot)"
            )
            Logger.info("注意：使用装备分类器自动分配槽位和归类，舰载机使用智能tubeId分配")
        }

        return localFitting
    }

    /// 槽位类型枚举
    private enum SlotType {
        case lowSlot
        case medSlot
        case hiSlot
        case rigSlot
        case subSystemSlot
        case serviceSlot
    }

    /// 槽位计数器
    private struct SlotCounters {
        var lowSlot = 0
        var medSlot = 0
        var hiSlot = 0
        var rigSlot = 0
        var subSystemSlot = 0
        var serviceSlot = 0
    }

    /// 根据槽位类型获取对应的flag
    private static func getSlotFlag(slotType: SlotType, slotCounters: inout SlotCounters)
        -> FittingFlag
    {
        switch slotType {
        case .lowSlot:
            let flag = getLoSlotFlag(index: slotCounters.lowSlot)
            slotCounters.lowSlot += 1
            return flag
        case .medSlot:
            let flag = getMedSlotFlag(index: slotCounters.medSlot)
            slotCounters.medSlot += 1
            return flag
        case .hiSlot:
            let flag = getHiSlotFlag(index: slotCounters.hiSlot)
            slotCounters.hiSlot += 1
            return flag
        case .rigSlot:
            let flag = getRigSlotFlag(index: slotCounters.rigSlot)
            slotCounters.rigSlot += 1
            return flag
        case .subSystemSlot:
            let flag = getSubSystemSlotFlag(index: slotCounters.subSystemSlot)
            slotCounters.subSystemSlot += 1
            return flag
        case .serviceSlot:
            let flag = getServiceSlotFlag(index: slotCounters.serviceSlot)
            slotCounters.serviceSlot += 1
            return flag
        }
    }

    /// 获取高槽flag
    private static func getHiSlotFlag(index: Int) -> FittingFlag {
        switch index {
        case 0: return .hiSlot0
        case 1: return .hiSlot1
        case 2: return .hiSlot2
        case 3: return .hiSlot3
        case 4: return .hiSlot4
        case 5: return .hiSlot5
        case 6: return .hiSlot6
        case 7: return .hiSlot7
        default: return .hiSlot0
        }
    }

    /// 获取中槽flag
    private static func getMedSlotFlag(index: Int) -> FittingFlag {
        switch index {
        case 0: return .medSlot0
        case 1: return .medSlot1
        case 2: return .medSlot2
        case 3: return .medSlot3
        case 4: return .medSlot4
        case 5: return .medSlot5
        case 6: return .medSlot6
        case 7: return .medSlot7
        default: return .medSlot0
        }
    }

    /// 获取低槽flag
    private static func getLoSlotFlag(index: Int) -> FittingFlag {
        switch index {
        case 0: return .loSlot0
        case 1: return .loSlot1
        case 2: return .loSlot2
        case 3: return .loSlot3
        case 4: return .loSlot4
        case 5: return .loSlot5
        case 6: return .loSlot6
        case 7: return .loSlot7
        default: return .loSlot0
        }
    }

    /// 获取改装件槽flag
    private static func getRigSlotFlag(index: Int) -> FittingFlag {
        switch index {
        case 0: return .rigSlot0
        case 1: return .rigSlot1
        case 2: return .rigSlot2
        default: return .rigSlot0
        }
    }

    /// 获取子系统槽flag
    private static func getSubSystemSlotFlag(index: Int) -> FittingFlag {
        switch index {
        case 0: return .subSystemSlot0
        case 1: return .subSystemSlot1
        case 2: return .subSystemSlot2
        case 3: return .subSystemSlot3
        default: return .subSystemSlot0
        }
    }

    /// 获取服务槽flag
    private static func getServiceSlotFlag(index: Int) -> FittingFlag {
        switch index {
        case 0: return .serviceSlot0
        case 1: return .serviceSlot1
        case 2: return .serviceSlot2
        case 3: return .serviceSlot3
        case 4: return .serviceSlot4
        case 5: return .serviceSlot5
        case 6: return .serviceSlot6
        case 7: return .serviceSlot7
        default: return .serviceSlot0
        }
    }

    // MARK: - 批量查询和分类辅助方法

    /// 使用正则表达式检查是否为数量格式（物品名称 x数量）
    private static func isQuantityFormat(line: String) -> Bool {
        // 正则表达式：匹配 "物品名称 x数字" 格式
        // 物品名称可以包含字母、数字、空格、特殊字符等，但不能以x开头
        // x前后可以有空格，数字可以是1位或多位
        let pattern = #"^.+\s+x\s*\d+$"#

        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            let range = NSRange(location: 0, length: line.utf16.count)
            return regex.firstMatch(in: line, options: [], range: range) != nil
        } catch {
            Logger.warning("正则表达式错误：\(error)")
            // 如果正则表达式失败，回退到简单的字符串检查
            return line.contains(" x")
                && line.split(separator: " ").last?.allSatisfy(\.isNumber) == true
        }
    }

    /// 从数量格式的行中提取物品名称和数量
    private static func parseQuantityLine(line: String) -> (itemName: String, quantity: Int)? {
        // 正则表达式：捕获物品名称和数量
        let pattern = #"^(.+?)\s+x\s*(\d+)$"#

        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            let range = NSRange(location: 0, length: line.utf16.count)

            if let match = regex.firstMatch(in: line, options: [], range: range) {
                let itemNameRange = match.range(at: 1)
                let quantityRange = match.range(at: 2)

                if let itemNameNSRange = Range(itemNameRange, in: line),
                   let quantityNSRange = Range(quantityRange, in: line)
                {
                    let itemName = String(line[itemNameNSRange]).trimmingCharacters(
                        in: .whitespacesAndNewlines)
                    let quantityString = String(line[quantityNSRange])

                    if let quantity = Int(quantityString) {
                        return (itemName: itemName, quantity: quantity)
                    }
                }
            }
        } catch {
            Logger.warning("解析数量行正则表达式错误：\(error)")
        }

        // 如果正则表达式失败，回退到简单的字符串分割
        let parts = line.components(separatedBy: " x")
        if parts.count == 2,
           let quantity = Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
        {
            let itemName = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            return (itemName: itemName, quantity: quantity)
        }

        return nil
    }

    /// 收集EFT文本中的所有物品名称
    private static func collectAllItemNames(lines: [String], startIndex: Int) -> Set<String> {
        var itemNames: Set<String> = []

        for index in startIndex ..< lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)

            // 跳过空行和空槽位标记
            if line.isEmpty || (line.hasPrefix("[") && line.hasSuffix("]")) {
                continue
            }

            // 解析装备行（可能包含弹药）
            if line.contains(",") {
                let parts = line.components(separatedBy: ",").map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                for part in parts {
                    if !part.isEmpty {
                        itemNames.insert(part)
                    }
                }
            } else if isQuantityFormat(line: line) {
                // 使用正则表达式解析数量格式的行
                if let parsed = parseQuantityLine(line: line) {
                    itemNames.insert(parsed.itemName)
                }
            } else {
                // 单个装备名称
                if !line.isEmpty {
                    itemNames.insert(line)
                }
            }
        }

        return itemNames
    }

    /// 批量查询物品名称对应的typeId
    private static func batchQueryTypeIds(itemNames: Set<String>, databaseManager: DatabaseManager)
        throws -> [String: Int]
    {
        guard !itemNames.isEmpty else { return [:] }

        var nameToTypeIdMap: [String: Int] = [:]

        // 将物品名称分批查询，避免SQL语句过长
        let batchSize = 500
        let itemNamesArray = Array(itemNames)

        for i in stride(from: 0, to: itemNamesArray.count, by: batchSize) {
            let endIndex = min(i + batchSize, itemNamesArray.count)
            let batch = Array(itemNamesArray[i ..< endIndex])

            let placeholders = Array(repeating: "?", count: batch.count).joined(separator: ",")
            // 查询en_name和zh_name以支持多语言物品名称
            let query = """
                SELECT type_id, en_name, zh_name 
                FROM types 
                WHERE en_name IN (\(placeholders)) OR zh_name IN (\(placeholders))
            """

            // 构建参数数组：每个物品名称需要查询两次（en_name和zh_name）
            var parameters: [String] = []
            parameters.append(contentsOf: batch) // 用于en_name查询
            parameters.append(contentsOf: batch) // 用于zh_name查询

            if case let .success(rows) = databaseManager.executeQuery(query, parameters: parameters) {
                for row in rows {
                    if let typeId = row["type_id"] as? Int {
                        // 检查en_name匹配
                        if let enName = row["en_name"] as? String,
                           batch.contains(enName)
                        {
                            nameToTypeIdMap[enName] = typeId
                        }

                        // 检查zh_name匹配
                        if let zhName = row["zh_name"] as? String,
                           batch.contains(zhName)
                        {
                            nameToTypeIdMap[zhName] = typeId
                        }
                    }
                }
            }
        }

        // Logger.info("批量查询完成：输入\(itemNames.count)个物品名称，匹配到\(nameToTypeIdMap.count)个typeId")
        return nameToTypeIdMap
    }

    /// 数量物品解析结果
    private struct QuantityItemResult {
        let typeId: Int
        let itemName: String
        let quantity: Int
        let category: EquipmentCategory
    }

    /// 解析数量格式物品并根据分类决定归属
    private static func parseQuantityItemWithClassification(
        line: String,
        nameToTypeIdMap: [String: Int],
        classifications: [Int: EquipmentClassificationResult]
    ) throws -> QuantityItemResult? {
        // 使用正则表达式解析数量格式
        guard let parsed = parseQuantityLine(line: line) else {
            Logger.warning("数量物品行格式错误：\(line)")
            return nil
        }

        let itemName = parsed.itemName
        let quantity = parsed.quantity

        // 验证数量是否合理
        guard quantity > 0 else {
            Logger.warning("数量物品数量无效：\(quantity)")
            return nil
        }

        // 查找物品ID
        guard let typeId = nameToTypeIdMap[itemName] else {
            Logger.warning("未找到数量物品：\(itemName)")
            return nil
        }

        // 获取分类结果
        let category = classifications[typeId]?.category ?? .unknown

        return QuantityItemResult(
            typeId: typeId,
            itemName: itemName,
            quantity: quantity,
            category: category
        )
    }

    /// 基于分类器结果解析装备行，自动分配到正确的槽位
    private static func parseEquipmentLineWithClassification(
        line: String,
        slotCounters: inout SlotCounters,
        nameToTypeIdMap: [String: Int],
        classifications: [Int: EquipmentClassificationResult]
    ) throws -> LocalFittingItem? {
        // 分离装备名称和弹药名称
        let parts = line.components(separatedBy: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let moduleName = parts[0]
        let chargeName = parts.count > 1 ? parts[1] : nil

        // 查找装备ID
        guard let moduleTypeId = nameToTypeIdMap[moduleName] else {
            Logger.warning("未找到装备：\(moduleName)")
            return nil
        }

        // 根据分类结果确定槽位类型和flag
        guard let classification = classifications[moduleTypeId] else {
            Logger.warning("装备 \(moduleName) 未分类，跳过")
            return nil
        }

        let slotType: SlotType
        switch classification.category {
        case .lowSlot:
            slotType = .lowSlot
        case .medSlot:
            slotType = .medSlot
        case .hiSlot:
            slotType = .hiSlot
        case .rig:
            slotType = .rigSlot
        case .subsystem:
            slotType = .subSystemSlot
        default:
            Logger.warning("装备 \(moduleName) 的类型(\(classification.category))不是可安装的装备，跳过")
            return nil
        }

        // 根据分类确定的槽位类型获取flag
        let flag = getSlotFlag(slotType: slotType, slotCounters: &slotCounters)

        // 查找弹药ID（如果有）
        var chargeTypeId: Int? = nil
        if let chargeName = chargeName {
            if let chargeId = nameToTypeIdMap[chargeName] {
                // 验证是否为弹药
                if let chargeClassification = classifications[chargeId],
                   chargeClassification.category == .charge
                {
                    chargeTypeId = chargeId
                } else {
                    Logger.warning("物品 \(chargeName) 不是弹药类型，但仍作为弹药处理")
                    chargeTypeId = chargeId // 即使分类不匹配，也按EFT格式处理
                }
            } else {
                Logger.warning("未找到弹药：\(chargeName)")
            }
        }

        Logger.debug("装备 \(moduleName) 分类为 \(classification.category)，分配到 \(flag)")

        return LocalFittingItem(
            flag: flag,
            quantity: 1,
            type_id: moduleTypeId,
            status: 1, // 默认在线状态
            charge_type_id: chargeTypeId,
            charge_quantity: chargeTypeId != nil ? 1 : nil,
            muta: nil
        )
    }

    /// 解析无人机/舰载机行的结果
    private struct DroneOrFighterResult {
        let typeId: Int
        let quantity: Int
        let isFighter: Bool
    }
}
