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

// 空间站信息
public struct StationInfo: Codable {
    let name: String
    let station_id: Int64
    let system_id: Int
    let type_id: Int
}

// 建筑物信息
public struct StructureInfo: Codable {
    let name: String
    let owner_id: Int
    let solar_system_id: Int
    let type_id: Int
}

// 资产位置信息
public struct AssetLocation {
    let locationId: Int64
    let locationType: String
    let stationInfo: StationInfo?
    let structureInfo: StructureInfo?
    let solarSystemInfo: SolarSystemInfo?
    let iconFileName: String?
    let error: Error?  // 添加错误信息字段
    let itemCount: Int // 添加物品数量字段
    
    // 格式化显示名称
    var displayName: String {
        if let station = stationInfo, let system = solarSystemInfo {
            if station.name.hasPrefix(system.systemName) {
                // 如果空间站名称以星系名开头，返回完整名称供UI层处理加粗
                return station.name
            }
            // 如果不以星系名开头，直接返回空间站名称
            return station.name
        } else if let structure = structureInfo, let system = solarSystemInfo {
            if structure.name.hasPrefix(system.systemName) {
                // 如果建筑物名称以星系名开头，返回完整名称供UI层处理加粗
                return structure.name
            }
            // 如果不以星系名开头，直接返回建筑物名称
            return structure.name
        } else if let error = error {
            // 如果有错误，显示错误信息
            return "[\(locationType) \(locationId)] - \(error.localizedDescription)"
        }
        return "Unknown Location [\(locationType) \(locationId)]"
    }
}

public struct ESIErrorResponse: Codable {
    let error: String
}

// 资产名称响应
private struct AssetNameResponse: Codable {
    let item_id: Int64
    let name: String
}

// 修改CacheableAssetNode以包含名称
private struct CacheableAssetNode: Codable {
    let asset: CharacterAsset
    let children: [CacheableAssetNode]
    let name: String?  // 添加名称字段
    
    init(from node: AssetNode) {
        self.asset = node.asset
        self.children = node.children.map { CacheableAssetNode(from: $0) }
        self.name = node.name
    }
    
    func toAssetNode() -> AssetNode {
        return AssetNode(
            asset: asset,
            children: children.map { $0.toAssetNode() },
            name: name
        )
    }
}

// 修改AssetNode以包含名称
public struct AssetNode {
    let asset: CharacterAsset
    var children: [AssetNode]
    var name: String?  // 添加名称字段
    
    // 递归展示资产树
    func displayAssetTree(level: Int = 0) -> String {
        var result = ""
        let indent = String(repeating: "    ", count: level)
        
        // 添加更详细的信息
        result += "\(indent)- Location:\(asset.location_id) | TypeID:\(asset.type_id) x\(asset.quantity) | Flag:[\(asset.location_flag)] | Type:[\(asset.location_type)]"
        if let isCopy = asset.is_blueprint_copy {
            result += " | Blueprint:\(isCopy ? "Copy" : "Original")"
        }
        
        for child in children {
            result += "\n" + child.displayAssetTree(level: level + 1)
        }
        
        return result
    }
    
    // 搜索特定物品
    func searchAsset(typeIds: [Int]) -> [AssetPath] {
        var paths: [AssetPath] = []
        
        // 如果当前节点匹配
        if typeIds.contains(asset.type_id) {
            paths.append(AssetPath(nodes: [self]))
        }
        
        // 在子节点中搜索
        for child in children {
            let childPaths = child.searchAsset(typeIds: typeIds)
            // 将当前节点添加到子节点的路径前面
            for var path in childPaths {
                path.nodes.insert(self, at: 0)
                paths.append(path)
            }
        }
        
        return paths
    }
}

public struct AssetPath {
    var nodes: [AssetNode]
    
    // 格式化显示路径
    func display() -> String {
        var result = ""
        for (index, node) in nodes.enumerated() {
            let indent = String(repeating: "    ", count: index)
            result += "\(indent)- TypeID:\(node.asset.type_id) x\(node.asset.quantity) [\(node.asset.location_flag)]"
            if index < nodes.count - 1 {
                result += "\n"
            }
        }
        return result
    }
}

// MARK: - Progress Tracking
public enum AssetLoadingProgress {
    case fetchingAPI(page: Int, totalPages: Int?)
    case buildingTree(step: Int, total: Int)
    case complete
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
private struct AssetsCacheEntry: Codable {
    let assets: [CharacterAsset]
    let timestamp: Date
}

// 用于缓存的完整资产数据结构
private struct AssetTreeCacheEntry: Codable {
    let assetTree: [CacheableAssetNode]
    let locations: [CacheableAssetLocation]
    let timestamp: Date
}

// 用于缓存的AssetLocation版本
private struct CacheableAssetLocation: Codable {
    let locationId: Int64
    let locationType: String
    let stationInfo: StationInfo?
    let structureInfo: StructureInfo?
    let solarSystemInfo: SolarSystemInfo?
    let iconFileName: String?
    let errorDescription: String?
    let itemCount: Int
    
    // 从AssetLocation转换
    init(from location: AssetLocation) {
        self.locationId = location.locationId
        self.locationType = location.locationType
        self.stationInfo = location.stationInfo
        self.structureInfo = location.structureInfo
        self.solarSystemInfo = location.solarSystemInfo
        self.iconFileName = location.iconFileName
        self.errorDescription = location.error?.localizedDescription
        self.itemCount = location.itemCount
    }
    
    // 转换回AssetLocation
    func toAssetLocation() -> AssetLocation {
        return AssetLocation(
            locationId: locationId,
            locationType: locationType,
            stationInfo: stationInfo,
            structureInfo: structureInfo,
            solarSystemInfo: solarSystemInfo,
            iconFileName: iconFileName,
            error: errorDescription.map { NSError(domain: "AssetLocation", code: 0, userInfo: [NSLocalizedDescriptionKey: $0]) },
            itemCount: itemCount
        )
    }
}

private struct AssetLocationsCacheEntry: Codable {
    let locations: [CacheableAssetLocation]
    let timestamp: Date
}

public class CharacterAssetsAPI {
    public static let shared = CharacterAssetsAPI()
    
    // 缓存相关
    private let cacheQueue = DispatchQueue(label: "com.eve-nexus.assets-cache", attributes: .concurrent)
    private var assetTreeMemoryCache: [Int: AssetTreeCacheEntry] = [:]
    private let cacheTimeout: TimeInterval = 1800 // 30分钟缓存
    private let assetTreeCachePrefix = "asset_tree_cache_"
    
    // 请求控制
    private let requestDelay: TimeInterval = 0.1 // 每秒10个请求
    
    private init() {}
    
    // MARK: - Cache Management
    private func isAssetTreeCacheValid(_ cache: AssetTreeCacheEntry?) -> Bool {
        guard let cache = cache else { return false }
        return Date().timeIntervalSince(cache.timestamp) < cacheTimeout
    }
    
    private func getAssetTreeMemoryCache(characterId: Int) -> AssetTreeCacheEntry? {
        var result: AssetTreeCacheEntry?
        cacheQueue.sync {
            result = assetTreeMemoryCache[characterId]
        }
        return result
    }
    
    private func setAssetTreeMemoryCache(characterId: Int, cache: AssetTreeCacheEntry) {
        cacheQueue.async(flags: .barrier) {
            self.assetTreeMemoryCache[characterId] = cache
        }
    }
    
    private func getAssetTreeDiskCache(characterId: Int) -> AssetTreeCacheEntry? {
        let key = assetTreeCachePrefix + String(characterId)
        guard let data = UserDefaults.standard.data(forKey: key),
              let cache = try? JSONDecoder().decode(AssetTreeCacheEntry.self, from: data) else {
            return nil
        }
        return cache
    }
    
    private func saveAssetTreeToDiskCache(characterId: Int, cache: AssetTreeCacheEntry) {
        let key = assetTreeCachePrefix + String(characterId)
        if let encoded = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
    
    // MARK: - Network Requests
    private func fetchWithRetry(url: URL, characterId: Int) async throws -> Data {
        let maxRetries = 3
        var lastError: Error? = nil
        
        for attempt in 0..<maxRetries {
            do {
                let data = try await NetworkManager.shared.fetchDataWithToken(from: url, characterId: characterId)
                return data
            } catch let error as NetworkError {
                // 检查是否是404错误
                if case .httpError(let statusCode) = error, statusCode == 404 {
                    // 404错误，直接抛出pageNotFound
                    throw AssetError.pageNotFound
                }
                
                lastError = error
                Logger.warning("获取资产数据失败 (尝试 \(attempt + 1)/\(maxRetries)): \(error)")
                if attempt < maxRetries - 1 {
                    try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt))) * 1_000_000_000) // 指数退避
                }
            } catch {
                lastError = error
                Logger.warning("获取资产数据失败 (尝试 \(attempt + 1)/\(maxRetries)): \(error)")
                if attempt < maxRetries - 1 {
                    try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt))) * 1_000_000_000) // 指数退避
                }
            }
        }
        
        throw AssetError.networkError(lastError ?? NSError(domain: "", code: -1))
    }
    
    // MARK: - Public Methods
    public func fetchAllAssets(
        characterId: Int,
        forceRefresh: Bool = false,
        progressCallback: ((AssetLoadingProgress) -> Void)? = nil
    ) async throws -> [CharacterAsset] {
        // 检查缓存
        if !forceRefresh {
            if let memoryCached = getAssetTreeMemoryCache(characterId: characterId),
               isAssetTreeCacheValid(memoryCached) {
                Logger.debug("使用内存中的资产缓存")
                // 从缓存的资产树中提取所有资产
                let assets = extractAssetsFromTree(memoryCached.assetTree)
                return assets
            }
            
            if let diskCached = getAssetTreeDiskCache(characterId: characterId),
               isAssetTreeCacheValid(diskCached) {
                Logger.debug("使用磁盘中的资产缓存")
                // 从缓存的资产树中提取所有资产
                let assets = extractAssetsFromTree(diskCached.assetTree)
                return assets
            }
        }
        
        var allAssets: [CharacterAsset] = []
        var page = 1
        
        while true {
            do {
                let urlString = "https://esi.evetech.net/latest/characters/\(characterId)/assets/?datasource=tranquility&page=\(page)"
                guard let url = URL(string: urlString) else {
                    throw AssetError.invalidURL
                }
                
                let data = try await fetchWithRetry(url: url, characterId: characterId)
                
                // 尝试解码数据
                if let errorResponse = try? JSONDecoder().decode(ESIErrorResponse.self, from: data),
                   errorResponse.error == "Requested page does not exist!" {
                    // 如果是页面不存在的响应，视为正常结束
                    Logger.info("资产数据获取完成，共\(allAssets.count)个项目")
                    break
                }
                
                let pageAssets = try JSONDecoder().decode([CharacterAsset].self, from: data)
                allAssets.append(contentsOf: pageAssets)
                
                // 只在成功获取数据后才显示进度
                progressCallback?(.fetchingAPI(page: page, totalPages: nil))
                Logger.info("成功获取第\(page)页资产数据，本页包含\(pageAssets.count)个项目")
                
                page += 1
                try await Task.sleep(nanoseconds: UInt64(requestDelay * 1_000_000_000))
                
            } catch AssetError.pageNotFound {
                // 正常的页面结束，跳出循环
                Logger.info("资产数据获取完成，共\(allAssets.count)个项目")
                break
            } catch {
                Logger.error("获取资产数据失败: \(error)")
                throw AssetError.networkError(error)
            }
        }
        
        return allAssets
    }
    
    // 辅助方法：从缓存的资产树中提取所有资产
    private func extractAssetsFromTree(_ nodes: [CacheableAssetNode]) -> [CharacterAsset] {
        var assets: [CharacterAsset] = []
        
        func extract(from node: CacheableAssetNode) {
            assets.append(node.asset)
            for child in node.children {
                extract(from: child)
            }
        }
        
        for node in nodes {
            extract(from: node)
        }
        
        return assets
    }
    
    // MARK: - Asset Tree Building
    public func buildAssetTree(assets: [CharacterAsset]) -> [AssetNode] {
        // 建立 item_id 到资产的映射
        var assetMap: [Int64: CharacterAsset] = [:]
        // 建立 location_id 到资产列表的映射
        var locationMap: [Int64: [CharacterAsset]] = [:]
        
        // 构建映射关系
        for asset in assets {
            assetMap[asset.item_id] = asset
            locationMap[asset.location_id, default: []].append(asset)
        }
        
        // 递归构建树节点
        func buildNode(from asset: CharacterAsset) -> AssetNode {
            let children = locationMap[asset.item_id, default: []].map { buildNode(from: $0) }
            return AssetNode(asset: asset, children: children)
        }
        
        // 找出顶层资产（没有其他资产以它的 item_id 作为 location_id 的资产）
        let topLevelAssets = assets.filter { asset in
            !assets.contains { $0.item_id == asset.location_id }
        }
        
        return topLevelAssets.map { buildNode(from: $0) }
    }
    
    // MARK: - Search Methods
    public func searchAssets(
        typeIds: [Int],
        characterId: Int,
        progressCallback: ((AssetLoadingProgress) -> Void)? = nil
    ) async throws -> [AssetPath] {
        // 获取资产数据
        let assets = try await fetchAllAssets(characterId: characterId, progressCallback: progressCallback)
        progressCallback?(.buildingTree(step: 1, total: 2))
        
        // 构建资产树
        let assetTree = buildAssetTree(assets: assets)
        progressCallback?(.buildingTree(step: 2, total: 2))
        
        // 搜索物品
        var results: [AssetPath] = []
        for node in assetTree {
            results.append(contentsOf: node.searchAsset(typeIds: typeIds))
        }
        
        progressCallback?(.complete)
        return results
    }
    
    // 获取空间站信息
    private func fetchStationInfo(stationId: Int64) async throws -> StationInfo {
        let urlString = "https://esi.evetech.net/latest/universe/stations/\(stationId)/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw AssetError.invalidURL
        }
        
        do {
            let data = try await NetworkManager.shared.fetchData(from: url)
            let stationInfo = try JSONDecoder().decode(StationInfo.self, from: data)
            return stationInfo
        } catch {
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
    
    // 获取建筑物信息
    private func fetchStructureInfo(structureId: Int64, characterId: Int) async throws -> StructureInfo {
        let urlString = "https://esi.evetech.net/latest/universe/structures/\(structureId)/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw AssetError.invalidURL
        }
        
        do {
            // 添加必要的请求头
            let headers = [
                "Accept": "application/json",
                "Content-Type": "application/json"
            ]
            
            let data = try await NetworkManager.shared.fetchDataWithToken(
                from: url,
                characterId: characterId,
                headers: headers
            )
            
            do {
                let structureInfo = try JSONDecoder().decode(StructureInfo.self, from: data)
                return structureInfo
            } catch {
                Logger.error("解析建筑物信息失败: \(error)")
                throw AssetError.decodingError(error)
            }
        } catch {
            Logger.error("获取建筑物信息失败: \(error)")
            throw AssetError.locationFetchError("Failed to fetch structure info: \(error)")
        }
    }
    
    // 获取二级位置的名称
    private func fetchSecondLevelNames(characterId: Int, locationIds: [Int64]) async throws -> [Int64: String] {
        let urlString = "https://esi.evetech.net/latest/characters/\(characterId)/assets/names/"
        guard let url = URL(string: urlString) else {
            throw AssetError.invalidURL
        }
        
        // 准备请求头
        let headers = [
            "Accept": "application/json",
            "Content-Type": "application/json"
        ]
        
        // 将locationIds转换为JSON数据
        guard let jsonData = try? JSONEncoder().encode(locationIds) else {
            throw AssetError.invalidData("Failed to encode location IDs to JSON")
        }
        
        do {
            let data = try await NetworkManager.shared.postDataWithToken(
                to: url,
                body: jsonData,
                characterId: characterId,
                headers: headers
            )
            
            let nameResponses = try JSONDecoder().decode([AssetNameResponse].self, from: data)
            return Dictionary(uniqueKeysWithValues: nameResponses.map { ($0.item_id, $0.name) })
        } catch {
            Logger.error("获取资产名称失败: \(error)")
            throw AssetError.locationFetchError("Failed to fetch asset names: \(error)")
        }
    }
    
    // 收集所有二级位置ID
    private func collectSecondLevelLocationIds(from nodes: [AssetNode]) -> Set<Int64> {
        var locationIds = Set<Int64>()
        
        for node in nodes {
            // 对于每个顶层节点的子节点，收集它们的item_id
            for child in node.children {
                locationIds.insert(child.asset.item_id)
                // 如果这个子节点被其他资产用作位置，那么它就是一个二级位置
                if nodes.contains(where: { $0.asset.location_id == child.asset.item_id }) {
                    locationIds.insert(child.asset.item_id)
                }
            }
        }
        
        return locationIds
    }
    
    // 更新资产树中的名称
    private func updateAssetTreeWithNames(tree: [AssetNode], names: [Int64: String]) -> [AssetNode] {
        return tree.map { node in
            var updatedNode = node
            if let name = names[node.asset.item_id] {
                updatedNode.name = name
            }
            updatedNode.children = updateAssetTreeWithNames(tree: node.children, names: names)
            return updatedNode
        }
    }
    
    // 处理资产位置信息
    func processAssetLocations(assets: [CharacterAsset], characterId: Int, databaseManager: DatabaseManager, forceRefresh: Bool = false) async throws -> ([AssetNode], [AssetLocation]) {
        // 检查缓存
        if !forceRefresh {
            if let memoryCached = getAssetTreeMemoryCache(characterId: characterId),
               isAssetTreeCacheValid(memoryCached) {
                Logger.debug("使用内存中的资产树缓存")
                return (
                    memoryCached.assetTree.map { $0.toAssetNode() },
                    memoryCached.locations.map { $0.toAssetLocation() }
                )
            }
            
            if let diskCached = getAssetTreeDiskCache(characterId: characterId),
               isAssetTreeCacheValid(diskCached) {
                Logger.debug("使用磁盘中的资产树缓存")
                let cache = AssetTreeCacheEntry(
                    assetTree: diskCached.assetTree,
                    locations: diskCached.locations,
                    timestamp: diskCached.timestamp
                )
                setAssetTreeMemoryCache(characterId: characterId, cache: cache)
                return (
                    diskCached.assetTree.map { $0.toAssetNode() },
                    diskCached.locations.map { $0.toAssetLocation() }
                )
            }
        }
        
        // 如果没有缓存或需要强制刷新，则处理资产位置信息
        Logger.debug("开始处理资产位置信息")
        
        // 1. 先构建资产树
        var assetTree = buildAssetTree(assets: assets)
        
        // 2. 获取二级位置的名称
        let secondLevelIds = Array(collectSecondLevelLocationIds(from: assetTree))
        if !secondLevelIds.isEmpty {
            do {
                let names = try await fetchSecondLevelNames(characterId: characterId, locationIds: secondLevelIds)
                assetTree = updateAssetTreeWithNames(tree: assetTree, names: names)
            } catch {
                Logger.error("获取二级位置名称失败: \(error)")
                // 继续处理，即使获取名称失败
            }
        }
        
        // 2. 从资产树中提取所有顶层位置ID和类型，并计算每个位置的物品数量
        var locationMap: [Int64: String] = [:] // locationId -> locationType
        var locationItemCount: [Int64: Int] = [:] // locationId -> itemCount
        
        func extractLocations(from nodes: [AssetNode]) {
            for node in nodes {
                // 只处理顶层节点
                locationMap[node.asset.location_id] = node.asset.location_type
                
                // 递归计算物品数量，每个物品都单独计数
                func countItems(in node: AssetNode) -> Int {
                    // 当前节点算一个
                    var count = 1
                    // 加上所有子节点的数量
                    for child in node.children {
                        count += countItems(in: child)
                    }
                    return count
                }
                
                // 找出所有直接属于这个位置的物品
                let itemsInLocation = assets.filter { asset in
                    asset.location_id == node.asset.location_id
                }
                
                // 为每个物品计算其所有子物品的数量
                var totalItems = 0
                for asset in itemsInLocation {
                    if let assetNode = findNode(itemId: asset.item_id, in: assetTree) {
                        totalItems += countItems(in: assetNode)
                    }
                }
                
                // 计算该位置下的总物品数量
                locationItemCount[node.asset.location_id] = totalItems
                
                Logger.debug("位置 \(node.asset.location_id) 包含 \(totalItems) 个物品")
            }
        }
        
        // 辅助函数：根据item_id查找节点
        func findNode(itemId: Int64, in nodes: [AssetNode]) -> AssetNode? {
            for node in nodes {
                if node.asset.item_id == itemId {
                    return node
                }
                if let found = findNode(itemId: itemId, in: node.children) {
                    return found
                }
            }
            return nil
        }
        
        // 只提取顶层资产的位置信息
        extractLocations(from: assetTree)
        
        // 3. 获取所有位置的详细信息
        var locations: [AssetLocation] = []
        
        for (locationId, locationType) in locationMap {
            var location: AssetLocation?
            var locationError: Error?
            
            do {
                switch locationType.lowercased() {
                case "station":
                    do {
                        // 获取空间站信息
                        let stationInfo = try await fetchStationInfo(stationId: locationId)
                        
                        // 获取星系信息
                        if let systemInfo = await getSolarSystemInfo(solarSystemId: stationInfo.system_id, databaseManager: databaseManager) {
                            // 获取空间站图标
                            let iconFileName = getStationIcon(typeId: stationInfo.type_id, databaseManager: databaseManager)
                            Logger.debug("获取地点 \(locationId): \(stationInfo.name)")
                            // 创建位置信息
                            location = AssetLocation(
                                locationId: locationId,
                                locationType: locationType,
                                stationInfo: stationInfo,
                                structureInfo: nil,
                                solarSystemInfo: systemInfo,
                                iconFileName: iconFileName,
                                error: nil,
                                itemCount: locationItemCount[locationId] ?? 0
                            )
                        }
                    } catch {
                        locationError = error
                    }
                    
                case "item": // 建筑物资产
                    do {
                        // 获取建筑物信息
                        let structureInfo = try await fetchStructureInfo(structureId: locationId, characterId: characterId)
                        
                        // 获取星系信息
                        if let systemInfo = await getSolarSystemInfo(solarSystemId: structureInfo.solar_system_id, databaseManager: databaseManager) {
                            // 获取建筑物图标
                            let iconFileName = getStationIcon(typeId: structureInfo.type_id, databaseManager: databaseManager)
                            // 创建位置信息
                            Logger.debug("获取地点 \(locationId): \(structureInfo.name)")
                            location = AssetLocation(
                                locationId: locationId,
                                locationType: locationType,
                                stationInfo: nil,
                                structureInfo: structureInfo,
                                solarSystemInfo: systemInfo,
                                iconFileName: iconFileName,
                                error: nil,
                                itemCount: locationItemCount[locationId] ?? 0
                            )
                        }
                    } catch {
                        locationError = error
                    }
                    
                default:
                    Logger.info("未知类型的位置: \(locationType), ID: \(locationId)")
                    locationError = AssetError.incompleteData("Unknown location type: \(locationType)")
                }
            }
            
            // 如果获取信息失败，创建一个带错误信息的位置
            if location == nil {
                location = AssetLocation(
                    locationId: locationId,
                    locationType: locationType,
                    stationInfo: nil,
                    structureInfo: nil,
                    solarSystemInfo: nil,
                    iconFileName: DatabaseConfig.defaultItemIcon,
                    error: locationError,
                    itemCount: locationItemCount[locationId] ?? 0
                )
            }
            
            if let location = location {
                locations.append(location)
            }
        }
        
        // 4. 按星域和星系名称排序，未知位置排在最后
        let sortedLocations = locations.sorted { loc1, loc2 in
            // 如果有一个位置没有系统信息，将其排在后面
            if loc1.solarSystemInfo == nil {
                return false
            }
            if loc2.solarSystemInfo == nil {
                return true
            }
            
            guard let system1 = loc1.solarSystemInfo,
                  let system2 = loc2.solarSystemInfo else {
                return false
            }
            
            if system1.regionName != system2.regionName {
                return system1.regionName < system2.regionName
            }
            return system1.systemName < system2.systemName
        }
        
        // 保存到缓存
        let cacheableTree = assetTree.map { CacheableAssetNode(from: $0) }
        let cacheableLocations = sortedLocations.map { CacheableAssetLocation(from: $0) }
        let cacheEntry = AssetTreeCacheEntry(
            assetTree: cacheableTree,
            locations: cacheableLocations,
            timestamp: Date()
        )
        setAssetTreeMemoryCache(characterId: characterId, cache: cacheEntry)
        saveAssetTreeToDiskCache(characterId: characterId, cache: cacheEntry)
        
        Logger.debug("资产树和位置信息处理完成，已保存到缓存")
        return (assetTree, sortedLocations)
    }
} 
