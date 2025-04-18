import Foundation

// 行星资源计算结果
struct PlanetaryResourceResult {
    var typeId: Int
    var name: String
    var quantity: Double
    var depth: Int  // 用于记录资源层级深度
}

// 资源可用行星结果
struct ResourcePlanetResult {
    var resourceId: Int
    var resourceName: String
    var availablePlanets: [(id: Int, name: String, iconFileName: String)]
}

// 星系评分结果
struct SystemScoreResult {
    var systemId: Int
    var systemName: String
    var regionId: Int
    var regionName: String
    var security: Double
    var score: Double
    var availableResources: [Int: Int]
    var missingResources: [Int]
    var additionalResources: [Int: (resourceId: Int, jumps: Int)]
}

class PlanetaryResourceCalculator {
    private let databaseManager: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    // 计算行星产品所需的基础资源
    func calculateBaseResources(for typeId: Int) -> [PlanetaryResourceResult] {
        var baseResourcesWithDepth: [(typeId: Int, depth: Int)] = []  // 存储基础资源ID和深度
        var processedTypes = Set<Int>()  // 用于检测循环依赖
        processedTypes.insert(typeId)  // 将初始产品ID加入已处理集合

        // 存储每一层级需要查询的资源ID
        var currentLevelTypeIds = [typeId]
        var depth = 0

        while !currentLevelTypeIds.isEmpty {
            // 构建IN查询
            let query = """
                    SELECT ps.input_typeid, ps.input_value, ps.output_value, ps.output_typeid
                    FROM planetSchematics ps
                    WHERE ps.output_typeid IN (\(currentLevelTypeIds.map { String($0) }.joined(separator: ",")))
                """

            var nextLevelTypeIds = Set<Int>()
            var currentLevelHasRecipes = false

            if case let .success(rows) = databaseManager.executeQuery(query) {
                for row in rows {
                    currentLevelHasRecipes = true
                    guard let inputTypeIdsStr = row["input_typeid"] as? String,
                        let inputValuesStr = row["input_value"] as? String
                    else {
                        continue
                    }

                    // 分割输入类型ID和数量
                    let inputTypeIds = inputTypeIdsStr.split(separator: ",").compactMap { Int($0) }
                    let inputValues = inputValuesStr.split(separator: ",").compactMap { Int($0) }

                    // 确保数据完整性
                    guard inputTypeIds.count == inputValues.count else { continue }

                    // 添加下一层级需要查询的资源ID
                    for inputTypeId in inputTypeIds {
                        if !processedTypes.contains(inputTypeId) {
                            nextLevelTypeIds.insert(inputTypeId)
                            processedTypes.insert(inputTypeId)
                        }
                    }
                }
            }

            // 如果这一层级的资源都没有配方，且不是初始产品，说明它们是基础资源
            if !currentLevelHasRecipes {
                for resourceId in currentLevelTypeIds {
                    if resourceId != typeId {  // 排除初始产品
                        baseResourcesWithDepth.append((typeId: resourceId, depth: depth))
                    }
                }
            }

            // 准备下一层级的查询
            currentLevelTypeIds = Array(nextLevelTypeIds)
            depth += 1
        }

        // 所有溯源完成后，一次性查询所有基础资源的名称
        if !baseResourcesWithDepth.isEmpty {
            let allResourceIds = baseResourcesWithDepth.map { $0.typeId }
            let nameQuery = """
                    SELECT type_id, name
                    FROM types
                    WHERE type_id IN (\(allResourceIds.map { String($0) }.joined(separator: ",")))
                """

            var results: [PlanetaryResourceResult] = []
            if case let .success(nameRows) = databaseManager.executeQuery(nameQuery) {
                // 创建ID到名称的映射
                var nameMap: [Int: String] = [:]
                for row in nameRows {
                    if let typeId = row["type_id"] as? Int,
                        let name = row["name"] as? String
                    {
                        nameMap[typeId] = name
                    }
                }

                // 使用映射创建最终结果
                for resource in baseResourcesWithDepth {
                    results.append(
                        PlanetaryResourceResult(
                            typeId: resource.typeId,
                            name: nameMap[resource.typeId] ?? "未知资源",
                            quantity: 1.0,
                            depth: resource.depth
                        ))
                }

                // 记录找到的基础资源
                Logger.info("产品需要以下基础资源：")
                for result in results.sorted(by: { $0.depth < $1.depth }) {
                    Logger.info(
                        "资源: \(result.name) (ID: \(result.typeId)), 数量: \(String(format: "%.2f", result.quantity)), 深度: \(result.depth)"
                    )
                }

                // 返回排序后的结果
                return results.sorted { $0.depth < $1.depth }
            }
        }

        return []
    }

    // 查找资源可用的行星类型
    func findResourcePlanets(for resourceIds: [Int]) -> [ResourcePlanetResult] {
        var results: [ResourcePlanetResult] = []

        // 一次性联合查询获取所有信息
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
                SELECT 
                    pt.resource_id,
                    r.name as resource_name,
                    pt.planet_type_id,
                    p.name as planet_name,
                    p.icon_filename as iconFileName
                FROM PlanetTypes pt
                JOIN types r ON r.type_id = pt.resource_id
                JOIN types p ON p.type_id = pt.planet_type_id
                ORDER BY pt.resource_id, pt.planet_type_id
            """

        if case let .success(rows) = databaseManager.executeQuery(query) {
            var currentResourceId: Int?
            var currentResourceName: String?
            var currentPlanets: [(id: Int, name: String, iconFileName: String)] = []

            // 处理查询结果
            for row in rows {
                guard let resourceId = row["resource_id"] as? Int,
                    let resourceName = row["resource_name"] as? String,
                    let iconFileName = row["iconFileName"] as? String,
                    let planetTypeId = (row["planet_type_id"] as? Double).map({ Int($0) })
                        ?? (row["planet_type_id"] as? Int),
                    let planetName = row["planet_name"] as? String
                else {
                    continue
                }

                // 如果是新的资源，保存之前的结果并开始新的收集
                if currentResourceId != resourceId {
                    if let id = currentResourceId, let name = currentResourceName {
                        results.append(
                            ResourcePlanetResult(
                                resourceId: id,
                                resourceName: name,
                                availablePlanets: currentPlanets
                            ))
                    }

                    currentResourceId = resourceId
                    currentResourceName = resourceName
                    currentPlanets = []
                }

                currentPlanets.append(
                    (id: planetTypeId, name: planetName, iconFileName: iconFileName))
            }

            // 添加最后一个资源的结果
            if let id = currentResourceId, let name = currentResourceName {
                results.append(
                    ResourcePlanetResult(
                        resourceId: id,
                        resourceName: name,
                        availablePlanets: currentPlanets
                    ))
            }
        }

        return results
    }

    // 计算星系评分
    func calculateSystemScores(
        for systems: Set<Int>,
        requiredResources: [PlanetaryResourceResult],
        resourcePlanets: [ResourcePlanetResult],
        maxJumps: Int,
        starMap: [String: [Int]]
    ) -> [SystemScoreResult] {
        Logger.debug("开始计算星系评分，需要计算的星系数量: \(systems.count)，需要的资源数量: \(requiredResources.count)")
        Logger.debug(
            "需要的资源列表: \(requiredResources.map { "\($0.name)(ID: \($0.typeId))" }.joined(separator: ", "))"
        )
        Logger.debug("最大允许跳数: \(maxJumps)")

        var results: [SystemScoreResult] = []

        // 创建资源ID到行星类型的映射
        var resourceToPlanetTypes: [Int: Set<Int>] = [:]
        for result in resourcePlanets {
            resourceToPlanetTypes[result.resourceId] = Set(result.availablePlanets.map { $0.id })
            Logger.debug(
                "资源 \(result.resourceName)(ID: \(result.resourceId)) 可在以下行星类型生产: \(result.availablePlanets.map { $0.name }.joined(separator: ", "))"
            )
        }

        // 查询所有相关星系的信息
        Logger.debug("查询所有相关星系信息...")
        let query = """
                SELECT 
                    s.solarsystem_id,
                    s.region_id,
                    r.regionName as region_name,
                    s.system_security,
                    s.temperate,
                    s.barren,
                    s.oceanic,
                    s.ice,
                    s.gas,
                    s.lava,
                    s.storm,
                    s.plasma,
                    ss.solarSystemName as system_name
                FROM universe s
                JOIN regions r ON r.regionID = s.region_id
                JOIN solarsystems ss ON ss.solarSystemID = s.solarsystem_id
                WHERE s.solarsystem_id IN (\(systems.map { String($0) }.joined(separator: ",")))
            """

        guard case let .success(rows) = databaseManager.executeQuery(query) else {
            Logger.error("查询星系信息失败")
            return []
        }

        Logger.debug("查询到 \(rows.count) 个星系信息，开始评分计算")
        var processedSystems = 0
        var eligibleSystems = 0

        // 处理每个星系
        for row in rows {
            guard let systemId = row["solarsystem_id"] as? Int,
                let regionId = row["region_id"] as? Int,
                let regionName = row["region_name"] as? String,
                let systemName = row["system_name"] as? String,
                let security = row["system_security"] as? Double
            else {
                continue
            }

            processedSystems += 1
            Logger.debug("-------------------------------------------")
            Logger.debug(
                "评估星系: \(systemName) (ID: \(systemId), 地区: \(regionName), 安全等级: \(String(format: "%.1f", security)))"
            )

            // 获取当前星系的可用资源
            var availableResources: [Int: Int] = [:]  // [resourceId: planetCount]
            var missingResources: [Int] = []

            // 检查星系中存在哪些类型的行星
            var planetTypeCounts: [String: Int] = [:]
            for (planetType, columnName) in PlanetaryUtils.planetTypeToColumn {
                if let count = row[columnName] as? Int, count > 0 {
                    let planetName =
                        resourcePlanets.flatMap { $0.availablePlanets }.first {
                            $0.id == planetType
                        }?.name ?? "未知行星"
                    planetTypeCounts[planetName] = count
                }
            }
            Logger.debug(
                "星系包含行星类型: \(planetTypeCounts.map { "\($0.key): \($0.value)颗" }.joined(separator: ", "))"
            )

            // 检查当前星系的资源
            for resource in requiredResources {
                var found = false
                var planetCount = 0

                // 获取该资源可用的行星类型
                if let planetTypes = resourceToPlanetTypes[resource.typeId] {
                    // 检查每种行星类型的数量
                    for planetType in planetTypes {
                        if let columnName = PlanetaryUtils.planetTypeToColumn[planetType],
                            let count = row[columnName] as? Int
                        {
                            planetCount += count
                        }
                    }

                    // 如果找到了任何可用的行星，标记为已找到
                    if planetCount > 0 {
                        found = true
                        availableResources[resource.typeId] = planetCount
                        Logger.debug("资源 \(resource.name) 在当前星系发现 \(planetCount) 个可用行星")
                    } else {
                        Logger.debug("资源 \(resource.name) 在当前星系无可用行星")
                    }
                }

                if !found {
                    missingResources.append(resource.typeId)
                }
            }

            if availableResources.isEmpty {
                Logger.debug("当前星系没有任何所需资源，需要检查邻近星系")
            } else {
                Logger.debug("当前星系有 \(availableResources.count)/\(requiredResources.count) 种所需资源")
            }

            // 如果当前星系缺少资源，检查相邻星系
            var additionalResources: [Int: (resourceId: Int, jumps: Int)] = [:]  // [systemId: (resourceId, jumps)]
            if !missingResources.isEmpty && maxJumps > 0 {
                Logger.debug("缺少 \(missingResources.count) 种资源，开始在邻近星系寻找...")

                // 使用BFS查找最近的资源
                var visited = Set<Int>()
                var queue = [(systemId, 0)]  // (systemId, jumps)
                visited.insert(systemId)

                // 收集所有需要查询的相邻星系ID
                var neighborSystemIds = Set<Int>()
                var systemJumps: [Int: Int] = [:]  // [systemId: jumps]

                while !queue.isEmpty && !missingResources.isEmpty {
                    let (currentSystemId, jumps) = queue.removeFirst()

                    // 如果跳数超过限制，跳过
                    if jumps > maxJumps {
                        continue
                    }

                    // 获取相邻星系
                    let neighbors = starMap[String(currentSystemId)] ?? []

                    for neighborId in neighbors {
                        if visited.contains(neighborId) {
                            continue
                        }

                        visited.insert(neighborId)
                        let nextJumps = jumps + 1

                        // 确保下一跳系统不超过最大跳数限制
                        if nextJumps <= maxJumps {
                            queue.append((neighborId, nextJumps))
                            neighborSystemIds.insert(neighborId)
                            systemJumps[neighborId] = nextJumps
                        }
                    }
                }

                Logger.debug("发现 \(neighborSystemIds.count) 个邻近星系在 \(maxJumps) 跳范围内")

                // 一次性查询所有相邻星系的行星数量
                if !neighborSystemIds.isEmpty {
                    let neighborQuery = """
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
                            WHERE solarsystem_id IN (\(neighborSystemIds.map { String($0) }.joined(separator: ",")))
                        """

                    if case let .success(neighborRows) = databaseManager.executeQuery(neighborQuery)
                    {
                        Logger.debug("查询到 \(neighborRows.count) 个邻近星系信息")

                        // 创建星系ID到行星数量的映射
                        var systemPlanets: [Int: [String: Int]] = [:]
                        for row in neighborRows {
                            if let systemId = row["solarsystem_id"] as? Int {
                                var planets: [String: Int] = [:]
                                for (key, value) in row {
                                    if key != "solarsystem_id",
                                        let count = value as? Int
                                    {
                                        planets[key] = count
                                    }
                                }
                                systemPlanets[systemId] = planets
                            }
                        }

                        // 检查每个相邻星系的资源
                        for (neighborId, planets) in systemPlanets {
                            for resourceId in missingResources {
                                var found = false
                                var planetCount = 0

                                // 获取该资源可用的行星类型
                                if let planetTypes = resourceToPlanetTypes[resourceId] {
                                    // 检查每种行星类型的数量
                                    for planetType in planetTypes {
                                        if let columnName = PlanetaryUtils.planetTypeToColumn[
                                            planetType],
                                            let count = planets[columnName]
                                        {
                                            planetCount += count
                                        }
                                    }

                                    // 如果找到了任何可用的行星，标记为已找到
                                    if planetCount > 0 {
                                        found = true
                                        if let jumps = systemJumps[neighborId], jumps <= maxJumps {
                                            additionalResources[neighborId] = (resourceId, jumps)
                                            // 获取资源名称
                                            let resourceName =
                                                requiredResources.first(where: {
                                                    $0.typeId == resourceId
                                                })?.name ?? "未知资源"
                                            Logger.debug(
                                                "资源 \(resourceName) 在距离 \(jumps) 跳的邻近星系 \(neighborId) 中找到"
                                            )
                                        } else if let jumps = systemJumps[neighborId] {
                                            Logger.debug(
                                                "忽略距离超出限制的系统 \(neighborId) 距离为 \(jumps) 跳，最大允许跳数: \(maxJumps)"
                                            )
                                        }
                                    }
                                }

                                if found {
                                    missingResources.removeAll { $0 == resourceId }
                                }
                            }
                        }
                    }
                }

                Logger.debug("找到 \(additionalResources.count) 个邻近星系提供缺失资源")
            }

            // 如果指定跳数内无法满足所有资源需求，跳过该星系
            if !missingResources.isEmpty {
                Logger.debug(
                    "星系 \(systemName) 不满足条件: 即使在 \(maxJumps) 跳范围内仍然缺少 \(missingResources.count) 种资源"
                )
                continue
            }

            // 计算资源覆盖率
            var coveredResources = Set<Int>()
            for (resourceId, _) in availableResources {
                coveredResources.insert(resourceId)
            }
            for (_, info) in additionalResources {
                coveredResources.insert(info.resourceId)
            }

            let coveredCount = coveredResources.count
            let totalCount = requiredResources.count

            // 如果资源覆盖率不足100%，跳过该星系
            if coveredCount < totalCount {
                Logger.debug("星系 \(systemName) 不满足条件: 资源覆盖率不足 (\(coveredCount)/\(totalCount))")
                continue
            }

            // 计算总分
            var score = 0.0
            Logger.debug("星系 \(systemName) 满足条件! 开始计算评分...")
            eligibleSystems += 1

            // 1. 基础分：每个可用资源的行星数量
            var resourcesWithAtLeastTwoPlanets = 0
            var baseScore = 0.0
            for (resourceId, count) in availableResources {
                let resourceScore = Double(count) * 10
                baseScore += resourceScore

                // 获取资源名称用于日志
                let resourceName =
                    requiredResources.first(where: { $0.typeId == resourceId })?.name ?? "未知资源"
                Logger.debug("本地资源: \(resourceName) 有 \(count) 个星球，得分 +\(resourceScore)")

                // 统计有至少2个星球的资源数量
                if count >= 2 {
                    resourcesWithAtLeastTwoPlanets += 1
                    Logger.debug("资源 \(resourceName) 有至少2个星球")
                }
            }
            score += baseScore

            // 2. 均衡性评分：如果每种资源都有至少2个星球，额外加分
            // 根据达成这个条件的资源比例给予奖励分数
            if !availableResources.isEmpty {
                let balanceRatio =
                    Double(resourcesWithAtLeastTwoPlanets) / Double(availableResources.count)
                let balanceScore = balanceRatio * 100
                score += balanceScore
                Logger.debug(
                    "均衡性评分: \(resourcesWithAtLeastTwoPlanets)/\(availableResources.count) 资源有至少2个星球, 均衡率 \(String(format: "%.2f", balanceRatio)), 得分 +\(String(format: "%.2f", balanceScore))"
                )

                // 如果所有资源都有至少2个星球，给予额外奖励
                if resourcesWithAtLeastTwoPlanets == availableResources.count {
                    score += 50
                    Logger.debug("所有资源都有至少2个星球，额外奖励 +50")
                }
            }

            // 3. 额外资源分：考虑相邻星系的资源
            // 降低相邻星系资源的分数权重，使本地资源更受欢迎
            var neighborScore = 0.0
            for (neighborId, info) in additionalResources {
                let baseNeighborScore = 5.0
                let jumpPenalty = Double(info.jumps) * 5
                let resourceNeighborScore = baseNeighborScore - jumpPenalty
                neighborScore += resourceNeighborScore

                // 获取资源名称用于日志
                let resourceName =
                    requiredResources.first(where: { $0.typeId == info.resourceId })?.name ?? "未知资源"
                Logger.debug(
                    "相邻资源: \(resourceName) 在星系 \(neighborId) 距离 \(info.jumps) 跳, 基础分 \(baseNeighborScore), 跳数惩罚 -\(jumpPenalty), 最终得分 \(resourceNeighborScore)"
                )
            }
            score += neighborScore

            // 4. 如果所有资源都可本地获取，无需跳转其他星系，给予显著奖励
            if !availableResources.isEmpty && additionalResources.isEmpty
                && missingResources.isEmpty
            {
                let localBonus = 200.0
                score += localBonus
                Logger.debug("所有资源都可本地获取，无需跳转，额外奖励 +\(localBonus)")
            }
            // 如果所有资源都可用（包括相邻星系），给予额外奖励
            else if missingResources.isEmpty {
                let completeBonus = 50.0
                score += completeBonus
                Logger.debug("所有资源都可获取(含相邻星系)，奖励 +\(completeBonus)")
            }

            // 5. 如果没有任何可用资源，给予一个基础分，以便排序
            if availableResources.isEmpty && additionalResources.isEmpty {
                score = 1.0
                Logger.debug("没有任何可用资源，设置基础分 1.0")
            }

            Logger.debug("星系 \(systemName) 最终得分: \(String(format: "%.2f", score))")

            // 创建结果
            let result = SystemScoreResult(
                systemId: systemId,
                systemName: systemName,
                regionId: regionId,
                regionName: regionName,
                security: security,
                score: score,
                availableResources: availableResources,
                missingResources: missingResources,
                additionalResources: additionalResources
            )

            results.append(result)
        }

        Logger.debug("评分计算完成，处理了 \(processedSystems) 个星系，其中 \(eligibleSystems) 个星系符合条件")

        // 按分数降序排序
        let sortedResults = results.sorted { $0.score > $1.score }

        if sortedResults.isEmpty {
            Logger.debug("没有找到能够生产所需资源的星系，请考虑增加搜索范围或选择其他产品")
        } else {
            Logger.debug(
                "最高评分星系: \(sortedResults[0].systemName)，得分: \(String(format: "%.2f", sortedResults[0].score))"
            )
        }

        return sortedResults
    }
}
