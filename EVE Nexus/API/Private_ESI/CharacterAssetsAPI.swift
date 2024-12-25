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

public struct ESIErrorResponse: Codable {
    let error: String
}

// 资产名称响应
private struct AssetNameResponse: Codable {
    let item_id: Int64
    let name: String
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
private struct AssetJsonCache: Codable {
    let json: String
    let timestamp: Date
}

// MARK: - Data Models
public struct AssetTreeNode: Codable, Hashable {
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
    let type_name: String?      // 物品类型名称
    let system_name: String?    // 星系名称
    let region_name: String?    // 星域名称
    let security_status: Double? // 星系安全等级
    let items: [AssetTreeNode]?
    
    // 实现 Hashable
    public func hash(into hasher: inout Hasher) {
        hasher.combine(item_id)
    }
    
    public static func == (lhs: AssetTreeNode, rhs: AssetTreeNode) -> Bool {
        return lhs.item_id == rhs.item_id
    }
}

public class CharacterAssetsAPI {
    public static let shared = CharacterAssetsAPI()
    
    // 缓存相关
    private let cacheTimeout: TimeInterval = 3600 // 1小时缓存
    private let assetJsonCachePrefix = "character_assets_json_"
    
    // 请求控制
    private let requestDelay: TimeInterval = 0.1 // 每秒10个请求
    
    private init() {}
    
    // MARK: - Cache Management
    private func isAssetJsonCacheValid(_ timestamp: Date) -> Bool {
        return Date().timeIntervalSince(timestamp) < cacheTimeout
    }
    
    private func getAssetJsonCache(characterId: Int) -> (json: String, timestamp: Date)? {
        let key = assetJsonCachePrefix + String(characterId)
        guard let data = UserDefaults.standard.data(forKey: key),
              let cache = try? JSONDecoder().decode(AssetJsonCache.self, from: data) else {
            return nil
        }
        return (cache.json, cache.timestamp)
    }
    
    private func saveAssetJsonCache(characterId: Int, json: String) {
        let key = assetJsonCachePrefix + String(characterId)
        let cache = AssetJsonCache(json: json, timestamp: Date())
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    
    // MARK: - Public Methods
    public func fetchAssetTreeJson(
        characterId: Int,
        forceRefresh: Bool = false,
        progressCallback: ((AssetLoadingProgress) -> Void)? = nil
    ) async throws -> String {
        // 检查缓存
        if !forceRefresh {
            if let cached = getAssetJsonCache(characterId: characterId),
               isAssetJsonCacheValid(cached.timestamp) {
                Logger.debug("使用缓存的资产JSON")
                return cached.json
            }
        }
        
        // 获取资产数据
        let assets = try await fetchAllAssets(characterId: characterId, progressCallback: progressCallback)
        
        // 生成资产树JSON
        guard let jsonString = try await generateAssetTreeJson(
            assets: assets,
            characterId: characterId,
            databaseManager: DatabaseManager()
        ) else {
            throw AssetError.invalidData("Failed to generate asset tree JSON")
        }
        
        // 保存到缓存
        saveAssetJsonCache(characterId: characterId, json: jsonString)
        
        return jsonString
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
    
    // 获取资产名称
    private func fetchAssetNames(characterId: Int, assetIds: [Int64]) async throws -> [Int64: String] {
        let batchSize = 900 // ESI API 限制每次最多 900 个
        var results: [Int64: String] = [:]
        
        // 将 assetIds 分批处理
        for batch in stride(from: 0, to: assetIds.count, by: batchSize) {
            let endIndex = min(batch + batchSize, assetIds.count)
            let currentBatch = Array(assetIds[batch..<endIndex])
            
            Logger.debug("处理资产名称批次 \(batch/batchSize + 1)，数量：\(currentBatch.count)")
            
            let urlString = "https://esi.evetech.net/latest/characters/\(characterId)/assets/names/"
            guard let url = URL(string: urlString) else {
                throw AssetError.invalidURL
            }
            
            // 准备请求头
            let headers = [
                "Accept": "application/json",
                "Content-Type": "application/json"
            ]
            
            // 将 assetIds 转换为 JSON 数据
            guard let jsonData = try? JSONEncoder().encode(currentBatch) else {
                throw AssetError.invalidData("Failed to encode asset IDs to JSON")
            }
            
            do {
                let data = try await NetworkManager.shared.postDataWithToken(
                    to: url,
                    body: jsonData,
                    characterId: characterId,
                    headers: headers
                )
                
                let nameResponses = try JSONDecoder().decode([AssetNameResponse].self, from: data)
                Logger.debug("获取资产名称批次 \(batch/batchSize + 1) 成功: \(nameResponses.count) 个名称")
                
                // 合并结果
                for response in nameResponses {
                    results[response.item_id] = response.name
                }
                
                // 添加延迟以遵守 API 限制
                if endIndex < assetIds.count {
                    try await Task.sleep(nanoseconds: 100_000_000) // 100ms 延迟
                }
                
            } catch {
                Logger.error("获取资产名称批次 \(batch/batchSize + 1) 失败: \(error)")
                // 继续处理其他批次，而不是立即失败
                continue
            }
        }
        
        if results.isEmpty {
            Logger.warning("没有成功获取到任何资产名称")
        } else {
            Logger.info("成功获取 \(results.count) 个资产名称")
        }
        
        return results
    }
    
    private func generateAssetTreeJson(
        assets: [CharacterAsset],
        characterId: Int,
        databaseManager: DatabaseManager
    ) async throws -> String? {
        // 建立 location_id 到资产列表的映射
        var locationMap: [Int64: [CharacterAsset]] = [:]
        var containerIds: Set<Int64> = []
        
        // 构建映射关系并收集容器ID
        for asset in assets {
            locationMap[asset.location_id, default: []].append(asset)
            // 如果有其他资产以这个资产的 item_id 作为 location_id，那么这个资产是一个容器
            if assets.contains(where: { $0.location_id == asset.item_id }) {
                containerIds.insert(asset.item_id)
            }
        }
        
        // 获取所有容器的名称
        let containerNames = try await fetchAssetNames(characterId: characterId, assetIds: Array(containerIds))
        
        // 递归构建树节点
        func buildTreeNode(from asset: CharacterAsset) -> AssetTreeNode {
            // 获取图标名称和物品类型名称
            let query = "SELECT icon_filename, name FROM types WHERE type_id = ?"
            var iconName: String? = nil
            var typeName: String? = nil
            if case .success(let rows) = databaseManager.executeQuery(query, parameters: [asset.type_id]),
               let row = rows.first {
                if let filename = row["icon_filename"] as? String {
                    iconName = filename.isEmpty ? DatabaseConfig.defaultItemIcon : filename
                }
                typeName = row["name"] as? String
            }
            
            // 获取子项
            let children = locationMap[asset.item_id, default: []].map { buildTreeNode(from: $0) }
            
            return AssetTreeNode(
                location_id: asset.location_id,
                item_id: asset.item_id,
                type_id: asset.type_id,
                location_type: asset.location_type,
                location_flag: asset.location_flag,
                quantity: asset.quantity,
                name: containerNames[asset.item_id],
                icon_name: iconName,
                is_singleton: asset.is_singleton,
                is_blueprint_copy: asset.is_blueprint_copy,
                type_name: typeName,
                system_name: nil,  // 将在顶层节点设置
                region_name: nil,  // 将在顶层节点设置
                security_status: nil, // 星系安全等级
                items: children.isEmpty ? nil : children
            )
        }
        
        // 找出顶层位置（空间站和建筑物）
        var topLocations: Set<Int64> = Set(assets.map { $0.location_id })
        for asset in assets {
            topLocations.remove(asset.item_id)
        }
        
        // 为每个顶层位置创建一个虚拟的根节点
        var rootNodes: [AssetTreeNode] = []
        for locationId in topLocations {
            if let items = locationMap[locationId] {
                // 获取位置类型（从第一个子项获取）
                let locationType = items.first?.location_type ?? "unknown"
                
                // 获取位置的图标、名称和系统信息
                var iconName: String? = nil
                var locationName: String? = nil
                var systemName: String? = nil
                var regionName: String? = nil
                var securityStatus: Double? = nil
                
                if let stationInfo = try? await fetchStationInfo(stationId: locationId) {
                    // 如果是空间站，获取空间站的图标和名称
                    iconName = getStationIcon(typeId: stationInfo.type_id, databaseManager: databaseManager)
                    locationName = stationInfo.name
                    // 获取星系和星域信息
                    if let systemInfo = await getSolarSystemInfo(solarSystemId: stationInfo.system_id, databaseManager: databaseManager) {
                        systemName = systemInfo.systemName
                        regionName = systemInfo.regionName
                        securityStatus = systemInfo.security
                    }
                } else if let structureInfo = try? await fetchStructureInfo(structureId: locationId, characterId: characterId) {
                    // 如果是建筑物，获取建筑物的图标和名称
                    iconName = getStationIcon(typeId: structureInfo.type_id, databaseManager: databaseManager)
                    locationName = structureInfo.name
                    // 获取星系和星域信息
                    if let systemInfo = await getSolarSystemInfo(solarSystemId: structureInfo.solar_system_id, databaseManager: databaseManager) {
                        systemName = systemInfo.systemName
                        regionName = systemInfo.regionName
                        securityStatus = systemInfo.security
                    }
                }
                
                // 创建位置节点
                let locationNode = AssetTreeNode(
                    location_id: locationId,
                    item_id: locationId,
                    type_id: 0,  // 位置本身没有type_id
                    location_type: locationType,
                    location_flag: "root",
                    quantity: 1,
                    name: locationName,
                    icon_name: iconName,
                    is_singleton: true,
                    is_blueprint_copy: nil,
                    type_name: nil,
                    system_name: systemName,
                    region_name: regionName,
                    security_status: securityStatus,
                    items: items.map { buildTreeNode(from: $0) }
                )
                rootNodes.append(locationNode)
            }
        }
        
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
}
