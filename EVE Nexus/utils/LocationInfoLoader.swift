import Foundation

// 修改位置信息模型
public struct LocationInfoDetail {
    public let stationName: String  // 空间站或建筑物名称，如果是星系则为""
    public let solarSystemName: String
    public let security: Double
    
    public init(stationName: String, solarSystemName: String, security: Double) {
        self.stationName = stationName
        self.solarSystemName = solarSystemName
        self.security = security
    }
}

// 修改为 internal 访问级别
class LocationInfoLoader {
    private let databaseManager: DatabaseManager
    private let characterId: Int64
    
    init(databaseManager: DatabaseManager, characterId: Int64) {
        self.databaseManager = databaseManager
        self.characterId = characterId
    }
    
    /// 批量加载位置信息
    /// - Parameter locationIds: 位置ID数组
    /// - Returns: 位置信息字典 [位置ID: 位置信息]
    func loadLocationInfo(locationIds: Set<Int64>) async -> [Int64: LocationInfoDetail] {
        var locationInfoCache: [Int64: LocationInfoDetail] = [:]
        
        // 过滤掉无效的位置ID
        let validLocationIds = locationIds.filter { $0 > 0 }
        
        if validLocationIds.isEmpty {
            Logger.debug("没有有效的位置ID需要加载")
            return locationInfoCache
        }
        
        Logger.debug("开始加载位置信息 - 有效位置IDs: \(validLocationIds)")
        
        // 1. 尝试作为星系ID查询
        let universeQuery = """
            SELECT u.solarsystem_id, u.system_security,
                   s.solarSystemName
            FROM universe u
            JOIN solarsystems s ON s.solarSystemID = u.solarsystem_id
            WHERE u.solarsystem_id IN (\(validLocationIds.map { String($0) }.joined(separator: ",")))
        """
        
        if case .success(let rows) = databaseManager.executeQuery(universeQuery) {
            for row in rows {
                if let systemId = row["solarsystem_id"] as? Int64,
                   let security = row["system_security"] as? Double,
                   let systemName = row["solarSystemName"] as? String {
                    locationInfoCache[systemId] = LocationInfoDetail(
                        stationName: "",
                        solarSystemName: systemName,
                        security: security
                    )
                    Logger.debug("从数据库加载到星系信息 - ID: \(systemId), 名称: \(systemName)")
                }
            }
        }
        
        // 2. 对于未解析的ID，尝试作为空间站ID查询
        let remainingIds = validLocationIds.filter { !locationInfoCache.keys.contains($0) }
        if !remainingIds.isEmpty {
            let stationQuery = """
                SELECT s.stationID, s.stationName, ss.solarSystemName, u.system_security
                FROM stations s
                JOIN solarSystems ss ON s.solarSystemID = ss.solarSystemID
                JOIN universe u ON u.solarsystem_id = ss.solarSystemID
                WHERE s.stationID IN (\(remainingIds.map { String($0) }.joined(separator: ",")))
            """
            
            if case .success(let rows) = databaseManager.executeQuery(stationQuery) {
                for row in rows {
                    if let stationId = row["stationID"] as? Int64,
                       let stationName = row["stationName"] as? String,
                       let systemName = row["solarSystemName"] as? String,
                       let security = row["system_security"] as? Double {
                        locationInfoCache[stationId] = LocationInfoDetail(
                            stationName: stationName,
                            solarSystemName: systemName,
                            security: security
                        )
                        Logger.debug("从数据库加载到空间站信息 - ID: \(stationId), 名称: \(stationName)")
                    }
                }
            }
        }
        
        // 3. 对于仍未解析的ID，尝试作为玩家建筑物查询
        let finalRemainingIds = remainingIds.filter { !locationInfoCache.keys.contains($0) }
        Logger.debug("需要从API获取的建筑物数量: \(finalRemainingIds.count)")
        
        for locationId in finalRemainingIds {
            do {
                Logger.debug("尝试获取建筑物信息 - ID: \(locationId)")
                let structureInfo = try await UniverseStructureAPI.shared.fetchStructureInfo(
                    structureId: locationId,
                    characterId: Int(characterId)
                )
                
                // 获取星系信息
                let systemQuery = """
                    SELECT ss.solarSystemName, u.system_security
                    FROM solarSystems ss
                    JOIN universe u ON u.solarsystem_id = ss.solarSystemID
                    WHERE ss.solarSystemID = ?
                """
                
                if case .success(let rows) = databaseManager.executeQuery(systemQuery, parameters: [structureInfo.solar_system_id]),
                   let row = rows.first,
                   let systemName = row["solarSystemName"] as? String,
                   let security = row["system_security"] as? Double {
                    locationInfoCache[locationId] = LocationInfoDetail(
                        stationName: structureInfo.name,
                        solarSystemName: systemName,
                        security: security
                    )
                    Logger.debug("成功获取建筑物信息 - ID: \(locationId), 名称: \(structureInfo.name)")
                }
            } catch {
                Logger.error("获取建筑物信息失败 - ID: \(locationId), 错误: \(error)")
            }
        }
        
        return locationInfoCache
    }
} 
