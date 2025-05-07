import Foundation

@MainActor
final class FWSystemStateManager {
    static let shared = FWSystemStateManager()
    
    // 缓存相关
    private var systemStates: [Int: FWSystemState] = [:]
    private var lastCalculationTime: Date?
    private let cacheTimeout: TimeInterval = 300  // 5分钟缓存
    
    // 系统名称缓存
    private var systemNameCache: [Int: (en: String, zh: String)] = [:]
    
    private init() {}
    
    // 系统状态结构体
    struct FWSystemState {
        let systemId: Int
        let systemName: String
        let systemType: SystemType
        let ownerFactionId: Int
        let occupierFactionId: Int
        let security: Double
        let constellationName: String
        let regionName: String
        let victoryPoints: Int
        let victoryPointsThreshold: Int
        let contested: String
        let enemyNeighbours: [(id: Int, name: String, factionId: Int)]
        let frontlineNeighbours: [(id: Int, name: String)]
    }
    
    // 计算所有系统状态
    func calculateSystemStates(
        systems: [FWSystem],
        wars: [FWWar],
        systemNeighbours: SystemNeighbours,
        databaseManager: DatabaseManager,
        forceRefresh: Bool = false
    ) async {
        // 检查缓存
        if !forceRefresh,
           let lastCalc = lastCalculationTime,
           Date().timeIntervalSince(lastCalc) < cacheTimeout,
           !systemStates.isEmpty {
            Logger.debug("使用缓存的FW系统状态数据，跳过计算")
            return
        }
        
        Logger.info("开始计算所有FW系统状态")
        
        // 获取主权数据
        var sovereigntyData: [Int: SovereigntyData] = [:]
        do {
            let sovereigntyDataArray = try await SovereigntyDataAPI.shared.fetchSovereigntyData(forceRefresh: false)
            sovereigntyData = Dictionary(uniqueKeysWithValues: sovereigntyDataArray.map { ($0.systemId, $0) })
        } catch {
            Logger.error("获取主权数据失败: \(error)")
        }
        
        // 获取所有星系的中英文名称
        let solarSystemIds = systems.map { $0.solar_system_id }
        let query = "SELECT solarSystemID, solarSystemName, solarSystemName_en FROM solarsystems WHERE solarSystemID IN (\(String(repeating: "?,", count: solarSystemIds.count).dropLast()))"
        if case let .success(rows) = databaseManager.executeQuery(query, parameters: solarSystemIds) {
            systemNameCache = Dictionary(uniqueKeysWithValues: rows.compactMap { row in
                guard let id = row["solarSystemID"] as? Int,
                      let name = row["solarSystemName"] as? String,
                      let nameEn = row["solarSystemName_en"] as? String else {
                    return nil
                }
                return (id, (en: nameEn, zh: name))
            })
        }
        
        // 第一步：计算所有前线星系
        let frontlineSystems = Set(systems.filter { currentSystem in
            let currentNeighbourIds = systemNeighbours[String(currentSystem.solar_system_id)] ?? []
            let systemName = systemNameCache[currentSystem.solar_system_id]?.zh ?? "未知星系"
            
            // 检查是否有敌对邻居
            var enemyNeighbours: [(Int, String, Int)] = []
            let hasEnemyNeighbour = currentNeighbourIds.contains { neighbourId in
                if let neighbourFactionId = getFactionIdForSystem(neighbourId, systems: systems, sovereigntyData: sovereigntyData) {
                    let isEnemy = isEnemyFaction(currentSystem.occupier_faction_id, neighbourFactionId, wars: wars)
                    if isEnemy {
                        let neighbourName = systemNameCache[neighbourId]?.zh ?? "未知星系"
                        enemyNeighbours.append((neighbourId, neighbourName, neighbourFactionId))
                    }
                    return isEnemy
                }
                return false
            }
            
            if hasEnemyNeighbour {
                let enemyNeighboursStr = enemyNeighbours.map { "\($0.1)(ID:\($0.0), 势力:\($0.2))" }.joined(separator: ", ")
                Logger.info("星系 \(currentSystem.solar_system_id) (\(systemName), 势力:\(currentSystem.occupier_faction_id)) 被判定为前线，原因：有敌对邻居 [\(enemyNeighboursStr)]")
            }
            
            return hasEnemyNeighbour
        }.map { $0.solar_system_id })
        
        Logger.info("前线星系数量: \(frontlineSystems.count)")
        
        // 第二步：计算指挥星系
        let commandSystems = Set(systems.filter { currentSystem in
            let currentNeighbourIds = systemNeighbours[String(currentSystem.solar_system_id)] ?? []
            let systemName = systemNameCache[currentSystem.solar_system_id]?.zh ?? "未知星系"
            
            // 检查邻居中是否有前线
            var frontlineNeighbours: [(Int, String)] = []
            let hasFrontlineNeighbour = currentNeighbourIds.contains { neighbourId in
                let isFrontline = frontlineSystems.contains(neighbourId)
                if isFrontline {
                    let neighbourName = systemNameCache[neighbourId]?.zh ?? "未知星系"
                    frontlineNeighbours.append((neighbourId, neighbourName))
                }
                return isFrontline
            }
            
            if hasFrontlineNeighbour {
                let frontlineNeighboursStr = frontlineNeighbours.map { "\($0.1)(ID:\($0.0))" }.joined(separator: ", ")
                Logger.info("星系 \(currentSystem.solar_system_id) (\(systemName), 势力:\(currentSystem.occupier_faction_id)) 被判定为指挥，原因：有前线邻居 [\(frontlineNeighboursStr)]")
            }
            
            return hasFrontlineNeighbour
        }.map { $0.solar_system_id })
        
        Logger.info("指挥星系数量: \(commandSystems.count)")
        
        // 获取所有星系信息
        let systemInfoMap = await getBatchSolarSystemInfo(
            solarSystemIds: solarSystemIds,
            databaseManager: databaseManager
        )
        
        // 存储所有系统状态
        for system in systems {
            let systemName = systemNameCache[system.solar_system_id]?.zh ?? "未知星系"
            let systemInfo = systemInfoMap[system.solar_system_id]
            
            // 获取邻居信息
            let neighbourIds = systemNeighbours[String(system.solar_system_id)] ?? []
            var enemyNeighbours: [(id: Int, name: String, factionId: Int)] = []
            var frontlineNeighbours: [(id: Int, name: String)] = []
            
            for neighbourId in neighbourIds {
                if let neighbourFactionId = getFactionIdForSystem(neighbourId, systems: systems, sovereigntyData: sovereigntyData),
                   isEnemyFaction(system.occupier_faction_id, neighbourFactionId, wars: wars) {
                    let neighbourName = systemNameCache[neighbourId]?.zh ?? "未知星系"
                    enemyNeighbours.append((neighbourId, neighbourName, neighbourFactionId))
                }
                
                if frontlineSystems.contains(neighbourId) {
                    let neighbourName = systemNameCache[neighbourId]?.zh ?? "未知星系"
                    frontlineNeighbours.append((neighbourId, neighbourName))
                }
            }
            
            // 确定系统类型
            let systemType: SystemType
            if frontlineSystems.contains(system.solar_system_id) {
                systemType = .frontline
                Logger.info("星系 \(system.solar_system_id) (\(systemName), 势力:\(system.occupier_faction_id)) 最终被判定为前线")
            } else if commandSystems.contains(system.solar_system_id) {
                systemType = .command
                Logger.info("星系 \(system.solar_system_id) (\(systemName), 势力:\(system.occupier_faction_id)) 最终被判定为指挥")
            } else {
                systemType = .reserve
                Logger.info("星系 \(system.solar_system_id) (\(systemName), 势力:\(system.occupier_faction_id)) 最终被判定为后备")
            }
            
            // 创建系统状态
            let state = FWSystemState(
                systemId: system.solar_system_id,
                systemName: systemName,
                systemType: systemType,
                ownerFactionId: system.owner_faction_id,
                occupierFactionId: system.occupier_faction_id,
                security: systemInfo?.security ?? 0.0,
                constellationName: systemInfo?.constellationName ?? "",
                regionName: systemInfo?.regionName ?? "",
                victoryPoints: system.victory_points,
                victoryPointsThreshold: system.victory_points_threshold,
                contested: system.contested,
                enemyNeighbours: enemyNeighbours,
                frontlineNeighbours: frontlineNeighbours
            )
            
            systemStates[system.solar_system_id] = state
        }
        
        lastCalculationTime = Date()
    }
    
    // 获取系统状态
    func getSystemState(for systemId: Int) -> FWSystemState? {
        return systemStates[systemId]
    }
    
    // 获取所有系统状态
    func getAllSystemStates() -> [FWSystemState] {
        return Array(systemStates.values)
    }
    
    // 获取系统名称
    func getSystemName(for systemId: Int) -> (en: String, zh: String)? {
        return systemNameCache[systemId]
    }
    
    // 辅助函数：获取系统所属势力
    private func getFactionIdForSystem(_ systemId: Int, systems: [FWSystem], sovereigntyData: [Int: SovereigntyData]) -> Int? {
        // 首先在FWSystem中查找
        if let fwSystem = systems.first(where: { $0.solar_system_id == systemId }) {
            Logger.info("星系 \(systemId) 在FWSystem中，使用occupier_faction_id: \(fwSystem.occupier_faction_id)")
            return fwSystem.occupier_faction_id
        }
        // 如果不在FWSystem中，从主权数据中查找
        if let sovereignty = sovereigntyData[systemId] {
            Logger.info("星系 \(systemId) 不在FWSystem中，使用主权数据factionId: \(sovereignty.factionId ?? -1)")
            return sovereignty.factionId
        }
        Logger.info("星系 \(systemId) 既不在FWSystem中，也没有主权数据")
        return nil
    }
    
    // 辅助函数：判断两个势力是否为敌对关系
    private func isEnemyFaction(_ factionId1: Int, _ factionId2: Int, wars: [FWWar]) -> Bool {
        return wars.contains { war in
            (war.faction_id == factionId1 && war.against_id == factionId2) ||
            (war.faction_id == factionId2 && war.against_id == factionId1)
        }
    }
} 