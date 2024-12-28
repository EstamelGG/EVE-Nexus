import Foundation

// MARK: - Data Models
private struct CharacterAsset: Codable {
    let is_singleton: Bool
    let item_id: Int64
    let location_id: Int64
    let location_flag: String
    let location_type: String
    let quantity: Int
    let type_id: Int
    let is_blueprint_copy: Bool?
}

// ESI错误响应
private struct ESIErrorResponse: Codable {
    let error: String
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
    let name: String?
    let icon_name: String?
    let is_singleton: Bool
    let is_blueprint_copy: Bool?
    let system_name: String?    // 星系名称
    let region_name: String?    // 星域名称
    let security_status: Double? // 星系安全等级
    let items: [AssetTreeNode]?
}

// MARK: - Error Types
public enum AssetError: Error {
    case networkError(Error)
    case incompleteData(String)
    case decodingError(Error)
    case invalidURL
    case maxRetriesReached
    case pageNotFound
    case locationFetchError(String)
    case invalidData(String)
}

// MARK: - Cache Structure
private struct AssetTreeCacheEntry: Codable {
    let jsonString: String
    let timestamp: Date
}

// MARK: - Progress Types
public enum AssetLoadingProgress {
    case fetchingPage(Int)      // 获取第几页
    case calculatingJson        // 计算JSON
    case fetchingNames         // 获取名称
}

public class CharacterAssetsJsonAPI {
    public static let shared = CharacterAssetsJsonAPI()
    private let cacheTimeout: TimeInterval = 8 * 3600 // 8 小时缓存
    private let assetTreeCachePrefix = "asset_tree_json_cache_"
    
    private init() {}
    
    // MARK: - Public Methods
    public func generateAssetTreeJson(
        characterId: Int,
        forceRefresh: Bool = false,
        progressCallback: ((AssetLoadingProgress) -> Void)? = nil
    ) async throws -> String? {
        // 检查缓存
        if !forceRefresh {
            if let cachedJson = getCachedJson(characterId: characterId) {
                Logger.debug("使用缓存的资产树JSON")
                return cachedJson
            }
        }
        
        // 1. 获取所有资产
        let assets = try await fetchAllAssets(characterId: characterId) { page in
            progressCallback?(.fetchingPage(page))
        }
        
        // 2. 生成资产树JSON
        progressCallback?(.calculatingJson)
        if let jsonString = try await generateAssetTreeJson(
            assets: assets,
            names: [:],
            characterId: characterId,
            databaseManager: DatabaseManager(),
            progressCallback: progressCallback
        ) {
            // 保存到缓存
            saveToCache(jsonString: jsonString, characterId: characterId)
            return jsonString
        }
        return nil
    }
    
    // MARK: - Cache Methods
    private func getCacheFilePath(characterId: Int) -> URL? {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let cacheDirectory = documentsDirectory.appendingPathComponent("AssetCache", isDirectory: true)
        
        // 确保缓存目录存在
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        return cacheDirectory.appendingPathComponent("\(assetTreeCachePrefix)\(characterId).json")
    }
    
    private func isValidCache(_ cache: AssetTreeCacheEntry) -> Bool {
        return Date().timeIntervalSince(cache.timestamp) < cacheTimeout
    }
    
    private func getCachedJson(characterId: Int) -> String? {
        guard let cacheFile = getCacheFilePath(characterId: characterId),
              let data = try? Data(contentsOf: cacheFile),
              let cache = try? JSONDecoder().decode(AssetTreeCacheEntry.self, from: data),
              isValidCache(cache) else {
            return nil
        }
        return cache.jsonString
    }
    
    private func saveToCache(jsonString: String, characterId: Int) {
        let cache = AssetTreeCacheEntry(jsonString: jsonString, timestamp: Date())
        guard let cacheFile = getCacheFilePath(characterId: characterId),
              let encoded = try? JSONEncoder().encode(cache) else {
            return
        }
        
        do {
            try encoded.write(to: cacheFile)
            Logger.debug("资产树JSON已缓存到文件: \(cacheFile.path)")
        } catch {
            Logger.error("保存资产树缓存失败: \(error)")
        }
    }
    
    // MARK: - Private Methods
    // 获取所有资产
    private func fetchAllAssets(
        characterId: Int,
        progressCallback: ((Int) -> Void)? = nil
    ) async throws -> [CharacterAsset] {
        var allAssets: [CharacterAsset] = []
        var currentPage = 1
        let concurrentLimit = 3 // 并发数量限制
        var shouldContinue = true
        
        while shouldContinue {
            // 创建任务组进行并发请求
            try await withThrowingTaskGroup(of: (Int, [CharacterAsset]).self) { group in
                // 添加并发任务
                for offset in 0..<concurrentLimit {
                    let page = currentPage + offset
                    group.addTask {
                        let urlString = "https://esi.evetech.net/latest/characters/\(characterId)/assets/?datasource=tranquility&page=\(page)"
                        guard let url = URL(string: urlString) else {
                            throw AssetError.invalidURL
                        }
                        
                        do {
                            let data = try await NetworkManager.shared.fetchDataWithToken(
                                from: url,
                                characterId: characterId,
                                noRetryKeywords: ["Requested page does not exist"]
                            )
                            
                            // 检查是否是页面不存在的响应
                            if let errorResponse = try? JSONDecoder().decode(ESIErrorResponse.self, from: data),
                               errorResponse.error == "Requested page does not exist!" {
                                return (page, []) // 返回空数组和页码，表示该页不存在
                            }
                            
                            let pageAssets = try JSONDecoder().decode([CharacterAsset].self, from: data)
                            Logger.info("成功获取第\(page)页资产数据，本页包含\(pageAssets.count)个项目")
                            progressCallback?(page)
                            return (page, pageAssets)
                            
                        } catch let error as NetworkError {
                            if case .httpError(let statusCode, let message) = error,
                               statusCode == 404,
                               message?.contains("Requested page does not exist") == true {
                                return (page, []) // 返回空数组和页码，表示该页不存在
                            }
                            throw error
                        }
                    }
                }
                
                // 收集并发任务的结果
                var validPages = Set<Int>()
                var maxValidPage = 0
                
                // 处理每个任务的结果
                for try await (page, pageAssets) in group {
                    if !pageAssets.isEmpty {
                        allAssets.append(contentsOf: pageAssets)
                        validPages.insert(page)
                        maxValidPage = max(maxValidPage, page)
                    }
                }
                
                // 检查是否所有页面都已获取完毕
                if validPages.isEmpty || maxValidPage < currentPage + concurrentLimit - 1 {
                    Logger.info("资产数据获取完成，共\(allAssets.count)个项目")
                    shouldContinue = false
                    return
                }
                
                // 更新起始页码到最后一个有效页面之后
                currentPage = maxValidPage + 1
                
                // 添加短暂延迟以避免请求过于频繁
                try await Task.sleep(nanoseconds: UInt64(0.1 * 1_000_000_000)) // 100ms延迟
            }
        }
        
        return allAssets
    }
    
    // 获取空间站信息
    private func fetchStationInfo(stationId: Int64, databaseManager: DatabaseManager) async throws -> StationInfo {
        let query = """
            SELECT stationID, stationTypeID, stationName, regionID, solarSystemID, security
            FROM stations
            WHERE stationID = ?
        """
        
        // 将 stationId 转换为字符串
        let stationIdStr = String(stationId)
        let result = databaseManager.executeQuery(query, parameters: [stationIdStr])
        
        switch result {
        case .success(let rows):
            guard let row = rows.first,
                  let stationName = row["stationName"] as? String,
                  let stationTypeID = row["stationTypeID"] as? Int,
                  let solarSystemID = row["solarSystemID"] as? Int,
                  let regionID = row["regionID"] as? Int,
                  let security = row["security"] as? Double else {
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
            
        case .error(let error):
            Logger.error("从数据库获取空间站信息失败: \(error)")
            throw AssetError.locationFetchError("Failed to fetch station info: \(error)")
        }
    }
    
    // 获取空间站图标
    private func getStationIcon(typeId: Int, databaseManager: DatabaseManager) -> String? {
        let query = "SELECT icon_filename FROM types WHERE type_id = ?"
        
        if case .success(let rows) = databaseManager.executeQuery(query, parameters: [typeId]),
           let row = rows.first,
           let iconFileName = row["icon_filename"] as? String {
            return iconFileName.isEmpty ? DatabaseConfig.defaultItemIcon : iconFileName
        }
        return DatabaseConfig.defaultItemIcon
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
    private func fetchContainerNames(containerIds: [Int64], characterId: Int) async throws -> [Int64: String] {
        guard !containerIds.isEmpty else { return [:] }
        
        let urlString = "https://esi.evetech.net/latest/characters/\(characterId)/assets/names/"
        guard let url = URL(string: urlString) else {
            throw AssetError.invalidURL
        }
        
        let headers = [
            "Accept": "application/json",
            "Content-Type": "application/json"
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
        databaseManager: DatabaseManager
    ) -> AssetTreeNode {
        // 获取图标名称和物品类型名称
        let query = "SELECT icon_filename FROM types WHERE type_id = ?"
        var iconName: String? = nil
        if case .success(let rows) = databaseManager.executeQuery(query, parameters: [asset.type_id]),
           let row = rows.first {
            if let filename = row["icon_filename"] as? String {
                iconName = filename.isEmpty ? DatabaseConfig.defaultItemIcon : filename
            }
        }
        
        // 获取子项
        let children = locationMap[asset.item_id, default: []].map { childAsset in
            buildTreeNode(
                from: childAsset,
                locationMap: locationMap,
                names: names,
                databaseManager: databaseManager
            )
        }
        
        return AssetTreeNode(
            location_id: asset.location_id,
            item_id: asset.item_id,
            type_id: asset.type_id,
            location_type: asset.location_type,
            location_flag: asset.location_flag,
            quantity: asset.quantity,
            name: names[asset.item_id],
            icon_name: iconName,
            is_singleton: asset.is_singleton,
            is_blueprint_copy: asset.is_blueprint_copy,
            system_name: nil,
            region_name: nil,
            security_status: nil,
            items: children.isEmpty ? nil : children
        )
    }
    
    private func generateAssetTreeJson(
        assets: [CharacterAsset],
        names: [Int64: String],
        characterId: Int,
        databaseManager: DatabaseManager,
        progressCallback: ((AssetLoadingProgress) -> Void)? = nil
    ) async throws -> String? {
        // 建立 location_id 到资产列表的映射
        var locationMap: [Int64: [CharacterAsset]] = [:]
        
        // 构建映射关系
        for asset in assets {
            locationMap[asset.location_id, default: []].append(asset)
        }
        
        // 找出顶层位置（空间站和建筑物）
        var topLocations: Set<Int64> = Set(assets.map { $0.location_id })
        for asset in assets {
            topLocations.remove(asset.item_id)
        }
        
        // 创建初始的根节点
        var rootNodes = try await createInitialRootNodes(
            topLocations: topLocations,
            locationMap: locationMap,
            characterId: characterId,
            databaseManager: databaseManager,
            names: names
        )
        
        // 收集所有容器的ID
        let containerIds = collectContainerIds(from: rootNodes)
        
        // 获取容器名称
        progressCallback?(.fetchingNames)
        let containerNames = try await fetchContainerNames(
            containerIds: Array(containerIds),
            characterId: characterId
        )
        
        // 合并所有名称
        var allNames = names
        for (id, name) in containerNames {
            allNames[id] = name
        }
        
        // 使用更新后的名称重新构建树
        rootNodes = try await createInitialRootNodes(
            topLocations: topLocations,
            locationMap: locationMap,
            characterId: characterId,
            databaseManager: databaseManager,
            names: allNames
        )
        
        // 转换为JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        do {
            let jsonData = try encoder.encode(rootNodes)
            return String(data: jsonData, encoding: .utf8)
        } catch {
            Logger.error("生成资产树JSON失败: \(error)")
            return nil
        }
    }
    
    // 获取位置信息的辅助方法
    private func fetchLocationInfo(
        locationId: Int64,
        locationType: String,
        characterId: Int,
        databaseManager: DatabaseManager
    ) async throws -> (name: String?, typeId: Int?, systemId: Int?, systemName: String?, regionName: String?, securityStatus: Double?) {
        var locationName: String? = nil
        var typeId: Int? = nil
        var systemId: Int? = nil
        var systemName: String? = nil
        var regionName: String? = nil
        var securityStatus: Double? = nil
        
        if locationType == "station" {
            if let stationInfo = try? await self.fetchStationInfo(stationId: locationId, databaseManager: databaseManager) {
                locationName = stationInfo.name
                typeId = stationInfo.type_id
                systemId = stationInfo.system_id
                securityStatus = stationInfo.security
                
                // 获取星系和星域名称
                if let systemInfo = await getSolarSystemInfo(solarSystemId: stationInfo.system_id, databaseManager: databaseManager) {
                    systemName = systemInfo.systemName
                    regionName = systemInfo.regionName
                }
            } else if let structureInfo = try? await UniverseStructureAPI.shared.fetchStructureInfo(structureId: locationId, characterId: characterId) {
                locationName = structureInfo.name
                typeId = structureInfo.type_id
                systemId = structureInfo.solar_system_id
                
                if let systemInfo = await getSolarSystemInfo(solarSystemId: structureInfo.solar_system_id, databaseManager: databaseManager) {
                    systemName = systemInfo.systemName
                    regionName = systemInfo.regionName
                    securityStatus = systemInfo.security
                }
            }
        } else {
            if let structureInfo = try? await UniverseStructureAPI.shared.fetchStructureInfo(structureId: locationId, characterId: characterId) {
                locationName = structureInfo.name
                typeId = structureInfo.type_id
                systemId = structureInfo.solar_system_id
                
                if let systemInfo = await getSolarSystemInfo(solarSystemId: structureInfo.solar_system_id, databaseManager: databaseManager) {
                    systemName = systemInfo.systemName
                    regionName = systemInfo.regionName
                    securityStatus = systemInfo.security
                }
            } else if let stationInfo = try? await self.fetchStationInfo(stationId: locationId, databaseManager: databaseManager) {
                locationName = stationInfo.name
                typeId = stationInfo.type_id
                systemId = stationInfo.system_id
                securityStatus = stationInfo.security
                
                if let systemInfo = await getSolarSystemInfo(solarSystemId: stationInfo.system_id, databaseManager: databaseManager) {
                    systemName = systemInfo.systemName
                    regionName = systemInfo.regionName
                }
            }
        }
        
        return (locationName, typeId, systemId, systemName, regionName, securityStatus)
    }
    
    // 辅助函数：创建初始的根节点
    private func createInitialRootNodes(
        topLocations: Set<Int64>,
        locationMap: [Int64: [CharacterAsset]],
        characterId: Int,
        databaseManager: DatabaseManager,
        names: [Int64: String] = [:]
    ) async throws -> [AssetTreeNode] {
        var rootNodes: [AssetTreeNode] = []
        let concurrentLimit = 5 // 并发数量限制
        
        // 将 topLocations 转换为数组以便分批处理
        let locationArray = Array(topLocations)
        var currentIndex = 0
        
        while currentIndex < locationArray.count {
            // 创建任务组进行并发请求
            try await withThrowingTaskGroup(of: (Int64, String?, String?, Int?, Int?, String?, String?, Double?).self) { group in
                // 添加并发任务
                for offset in 0..<concurrentLimit {
                    let index = currentIndex + offset
                    guard index < locationArray.count else { break }
                    
                    let locationId = locationArray[index]
                    group.addTask {
                        guard let items = locationMap[locationId] else {
                            return (locationId, nil, nil, nil, nil, nil, nil, nil)
                        }
                        
                        let locationType = items.first?.location_type ?? "unknown"
                        var locationName: String? = nil
                        var iconName: String? = nil
                        var typeId: Int? = nil
                        var systemId: Int? = nil
                        var systemName: String? = nil
                        var regionName: String? = nil
                        var securityStatus: Double? = nil
                        
                        // 获取位置信息
                        let info = try await self.fetchLocationInfo(
                            locationId: locationId,
                            locationType: locationType,
                            characterId: characterId,
                            databaseManager: databaseManager
                        )
                        
                        (locationName, typeId, systemId, systemName, regionName, securityStatus) = info
                        
                        if let tid = typeId {
                            iconName = self.getStationIcon(typeId: tid, databaseManager: databaseManager)
                        }
                        
                        return (locationId, locationName, iconName, typeId, systemId, systemName, regionName, securityStatus)
                    }
                }
                
                // 收集并发任务的结果
                for try await (locationId, locationName, iconName, typeId, _, systemName, regionName, securityStatus) in group {
                    if let items = locationMap[locationId] {
                        let locationType = items.first?.location_type ?? "unknown"
                        
                        let locationNode = AssetTreeNode(
                            location_id: locationId,
                            item_id: locationId,
                            type_id: typeId ?? 0,
                            location_type: locationType,
                            location_flag: "root",
                            quantity: 1,
                            name: locationName,
                            icon_name: iconName,
                            is_singleton: true,
                            is_blueprint_copy: nil,
                            system_name: systemName,
                            region_name: regionName,
                            security_status: securityStatus,
                            items: items.map { buildTreeNode(from: $0, locationMap: locationMap, names: names, databaseManager: databaseManager) }
                        )
                        rootNodes.append(locationNode)
                    }
                }
            }
            
            currentIndex += concurrentLimit
            
            // 添加短暂延迟以避免请求过于频繁
            if currentIndex < locationArray.count {
                try await Task.sleep(nanoseconds: UInt64(0.1 * 1_000_000_000)) // 100ms延迟
            }
        }
        
        return rootNodes
    }
} 
