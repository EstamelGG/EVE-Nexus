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
        
        if locationIds.isEmpty {
            return locationInfoCache
        }
        
        // 1. 从数据库加载空间站信息
        let query = """
            SELECT s.stationID, s.stationName, ss.solarSystemName, u.system_security as security
            FROM stations s
            JOIN solarSystems ss ON s.solarSystemID = ss.solarSystemID
            JOIN universe u ON u.solarsystem_id = ss.solarSystemID
            WHERE s.stationID IN (\(locationIds.map { String($0) }.joined(separator: ",")))
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
                }
            }
        }
        
        // 2. 处理未在数据库中找到的位置（玩家建筑物）
        let remainingLocationIds = locationIds.filter { !locationInfoCache.keys.contains($0) }
        
        for locationId in remainingLocationIds {
            do {
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
                
                if case .success(let rows) = databaseManager.executeQuery(systemQuery, parameters: [String(structureInfo.solar_system_id)]),
                   let row = rows.first,
                   let solarSystemName = row["solarSystemName"] as? String,
                   let security = row["security"] as? Double {
                    locationInfoCache[locationId] = LocationInfoDetail(
                        stationName: structureInfo.name,
                        solarSystemName: solarSystemName,
                        security: security
                    )
                }
            } catch {
                Logger.error("获取建筑物信息失败 - ID: \(locationId), 错误: \(error)")
            }
        }
        
        return locationInfoCache
    }
} 