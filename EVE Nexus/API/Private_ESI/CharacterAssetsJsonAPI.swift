import Foundation

// MARK: - Data Models

public struct CharacterAsset: Codable {
    let is_singleton: Bool
    let item_id: Int64
    let location_id: Int64
    let location_flag: String
    let location_type: String
    let quantity: Int
    let type_id: Int
    let is_blueprint_copy: Bool?
}

// 资产树包装结构
public struct AssetTreeWrapper: Codable {
    let update_time: Int64
    let assetsTree: [AssetTreeNode]
}

// 空间站信息
private struct StationInfo: Codable {
    let name: String
    let station_id: Int64
    let system_id: Int
    let type_id: Int
    let region_id: Int
    let security: Double
}

// 资产名称响应
private struct AssetNameResponse: Codable {
    let item_id: Int64
    let name: String
}

// 用于展示的资产树结构
public struct AssetTreeNode: Codable {
    let location_id: Int64
    let item_id: Int64
    let type_id: Int
    let location_type: String
    let location_flag: String
    let quantity: Int
    var name: String?
    let icon_name: String?
    let is_singleton: Bool
    let is_blueprint_copy: Bool?
    let system_id: Int?  // 星系ID
    let region_id: Int?  // 星域ID
    let security_status: Double?  // 星系安全等级
    var items: [AssetTreeNode]?
}

// 多语言系统信息
private struct SysInfo {
    let regionId: Int  // 星域ID
    let security: Double  // 安全等级
}

// MARK: - Error Types

public enum AssetError: Error {
    case invalidURL
    case locationFetchError(String)
    case invalidData(String)
}

// MARK: - Progress Types

public enum AssetLoadingProgress {
    case loading(page: Int)  // 正在加载特定页面
    case buildingTree  // 正在构建资产树
    case processingLocations  // 正在处理位置信息
    case fetchingStructureInfo(current: Int, total: Int)  // 正在获取建筑详情
    case preparingContainers  // 正在准备容器信息
    case loadingNames(current: Int, total: Int)  // 正在加载容器名称
    case savingCache  // 正在保存缓存
    case completed  // 加载完成
}

public class CharacterAssetsJsonAPI {
    public static let shared = CharacterAssetsJsonAPI()
    private let cacheTimeout: TimeInterval = 24 * 3600  // 24 小时缓存

    private init() {}

    // MARK: - Public Methods

    public func generateAssetTreeJson(
        characterId: Int,
        forceRefresh: Bool = false,
        progressCallback: ((AssetLoadingProgress) -> Void)? = nil
    ) async throws -> String? {
        // 1. 检查缓存
        if !forceRefresh {
            if let cacheFile = getCacheFilePath(characterId: characterId),
                let jsonString = try? String(contentsOf: cacheFile, encoding: .utf8),
                let data = jsonString.data(using: .utf8),
                let wrapper = try? JSONDecoder().decode(AssetTreeWrapper.self, from: data)
            {
                // 检查缓存是否过期
                let cacheDate = Date(timeIntervalSince1970: TimeInterval(wrapper.update_time))
                let isExpired = Date().timeIntervalSince(cacheDate) >= cacheTimeout

                if !isExpired {
                    let remainingTime = cacheTimeout - Date().timeIntervalSince(cacheDate)
                    let remainingHours = Int(remainingTime / 3600)
                    let remainingMinutes = Int(
                        (remainingTime.truncatingRemainder(dividingBy: 3600)) / 60)
                    Logger.info(
                        "使用有效的缓存数据 - 剩余有效期: \(remainingHours)小时\(remainingMinutes)分钟 - 文件: \(cacheFile.path)"
                    )
                    return jsonString
                }
            }
        }

        // 2. 如果没有缓存、缓存过期或强制刷新，获取新数据
        Logger.info("开始获取新的资产数据 - 原因: \(forceRefresh ? "强制刷新" : "无缓存或缓存过期")")
        let assets = try await fetchAllAssets(characterId: characterId) { progress in
            progressCallback?(progress)
        }

        if let jsonString = try await buildAssetTreeJson(
            assets: assets,
            names: [:],
            characterId: characterId,
            databaseManager: DatabaseManager(),
            progressCallback: progressCallback
        ) {
            // 保存到缓存
            saveToCache(jsonString: jsonString, characterId: characterId)
            // 通知进度完成
            progressCallback?(.completed)
            return jsonString
        }

        progressCallback?(.completed)
        return nil
    }

    // MARK: - Cache Methods

    private func getCacheFilePath(characterId: Int, timestamp _: Date? = nil) -> URL? {
        guard
            let documentsDirectory = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask
            ).first
        else {
            return nil
        }
        let cacheDirectory = documentsDirectory.appendingPathComponent(
            "AssetCache", isDirectory: true
        )

        // 确保缓存目录存在
        try? FileManager.default.createDirectory(
            at: cacheDirectory, withIntermediateDirectories: true
        )

        // 简化文件名，不再包含时间戳
        return cacheDirectory.appendingPathComponent("asset_tree_\(characterId).json")
    }

    private func saveToCache(jsonString: String, characterId: Int) {
        guard let cacheFile = getCacheFilePath(characterId: characterId),
            let data = jsonString.data(using: .utf8)
        else {
            return
        }

        do {
            try data.write(to: cacheFile)
            Logger.debug("资产树JSON已缓存到文件: \(cacheFile.path)")
        } catch {
            Logger.error("保存资产树缓存失败: \(error)")
        }
    }

    // 获取所有资产
    private func fetchAllAssets(
        characterId: Int,
        forceRefresh _: Bool = false,
        progressCallback: ((AssetLoadingProgress) -> Void)? = nil
    ) async throws -> [CharacterAsset] {
        let baseUrlString =
            "https://esi.evetech.net/characters/\(characterId)/assets/?datasource=tranquility"
        guard let baseUrl = URL(string: baseUrlString) else {
            throw AssetError.invalidURL
        }

        return try await NetworkManager.shared.fetchPaginatedData(
            from: baseUrl,
            characterId: characterId,
            maxConcurrentPages: 3,
            decoder: { try JSONDecoder().decode([CharacterAsset].self, from: $0) },
            progressCallback: { currentPage, totalPages in
                progressCallback?(.loading(page: currentPage))
            }
        )
    }

    // 获取空间站信息
    private func fetchStationInfo(stationId: Int64, databaseManager: DatabaseManager) async throws
        -> StationInfo
    {
        let query = """
                SELECT stationID, stationTypeID, stationName, regionID, solarSystemID, security
                FROM stations
                WHERE stationID = ?
            """

        // 将 stationId 转换为字符串
        let stationIdStr = String(stationId)
        let result = databaseManager.executeQuery(query, parameters: [stationIdStr])

        switch result {
        case let .success(rows):
            guard let row = rows.first,
                let stationName = row["stationName"] as? String,
                let stationTypeID = row["stationTypeID"] as? Int,
                let solarSystemID = row["solarSystemID"] as? Int,
                let regionID = row["regionID"] as? Int,
                let security = row["security"] as? Double
            else {
                throw AssetError.locationFetchError("Failed to fetch station info from database")
            }

            return StationInfo(
                name: stationName,
                station_id: stationId,
                system_id: solarSystemID,
                type_id: stationTypeID,
                region_id: regionID,
                security: security
            )

        case let .error(error):
            Logger.error("从数据库获取空间站信息失败: \(error)")
            throw AssetError.locationFetchError("Failed to fetch station info: \(error)")
        }
    }

    // 获取空间站图标
    private func getStationIcon(typeId: Int, databaseManager: DatabaseManager) -> (
        normal: String, blueprint_copy: String
    )? {
        let query = "SELECT icon_filename, bpc_icon_filename FROM types WHERE type_id = ?"
        if case let .success(rows) = databaseManager.executeQuery(query, parameters: [typeId]),
            let row = rows.first,
            let iconFile = row["icon_filename"] as? String
        {
            let normalIcon = iconFile.isEmpty ? DatabaseConfig.defaultItemIcon : iconFile
            var bpcIcon = normalIcon

            // 如果有蓝图复制品图标则使用
            if let bpcIconFile = row["bpc_icon_filename"] as? String, !bpcIconFile.isEmpty {
                bpcIcon = bpcIconFile
            }

            return (normal: normalIcon, blueprint_copy: bpcIcon)
        }
        return (
            normal: DatabaseConfig.defaultItemIcon, blueprint_copy: DatabaseConfig.defaultItemIcon
        )
    }

    // 收集所有容器的ID (除了最顶层建筑物)
    private func collectContainerIds(from nodes: [AssetTreeNode]) -> Set<Int64> {
        var containerIds = Set<Int64>()

        func collect(from node: AssetTreeNode, isRoot: Bool = false) {
            // 如果不是根节点且有子项，则这是一个容器
            if !isRoot && node.items != nil && !node.items!.isEmpty {
                containerIds.insert(node.item_id)
            }

            // 递归处理子节点
            if let items = node.items {
                for item in items {
                    collect(from: item)
                }
            }
        }

        // 从根节点开始收集，但标记为根节点以跳过它们
        for node in nodes {
            collect(from: node, isRoot: true)
        }

        return containerIds
    }

    // 获取容器名称
    private func fetchContainerNames(containerIds: [Int64], characterId: Int) async throws
        -> [Int64: String]
    {
        guard !containerIds.isEmpty else { return [:] }

        let urlString = "https://esi.evetech.net/characters/\(characterId)/assets/names/"
        guard let url = URL(string: urlString) else {
            throw AssetError.invalidURL
        }

        let headers = [
            "Accept": "application/json",
            "Content-Type": "application/json",
        ]

        // 将ID列表转换为JSON数据
        guard let jsonData = try? JSONEncoder().encode(containerIds) else {
            throw AssetError.invalidData("Failed to encode container IDs")
        }

        do {
            let data = try await NetworkManager.shared.postDataWithToken(
                to: url,
                body: jsonData,
                characterId: characterId,
                headers: headers
            )

            let nameResponses = try JSONDecoder().decode([AssetNameResponse].self, from: data)

            // 转换为字典
            var namesDict: [Int64: String] = [:]
            for response in nameResponses {
                namesDict[response.item_id] = response.name
            }

            return namesDict
        } catch {
            Logger.error("获取容器名称失败: \(error)")
            throw error
        }
    }

    // 递归构建树节点的辅助函数
    private func buildTreeNode(
        from asset: CharacterAsset,
        locationMap: [Int64: [CharacterAsset]],
        names: [Int64: String],
        databaseManager: DatabaseManager,
        iconMap: [Int: (normal: String, blueprint_copy: String)]
    ) -> AssetTreeNode {
        // 从图标映射中获取图标名称，根据是否为蓝图复制品选择图标
        let defaultIcon = DatabaseConfig.defaultItemIcon
        let iconInfo = iconMap[asset.type_id] ?? (normal: defaultIcon, blueprint_copy: defaultIcon)
        let iconName: String

        if let isBlueprintCopy = asset.is_blueprint_copy, isBlueprintCopy {
            // 如果是蓝图复制品，使用BPC图标
            iconName = iconInfo.blueprint_copy
        } else {
            // 否则使用普通图标
            iconName = iconInfo.normal
        }

        // 获取子项
        let children = locationMap[asset.item_id, default: []].map { childAsset in
            buildTreeNode(
                from: childAsset,
                locationMap: locationMap,
                names: names,
                databaseManager: databaseManager,
                iconMap: iconMap
            )
        }

        // 处理名称 - 对于玩家自定义名称的容器，保留名称
        // 对于系统位置（如空间站内部的仓库等），不需要特殊处理，因为它们没有自己的名称
        let nodeName: String? = names[asset.item_id]

        return AssetTreeNode(
            location_id: asset.location_id,
            item_id: asset.item_id,
            type_id: asset.type_id,
            location_type: asset.location_type,
            location_flag: asset.location_flag,
            quantity: asset.quantity,
            name: nodeName,
            icon_name: iconName,
            is_singleton: asset.is_singleton,
            is_blueprint_copy: asset.is_blueprint_copy,
            system_id: nil,  // 子节点不需要系统和区域信息
            region_id: nil,
            security_status: nil,
            items: children.isEmpty ? nil : children
        )
    }

    // 获取所有物品的图标信息
    private func fetchAllItemIcons(typeIds: Set<Int>, databaseManager: DatabaseManager) -> [Int: (
        normal: String, blueprint_copy: String
    )] {
        // 构建查询语句，仅获取图标相关信息
        let query = """
                SELECT type_id, icon_filename, bpc_icon_filename
                FROM types
                WHERE type_id IN (\(typeIds.sorted().map { String($0) }.joined(separator: ",")))
            """

        var iconMap: [Int: (normal: String, blueprint_copy: String)] = [:]

        if case let .success(rows) = databaseManager.executeQuery(query) {
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                    let iconFilename = row["icon_filename"] as? String
                {
                    let normalIcon =
                        iconFilename.isEmpty ? DatabaseConfig.defaultItemIcon : iconFilename

                    // 获取蓝图复制品图标，如果没有则使用普通图标
                    var bpcIcon = normalIcon
                    if let bpcIconFilename = row["bpc_icon_filename"] as? String,
                        !bpcIconFilename.isEmpty
                    {
                        bpcIcon = bpcIconFilename
                    }

                    // 保存到图标映射
                    iconMap[typeId] = (normal: normalIcon, blueprint_copy: bpcIcon)
                }
            }
        }

        return iconMap
    }

    private func buildAssetTreeJson(
        assets: [CharacterAsset],
        names: [Int64: String],
        characterId: Int,
        databaseManager: DatabaseManager,
        progressCallback: ((AssetLoadingProgress) -> Void)? = nil
    ) async throws -> String? {
        progressCallback?(.buildingTree)

        // 建立 location_id 到资产列表的映射
        var locationMap: [Int64: [CharacterAsset]] = [:]

        // 构建映射关系并收集所有资产的 type_id
        var allTypeIds = Set<Int>()
        for asset in assets {
            locationMap[asset.location_id, default: []].append(asset)
            allTypeIds.insert(asset.type_id)
        }

        // 找出顶层位置（空间站和建筑物）
        var topLocations: Set<Int64> = Set(assets.map { $0.location_id })
        for asset in assets {
            topLocations.remove(asset.item_id)
        }

        // 添加进度回调 - 处理位置信息
        progressCallback?(.processingLocations)

        // 获取建筑物的 type_id
        let totalLocations = topLocations.count
        var processedLocations = 0
        for locationId in topLocations {
            if let items = locationMap[locationId] {
                let locationType =
                    items.first?.location_type ?? NSLocalizedString("Unknown", comment: "")

                // 更新进度 - 获取位置详情
                processedLocations += 1
                progressCallback?(
                    .fetchingStructureInfo(current: processedLocations, total: totalLocations))

                let info = try await fetchLocationInfo(
                    locationId: locationId,
                    locationType: locationType,
                    characterId: characterId,
                    databaseManager: databaseManager
                )
                if let typeId = info.typeId {
                    allTypeIds.insert(typeId)
                }
            }
        }

        // 一次性获取所有物品的图标信息（包括建筑物）
        let iconMap = fetchAllItemIcons(typeIds: allTypeIds, databaseManager: databaseManager)

        // 创建初始的根节点
        var rootNodes = try await createInitialRootNodes(
            topLocations: topLocations,
            locationMap: locationMap,
            characterId: characterId,
            databaseManager: databaseManager,
            names: names,
            iconMap: iconMap
        )

        // 添加进度回调 - 准备容器信息
        progressCallback?(.preparingContainers)

        // 收集所有容器的ID
        let containerIds = collectContainerIds(from: rootNodes)

        // 获取容器名称
        var allNames = names
        if !containerIds.isEmpty {
            progressCallback?(.loadingNames(current: 0, total: containerIds.count))
            let containerNames = try await fetchContainerNames(
                containerIds: Array(containerIds),
                characterId: characterId
            )
            for (id, name) in containerNames {
                allNames[id] = name
            }
        }

        // 使用更新后的名称重新构建树
        rootNodes = try await createInitialRootNodes(
            topLocations: topLocations,
            locationMap: locationMap,
            characterId: characterId,
            databaseManager: databaseManager,
            names: allNames,
            iconMap: iconMap
        )

        // 创建包装对象
        let wrapper = AssetTreeWrapper(
            update_time: Int64(Date().timeIntervalSince1970),
            assetsTree: rootNodes
        )

        // 转换为JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            progressCallback?(.savingCache)
            let jsonData = try encoder.encode(wrapper)
            return String(data: jsonData, encoding: .utf8)
        } catch {
            Logger.error("生成资产树JSON失败: \(error)")
            return nil
        }
    }

    // 获取多语言星系信息
    private func fetchSystemInfo(solarSystemId: Int, databaseManager: DatabaseManager) async
        -> SysInfo?
    {
        // 构建查询语句获取星系信息和区域信息
        let query = """
                SELECT region_id, system_security from universe where solarsystem_id = ?
            """

        if case let .success(rows) = databaseManager.executeQuery(
            query, parameters: [solarSystemId]
        ) {
            if let row = rows.first,
                let security = row["system_security"] as? Double,
                let region_id = row["region_id"] as? Int
            {
                return SysInfo(
                    regionId: region_id,
                    security: security
                )
            }
        }
        return nil
    }

    // 获取位置信息的辅助方法
    private func fetchLocationInfo(
        locationId: Int64,
        locationType: String,
        characterId: Int,
        databaseManager: DatabaseManager
    ) async throws -> (
        name: String?, typeId: Int?, systemId: Int?, securityStatus: Double?, regionId: Int?
    ) {
        var locationName: String?
        var typeId: Int?
        var systemId: Int?
        var securityStatus: Double?
        var regionId: Int?

        // 处理太空中的物资（solar_system类型）
        if locationType == "solar_system" {
            // 此时locationId就是星系ID
            systemId = Int(locationId)
            if let systemInfo = await fetchSystemInfo(
                solarSystemId: Int(locationId), databaseManager: databaseManager
            ) {
                securityStatus = systemInfo.security
                regionId = systemInfo.regionId
            }
            return (locationName, typeId, systemId, securityStatus, regionId)
        }

        if locationType == "station" {
            if let stationInfo = try? await fetchStationInfo(
                stationId: locationId, databaseManager: databaseManager
            ) {
                locationName = stationInfo.name
                typeId = stationInfo.type_id
                systemId = stationInfo.system_id
                securityStatus = stationInfo.security
                regionId = stationInfo.region_id

                // 获取星系和星域名称（多语言）
                if let systemInfo = await fetchSystemInfo(
                    solarSystemId: stationInfo.system_id, databaseManager: databaseManager
                ) {
                    securityStatus = systemInfo.security
                }
            } else if let structureInfo = try? await UniverseStructureAPI.shared.fetchStructureInfo(
                structureId: locationId, characterId: characterId
            ) {
                locationName = structureInfo.name
                typeId = structureInfo.type_id
                systemId = structureInfo.solar_system_id

                if let systemInfo = await fetchSystemInfo(
                    solarSystemId: structureInfo.solar_system_id, databaseManager: databaseManager
                ) {
                    securityStatus = systemInfo.security
                    regionId = systemInfo.regionId
                }
            }
        } else {
            if let structureInfo = try? await UniverseStructureAPI.shared.fetchStructureInfo(
                structureId: locationId, characterId: characterId
            ) {
                locationName = structureInfo.name
                typeId = structureInfo.type_id
                systemId = structureInfo.solar_system_id

                if let systemInfo = await fetchSystemInfo(
                    solarSystemId: structureInfo.solar_system_id, databaseManager: databaseManager
                ) {
                    securityStatus = systemInfo.security
                    regionId = systemInfo.regionId
                }
            } else if let stationInfo = try? await fetchStationInfo(
                stationId: locationId, databaseManager: databaseManager
            ) {
                locationName = stationInfo.name
                typeId = stationInfo.type_id
                systemId = stationInfo.system_id
                securityStatus = stationInfo.security
                regionId = stationInfo.region_id

                if let systemInfo = await fetchSystemInfo(
                    solarSystemId: stationInfo.system_id, databaseManager: databaseManager
                ) {
                    securityStatus = systemInfo.security
                }
            }
        }

        return (locationName, typeId, systemId, securityStatus, regionId)
    }

    // 辅助函数：创建初始的根节点
    private func createInitialRootNodes(
        topLocations: Set<Int64>,
        locationMap: [Int64: [CharacterAsset]],
        characterId: Int,
        databaseManager: DatabaseManager,
        names: [Int64: String] = [:],
        iconMap: [Int: (normal: String, blueprint_copy: String)]
    ) async throws -> [AssetTreeNode] {
        var rootNodes: [AssetTreeNode] = []
        let concurrentLimit = 5  // 并发数量限制

        // 将 topLocations 转换为数组以便分批处理
        let locationArray = Array(topLocations)
        var currentIndex = 0

        while currentIndex < locationArray.count {
            // 创建任务组进行并发请求
            try await withThrowingTaskGroup(
                of: (Int64, String?, String?, Int?, Double?, Int?, Int?).self
            ) { group in
                // 添加并发任务
                let endIndex = min(currentIndex + concurrentLimit, locationArray.count)
                for locationId in locationArray[currentIndex..<endIndex] {
                    if let items = locationMap[locationId] {
                        let locationType =
                            items.first?.location_type ?? NSLocalizedString("Unknown", comment: "")
                        group.addTask {
                            let info = try await self.fetchLocationInfo(
                                locationId: locationId,
                                locationType: locationType,
                                characterId: characterId,
                                databaseManager: databaseManager
                            )

                            // 根据位置类型获取图标
                            var iconName: String?
                            if locationType == "solar_system" {
                                // 如果是星系，使用星系图标
                                iconName = self.getSystemIcon(
                                    solarSystemId: Int(locationId), databaseManager: databaseManager
                                )
                            } else {
                                // 其他类型使用建筑物图标
                                if info.typeId != nil {
                                    if let iconInfo = self.getStationIcon(
                                        typeId: info.typeId!, databaseManager: databaseManager
                                    ) {
                                        // 顶层位置使用普通图标，不需要考虑蓝图复制品图标
                                        iconName = iconInfo.normal
                                    } else {
                                        iconName = nil
                                    }
                                } else {
                                    iconName = nil
                                }
                            }

                            return (
                                locationId,
                                info.name,
                                iconName,
                                info.typeId,
                                info.securityStatus,
                                info.systemId,
                                info.regionId
                            )
                        }
                    }
                }

                // 收集结果
                for try await (
                    locationId, locationName, iconName, typeId, securityStatus, systemId, regionId
                ) in group {
                    if let items = locationMap[locationId] {
                        let locationType =
                            items.first?.location_type ?? NSLocalizedString("Unknown", comment: "")

                        // 根据位置类型决定是否存储名称
                        // 对于空间站和星系，不存储名称（从游戏数据库查询）
                        // 对于其他类型（玩家命名的结构等），保留名称
                        let nodeName: String?
                        switch locationType {
                        case "station", "solar_system":
                            // 这些是游戏内置位置，不保存名称，UI显示时从本地数据库查询
                            nodeName = nil
                        default:
                            // 其他是玩家自定义名称的位置，保留名称
                            nodeName = locationName
                        }

                        let locationNode = AssetTreeNode(
                            location_id: locationId,
                            item_id: locationId,
                            type_id: typeId ?? 0,
                            location_type: locationType,
                            location_flag: "root",
                            quantity: 1,
                            name: nodeName,
                            icon_name: iconName,
                            is_singleton: true,
                            is_blueprint_copy: nil,
                            system_id: systemId,
                            region_id: regionId,
                            security_status: securityStatus,
                            items: items.map {
                                buildTreeNode(
                                    from: $0, locationMap: locationMap, names: names,
                                    databaseManager: databaseManager, iconMap: iconMap
                                )
                            }
                        )
                        rootNodes.append(locationNode)
                    }
                }
            }

            currentIndex += concurrentLimit

            // 更新进度
            // progressCallback?(.fetchingLocationInfo(current: min(currentIndex, locationArray.count), total: locationArray.count))

            // 添加短暂延迟以避免请求过于频繁
            if currentIndex < locationArray.count {
                try await Task.sleep(nanoseconds: UInt64(0.1 * 1_000_000_000))  // 100ms延迟
            }
        }

        return rootNodes
    }

    // 获取星系图标
    private func getSystemIcon(solarSystemId: Int, databaseManager: DatabaseManager) -> String? {
        let query = """
                SELECT t.icon_filename 
                FROM universe u 
                JOIN types t ON u.system_type = t.type_id 
                WHERE u.solarsystem_id = ?
            """

        guard
            case let .success(rows) = databaseManager.executeQuery(
                query, parameters: [solarSystemId]
            ),
            let row = rows.first,
            let iconFileName = row["icon_filename"] as? String
        else {
            return DatabaseConfig.defaultItemIcon
        }

        return iconFileName.isEmpty ? DatabaseConfig.defaultItemIcon : iconFileName
    }
}
