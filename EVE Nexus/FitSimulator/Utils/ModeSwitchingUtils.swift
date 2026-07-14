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
    private static func initializeCache(databaseManager: DatabaseManager) {
        // 如果已经初始化过，直接返回
        if shipNameToModesCache != nil {
            return
        }

        // 1. 检索所有模式装备（groupID = 1306）
        let modeQuery = """
            SELECT type_id, name, en_name, icon_filename
            FROM types
            WHERE groupID = 1306
            ORDER BY name
        """

        guard case let .success(modeRows) = databaseManager.executeQuery(modeQuery) else {
            shipNameToModesCache = [:]
            return
        }

        // 2. 从模式装备名称中提取可能的飞船名称（第一个单词）
        var shipNameToModes: [String: [(typeId: Int, name: String, iconFileName: String)]] = [:]

        for modeRow in modeRows {
            guard let modeTypeId = modeRow["type_id"] as? Int,
                  let modeName = modeRow["name"] as? String,
                  let modeEnName = modeRow["en_name"] as? String,
                  let iconFileName = modeRow["icon_filename"] as? String
            else {
                continue
            }

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
                iconFileName: iconFileName.isEmpty ? "not_found" : iconFileName
            ))
        }

        // 3. 验证这些飞船名称是否对应真实的飞船（categoryID = 6）
        // 获取所有可能的飞船名称
        let possibleShipNames = Array(shipNameToModes.keys)
        guard !possibleShipNames.isEmpty else {
            shipNameToModesCache = [:]
            return
        }

        // 批量查询这些名称对应的飞船
        // 使用 IN 子句批量查询
        let placeholders = possibleShipNames.map { _ in "?" }.joined(separator: ",")
        let shipQuery = """
            SELECT type_id, en_name
            FROM types
            WHERE categoryID = 6
              AND en_name IN (\(placeholders))
        """

        guard case let .success(shipRows) = databaseManager.executeQuery(
            shipQuery, parameters: possibleShipNames
        ) else {
            shipNameToModesCache = [:]
            return
        }

        // 4. 建立有效的映射关系（只保留真实存在的飞船）
        var validShipNameToModes: [String: [(typeId: Int, name: String, iconFileName: String)]] = [:]

        for shipRow in shipRows {
            guard let shipTypeId = shipRow["type_id"] as? Int,
                  let shipEnName = shipRow["en_name"] as? String
            else {
                continue
            }

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
