import Foundation

/// 检查旗舰级装备限制
/// - Parameters:
///   - shipAttributes: 飞船的所有属性 [attribute_id: value]
///   - moduleVolume: 装备的体积
/// - Returns: 如果违反限制返回 false，否则返回 true
private func checkCapitalShipLimits(
    shipAttributes: [String: Double],
    moduleVolume: Double
) -> Bool {
    // 检查是否是旗舰级舰船
    let isCapitalShip = Int(shipAttributes["isCapitalSize"] ?? 0) == 1
    Logger.info("是否是旗舰级舰船: \(isCapitalShip)")

    // 检查是否是旗舰装备
    let isCapitalModule = moduleVolume >= 4000
    Logger.info("是否是旗舰装备: \(moduleVolume) -> \(isCapitalModule)")

    // 检查非旗舰飞船上安装旗舰装备的情况
    if !isCapitalShip && isCapitalModule {
        Logger.fault("非旗舰飞船上不能安装旗舰装备")
        return false
    }

    return true
}

/// 检查炮台和发射器数量是否超过限制
/// - Parameters:
///   - shipAttributes: 飞船的所有属性 [attribute_id: value]
///   - itemEffects: 装备的所有效果 [effect_id]
///   - currentModules: 当前安装的模块列表
///   - turretSlotsNum: 飞船炮台槽位数量
///   - launcherSlotsNum: 飞船发射器槽位数量
/// - Returns: 如果超过限制返回 false，否则返回 true
private func checkTurretAndLauncherLimits(
    shipAttributes: [String: Double],
    itemEffects: [Int],
    currentModules: [SimModule],
    turretSlotsNum: Int,
    launcherSlotsNum: Int
) -> Bool {
    // 使用模拟数据中的炮台和发射器槽位数量限制
    let maxTurrets = turretSlotsNum
    let maxLaunchers = launcherSlotsNum
    Logger.info("飞船炮台槽位数量限制: \(maxTurrets)")
    Logger.info("飞船发射器槽位数量限制: \(maxLaunchers)")

    // 统计当前已安装的炮台和发射器数量
    var currentTurrets = 0
    var currentLaunchers = 0

    // 遍历所有槽位中的装备
    for module in currentModules {
        // 检查装备效果
        let moduleEffects = module.effects
        // 如果是炮台
        if moduleEffects.contains(42) {
            currentTurrets += 1
        }
        // 如果是发射器
        if moduleEffects.contains(40) {
            currentLaunchers += 1
        }
    }

    Logger.info("当前已安装炮台数量: \(currentTurrets)")
    Logger.info("当前已安装发射器数量: \(currentLaunchers)")

    // 检查新装备是否是炮台或发射器
    let isTurret = itemEffects.contains(42)
    let isLauncher = itemEffects.contains(40)

    Logger.info("新装备是否是炮台: \(isTurret)")
    Logger.info("新装备是否是发射器: \(isLauncher)")

    // 如果是炮台，检查是否超过限制
    if isTurret && currentTurrets >= maxTurrets {
        Logger.fault("炮台数量已达到飞船限制 (\(currentTurrets)/\(maxTurrets))")
        return false
    }

    // 如果是发射器，检查是否超过限制
    if isLauncher && currentLaunchers >= maxLaunchers {
        Logger.fault("发射器数量已达到飞船限制 (\(currentLaunchers)/\(maxLaunchers))")
        return false
    }

    return true
}

/// 检查是否有子系统重复
/// - Parameters:
///   - itemAttributes: 装备的所有属性 [attribute_id: value]
///   - currentModules: 当前安装的模块列表
/// - Returns: 如果与现有子系统装备1366属性值相同返回 false，否则返回 true
private func duplicateSubSysCheck(
    itemAttributesName: [String: Double],
    currentModules: [SimModule]
) -> Bool {
    // 检查当前装备是否有1366属性
    guard let currentValue = itemAttributesName["subSystemSlot"] else {
        // 如果没有1366属性，不需要检查
        Logger.info("不是子系统，无需检查重复性")
        return true
    }

    Logger.info("是子系统，值为: \(currentValue)")

    // 遍历所有已安装的装备，检查是否有相同1366属性值的装备
    for module in currentModules {
        // 获取已安装装备的1366属性
        if let existingValue = module.attributesByName["subSystemSlot"] {
            Logger.info(
                "发现已安装的子系统，槽位类型: \(module.flag?.rawValue ?? "未知"), 属性值: \(existingValue)"
            )

            // 如果1366属性值相同，则不允许安装
            if existingValue == currentValue {
                Logger.fault("子系统1366属性值 \(currentValue) 与已安装子系统重复，不允许安装")
                return false
            }
        }
    }

    // 如果没有找到相同1366属性值的装备，允许安装
    Logger.info("子系统1366属性值不与任何已安装子系统重复，允许安装")
    return true
}

/// 检查飞船是否可以安装特定的子系统装备
/// - Parameters:
///   - shipTypeID: 飞船的type_id
///   - itemAttributes: 装备的所有属性 [attribute_id: value]
///   - itemEffects: 装备的所有效果 [effect_id]
///   - currentModules: 当前安装的模块列表
/// - Returns: 如果飞船可以安装该子系统返回 true，否则返回 false
private func checkSubsystemCompatibility(
    shipTypeID: Int,
    itemAttributes: [Int: Double],
    itemAttributesName: [String: Double],
    itemEffects: [Int],
    currentModules: [SimModule]
) -> Bool {
    // 检查装备是否是子系统
    let isSubsystem = itemEffects.contains(3772)
    if !isSubsystem {
        // 如果不是子系统，则无需检查
        Logger.info("装备不是子系统，无需检查兼容性")
        return true
    }

    Logger.info("装备是子系统，检查与飞船兼容性")

    // 确保飞船type_id有效
    if shipTypeID <= 0 {
        Logger.fault("无效的飞船type_id: \(shipTypeID)")
        return false
    }

    // 子系统通常有属性1380，表示适用的飞船type_id
    if let subsystemShipTypeID = itemAttributesName["fitsToShipType"] {
        let compatibleShipTypeID = Int(subsystemShipTypeID)
        Logger.info("子系统适用的飞船type_id: \(compatibleShipTypeID), 当前飞船type_id: \(shipTypeID)")

        // 检查飞船type_id是否匹配
        if compatibleShipTypeID == shipTypeID {
            Logger.info("子系统与飞船兼容")
            /// 检查子系统重复
            if !duplicateSubSysCheck(
                itemAttributesName: itemAttributesName,
                currentModules: currentModules
            ) {
                return false
            }
            return true
        } else {
            Logger.fault("子系统不适用于当前飞船")
            return false
        }
    } else {
        // 如果子系统没有1380属性，则无法确定兼容性
        Logger.fault("子系统没有适用飞船type_id属性(1380)")
        return false
    }
}

/// 获取装备装配限制属性
/// - Parameters:
///   - databaseManager: 数据库管理器实例
/// - Returns: (shipGroupAttributes: [Int], shipTypeAttributes: [Int]) 返回飞船组和飞船类型的属性ID数组
private func getCanFitAttributes(databaseManager: DatabaseManager) -> (shipGroupAttributes: [Int], shipTypeAttributes: [Int]) {
    var shipGroupAttributes: [Int] = []
    var shipTypeAttributes: [Int] = []

    let sql = """
            SELECT attribute_id, name, unitName 
            FROM dogmaAttributes 
            WHERE (name LIKE 'canFitShipType%' OR name LIKE 'canFitShipGroup%') 
            AND unitName IN ('groupID', 'typeID')
        """

    if case let .success(rows) = databaseManager.executeQuery(sql) {
        for row in rows {
            if let attrId = row["attribute_id"] as? Int,
                let unitName = row["unitName"] as? String
            {
                if unitName == "groupID" {
                    shipGroupAttributes.append(attrId)
                } else if unitName == "typeID" {
                    shipTypeAttributes.append(attrId)
                }
            }
        }
    }

    return (shipGroupAttributes, shipTypeAttributes)
}

/// 检查装备是否可以装配到指定类型的飞船上
/// - Parameters:
///   - shipTypeID: 飞船的type_id
///   - shipGroupID: 飞船的group_id
///   - itemAttributes: 装备的所有属性 [attribute_id: value]
///   - databaseManager: 数据库管理器实例
/// - Returns: 如果可以装配返回 true，否则返回 false
private func checkCanFitTo(
    shipTypeID: Int,
    shipGroupID: Int,
    itemAttributes: [Int: Double],
    databaseManager: DatabaseManager
) -> Bool {
    let (shipGroupAttributes, shipTypeAttributes) = getCanFitAttributes(databaseManager: databaseManager)
    Logger.info("shipTypeID: \(shipTypeID)")
    Logger.info("shipGroupID: \(shipGroupID)")
    
    // 检查飞船组限制
    for groupAttrID in shipGroupAttributes {
        if let groupValue = itemAttributes[groupAttrID] {
            let allowedGroupID = Int(groupValue)
            if allowedGroupID == shipGroupID {
                Logger.info("装备可以装配到飞船组 \(shipGroupID)")
                return true
            }
        }
    }

    // 检查飞船类型限制
    for typeAttrID in shipTypeAttributes {
        if let typeValue = itemAttributes[typeAttrID] {
            let allowedTypeID = Int(typeValue)
            if allowedTypeID == shipTypeID {
                Logger.info("装备可以装配到飞船类型 \(shipTypeID)")
                return true
            }
        }
    }

    // 如果没有找到任何匹配的限制，检查是否有任何限制属性
    let allRestrictionAttributes = shipGroupAttributes + shipTypeAttributes
    let hasAnyRestriction = allRestrictionAttributes.contains { itemAttributes[$0] != nil }

    if hasAnyRestriction {
        Logger.fault("装备有装配限制，但不适用于当前飞船")
        return false
    }

    // 如果没有找到任何限制属性，则默认允许装配
    Logger.info("装备没有特定的装配限制")
    return true
}

/// 检查装备是否达到最大安装数量限制
/// - Parameters:
///   - itemAttributes: 装备的所有属性 [attribute_id: value]
///   - currentModules: 当前安装的模块列表
///   - typeId: 要安装的装备的 type_id
///   - groupID: 要安装的装备的 group_id
/// - Returns: 如果未达到限制返回 true，否则返回 false
private func maxFit(
    itemAttributes: [Int: Double],
    itemAttributesName: [String: Double],
    currentModules: [SimModule],
    typeId: Int,
    groupID: Int
) -> Bool {
    // 检查装备是否有最大安装数量限制（属性1544）
    guard let maxFitValue = itemAttributesName["maxGroupFitted"] else {
        // 如果没有限制，则允许安装
        return true
    }

    // 计算当前已安装的同组装备数量
    var currentGroupCount = 0

    // 遍历所有槽位中的装备
    for module in currentModules {
        // 检查同组装备数量
        if module.groupID == groupID {
            currentGroupCount += 1
        }
    }

    // 检查是否达到限制
    let canFit = currentGroupCount < Int(maxFitValue)

    if !canFit {
        Logger.fault("同组装备已达到最大安装数量限制: 当前数量=\(currentGroupCount), 最大限制=\(Int(maxFitValue))")
    }

    return canFit
}

/// 检查装备是否可以安装
/// - Parameters:
///   - simulationInput: 模拟器输入数据
///   - itemAttributes: 装备的所有属性
///   - itemEffects: 装备的所有效果
///   - volume: 装备的体积
///   - typeId: 装备的 type_id
///   - itemGroupID: 装备的 group_id
///   - databaseManager: 数据库管理器
///   - turretSlotsNum: 飞船炮台槽位数量
///   - launcherSlotsNum: 飞船发射器槽位数量
/// - Returns: 是否可以安装
func canFit(
    simulationInput: SimulationInput,
    itemAttributes: [Int: Double],
    itemAttributesName: [String: Double],
    itemEffects: [Int],
    volume: Double,
    typeId: Int,
    itemGroupID: Int,
    databaseManager: DatabaseManager,
    turretSlotsNum: Int,
    launcherSlotsNum: Int
) -> Bool {
    let shipTypeID = simulationInput.ship.typeId
    let shipGroupID = simulationInput.ship.groupID
    let shipAttributes = simulationInput.ship.baseAttributesByName
    let currentModules = simulationInput.modules
    
    Logger.info("飞船type_id: \(shipTypeID)")
    Logger.info("飞船group_id: \(shipGroupID)")
    /// 检查装备是否可以装配到指定类型的飞船上
    if !checkCanFitTo(
        shipTypeID: shipTypeID,
        shipGroupID: shipGroupID,
        itemAttributes: itemAttributes,
        databaseManager: databaseManager
    ) {
        return false
    }

    /// 检查最大安装数量限制
    if !maxFit(
        itemAttributes: itemAttributes,
        itemAttributesName: itemAttributesName,
        currentModules: currentModules,
        typeId: typeId,
        groupID: itemGroupID
    ) {
        return false
    }

    /// 检查子系统兼容性
    if !checkSubsystemCompatibility(
        shipTypeID: shipTypeID,
        itemAttributes: itemAttributes,
        itemAttributesName: itemAttributesName,
        itemEffects: itemEffects,
        currentModules: currentModules
    ) {
        return false
    }

    /// 旗舰装备检查
    if !checkCapitalShipLimits(
        shipAttributes: shipAttributes,
        moduleVolume: volume
    ) {
        return false
    }

    /// 检查炮台和发射器数量
    if !checkTurretAndLauncherLimits(
        shipAttributes: shipAttributes,
        itemEffects: itemEffects,
        currentModules: currentModules,
        turretSlotsNum: turretSlotsNum,
        launcherSlotsNum: launcherSlotsNum
    ) {
        return false
    }

    /// 无特殊情况，允许安装
    return true
} 
