import Foundation

/// 模式切换工具类
/// 用于检测飞船是否支持模式切换，以及查找对应的模式装备
enum ModeSwitchingUtils {
    /// 缓存：飞船名称 -> 模式装备列表的映射
    private static var shipNameToModesCache: [String: [(typeId: Int, name: String, iconFileName: String)]]?
    /// 缓存：飞船类型ID -> 飞船名称的映射
    private static var shipIdToNameCache: [Int: String] = [:]

    /// 初始化模式装备映射缓存
    /// - Parameter databaseManager: 数据库管理器
    private static func initializeCache(databaseManager _: DatabaseManager) {
        // 如果已经初始化过，直接返回
        if shipNameToModesCache != nil {
            return
        }

        // 1. 内存索引检索所有模式装备（groupID = 1306）
        var shipNameToModes: [String: [(typeId: Int, name: String, iconFileName: String)]] = [:]
        for (modeTypeId, info) in SDEMemoryStore.types where info.groupID == 1306 {
            let modeName = info.name
            let modeEnName = info.enName
            let iconFileName = info.iconFilename

            // 按空格切分，取第一个单词作为可能的飞船名称
            let components = modeEnName.components(separatedBy: " ")
            guard let shipName = components.first, !shipName.isEmpty else {
                continue
            }

            // 将模式装备添加到对应飞船名称的列表中
            if shipNameToModes[shipName] == nil {
                shipNameToModes[shipName] = []
            }
            shipNameToModes[shipName]?.append((
                typeId: modeTypeId,
                name: modeName,
                iconFileName: iconFileName
            ))
        }

        // 2. 验证这些飞船名称是否对应真实的飞船（categoryID = 6，内存索引）
        let possibleShipNames = Set(shipNameToModes.keys)
        guard !possibleShipNames.isEmpty else {
            shipNameToModesCache = [:]
            return
        }

        var validShipNameToModes: [String: [(typeId: Int, name: String, iconFileName: String)]] = [:]
        for (shipTypeId, info) in SDEMemoryStore.types
            where info.categoryID == 6 && possibleShipNames.contains(info.enName)
        {
            let shipEnName = info.enName

            // 缓存飞船ID到名称的映射
            shipIdToNameCache[shipTypeId] = shipEnName

            // 如果这个飞船名称有对应的模式装备，添加到有效映射中
            if let modes = shipNameToModes[shipEnName] {
                validShipNameToModes[shipEnName] = modes
            }
        }

        shipNameToModesCache = validShipNameToModes
        Logger.info("模式切换缓存初始化完成，找到 \(validShipNameToModes.count) 个支持模式切换的飞船")
    }

    /// 获取飞船的英文名称（带缓存）
    private static func getShipEnName(
        shipTypeId: Int,
        databaseManager _: DatabaseManager
    ) -> String? {
        // 先查缓存
        if let cachedName = shipIdToNameCache[shipTypeId] {
            return cachedName
        }

        // 缓存未命中，查询内存索引
        guard let shipEnName = ItemInfoMap.typeInfo(for: shipTypeId)?.enName, !shipEnName.isEmpty else {
            return nil
        }

        // 更新缓存
        shipIdToNameCache[shipTypeId] = shipEnName
        return shipEnName
    }

    /// 检查飞船是否支持模式切换
    /// - Parameters:
    ///   - shipTypeId: 飞船类型ID
    ///   - databaseManager: 数据库管理器
    /// - Returns: 如果飞船支持模式切换返回true，否则返回false
    static func isModeSwitchingShip(shipTypeId: Int, databaseManager: DatabaseManager) -> Bool {
        // 初始化缓存
        initializeCache(databaseManager: databaseManager)

        // 获取飞船的英文名称
        guard let shipEnName = getShipEnName(
            shipTypeId: shipTypeId,
            databaseManager: databaseManager
        ) else {
            return false
        }

        // 检查缓存中是否有该飞船的模式装备
        return shipNameToModesCache?[shipEnName] != nil
    }

    /// 获取飞船的所有模式选项
    /// - Parameters:
    ///   - shipTypeId: 飞船类型ID
    ///   - databaseManager: 数据库管理器
    /// - Returns: 模式信息数组，包含 typeId, name, iconFileName
    static func getModeOptions(
        for shipTypeId: Int,
        databaseManager: DatabaseManager
    ) -> [(typeId: Int, name: String, iconFileName: String)] {
        // 初始化缓存
        initializeCache(databaseManager: databaseManager)

        // 获取飞船的英文名称
        guard let shipEnName = getShipEnName(
            shipTypeId: shipTypeId,
            databaseManager: databaseManager
        ) else {
            return []
        }

        // 从缓存中获取模式选项
        return shipNameToModesCache?[shipEnName] ?? []
    }

    /// 获取飞船的默认模式ID
    /// - Parameters:
    ///   - shipTypeId: 飞船类型ID
    ///   - databaseManager: 数据库管理器
    /// - Returns: 默认模式类型ID，如果找不到则返回nil
    static func getDefaultModeId(
        for shipTypeId: Int,
        databaseManager: DatabaseManager
    ) -> Int? {
        let modes = getModeOptions(for: shipTypeId, databaseManager: databaseManager)
        // 返回第一个模式作为默认模式
        return modes.first?.typeId
    }
}
