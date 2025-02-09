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

// 添加位置类型枚举
private enum LocationType {
    case solarSystem    // 30000000...39999999
    case station       // 60000000...69999999
    case structure     // >= 100000000
    case unknown
    
    static func from(id: Int64) -> LocationType {
        switch id {
        case 30000000...39999999:
            return .solarSystem
        case 60000000...69999999:
            return .station
        case 100000000...:
            return .structure
        default:
            return .unknown
        }
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
        let validIds = locationIds.filter { $0 > 0 }
        
        if validIds.isEmpty {
            Logger.debug("没有有效的位置ID需要加载")
            return locationInfoCache
        }
        
        Logger.debug("开始加载位置信息 - 有效位置IDs: \(validIds)")
        
        // 按类型分组
        let groupedIds = Dictionary(grouping: validIds) { LocationType.from(id: $0) }
        
        // 1. 处理星系
        if let solarSystemIds = groupedIds[.solarSystem] {
            Logger.debug("加载星系信息 - 数量: \(solarSystemIds.count)")
            let query = """
                SELECT u.solarsystem_id, u.system_security,
                       s.solarSystemName
                FROM universe u
                JOIN solarsystems s ON s.solarSystemID = u.solarsystem_id
                WHERE u.solarsystem_id IN (\(solarSystemIds.map { String($0) }.joined(separator: ",")))
            """
            
            if case .success(let rows) = databaseManager.executeQuery(query) {
                for row in rows {
                    if let systemId = row["solarsystem_id"] as? Int64,
                       let security = row["system_security"] as? Double,
                       let systemName = row["solarSystemName"] as? String {
                        locationInfoCache[systemId] = LocationInfoDetail(
                            stationName: "",
                            solarSystemName: systemName,
                            security: security
                        )
                        Logger.debug("成功加载星系信息 - ID: \(systemId), 名称: \(systemName)")
                    }
                }
            }
        }
        
        // 2. 处理空间站
        if let stationIds = groupedIds[.station] {
            Logger.debug("加载空间站信息 - 数量: \(stationIds.count)")
            let query = """
                SELECT s.stationID, s.stationName,
                       ss.solarSystemName, u.system_security
                FROM stations s
                JOIN solarsystems ss ON s.solarSystemID = ss.solarSystemID
                JOIN universe u ON u.solarsystem_id = ss.solarSystemID
                WHERE s.stationID IN (\(stationIds.map { String($0) }.joined(separator: ",")))
            """
            
            if case .success(let rows) = databaseManager.executeQuery(query) {
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
                        Logger.debug("成功加载空间站信息 - ID: \(stationId), 名称: \(stationName)")
                    }
                }
            }
        }
        
        // 3. 处理建筑物
        if let structureIds = groupedIds[.structure] {
            Logger.debug("加载建筑物信息 - 数量: \(structureIds.count)")
            
            for structureId in structureIds {
                do {
                    let structureInfo = try await UniverseStructureAPI.shared.fetchStructureInfo(
                        structureId: structureId,
                        characterId: Int(characterId)
                    )
                    
                    let query = """
                        SELECT ss.solarSystemName, u.system_security
                        FROM solarsystems ss
                        JOIN universe u ON u.solarsystem_id = ss.solarSystemID
                        WHERE ss.solarSystemID = ?
                    """
                    
                    if case .success(let rows) = databaseManager.executeQuery(query, parameters: [structureInfo.solar_system_id]),
                       let row = rows.first,
                       let systemName = row["solarSystemName"] as? String,
                       let security = row["system_security"] as? Double {
                        locationInfoCache[structureId] = LocationInfoDetail(
                            stationName: structureInfo.name,
                            solarSystemName: systemName,
                            security: security
                        )
                        Logger.debug("成功加载建筑物信息 - ID: \(structureId), 名称: \(structureInfo.name)")
                    }
                } catch {
                    Logger.error("加载建筑物信息失败 - ID: \(structureId), 错误: \(error)")
                }
            }
        }
        
        return locationInfoCache
    }
} 
