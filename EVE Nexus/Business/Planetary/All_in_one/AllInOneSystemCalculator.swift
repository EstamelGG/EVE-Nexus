import Foundation

class AllInOneSystemCalculator {
    private let databaseManager: DatabaseManager
    private let singlePlanetAnalyzer: SinglePlanetProductAnalyzer
    private let config: SystemScoringConfig
    
    init(databaseManager: DatabaseManager = DatabaseManager.shared) {
        self.databaseManager = databaseManager
        self.singlePlanetAnalyzer = SinglePlanetProductAnalyzer()
        self.config = SystemScoringConfig()
    }
    
    // MARK: - 主要计算方法
    
    /// 分析多产品需求，计算行星类型需求和冲突解决方案
    func analyzeMultiProductRequirements(selectedProducts: [SelectedProduct]) -> MultiProductRequirement {
        Logger.info("开始分析 \(selectedProducts.count) 个产品的多产品需求")
        
        // 统计每个行星类型被需要的次数
        var planetTypeUsage: [Int: [Int]] = [:] // [planetTypeId: [productIds]]
        
        for product in selectedProducts {
            for planetType in product.compatiblePlanetTypes {
                planetTypeUsage[planetType.typeId, default: []].append(product.id)
            }
        }
        
        // 识别共享和专用行星类型
        var sharedPlanetTypes: [Int] = []
        var dedicatedPlanetTypes: [Int: [Int]] = [:]
        var minimumPlanetRequirements: [Int: Int] = [:]
        
        for (planetTypeId, productIds) in planetTypeUsage {
            if productIds.count > 1 {
                // 可以被多个产品共享的行星类型
                sharedPlanetTypes.append(planetTypeId)
                // 共享行星类型至少需要与使用它的产品数量相等的行星数
                minimumPlanetRequirements[planetTypeId] = productIds.count
            } else {
                // 只被一个产品使用的专用行星类型
                dedicatedPlanetTypes[planetTypeId] = productIds
                minimumPlanetRequirements[planetTypeId] = 1
            }
        }
        
        Logger.info("分析结果：共享行星类型 \(sharedPlanetTypes.count) 个，专用行星类型 \(dedicatedPlanetTypes.count) 个")
        
        let conflictResolution = ConflictResolution(
            sharedPlanetTypes: sharedPlanetTypes,
            dedicatedPlanetTypes: dedicatedPlanetTypes,
            minimumPlanetRequirements: minimumPlanetRequirements
        )
        
        return MultiProductRequirement(
            selectedProducts: selectedProducts,
            planetTypeRequirements: minimumPlanetRequirements,
            conflictResolution: conflictResolution
        )
    }
    
    /// 计算星系评分
    func calculateSystemScores(
        for systemIds: Set<Int>,
        multiProductRequirement: MultiProductRequirement
    ) -> [AllInOneSystemResult] {
        Logger.info("开始计算 \(systemIds.count) 个星系的评分")
        
        var results: [AllInOneSystemResult] = []
        
        // 批量查询星系信息
        let systemsData = querySystemsData(systemIds: systemIds)
        
        for systemData in systemsData {
            if let result = evaluateSystem(systemData: systemData, requirement: multiProductRequirement) {
                results.append(result)
            }
        }
        
        // 按评分降序排序
        results.sort { $0.score > $1.score }
        
        Logger.info("完成评分计算，\(results.count) 个星系通过评估")
        return results
    }
    
    // MARK: - 私有方法
    
    private func querySystemsData(systemIds: Set<Int>) -> [SystemData] {
        guard !systemIds.isEmpty else { return [] }
        
        let systemIdsString = systemIds.map { String($0) }.joined(separator: ",")
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
            WHERE s.solarsystem_id IN (\(systemIdsString))
        """
        
        var systemsData: [SystemData] = []
        
        if case let .success(rows) = databaseManager.executeQuery(query) {
            for row in rows {
                if let systemData = parseSystemData(from: row) {
                    systemsData.append(systemData)
                }
            }
        }
        
        return systemsData
    }
    
    private func parseSystemData(from row: [String: Any]) -> SystemData? {
        guard let systemId = row["solarsystem_id"] as? Int,
              let regionId = row["region_id"] as? Int,
              let regionName = row["region_name"] as? String,
              let systemName = row["system_name"] as? String,
              let security = row["system_security"] as? Double else {
            return nil
        }
        
        var planetCounts: [Int: Int] = [:]
        
        // 解析行星数量
        for (planetTypeId, columnName) in PlanetaryUtils.planetTypeToColumn {
            if let count = row[columnName] as? Int {
                planetCounts[planetTypeId] = count
            }
        }
        
        return SystemData(
            systemId: systemId,
            systemName: systemName,
            regionId: regionId,
            regionName: regionName,
            security: security,
            planetCounts: planetCounts
        )
    }
    
    private func evaluateSystem(
        systemData: SystemData,
        requirement: MultiProductRequirement
    ) -> AllInOneSystemResult? {
        
        Logger.debug("评估星系：\(systemData.systemName) (ID: \(systemData.systemId))")
        
        // 检查每个产品是否可以在该星系中生产
        var productSupport: [Int: ProductSupportInfo] = [:]
        var canSupportAllProducts = true
        
        for product in requirement.selectedProducts {
            let supportInfo = evaluateProductSupport(
                product: product,
                systemData: systemData,
                requirement: requirement
            )
            
            productSupport[product.id] = supportInfo
            
            if !supportInfo.canSupport {
                canSupportAllProducts = false
            }
        }
        
        // 如果不能支持所有产品，跳过该星系
        guard canSupportAllProducts else {
            Logger.debug("星系 \(systemData.systemName) 不能支持所有产品，跳过")
            return nil
        }
        
        // 计算评分
        let score = calculateSystemScore(
            systemData: systemData,
            productSupport: productSupport,
            requirement: requirement
        )
        
        // 生成行星类型汇总
        let planetTypeSummary = generatePlanetTypeSummary(
            systemData: systemData,
            requirement: requirement
        )
        
        Logger.debug("星系 \(systemData.systemName) 评分：\(String(format: "%.2f", score))")
        
        return AllInOneSystemResult(
            id: systemData.systemId,
            systemId: systemData.systemId,
            systemName: systemData.systemName,
            regionId: systemData.regionId,
            regionName: systemData.regionName,
            security: systemData.security,
            score: score,
            productSupport: productSupport,
            planetTypeSummary: planetTypeSummary
        )
    }
    
    private func evaluateProductSupport(
        product: SelectedProduct,
        systemData: SystemData,
        requirement: MultiProductRequirement
    ) -> ProductSupportInfo {
        
        let requiredPlanetTypes = product.compatiblePlanetTypes.map { $0.typeId }
        var supportingPlanetTypes: [Int] = []
        var totalAvailablePlanets = 0
        
        // 检查每种兼容的行星类型
        for planetType in product.compatiblePlanetTypes {
            let planetTypeId = planetType.typeId
            let availableCount = systemData.planetCounts[planetTypeId] ?? 0
            
            if availableCount > 0 {
                supportingPlanetTypes.append(planetTypeId)
                totalAvailablePlanets += availableCount
            }
        }
        
        // 检查是否可以支持该产品
        let canSupport = checkProductCanBeSupported(
            product: product,
            systemData: systemData,
            requirement: requirement
        )
        
        return ProductSupportInfo(
            productId: product.id,
            productName: product.name,
            canSupport: canSupport,
            availablePlanetCount: totalAvailablePlanets,
            requiredPlanetTypes: requiredPlanetTypes,
            supportingPlanetTypes: supportingPlanetTypes
        )
    }
    
    private func checkProductCanBeSupported(
        product: SelectedProduct,
        systemData: SystemData,
        requirement: MultiProductRequirement
    ) -> Bool {
        
        // 获取该产品可用的行星类型
        let compatiblePlanetTypes = Set(product.compatiblePlanetTypes.map { $0.typeId })
        
        // 检查是否有足够的行星来支持该产品
        for planetTypeId in compatiblePlanetTypes {
            let availableCount = systemData.planetCounts[planetTypeId] ?? 0
            let minimumRequired = requirement.conflictResolution.minimumPlanetRequirements[planetTypeId] ?? 1
            
            // 如果这个行星类型有足够的数量，则可以支持
            if availableCount >= minimumRequired {
                return true
            }
        }
        
        return false
    }
    
    private func calculateSystemScore(
        systemData: SystemData,
        productSupport: [Int: ProductSupportInfo],
        requirement: MultiProductRequirement
    ) -> Double {
        
        var score = 0.0
        
        // 1. 基础分：每个支持的产品的可用行星数量
        for (_, supportInfo) in productSupport {
            if supportInfo.canSupport {
                score += Double(supportInfo.availablePlanetCount) * config.baseScorePerPlanet
            }
        }
        
        // 2. 均衡性奖励：如果所有产品都有足够的行星支持
        let supportedProductCount = productSupport.values.filter { $0.canSupport }.count
        if supportedProductCount == requirement.selectedProducts.count {
            score += config.allProductsSupportedBonus
            Logger.debug("所有产品都得到支持，奖励 +\(config.allProductsSupportedBonus)")
        }
        
        // 3. 多行星类型奖励：如果有多种行星类型可用
        let availablePlanetTypes = systemData.planetCounts.filter { $0.value > 0 }.count
        if availablePlanetTypes >= 3 {
            score += config.multiPlanetTypeBonus
            Logger.debug("多行星类型奖励 +\(config.multiPlanetTypeBonus)")
        }
        
        // 4. 行星数量均衡性评分
        let planetTypesWithMultiplePlanets = systemData.planetCounts.filter { $0.value >= 2 }.count
        if planetTypesWithMultiplePlanets > 0 {
            let balanceBonus = config.balanceBonus * Double(planetTypesWithMultiplePlanets) / Double(availablePlanetTypes)
            score += balanceBonus
            Logger.debug("行星数量均衡性奖励 +\(String(format: "%.2f", balanceBonus))")
        }
        
        return score
    }
    
    private func generatePlanetTypeSummary(
        systemData: SystemData,
        requirement: MultiProductRequirement
    ) -> [PlanetTypeSummary] {
        
        var summaries: [PlanetTypeSummary] = []
        
        // 获取行星类型名称和图标
        let planetTypeIds = Array(systemData.planetCounts.keys)
        let planetTypeInfo = getPlanetTypeInfo(for: planetTypeIds)
        
        for (planetTypeId, count) in systemData.planetCounts {
            guard count > 0 else { continue }
            
            let typeInfo = planetTypeInfo[planetTypeId]
            let usedByProducts = requirement.selectedProducts.filter { product in
                product.compatiblePlanetTypes.contains { $0.typeId == planetTypeId }
            }.map { $0.id }
            
            summaries.append(PlanetTypeSummary(
                typeId: planetTypeId,
                typeName: typeInfo?.name ?? "未知行星",
                iconFileName: typeInfo?.iconFileName ?? "not_found",
                count: count,
                usedByProducts: usedByProducts
            ))
        }
        
        // 按行星数量降序排序
        summaries.sort { $0.count > $1.count }
        
        return summaries
    }
    
    private func getPlanetTypeInfo(for planetTypeIds: [Int]) -> [Int: (name: String, iconFileName: String)] {
        guard !planetTypeIds.isEmpty else { return [:] }
        
        let typeIdsString = planetTypeIds.map { String($0) }.joined(separator: ",")
        let query = """
            SELECT type_id, name, icon_filename
            FROM types
            WHERE type_id IN (\(typeIdsString))
        """
        
        var result: [Int: (name: String, iconFileName: String)] = [:]
        
        if case let .success(rows) = databaseManager.executeQuery(query) {
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                   let name = row["name"] as? String,
                   let iconFileName = row["icon_filename"] as? String {
                    result[typeId] = (
                        name: name,
                        iconFileName: iconFileName.isEmpty ? "not_found" : iconFileName
                    )
                }
            }
        }
        
        return result
    }
}

// MARK: - 辅助数据结构

private struct SystemData {
    let systemId: Int
    let systemName: String
    let regionId: Int
    let regionName: String
    let security: Double
    let planetCounts: [Int: Int] // [planetTypeId: count]
} 