import Foundation

@MainActor
final class FWSystemStateManager {
    static let shared = FWSystemStateManager()

    // 缓存相关
    private var systemStates: [Int: FWSystemState] = [:]
    private var lastCalculationTime: Date?
    private let cacheTimeout: TimeInterval = 300 // 5分钟缓存

    private init() {}

    /// 星系状态结构体
    struct FWSystemState {
        let systemId: Int
        let systemType: SystemType
        let ownerFactionId: Int
        let occupierFactionId: Int
        let security: Double
        let constellationId: Int
        let regionId: Int
        let victoryPoints: Int
        let victoryPointsThreshold: Int
        let contested: String
        let enemyNeighbours: [(id: Int, factionId: Int)]
        let frontlineNeighbours: [Int]
    }

    /// 计算所有星系状态
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
           !systemStates.isEmpty
        {
            Logger.debug("使用缓存的FW星系状态数据，跳过计算")
            return
        }

        Logger.info("开始计算所有FW星系状态")

        // 获取主权数据
        var sovereigntyData: [Int: SovereigntyData] = [:]
        do {
            let sovereigntyDataArray = try await SovereigntyDataAPI.shared.fetchSovereigntyData(
                forceRefresh: false
            )
            sovereigntyData = Dictionary(
                uniqueKeysWithValues: sovereigntyDataArray.map { ($0.systemId, $0) }
            )
        } catch {
            Logger.error("获取主权数据失败: \(error)")
        }

        // 第一步：计算所有前线星系
        let frontlineSystems = Set(
            systems.filter { currentSystem in
                let currentNeighbourIds =
                    systemNeighbours[String(currentSystem.solar_system_id)] ?? []
                // 检查是否有敌对邻居
                return currentNeighbourIds.contains { neighbourId in
                    if let neighbourFactionId = getFactionIdForSystem(
                        neighbourId, systems: systems, sovereigntyData: sovereigntyData
                    ) {
                        return isEnemyFaction(
                            currentSystem.occupier_faction_id, neighbourFactionId, wars: wars
                        )
                    }
                    return false
                }

                // if hasEnemyNeighbour {
                // let enemyNeighboursStr = enemyNeighbours.map { "\($0.1)(ID:\($0.0), 势力:\($0.2))" }.joined(separator: ", ")
                //  Logger.info("星系 \(currentSystem.solar_system_id) (\(systemName), 势力:\(currentSystem.occupier_faction_id)) 被判定为前线，原因：有敌对邻居 [\(enemyNeighboursStr)]")
                // }

            }.map { $0.solar_system_id }
        )

        Logger.info("前线星系数量: \(frontlineSystems.count)")

        // 第二步：计算指挥星系
        let commandSystems = Set(
            systems.filter { currentSystem in
                let currentNeighbourIds =
                    systemNeighbours[String(currentSystem.solar_system_id)] ?? []

                // 检查邻居中是否有前线
                return currentNeighbourIds.contains { neighbourId in
                    frontlineSystems.contains(neighbourId)
                }

                // if hasFrontlineNeighbour {
                // let frontlineNeighboursStr = frontlineNeighbours.map { "\($0.1)(ID:\($0.0))" }.joined(separator: ", ")
                // Logger.info("星系 \(currentSystem.solar_system_id) (\(systemName), 势力:\(currentSystem.occupier_faction_id)) 被判定为指挥，原因：有前线邻居 [\(frontlineNeighboursStr)]")
                // }

            }.map { $0.solar_system_id }
        )

        Logger.info("指挥星系数量: \(commandSystems.count)")

        // 获取所有星系信息
        let systemInfoMap = await getBatchSolarSystemInfo(
            solarSystemIds: systems.map(\.solar_system_id),
            databaseManager: databaseManager
        )

        // 存储所有星系状态
        for system in systems {
            let systemInfo = systemInfoMap[system.solar_system_id]

            // 获取邻居信息
            let neighbourIds = systemNeighbours[String(system.solar_system_id)] ?? []
            var enemyNeighbours: [(id: Int, factionId: Int)] = []
            var frontlineNeighbours: [Int] = []

            for neighbourId in neighbourIds {
                if let neighbourFactionId = getFactionIdForSystem(
                    neighbourId, systems: systems, sovereigntyData: sovereigntyData
                ),
                    isEnemyFaction(system.occupier_faction_id, neighbourFactionId, wars: wars)
                {
                    enemyNeighbours.append((neighbourId, neighbourFactionId))
                }

                if frontlineSystems.contains(neighbourId) {
                    frontlineNeighbours.append(neighbourId)
                }
            }

            // 确定星系类型
            let systemType: SystemType
            if frontlineSystems.contains(system.solar_system_id) {
                systemType = .frontline
                // Logger.info("星系 \(system.solar_system_id) (\(systemName), 势力:\(system.occupier_faction_id)) 最终被判定为前线")
            } else if commandSystems.contains(system.solar_system_id) {
                systemType = .command
                // Logger.info("星系 \(system.solar_system_id) (\(systemName), 势力:\(system.occupier_faction_id)) 最终被判定为指挥")
            } else {
                systemType = .reserve
                // Logger.info("星系 \(system.solar_system_id) (\(systemName), 势力:\(system.occupier_faction_id)) 最终被判定为后备")
            }

            // 创建星系状态
            let state = FWSystemState(
                systemId: system.solar_system_id,
                systemType: systemType,
                ownerFactionId: system.owner_faction_id,
                occupierFactionId: system.occupier_faction_id,
                security: systemInfo?.security ?? 0.0,
                constellationId: systemInfo?.constellationId ?? 0,
                regionId: systemInfo?.regionId ?? 0,
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

    /// 获取星系状态
    func getSystemState(for systemId: Int) -> FWSystemState? {
        return systemStates[systemId]
    }

    /// 辅助函数：获取星系所属势力
    private func getFactionIdForSystem(
        _ systemId: Int, systems: [FWSystem], sovereigntyData: [Int: SovereigntyData]
    ) -> Int? {
        // 首先在FWSystem中查找
        if let fwSystem = systems.first(where: { $0.solar_system_id == systemId }) {
            // Logger.info("星系 \(systemId) 在FWSystem中，使用occupier_faction_id: \(fwSystem.occupier_faction_id)")
            return fwSystem.occupier_faction_id
        }
        // 如果不在FWSystem中，从主权数据中查找
        if let sovereignty = sovereigntyData[systemId] {
            // Logger.info("星系 \(systemId) 不在FWSystem中，使用主权数据factionId: \(sovereignty.factionId ?? -1)")
            return sovereignty.factionId
        }
        // Logger.info("星系 \(systemId) 既不在FWSystem中，也没有主权数据")
        return nil
    }

    /// 辅助函数：判断两个势力是否为敌对关系
    private func isEnemyFaction(_ factionId1: Int, _ factionId2: Int, wars: [FWWar]) -> Bool {
        return wars.contains { war in
            (war.faction_id == factionId1 && war.against_id == factionId2)
                || (war.faction_id == factionId2 && war.against_id == factionId1)
        }
    }
}
