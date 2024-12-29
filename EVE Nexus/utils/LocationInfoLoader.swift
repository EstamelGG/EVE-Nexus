import Foundation

// 位置信息模型
public struct LocationInfoDetail {
    public let stationName: String
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
        
        // 1. 从数据库加载空间站信息
        let query = """
            SELECT s.stationID, s.stationName, ss.solarSystemName, u.system_security as security
            FROM stations s
            JOIN solarSystems ss ON s.solarSystemID = ss.solarSystemID
            JOIN universe u ON u.solarsystem_id = ss.solarSystemID
            WHERE s.stationID IN (\(validLocationIds.map { String($0) }.joined(separator: ",")))
        """
        
        if case .success(let rows) = databaseManager.executeQuery(query) {
            for row in rows {
                if let stationIdInt = (row["stationID"] as? NSNumber)?.int64Value,
                   let stationName = row["stationName"] as? String,
                   let solarSystemName = row["solarSystemName"] as? String,
                   let security = row["security"] as? Double {
                    locationInfoCache[stationIdInt] = LocationInfoDetail(
                        stationName: stationName,
                        solarSystemName: solarSystemName,
                        security: security
                    )
                    Logger.debug("从数据库加载到空间站信息 - ID: \(stationIdInt), 名称: \(stationName)")
                }
            }
        }
        
        // 2. 处理未在数据库中找到的位置（玩家建筑物）
        let remainingLocationIds = validLocationIds.filter { !locationInfoCache.keys.contains($0) }
        Logger.debug("需要从API获取的建筑物数量: \(remainingLocationIds.count)")
        
        for locationId in remainingLocationIds {
            do {
                Logger.debug("尝试获取建筑物信息 - ID: \(locationId)")
                let structureInfo = try await UniverseStructureAPI.shared.fetchStructureInfo(
                    structureId: locationId,
                    characterId: Int(characterId)
                )
                
                // 获取星系信息
                let systemQuery = """
                    SELECT ss.solarSystemName, u.system_security as security
                    FROM solarSystems ss
                    JOIN universe u ON u.solarsystem_id = ss.solarSystemID
                    WHERE ss.solarSystemID = ?
                """
                
                if case .success(let rows) = databaseManager.executeQuery(systemQuery, parameters: [structureInfo.solar_system_id]),
                   let row = rows.first,
                   let solarSystemName = row["solarSystemName"] as? String,
                   let security = row["security"] as? Double {
                    locationInfoCache[locationId] = LocationInfoDetail(
                        stationName: structureInfo.name,
                        solarSystemName: solarSystemName,
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