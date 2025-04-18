import Foundation
import SwiftUI

// 定义行星资源链信息结构体
struct PIResourceChainInfo {
    // 资源ID
    let resourceId: Int
    // 资源名称
    let resourceName: String
    // 资源图标
    let iconFileName: String
    // 资源等级 (P0-P4)
    let resourceLevel: Int
    // 生产该资源所需的上一级资源ID列表
    let requiredResources: [Int]
    // 生产该资源所需的行星类型列表
    let requiredPlanetTypes: [Int]
    // 行星类型名称
    let planetTypeNames: [String]
    // 是否可以在指定星系中生产
    var canProduce: Bool = false
    // 生产该资源所需的行星类型在指定星系中是否存在
    var availablePlanetTypes: [Int] = []
    // 生产该资源所需的行星类型在指定星系中是否全部存在
    var allRequiredPlanetTypesAvailable: Bool = false
    // 生产该资源所需的行星类型在指定星系中是否存在部分
    var someRequiredPlanetTypesAvailable: Bool = false
}

// 定义行星资源链计算器
class PIResourceChainCalculator {
    private let databaseManager: DatabaseManager
    private let resourceCache: PIResourceCache
    private var planetTypeCache: [Int: [Int]] = [:]

    init(
        databaseManager: DatabaseManager = DatabaseManager.shared,
        resourceCache: PIResourceCache = PIResourceCache.shared
    ) {
        self.databaseManager = databaseManager
        self.resourceCache = resourceCache
    }

    // 一次性计算完整的资源链，包括所有层级
    func calculateFullResourceChain(
        for resourceId: Int, in systemIds: [Int],
        completion: @escaping ([PIResourceChainInfo]?) -> Void
    ) {
        // 首先获取资源的基本信息
        guard let resourceInfo = resourceCache.getResourceInfo(for: resourceId),
            let resourceLevel = resourceCache.getResourceLevel(for: resourceId)
        else {
            Logger.error("无法获取资源 \(resourceId) 的基本信息")
            completion(nil)
            return
        }

        // 递归获取资源链
        var resourceChain: [PIResourceChainInfo] = []
        var processedResourceIds = Set<Int>()

        // 添加当前资源
        let currentResource = PIResourceChainInfo(
            resourceId: resourceId,
            resourceName: resourceInfo.name,
            iconFileName: resourceInfo.iconFileName,
            resourceLevel: resourceLevel.rawValue,
            requiredResources: [],
            requiredPlanetTypes: [],
            planetTypeNames: []
        )

        resourceChain.append(currentResource)
        processedResourceIds.insert(resourceId)

        // 递归获取所有资源，包括最底层的P0资源
        recursivelyGetAllResources(
            for: resourceId,
            resourceChain: &resourceChain,
            processedResourceIds: &processedResourceIds
        )

        // 一次性查询所有资源的行星类型数据
        loadPlanetTypesForResources(resourceChain.map { $0.resourceId })

        // 获取每个资源所需的行星类型
        for i in 0..<resourceChain.count {
            let requiredPlanetTypes = getRequiredPlanetTypes(for: resourceChain[i].resourceId)
            let planetTypeNames = getPlanetTypeNames(for: requiredPlanetTypes)

            resourceChain[i] = PIResourceChainInfo(
                resourceId: resourceChain[i].resourceId,
                resourceName: resourceChain[i].resourceName,
                iconFileName: resourceChain[i].iconFileName,
                resourceLevel: resourceChain[i].resourceLevel,
                requiredResources: resourceChain[i].requiredResources,
                requiredPlanetTypes: requiredPlanetTypes,
                planetTypeNames: planetTypeNames
            )
        }

        // 检查每个资源在指定星系中是否可以生产
        checkResourceAvailability(in: systemIds, resourceChain: &resourceChain)

        // 返回完整的资源链
        completion(resourceChain)
    }

    // 递归获取所有资源，包括最底层的P0资源
    private func recursivelyGetAllResources(
        for resourceId: Int,
        resourceChain: inout [PIResourceChainInfo],
        processedResourceIds: inout Set<Int>
    ) {
        // 首先检查资源等级，如果是P0资源，直接返回
        if let resourceLevel = resourceCache.getResourceLevel(for: resourceId),
            resourceLevel == .p0
        {
            return
        }

        // 使用缓存获取配方信息
        guard let schematic = resourceCache.getSchematic(for: resourceId) else {
            Logger.error("无法获取资源 \(resourceId) 的配方数据. error 2")
            return
        }

        // 使用缓存的输入资源ID
        let requiredResourceIds = schematic.inputTypeIds

        // 更新当前资源的所需资源列表
        if let index = resourceChain.firstIndex(where: { $0.resourceId == resourceId }) {
            resourceChain[index] = PIResourceChainInfo(
                resourceId: resourceChain[index].resourceId,
                resourceName: resourceChain[index].resourceName,
                iconFileName: resourceChain[index].iconFileName,
                resourceLevel: resourceChain[index].resourceLevel,
                requiredResources: requiredResourceIds,
                requiredPlanetTypes: resourceChain[index].requiredPlanetTypes,
                planetTypeNames: resourceChain[index].planetTypeNames
            )
        }

        // 递归处理每个所需资源，直到找到所有P0资源
        for requiredId in requiredResourceIds {
            let alreadyProcessed = processedResourceIds.contains(requiredId)

            // 获取资源信息
            guard let resourceInfo = resourceCache.getResourceInfo(for: requiredId),
                let resourceLevel = resourceCache.getResourceLevel(for: requiredId)
            else {
                continue
            }

            // 只有在未处理过的情况下才添加资源到链中
            if !alreadyProcessed {
                let requiredResource = PIResourceChainInfo(
                    resourceId: requiredId,
                    resourceName: resourceInfo.name,
                    iconFileName: resourceInfo.iconFileName,
                    resourceLevel: resourceLevel.rawValue,
                    requiredResources: [],
                    requiredPlanetTypes: [],
                    planetTypeNames: []
                )

                resourceChain.append(requiredResource)
                processedResourceIds.insert(requiredId)
            }

            // 即使已经处理过，也需要继续递归，以便找到所有P0资源
            recursivelyGetAllResources(
                for: requiredId,
                resourceChain: &resourceChain,
                processedResourceIds: &processedResourceIds
            )
        }
    }

    // 一次性加载所有资源的行星类型数据
    private func loadPlanetTypesForResources(_ resourceIds: [Int]) {
        Logger.info("开始加载资源行星类型数据，资源ID: \(resourceIds)")
        let query = """
                WITH ResourceHarvester AS (
                    SELECT DISTINCT ph.typeid as resource_id, ph.harvest_typeid
                    FROM planetResourceHarvest ph
                    WHERE ph.typeid IN (\(resourceIds.map { String($0) }.joined(separator: ",")))
                ),
                PlanetTypes AS (
                    SELECT rh.resource_id, ta.value as planet_type_id
                    FROM ResourceHarvester rh
                    JOIN typeAttributes ta ON ta.type_id = rh.harvest_typeid
                    WHERE ta.attribute_id = 1632
                )
                SELECT resource_id, GROUP_CONCAT(planet_type_id) as planet_types
                FROM PlanetTypes
                GROUP BY resource_id
            """

        if case let .success(rows) = databaseManager.executeQuery(query) {
            Logger.info("查询到 \(rows.count) 条行星类型数据")
            for row in rows {
                if let resourceId = (row["resource_id"] as? Double).map({ Int($0) })
                    ?? (row["resource_id"] as? Int),
                    let planetTypesStr = row["planet_types"] as? String
                {
                    // 将字符串按逗号分割，并处理每个数值
                    let planetTypes =
                        planetTypesStr
                        .split(separator: ",")
                        .compactMap { str -> Int? in
                            // 移除可能的空格并转换为Double，然后转为Int
                            let cleanStr = str.trimmingCharacters(in: .whitespaces)
                            if let doubleValue = Double(cleanStr) {
                                return Int(doubleValue)
                            }
                            return nil
                        }
                    planetTypeCache[resourceId] = planetTypes
                    // Logger.info("资源 \(resourceId) 的行星类型: \(planetTypes)")
                }
            }
        } else {
            Logger.error("加载行星类型数据失败")
        }
    }

    // 从缓存中获取资源所需的行星类型
    private func getRequiredPlanetTypes(for resourceId: Int) -> [Int] {
        let types = planetTypeCache[resourceId] ?? []
        // Logger.info("获取资源 \(resourceId) 的行星类型: \(types)")
        return types
    }

    // 获取行星类型名称
    private func getPlanetTypeNames(for planetTypes: [Int]) -> [String] {
        // 如果没有行星类型，直接返回空数组
        if planetTypes.isEmpty {
            return []
        }

        Logger.info("查询行星类型名称，类型ID: \(planetTypes)")
        let query = """
                SELECT type_id, name
                FROM types
                WHERE type_id IN (\(planetTypes.map { String($0) }.joined(separator: ",")))
            """

        var planetTypeNames: [String] = []

        if case let .success(rows) = databaseManager.executeQuery(query) {
            for row in rows {
                if let name = row["name"] as? String {
                    planetTypeNames.append(name)
                }
            }
        }

        // Logger.info("查询到的行星类型名称: \(planetTypeNames)")
        return planetTypeNames
    }

    // 检查资源在指定星系中是否可以生产
    private func checkResourceAvailability(
        in systemIds: [Int], resourceChain: inout [PIResourceChainInfo]
    ) {
        // 查询指定星系中的行星类型
        let planetQuery = """
                SELECT 
                    solarsystem_id,
                    temperate,
                    barren,
                    oceanic,
                    ice,
                    gas,
                    lava,
                    storm,
                    plasma
                FROM universe
                WHERE solarsystem_id IN (\(systemIds.map { String($0) }.joined(separator: ",")))
            """

        // 如果查询失败，将所有资源标记为不可生产，但不中断整个流程
        guard case let .success(planetRows) = databaseManager.executeQuery(planetQuery) else {
            Logger.error("无法查询行星数据，将所有资源标记为不可生产")
            for i in 0..<resourceChain.count {
                resourceChain[i] = PIResourceChainInfo(
                    resourceId: resourceChain[i].resourceId,
                    resourceName: resourceChain[i].resourceName,
                    iconFileName: resourceChain[i].iconFileName,
                    resourceLevel: resourceChain[i].resourceLevel,
                    requiredResources: resourceChain[i].requiredResources,
                    requiredPlanetTypes: resourceChain[i].requiredPlanetTypes,
                    planetTypeNames: resourceChain[i].planetTypeNames,
                    canProduce: false,
                    availablePlanetTypes: [],
                    allRequiredPlanetTypesAvailable: false,
                    someRequiredPlanetTypesAvailable: false
                )
            }
            return
        }

        // 创建星系ID到行星类型的映射
        var systemToPlanetTypes: [Int: Set<Int>] = [:]

        for row in planetRows {
            if let systemId = row["solarsystem_id"] as? Int {
                var planetTypes = Set<Int>()

                // 使用PlanetaryUtils.columnToPlanetType进行映射
                for (columnName, typeId) in PlanetaryUtils.columnToPlanetType {
                    if let value = row[columnName] as? Int, value > 0 {
                        planetTypes.insert(typeId)
                    }
                }

                systemToPlanetTypes[systemId] = planetTypes
            }
        }

        // 合并所有星系的行星类型
        var allAvailablePlanetTypes = Set<Int>()
        for planetTypes in systemToPlanetTypes.values {
            allAvailablePlanetTypes.formUnion(planetTypes)
        }

        // 更新资源链中每个资源的可用性
        for i in 0..<resourceChain.count {
            let requiredPlanetTypes = Set(resourceChain[i].requiredPlanetTypes)

            // 检查是否有任何所需行星类型可用
            let availablePlanetTypes = requiredPlanetTypes.intersection(allAvailablePlanetTypes)

            // 检查是否所有所需行星类型都可用
            let allRequiredPlanetTypesAvailable =
                !requiredPlanetTypes.isEmpty
                && requiredPlanetTypes.isSubset(of: allAvailablePlanetTypes)

            // 检查是否部分所需行星类型可用
            let someRequiredPlanetTypesAvailable = !availablePlanetTypes.isEmpty

            // 更新资源信息
            resourceChain[i] = PIResourceChainInfo(
                resourceId: resourceChain[i].resourceId,
                resourceName: resourceChain[i].resourceName,
                iconFileName: resourceChain[i].iconFileName,
                resourceLevel: resourceChain[i].resourceLevel,
                requiredResources: resourceChain[i].requiredResources,
                requiredPlanetTypes: resourceChain[i].requiredPlanetTypes,
                planetTypeNames: resourceChain[i].planetTypeNames,
                canProduce: allRequiredPlanetTypesAvailable,
                availablePlanetTypes: Array(availablePlanetTypes),
                allRequiredPlanetTypesAvailable: allRequiredPlanetTypesAvailable,
                someRequiredPlanetTypesAvailable: someRequiredPlanetTypesAvailable
            )
        }
    }
}
