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

// 资产位置信息
public struct AssetLocation {
    let locationId: Int64
    let locationType: String
    let stationInfo: StationInfo?
    let solarSystemInfo: SolarSystemInfo?
    let iconFileName: String?
    
    // 格式化显示名称
    var displayName: String {
        if let station = stationInfo, let system = solarSystemInfo {
            if station.name.hasPrefix(system.systemName) {
                // 如果空间站名称以星系名开头，返回完整名称供UI层处理加粗
                return station.name
            }
            // 如果不以星系名开头，直接返回空间站名称
            return station.name
        }
        return "Unknown Location"
    }
}

public struct ESIErrorResponse: Codable {
    let error: String
}

public struct AssetNode {
    let asset: CharacterAsset
    var children: [AssetNode]
    
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
}

// MARK: - Cache Structure
private struct AssetsCacheEntry: Codable {
    let assets: [CharacterAsset]
    let timestamp: Date
}

public class CharacterAssetsAPI {
    public static let shared = CharacterAssetsAPI()
    
    // 缓存相关
    private let cacheQueue = DispatchQueue(label: "com.eve-nexus.assets-cache", attributes: .concurrent)
    private var memoryCache: [Int: AssetsCacheEntry] = [:]
    private let cacheTimeout: TimeInterval = 1800 // 30分钟缓存
    private let cachePrefix = "assets_cache_"
    
    // 请求控制
    private let requestDelay: TimeInterval = 0.1 // 每秒10个请求
    
    private init() {}
    
    // MARK: - Cache Management
    private func isAssetsCacheValid(_ cache: AssetsCacheEntry?) -> Bool {
        guard let cache = cache else { return false }
        return Date().timeIntervalSince(cache.timestamp) < cacheTimeout
    }
    
    private func getMemoryCache(characterId: Int) -> AssetsCacheEntry? {
        var result: AssetsCacheEntry?
        cacheQueue.sync {
            result = memoryCache[characterId]
        }
        return result
    }
    
    private func setMemoryCache(characterId: Int, cache: AssetsCacheEntry) {
        cacheQueue.async(flags: .barrier) {
            self.memoryCache[characterId] = cache
        }
    }
    
    private func getDiskCache(characterId: Int) -> AssetsCacheEntry? {
        let key = cachePrefix + String(characterId)
        guard let data = UserDefaults.standard.data(forKey: key),
              let cache = try? JSONDecoder().decode(AssetsCacheEntry.self, from: data) else {
            return nil
        }
        return cache
    }
    
    private func saveToDiskCache(characterId: Int, cache: AssetsCacheEntry) {
        let key = cachePrefix + String(characterId)
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
            if let memoryCached = getMemoryCache(characterId: characterId),
               isAssetsCacheValid(memoryCached) {
                return memoryCached.assets
            }
            
            if let diskCached = getDiskCache(characterId: characterId),
               isAssetsCacheValid(diskCached) {
                setMemoryCache(characterId: characterId, cache: diskCached)
                return diskCached.assets
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
        
        // 更新缓存
        let cacheEntry = AssetsCacheEntry(assets: allAssets, timestamp: Date())
        setMemoryCache(characterId: characterId, cache: cacheEntry)
        saveToDiskCache(characterId: characterId, cache: cacheEntry)
        
        return allAssets
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
    
    // 处理资产位置信息
    func processAssetLocations(assets: [CharacterAsset], databaseManager: DatabaseManager) async throws -> [AssetLocation] {
        var locations: [AssetLocation] = []
        var processedLocationIds = Set<Int64>()
        
        for asset in assets {
            // 只处理顶层资产且未处理过的位置
            if !processedLocationIds.contains(asset.location_id) {
                processedLocationIds.insert(asset.location_id)
                
                switch asset.location_type.lowercased() {
                case "station":
                    do {
                        // 获取空间站信息
                        let stationInfo = try await fetchStationInfo(stationId: asset.location_id)
                        
                        // 获取星系信息
                        if let systemInfo = await getSolarSystemInfo(solarSystemId: stationInfo.system_id, databaseManager: databaseManager) {
                            // 获取空间站图标
                            let iconFileName = getStationIcon(typeId: stationInfo.type_id, databaseManager: databaseManager)
                            
                            // 创建位置信息
                            let location = AssetLocation(
                                locationId: asset.location_id,
                                locationType: asset.location_type,
                                stationInfo: stationInfo,
                                solarSystemInfo: systemInfo,
                                iconFileName: iconFileName
                            )
                            locations.append(location)
                        }
                    } catch {
                        Logger.error("处理空间站资产失败: \(error)")
                        throw AssetError.locationFetchError("Failed to process station asset: \(error)")
                    }
                    
                default:
                    // 其他类型的位置暂时不处理
                    continue
                }
            }
        }
        
        // 按星域和星系名称排序
        return locations.sorted { loc1, loc2 in
            guard let system1 = loc1.solarSystemInfo,
                  let system2 = loc2.solarSystemInfo else {
                return false
            }
            
            if system1.regionName != system2.regionName {
                return system1.regionName < system2.regionName
            }
            return system1.systemName < system2.systemName
        }
    }
} 
