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

    private var useEnglishSystemNames: Bool {
        UserDefaults.standard.bool(forKey: "useEnglishSystemNames")
    }

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
        Logger.debug("位置ID分组结果: \(groupedIds.mapValues { $0.count })")

        // 1. 处理星系
        if let solarSystemIds = groupedIds[.solarSystem] {
            Logger.debug("加载星系信息 - 数量: \(solarSystemIds.count), IDs: \(solarSystemIds)")
            let query = """
                    SELECT u.solarsystem_id, u.system_security,
                           s.solarSystemName, s.solarSystemName_en
                    FROM universe u
                    JOIN solarsystems s ON s.solarSystemID = u.solarsystem_id
                    WHERE u.solarsystem_id IN (\(solarSystemIds.map { String($0) }.joined(separator: ",")))
                """

            if case let .success(rows) = databaseManager.executeQuery(query) {
                for row in rows {
                    if let systemId = row["solarsystem_id"] as? Int64,
                        let security = row["system_security"] as? Double,
                        let systemNameLocal = row["solarSystemName"] as? String,
                        let systemNameEn = row["solarSystemName_en"] as? String
                    {
                        let systemName = useEnglishSystemNames ? systemNameEn : systemNameLocal
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
            Logger.debug("加载空间站信息 - 数量: \(stationIds.count), IDs: \(stationIds)")
            let query = """
                    SELECT s.stationID, s.stationName,
                           ss.solarSystemName, ss.solarSystemName_en, u.system_security
                    FROM stations s
                    JOIN solarsystems ss ON s.solarSystemID = ss.solarSystemID
                    JOIN universe u ON u.solarsystem_id = ss.solarSystemID
                    WHERE s.stationID IN (\(stationIds.map { String($0) }.joined(separator: ",")))
                """

            if case let .success(rows) = databaseManager.executeQuery(query) {
                Logger.debug("SQL查询返回行数: \(rows.count)")
                for row in rows {
                    Logger.debug("处理空间站行: \(row)")
                    if let stationId = row["stationID"] as? Int,
                        let stationName = row["stationName"] as? String,
                        let systemNameLocal = row["solarSystemName"] as? String,
                        let systemNameEn = row["solarSystemName_en"] as? String,
                        let security = row["system_security"] as? Double
                    {
                        let systemName = useEnglishSystemNames ? systemNameEn : systemNameLocal
                        let stationIdInt64 = Int64(stationId)
                        locationInfoCache[stationIdInt64] = LocationInfoDetail(
                            stationName: stationName,
                            solarSystemName: systemName,
                            security: security
                        )
                        Logger.debug("成功加载空间站信息 - ID: \(stationIdInt64), 名称: \(stationName)")
                    } else {
                        Logger.error("空间站数据类型转换失败 - Row: \(row)")
                        Logger.error(
                            "类型信息 - stationID: \(type(of: row["stationID"])), stationName: \(type(of: row["stationName"])), systemName: \(type(of: row["solarSystemName"])), security: \(type(of: row["system_security"]))"
                        )
                    }
                }
            } else {
                Logger.error("空间站SQL查询失败")
            }
        }

        // 3. 处理建筑物
        if let structureIds = groupedIds[.structure] {
            Logger.debug("加载建筑物信息 - 数量: \(structureIds.count), IDs: \(structureIds)")

            for structureId in structureIds {
                do {
                    let structureInfo = try await UniverseStructureAPI.shared.fetchStructureInfo(
                        structureId: structureId,
                        characterId: Int(characterId)
                    )

                    let query = """
                            SELECT ss.solarSystemName, ss.solarSystemName_en, u.system_security
                            FROM solarsystems ss
                            JOIN universe u ON u.solarsystem_id = ss.solarSystemID
                            WHERE ss.solarSystemID = ?
                        """

                    if case let .success(rows) = databaseManager.executeQuery(
                        query, parameters: [structureInfo.solar_system_id]
                    ),
                        let row = rows.first,
                        let systemNameLocal = row["solarSystemName"] as? String,
                        let systemNameEn = row["solarSystemName_en"] as? String,
                        let security = row["system_security"] as? Double
                    {
                        let systemName = useEnglishSystemNames ? systemNameEn : systemNameLocal
                        locationInfoCache[structureId] = LocationInfoDetail(
                            stationName: structureInfo.name,
                            solarSystemName: systemName,
                            security: security
                        )
                        Logger.debug("成功加载建筑物信息 - ID: \(structureId), 名称: \(structureInfo.name)")
                    }
                } catch let error as NetworkError {
                    if case let .httpError(statusCode, _) = error, statusCode == 403 {
                        // 如果是403错误，说明没有访问权限，使用有限的信息
                        locationInfoCache[structureId] = LocationInfoDetail(
                            stationName: NSLocalizedString("Structure_No_Access", comment: ""),
                            solarSystemName: NSLocalizedString("Unknown_System", comment: ""),
                            security: 0.0
                        )
                        Logger.debug("建筑物无访问权限，使用默认信息 - ID: \(structureId)")
                    } else {
                        Logger.error("加载建筑物信息失败 - ID: \(structureId), 错误: \(error)")
                    }
                } catch {
                    Logger.error("加载建筑物信息失败 - ID: \(structureId), 错误: \(error)")
                }
            }
        }

        // 记录未能加载的位置ID
        let loadedIds = Set(locationInfoCache.keys)
        let unloadedIds = validIds.subtracting(loadedIds)
        if !unloadedIds.isEmpty {
            Logger.error("以下位置ID未能加载信息: \(unloadedIds)")
        }

        return locationInfoCache
    }
}
