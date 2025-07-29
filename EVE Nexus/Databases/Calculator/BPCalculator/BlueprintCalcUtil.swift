import Foundation

/// 蓝图计算工具类
/// 用于计算蓝图的实际材料需求和时间
class BlueprintCalcUtil {
    
    /// 建筑加成结构体
    struct StructureBonuses {
        let materialBonus: Double  // 材料效率加成乘数
        let timeBonus: Double      // 时间效率加成乘数
        
        init(materialBonus: Double = 1.0, timeBonus: Double = 1.0) {
            self.materialBonus = materialBonus
            self.timeBonus = timeBonus
        }
    }
    
    /// 蓝图计算参数结构体
    struct BlueprintCalcParams {
        let blueprintId: Int           // 蓝图ID
        let runs: Int                  // 流程数
        let timeEfficiency: Int        // 蓝图时间效率 (默认20)
        let materialEfficiency: Int    // 蓝图材料效率 (默认10)
        let facilityTypeId: Int        // 建筑typeid
        let facilityRigs: [Int]        // 建筑插件列表
        let facilityTax: Double        // 建筑税率
        let solarSystemId: Int         // 星系id
        let characterSkills: [Int: Int] // 角色技能ID -> 技能等级
        let isReaction: Bool           // 是否为反应类型
        
        init(
            blueprintId: Int,
            runs: Int = 1,
            timeEfficiency: Int = 20,
            materialEfficiency: Int = 10,
            facilityTypeId: Int,
            facilityRigs: [Int] = [],
            facilityTax: Double = 0.0,
            solarSystemId: Int,
            characterSkills: [Int: Int] = [:],
            isReaction: Bool = false
        ) {
            self.blueprintId = blueprintId
            self.runs = runs
            self.timeEfficiency = timeEfficiency
            self.materialEfficiency = materialEfficiency
            self.facilityTypeId = facilityTypeId
            self.facilityRigs = facilityRigs
            self.facilityTax = facilityTax
            self.solarSystemId = solarSystemId
            self.characterSkills = characterSkills
            self.isReaction = isReaction
        }
    }
    
    /// 蓝图材料需求结构体
    struct MaterialRequirement {
        let typeId: Int              // 材料类型ID
        let typeName: String         // 材料名称
        let typeEnName: String       // 材料英文名称
        let typeIcon: String         // 材料图标
        let originalQuantity: Int    // 原始数量（每流程）
        let finalQuantity: Int       // 最终数量（应用加成后）
        let isQuantityOne: Bool      // 是否为单个材料（不受加成影响）
    }
    
    /// 蓝图时间信息结构体
    struct TimeRequirement {
        let manufacturingTime: Int   // 制造时间（秒，每流程）
        let finalTime: TimeInterval  // 最终时间（应用加成后，总时间）
    }
    
    /// 蓝图计算结果结构体
    struct BlueprintCalcResult {
        let materials: [MaterialRequirement] // 材料需求列表
        let timeRequirement: TimeRequirement // 时间需求
        let facilityCost: Double       // 设施费用
        let totalCost: Double          // 总成本
        let product: BlueprintProduct? // 产品信息
        let success: Bool              // 计算是否成功
        let errorMessage: String?      // 错误信息
    }
    
    /// 计算蓝图材料需求和时间
    /// - Parameter params: 蓝图计算参数
    /// - Returns: 蓝图计算结果
    static func calculateBlueprint(
        params: BlueprintCalcParams
    ) -> BlueprintCalcResult {
        
        // 1. 获取建筑及其插件的总加成（累乘逻辑）
        let structureAndRigBonuses = getStructureAndRigBonuses(
            structureTypeId: params.facilityTypeId,
            rigIds: params.facilityRigs,
            blueprintId: params.blueprintId,
            isReaction: params.isReaction,
            systemId: params.solarSystemId
        )
        
        // 4. 获取蓝图自身的效率加成
        let blueprintBonuses = getBlueprintEfficiencyBonuses(materialEfficiency: params.materialEfficiency, timeEfficiency: params.timeEfficiency)
        Logger.info("蓝图效率加成分析:")
        Logger.info("  蓝图材料效率: \(params.materialEfficiency)% (减少\(params.materialEfficiency)%, 乘数: \(String(format: "%.3f", blueprintBonuses.materialBonus)))")
        Logger.info("  蓝图时间效率: \(params.timeEfficiency)% (减少\(params.timeEfficiency)%, 乘数: \(String(format: "%.3f", blueprintBonuses.timeBonus)))")
        
        // 5. 获取技能加成
        let skillBonuses = getAllEffectiveSkillBonuses(blueprintId: params.blueprintId, characterSkills: params.characterSkills, isReaction: params.isReaction)
        Logger.info("技能加成分析:")
        Logger.info("  技能时间效率加成: \(skillBonuses.timeBonus) (乘数: \(String(format: "%.3f", skillBonuses.timeBonus)))")
        
        // 显示详细的技能加成信息
        let skillBonusDetails = getSkillBonuses(blueprintId: params.blueprintId, characterSkills: params.characterSkills, isReaction: params.isReaction)
        for detail in skillBonusDetails {
            Logger.info("  \(detail)")
        }
        
        // 6. 计算并显示最终总加成
        let finalMaterialMultiplier = structureAndRigBonuses.materialBonus * blueprintBonuses.materialBonus
        let finalTimeMultiplier = structureAndRigBonuses.timeBonus * blueprintBonuses.timeBonus * skillBonuses.timeBonus
        
        let finalMaterialBonus = (finalMaterialMultiplier - 1.0) * 100.0
        let finalTimeBonus = (finalTimeMultiplier - 1.0) * 100.0
        
        Logger.info("最终总加成计算:")
        Logger.info("  材料效率总乘数: \(String(format: "%.3f", finalMaterialMultiplier)) (建筑+插件: \(String(format: "%.3f", structureAndRigBonuses.materialBonus)) × 蓝图: \(String(format: "%.3f", blueprintBonuses.materialBonus)))")
        Logger.info("  时间效率总乘数: \(String(format: "%.3f", finalTimeMultiplier)) (建筑+插件: \(String(format: "%.3f", structureAndRigBonuses.timeBonus)) × 蓝图: \(String(format: "%.3f", blueprintBonuses.timeBonus)) × 技能: \(String(format: "%.3f", skillBonuses.timeBonus)))")
        Logger.info("[Bonus Result] 最终材料效率乘数: \(String(format: "%.3f", finalMaterialMultiplier)) (最终加成: \(String(format: "%.1f", finalMaterialBonus))%)")
        Logger.info("[Bonus Result] 最终时间效率乘数: \(String(format: "%.3f", finalTimeMultiplier)) (最终加成: \(String(format: "%.1f", finalTimeBonus))%)")
        
        // 7. 获取蓝图基础材料需求
        guard let materialRequirements = getBlueprintMaterials(blueprintId: params.blueprintId) else {
        return BlueprintCalcResult(
                materials: [],
                timeRequirement: TimeRequirement(manufacturingTime: 0, finalTime: 0),
                facilityCost: 0,
                totalCost: 0,
                product: nil,
            success: false,
                errorMessage: "无法获取蓝图材料需求"
            )
        }
        
        // 8. 获取蓝图基础时间需求
        guard let timeRequirement = getBlueprintTime(blueprintId: params.blueprintId) else {
            return BlueprintCalcResult(
                materials: [],
                timeRequirement: TimeRequirement(manufacturingTime: 0, finalTime: 0),
                facilityCost: 0,
                totalCost: 0,
                product: nil,
                success: false,
                errorMessage: "无法获取蓝图时间需求"
            )
        }
        
        // 9. 计算最终材料需求（应用加成和流程数）
        let finalMaterials = calculateFinalMaterials(
            baseMaterials: materialRequirements,
            runs: params.runs,
            materialMultiplier: finalMaterialMultiplier
        )
        
        // 10. 计算最终时间需求（应用加成和流程数）
        let finalTime = calculateFinalTime(
            baseTime: timeRequirement,
            runs: params.runs,
            timeMultiplier: finalTimeMultiplier
        )
        
        // 11. 计算设施手续费
        let facilityCostParams = FacilityCostParams(
            materials: finalMaterials,
            solarSystemId: params.solarSystemId,
            facilityTax: params.facilityTax,
            isReaction: params.isReaction
        )
        let facilityCost = calculateFacilityCost(params: facilityCostParams)
        
        // 12. 计算总成本（材料成本 + 设施费用）
        let totalCost = calculateEIV(materials: finalMaterials) + facilityCost
        
        // 13. 获取产品信息
        let productInfo = getBlueprintProductInfo(blueprintId: params.blueprintId, runs: params.runs)
        
        return BlueprintCalcResult(
            materials: finalMaterials,
            timeRequirement: finalTime,
            facilityCost: facilityCost,
            totalCost: totalCost,
            product: productInfo,
            success: true,
            errorMessage: nil
        )
    }
    
    /// 建筑属性结构体（包含原始属性和安全等级修正系数）
    struct StructureAttributes {
        let materialBonus: Double     // 原始材料效率加成
        let timeBonus: Double         // 原始时间效率加成
        let highSecModifier: Double   // 高安修正系数
        let lowSecModifier: Double    // 低安修正系数
        let nullSecModifier: Double   // 0.0/虫洞修正系数
    }
    
    /// 获取建筑的效率加成和安全等级修正系数
    /// - Parameters:
    ///   - structureTypeId: 建筑类型ID
    ///   - isReaction: 是否为反应类型
    /// - Returns: 建筑属性结构体
    static func getStructureAttributes(structureTypeId: Int, isReaction: Bool) -> StructureAttributes {
        
        var attributeIds: [Int]
        
        if isReaction {
            // 反应建筑：查询时间效率加成 (2721) 和安全等级修正系数 (2355, 2356, 2357)
            attributeIds = [2721, 2355, 2356, 2357]
        } else {
            // 普通工业建筑：查询材料效率 (2600)、时间效率 (2602) 和安全等级修正系数 (2355, 2356, 2357)
            attributeIds = [2600, 2602, 2355, 2356, 2357]
        }
        
        let attributeIdPlaceholders = attributeIds.map { _ in "?" }.joined(separator: ",")
        let query = """
                SELECT attribute_id, value 
                FROM typeAttributes 
            WHERE type_id = ? AND attribute_id IN (\(attributeIdPlaceholders))
            """
        
        let parameters = [structureTypeId] + attributeIds.map { $0 as Any }
        
        var materialBonus: Double = 1.0
        var timeBonus: Double = 1.0
        var highSecModifier: Double = 1.0
        var lowSecModifier: Double = 1.0
        var nullSecModifier: Double = 1.0
        
        if case let .success(rows) = DatabaseManager.shared.executeQuery(query, parameters: parameters) {
            for row in rows {
                if let attributeId = row["attribute_id"] as? Int,
                   let value = row["value"] as? Double {
                    switch attributeId {
                    case 2600:  // 普通建筑材料效率加成
                        materialBonus = value
                    case 2602:  // 普通建筑时间效率加成
                        timeBonus = value
                    case 2721:  // 反应建筑时间效率加成
                        timeBonus = value
                    case 2355:  // 高安修正系数
                        highSecModifier = value
                    case 2356:  // 低安修正系数
                        lowSecModifier = value
                    case 2357:  // 0.0/虫洞修正系数
                        nullSecModifier = value
                    default:
                        break
                    }
                }
            }
        } else {
            Logger.warning("查询建筑ID \(structureTypeId) 的属性失败")
        }
        
        return StructureAttributes(
            materialBonus: materialBonus,
            timeBonus: timeBonus,
            highSecModifier: highSecModifier,
            lowSecModifier: lowSecModifier,
            nullSecModifier: nullSecModifier
        )
    }
    
    /// 插件属性结构体（包含原始属性和安全等级修正系数）
    struct RigAttributes {
        let rigId: Int
        let materialBonus: Double     // 原始材料效率加成
        let timeBonus: Double         // 原始时间效率加成
        let highSecModifier: Double   // 高安修正系数
        let lowSecModifier: Double    // 低安修正系数
        let nullSecModifier: Double   // 0.0/虫洞修正系数
    }
    
    /// 获取插件的效率加成和安全等级修正系数
    /// - Parameters:
    ///   - rigIds: 插件ID列表
    ///   - structureTypeId: 建筑类型ID
    ///   - isReaction: 是否为反应类型
    /// - Returns: 插件属性数组
    static func getRigAttributes(rigIds: [Int], structureTypeId: Int, isReaction: Bool) -> [RigAttributes] {
        guard !rigIds.isEmpty else {
            return []
        }
        
        // 根据建筑类型决定查询的插件属性ID
        var timeAttributeId: Int
        var materialAttributeId: Int
        
        if isReaction {
            timeAttributeId = 2713
            materialAttributeId = 2714
        } else {
            timeAttributeId = 2593
            materialAttributeId = 2594
        }
        
        // 构建查询条件 - 包含效率属性和安全等级修正系数
        let attributeIds: [Int] = [timeAttributeId, materialAttributeId, 2355, 2356, 2357]
        
        let rigIdPlaceholders = rigIds.map { _ in "?" }.joined(separator: ",")
        let attributeIdPlaceholders = attributeIds.map { _ in "?" }.joined(separator: ",")
        
        let query = """
            SELECT type_id, attribute_id, value 
            FROM typeAttributes 
            WHERE type_id IN (\(rigIdPlaceholders)) 
            AND attribute_id IN (\(attributeIdPlaceholders))
        """
        
        let parameters = rigIds.map { $0 as Any } + attributeIds.map { $0 as Any }
        
        // 创建插件属性字典
        var rigAttributesMap: [Int: (materialBonus: Double?, timeBonus: Double?, highSec: Double?, lowSec: Double?, nullSec: Double?)] = [:]
        
        // 初始化所有插件ID
        for rigId in rigIds {
            rigAttributesMap[rigId] = (nil, nil, nil, nil, nil)
        }
        
        if case let .success(rows) = DatabaseManager.shared.executeQuery(query, parameters: parameters) {
            for row in rows {
                if let rigId = row["type_id"] as? Int,
                   let attributeId = row["attribute_id"] as? Int,
                   let value = row["value"] as? Double {
                    
                    var currentAttributes = rigAttributesMap[rigId]!
                    
                    switch attributeId {
                    case timeAttributeId:
                        currentAttributes.timeBonus = value
                    case materialAttributeId:
                        currentAttributes.materialBonus = value
                    case 2355:  // 高安修正系数
                        currentAttributes.highSec = value
                    case 2356:  // 低安修正系数
                        currentAttributes.lowSec = value
                    case 2357:  // 0.0/虫洞修正系数
                        currentAttributes.nullSec = value
                    default:
                        break
                    }
                    
                    rigAttributesMap[rigId] = currentAttributes
                }
            }
        } else {
            Logger.warning("查询插件属性失败")
        }
        
        // 转换为结果数组
        var result: [RigAttributes] = []
        for rigId in rigIds {
            let attributes = rigAttributesMap[rigId]!
            result.append(RigAttributes(
                rigId: rigId,
                materialBonus: attributes.materialBonus ?? 0.0,
                timeBonus: attributes.timeBonus ?? 0.0,
                highSecModifier: attributes.highSec ?? 1.0,
                lowSecModifier: attributes.lowSec ?? 1.0,
                nullSecModifier: attributes.nullSec ?? 1.0
            ))
        }
        
        return result
    }
    
    /// 获取插件的效率加成（保持兼容性）
    /// - Parameters:
    ///   - rigIds: 插件ID列表
    ///   - structureTypeId: 建筑类型ID
    ///   - isReaction: 是否为反应类型
    /// - Returns: 插件加成结构体
    static func getRigBonuses(rigIds: [Int], structureTypeId: Int, isReaction: Bool) -> StructureBonuses {
        guard !rigIds.isEmpty else {
            return StructureBonuses()
        }
        
        let rigAttributes = getRigAttributes(rigIds: rigIds, structureTypeId: structureTypeId, isReaction: isReaction)
        
        var materialBonus: Double = 1.0
        var timeBonus: Double = 1.0
        
        for rig in rigAttributes {
            if rig.timeBonus != 0.0 {
                let percentageReduction = abs(rig.timeBonus)
                let multiplier = 1.0 - (percentageReduction / 100.0)
                timeBonus *= multiplier
            }
            
            if rig.materialBonus != 0.0 {
                let percentageReduction = abs(rig.materialBonus)
                let multiplier = 1.0 - (percentageReduction / 100.0)
                materialBonus *= multiplier
            }
        }
        
        return StructureBonuses(materialBonus: materialBonus, timeBonus: timeBonus)
    }
    
    /// 获取对当前蓝图产品有效的插件ID列表
    /// - Parameters:
    ///   - rigIds: 所有安装的插件ID列表
    ///   - blueprintId: 蓝图ID
    /// - Returns: 有效的插件ID列表
    static func getEffectiveRigIds(rigIds: [Int], blueprintId: Int) -> [Int] {
        guard !rigIds.isEmpty else {
            // Logger.info("没有安装插件，跳过插件作用范围检测")
            return []
        }
        
        // 1. 获取蓝图的产品类型ID
        guard let productTypeId = getBlueprintProductTypeId(blueprintId: blueprintId) else {
            // Logger.warning("无法获取蓝图ID \(blueprintId) 的产品类型，所有插件将被视为无效")
            return []
        }
        
        // 2. 获取产品的分类和分组
        guard let productInfo = getProductCategoryAndGroup(typeId: productTypeId) else {
            // Logger.warning("无法获取产品ID \(productTypeId) 的分类信息，所有插件将被视为无效")
            return []
        }
        
        // Logger.info("蓝图产品信息 - 产品ID: \(productTypeId), 分类ID: \(productInfo.categoryId), 分组ID: \(productInfo.groupId)")
        
        // 3. 筛选有效的插件
        var effectiveRigIds: [Int] = []
        
        for rigId in rigIds {
            if isRigEffectiveForProduct(rigId: rigId, categoryId: productInfo.categoryId, groupId: productInfo.groupId) {
                effectiveRigIds.append(rigId)
                // Logger.info("插件ID \(rigId) 对当前蓝图产品有效")
            }
        }
        
        return effectiveRigIds
    }
    
    /// 蓝图产品信息结构体
    struct BlueprintProduct {
        let typeId: Int              // 产品类型ID
        let typeName: String         // 产品名称
        let typeIcon: String         // 产品图标
        let quantity: Int            // 每流程产出数量
        let totalQuantity: Int       // 总产出数量（quantity × runs）
    }
    
    /// 获取蓝图的产品信息
    /// - Parameters:
    ///   - blueprintId: 蓝图ID
    ///   - runs: 流程数
    /// - Returns: 产品信息，如果查询失败返回nil
    static func getBlueprintProductInfo(blueprintId: Int, runs: Int) -> BlueprintProduct? {
        let query = """
            SELECT bo.typeID, bo.quantity, t.name, t.icon_filename
            FROM blueprint_manufacturing_output bo
            JOIN types t ON bo.typeID = t.type_id
            WHERE bo.blueprintTypeID = ?
        """
        
        if case let .success(rows) = DatabaseManager.shared.executeQuery(query, parameters: [blueprintId]),
           let row = rows.first,
           let productTypeId = row["typeID"] as? Int,
           let quantity = row["quantity"] as? Int,
           let typeName = row["name"] as? String,
           let typeIcon = row["icon_filename"] as? String {
            
            let product = BlueprintProduct(
                typeId: productTypeId,
                typeName: typeName,
                typeIcon: typeIcon,
                quantity: quantity,
                totalQuantity: quantity * runs
            )
            
            Logger.info("蓝图ID \(blueprintId) 的产品信息: \(typeName) (ID: \(productTypeId)), 每流程: \(quantity), 总产出: \(product.totalQuantity)")
            return product
        } else {
            Logger.error("查询蓝图ID \(blueprintId) 的产品信息失败")
            return nil
        }
    }
    
    /// 获取蓝图的产品类型ID（保持向后兼容）
    /// - Parameter blueprintId: 蓝图ID
    /// - Returns: 产品类型ID，如果查询失败返回nil
    static func getBlueprintProductTypeId(blueprintId: Int) -> Int? {
        return getBlueprintProductInfo(blueprintId: blueprintId, runs: 1)?.typeId
    }
    
    /// 获取产品的分类和分组信息
    /// - Parameter typeId: 产品类型ID
    /// - Returns: 包含分类ID和分组ID的元组，如果查询失败返回nil
    static func getProductCategoryAndGroup(typeId: Int) -> (categoryId: Int, groupId: Int)? {
        let query = "SELECT groupID, categoryID FROM types WHERE type_id = ?"
        
        if case let .success(rows) = DatabaseManager.shared.executeQuery(query, parameters: [typeId]),
           let row = rows.first,
           let groupId = row["groupID"] as? Int,
           let categoryId = row["categoryID"] as? Int {
            // Logger.info("产品ID \(typeId) 的分类和分组 - 分类ID: \(categoryId), 分组ID: \(groupId)")
            return (categoryId: categoryId, groupId: groupId)
        } else {
            Logger.error("查询产品ID \(typeId) 的分类和分组失败")
            return nil
        }
    }
    
    /// 判断插件是否对指定分类和分组的产品有效
    /// - Parameters:
    ///   - rigId: 插件ID
    ///   - categoryId: 产品分类ID
    ///   - groupId: 产品分组ID
    /// - Returns: 是否有效
    static func isRigEffectiveForProduct(rigId: Int, categoryId: Int, groupId: Int) -> Bool {
        let query = """
            SELECT category, group_id 
            FROM facility_rig_effects 
            WHERE id = ?
        """
        
        if case let .success(rows) = DatabaseManager.shared.executeQuery(query, parameters: [rigId]) {
            if rows.isEmpty {
                // Logger.info("插件ID \(rigId) 在facility_rig_effects表中没有找到记录，视为对所有产品有效")
                return true
            }
            
            for row in rows {
                if let effectCategory = row["category"] as? Int,
                   let effectGroupId = row["group_id"] as? Int {
                    
                    // 检查是否匹配
                    // 如果插件的category为0，表示对所有分类有效
                    // 如果插件的group_id为0，表示对所有分组有效
                    let categoryMatch = (effectCategory == 0 || effectCategory == categoryId)
                    let groupMatch = (effectGroupId == 0 || effectGroupId == groupId)
                    
                    if categoryMatch && groupMatch {
                        // Logger.info("插件ID \(rigId) 匹配 - 效果分类: \(effectCategory), 效果分组: \(effectGroupId)")
                        return true
                    }
                }
            }
            
            // Logger.info("插件ID \(rigId) 不匹配当前产品的分类(\(categoryId))和分组(\(groupId))")
            return false
        } else {
            // Logger.error("查询插件ID \(rigId) 的作用范围失败")
            return false
        }
    }
    
    /// 计算蓝图自身的效率加成
    /// - Parameters:
    ///   - materialEfficiency: 蓝图材料效率百分比（如8表示减少8%）
    ///   - timeEfficiency: 蓝图时间效率百分比（如16表示减少16%）
    /// - Returns: 蓝图效率加成结构体
    static func getBlueprintEfficiencyBonuses(materialEfficiency: Int, timeEfficiency: Int) -> StructureBonuses {
        // 蓝图效率是百分比减少值，需要转换为乘数
        // 材料效率：如8% → 1.0 - 0.08 = 0.92（材料变为原来的92%）
        let materialMultiplier = 1.0 - (Double(materialEfficiency) / 100.0)
        
        // 时间效率：如16% → 1.0 - 0.16 = 0.84（时间变为原来的84%）
        let timeMultiplier = 1.0 - (Double(timeEfficiency) / 100.0)
        
        // 计算最终的百分比加成（从乘数反推）
        let finalMaterialBonus = (materialMultiplier - 1.0) * 100.0
        let finalTimeBonus = (timeMultiplier - 1.0) * 100.0
        
        // 记录蓝图效率加成结果
        Logger.info("[Bonus Result] 蓝图材料效率: \(materialEfficiency)% → 乘数: \(String(format: "%.3f", materialMultiplier)) (最终加成: \(String(format: "%.1f", finalMaterialBonus))%)")
        Logger.info("[Bonus Result] 蓝图时间效率: \(timeEfficiency)% → 乘数: \(String(format: "%.3f", timeMultiplier)) (最终加成: \(String(format: "%.1f", finalTimeBonus))%)")
        
        return StructureBonuses(materialBonus: materialMultiplier, timeBonus: timeMultiplier)
    }
    
    /// 获取技能对蓝图的加成
    /// - Parameters:
    ///   - blueprintId: 蓝图ID
    ///   - characterSkills: 角色技能（技能ID -> 技能等级）
    ///   - isReaction: 是否为反应蓝图
    /// - Returns: 详细信息数组
    static func getSkillBonuses(blueprintId: Int, characterSkills: [Int: Int], isReaction: Bool = false) -> [String] {
        // 定义特殊技能ID：这些技能无需考虑蓝图是否需要，直接计算加成（但不对反应蓝图生效）
        let specialSkillIds: Set<Int> = [3380, 3388]
        
        // 1. 获取蓝图所需的技能ID列表
        let requiredSkillIds = getBlueprintRequiredSkills(blueprintId: blueprintId)
        
        // 2. 构建需要检查的技能ID列表：
        // - 特殊技能ID（3380, 3388）：只对非反应蓝图有效
        // - 蓝图所需技能：检查是否具有时间效率加成
        var skillsToCheck: [Int] = []
        
        // 只对非反应蓝图添加特殊技能ID
        if !isReaction {
            skillsToCheck.append(contentsOf: specialSkillIds)
        }
        
        // 添加蓝图所需技能
        skillsToCheck.append(contentsOf: requiredSkillIds)
        
        // 去重
        skillsToCheck = Array(Set(skillsToCheck))
        
        if skillsToCheck.isEmpty {
            return ["没有找到需要检查的技能"]
        }
        
        // 3. 获取这些技能中具有时间效率加成的技能
        let skillTimeEfficiencyBonuses = getSkillTimeEfficiencyBonuses(skillIds: skillsToCheck, isReaction: isReaction)
        
        if skillTimeEfficiencyBonuses.isEmpty {
            return ["检查的技能中没有时间效率加成技能"]
        }
        
        // 4. 展示每个技能的单独加成
        var skillBonusDetails: [String] = []
        
        for (skillId, bonusPerLevel) in skillTimeEfficiencyBonuses {
            let skillLevel = characterSkills[skillId] ?? 0
            let skillBonus = bonusPerLevel * Double(skillLevel)
            
            // 判断技能类型
            let skillType: String
            if specialSkillIds.contains(skillId) {
                if isReaction {
                    skillType = "特殊技能（反应蓝图不生效）"
                } else {
                    skillType = "特殊技能（无需蓝图要求）"
                }
            } else {
                skillType = "蓝图所需技能"
            }
            
            let detail = "技能ID \(skillId) (\(skillType)) - 等级: \(skillLevel), 每级加成: \(bonusPerLevel)%, 该技能加成: \(skillBonus)%"
            skillBonusDetails.append(detail)
        }
        return skillBonusDetails
    }
    
    /// 获取蓝图所需的技能ID列表
    /// - Parameter blueprintId: 蓝图ID
    /// - Returns: 技能ID列表
    static func getBlueprintRequiredSkills(blueprintId: Int) -> [Int] {
        let query = """
            SELECT DISTINCT typeID 
            FROM blueprint_manufacturing_skills 
            WHERE blueprintTypeID = ?
        """
        
        var skillIds: [Int] = []
        
        if case let .success(rows) = DatabaseManager.shared.executeQuery(query, parameters: [blueprintId]) {
            for row in rows {
                if let skillId = row["typeID"] as? Int {
                    skillIds.append(skillId)
                }
            }
        } else {
            Logger.error("查询蓝图ID \(blueprintId) 所需技能失败")
        }
        
        return skillIds
    }
    
    /// 获取技能的时间效率加成属性
    /// - Parameters:
    ///   - skillIds: 技能ID列表
    ///   - isReaction: 是否为反应类技能
    /// - Returns: 技能ID -> 每级加成百分比的字典
    static func getSkillTimeEfficiencyBonuses(skillIds: [Int], isReaction: Bool = false) -> [Int: Double] {
        guard !skillIds.isEmpty else {
            return [:]
        }
        
        // 定义技能ID对应的属性ID映射
        let skillAttributeMapping: [Int: Int] = [
            3380: 440,   // 技能3380使用属性440
            3388: 1961   // 技能3388使用属性1961
        ]
        
        var skillBonuses: [Int: Double] = [:]
        
        // 为每个技能ID查询对应的属性
        for skillId in skillIds {
            let attributeId: Int
            if let mappedAttributeId = skillAttributeMapping[skillId] {
                attributeId = mappedAttributeId
            } else if isReaction {
                attributeId = 2660  // 反应类技能使用属性2660
            } else {
                attributeId = 1982  // 其他技能使用属性1982
            }
            
        let query = """
            SELECT type_id, value 
            FROM typeAttributes 
                WHERE type_id = ? AND attribute_id = ?
            """
            
            if case let .success(rows) = DatabaseManager.shared.executeQuery(query, parameters: [skillId, attributeId]),
               let row = rows.first,
                   let bonusValue = row["value"] as? Double {
                    skillBonuses[skillId] = bonusValue
                let skillType = isReaction ? "反应类技能" : "普通技能"
                Logger.info("技能ID \(skillId) (\(skillType)) 使用属性ID \(attributeId) 获取时间效率加成: \(bonusValue)% 每级")
            }
        }
        
        return skillBonuses
    }
    
    /// 获取所有有效的技能加成（用于实际计算）
    /// - Parameters:
    ///   - blueprintId: 蓝图ID
    ///   - characterSkills: 角色技能（技能ID -> 技能等级）
    ///   - isReaction: 是否为反应蓝图
    /// - Returns: 技能加成结构体
    static func getAllEffectiveSkillBonuses(blueprintId: Int, characterSkills: [Int: Int], isReaction: Bool = false) -> StructureBonuses {
        // 定义特殊技能ID：这些技能无需考虑蓝图是否需要，直接计算加成（但不对反应蓝图生效）
        let specialSkillIds: Set<Int> = [3380, 3388]
        
        // 1. 获取蓝图所需的技能ID列表
        let requiredSkillIds = getBlueprintRequiredSkills(blueprintId: blueprintId)
        
        // 2. 构建需要检查的技能ID列表
        var skillsToCheck: [Int] = []
        
        // 只对非反应蓝图添加特殊技能ID
        if !isReaction {
            skillsToCheck.append(contentsOf: specialSkillIds)
        }
        
        skillsToCheck.append(contentsOf: requiredSkillIds)
        skillsToCheck = Array(Set(skillsToCheck)) // 去重
        
        // 3. 获取这些技能的时间效率加成
        let skillTimeEfficiencyBonuses = getSkillTimeEfficiencyBonuses(skillIds: skillsToCheck, isReaction: isReaction)
        
        // 4. 计算总的时间效率加成（累乘乘数）
        var totalTimeMultiplier: Double = 1.0
        
        for (skillId, bonusPerLevel) in skillTimeEfficiencyBonuses {
            let skillLevel = characterSkills[skillId] ?? 0
            let skillBonus = bonusPerLevel * Double(skillLevel)
            
            // 将百分比加成转换为乘数（如-30% → 0.7）
            let skillMultiplier = 1.0 + (skillBonus / 100.0)
            totalTimeMultiplier *= skillMultiplier
            
            // 记录日志
            let skillType: String
            if specialSkillIds.contains(skillId) {
                skillType = isReaction ? "特殊技能（反应蓝图不生效）" : "特殊技能"
            } else {
                skillType = "蓝图所需技能"
            }
            Logger.info("技能ID \(skillId) (\(skillType)) - 等级: \(skillLevel), 每级加成: \(bonusPerLevel)%, 该技能加成: \(skillBonus)%, 乘数: \(String(format: "%.3f", skillMultiplier))")
        }
        
        // 计算最终的百分比加成（从乘数反推）
        let finalTimeBonus = (totalTimeMultiplier - 1.0) * 100.0
        
        Logger.info(" [Bonus Result] 技能总时间效率乘数: \(String(format: "%.3f", totalTimeMultiplier)) (最终加成: \(String(format: "%.1f", finalTimeBonus))%)")
        
        return StructureBonuses(materialBonus: 1.0, timeBonus: totalTimeMultiplier)
    }
    
    /// 获取建筑及其插件的总加成（累乘逻辑）
    /// - Parameters:
    ///   - structureTypeId: 建筑类型ID
    ///   - rigIds: 插件ID列表
    ///   - blueprintId: 蓝图ID
    ///   - isReaction: 是否为反应类型
    ///   - systemId: 星系ID
    /// - Returns: 建筑及插件总加成结构体
    static func getStructureAndRigBonuses(
        structureTypeId: Int,
        rigIds: [Int],
        blueprintId: Int,
        isReaction: Bool,
        systemId: Int
    ) -> StructureBonuses {
        
        // 1. 获取带安全等级修正的建筑加成
        let structureBonuses = getStructureBonusesWithSecurity(structureTypeId: structureTypeId, isReaction: isReaction, systemId: systemId)
        
        // 2. 筛选有效的插件
        let effectiveRigIds = getEffectiveRigIds(rigIds: rigIds, blueprintId: blueprintId)
        
        // 3. 获取带安全等级修正的有效插件加成
        let rigBonuses = getRigBonusesWithSecurity(rigIds: effectiveRigIds, structureTypeId: structureTypeId, isReaction: isReaction, systemId: systemId)
        
        // 4. 计算总加成（累乘逻辑）
        let totalMaterialMultiplier = structureBonuses.materialBonus * rigBonuses.materialBonus
        let totalTimeMultiplier = structureBonuses.timeBonus * rigBonuses.timeBonus
        
        // 5. 计算最终的百分比加成（从乘数反推）
        let finalMaterialBonus = (totalMaterialMultiplier - 1.0) * 100.0
        let finalTimeBonus = (totalTimeMultiplier - 1.0) * 100.0
        
        // 6. 记录详细日志
        Logger.info("建筑及插件加成分析:")
        
        // 展示建筑材料效率计算过程
        let structureMaterialBonus = (structureBonuses.materialBonus - 1.0) * 100.0
        let rigMaterialBonus = (rigBonuses.materialBonus - 1.0) * 100.0
        Logger.info("  建筑材料效率: \(String(format: "%.3f", structureBonuses.materialBonus)) (加成: \(String(format: "%.1f", structureMaterialBonus))%)")
        if !effectiveRigIds.isEmpty {
            Logger.info("  插件材料效率: \(String(format: "%.3f", rigBonuses.materialBonus)) (加成: \(String(format: "%.1f", rigMaterialBonus))%)")
            Logger.info("  材料效率计算: \(String(format: "%.3f", structureBonuses.materialBonus)) × \(String(format: "%.3f", rigBonuses.materialBonus)) = \(String(format: "%.3f", totalMaterialMultiplier))")
        } else {
            Logger.info("  无有效插件，材料效率: \(String(format: "%.3f", structureBonuses.materialBonus))")
        }
        
        // 展示建筑时间效率计算过程
        let structureTimeBonus = (structureBonuses.timeBonus - 1.0) * 100.0
        let rigTimeBonus = (rigBonuses.timeBonus - 1.0) * 100.0
        Logger.info("  建筑时间效率: \(String(format: "%.3f", structureBonuses.timeBonus)) (加成: \(String(format: "%.1f", structureTimeBonus))%)")
        if !effectiveRigIds.isEmpty {
            Logger.info("  插件时间效率: \(String(format: "%.3f", rigBonuses.timeBonus)) (加成: \(String(format: "%.1f", rigTimeBonus))%)")
            Logger.info("  时间效率计算: \(String(format: "%.3f", structureBonuses.timeBonus)) × \(String(format: "%.3f", rigBonuses.timeBonus)) = \(String(format: "%.3f", totalTimeMultiplier))")
        } else {
            Logger.info("  无有效插件，时间效率: \(String(format: "%.3f", structureBonuses.timeBonus))")
        }
        
        Logger.info("[Bonus Result] 建筑材料效率乘数: \(String(format: "%.3f", totalMaterialMultiplier)) (最终加成: \(String(format: "%.1f", finalMaterialBonus))%)")
        Logger.info("[Bonus Result] 建筑时间效率乘数: \(String(format: "%.3f", totalTimeMultiplier)) (最终加成: \(String(format: "%.1f", finalTimeBonus))%)")
        
        return StructureBonuses(materialBonus: totalMaterialMultiplier, timeBonus: totalTimeMultiplier)
    }
    
    /// 获取安全类别的中文名称
    /// - Parameter securityClass: 安全类别
    /// - Returns: 中文名称
    static func getSecurityClassName(_ securityClass: SecurityClass) -> String {
        switch securityClass {
        case .highSec:
            return "高安"
        case .lowSec:
            return "低安"
        case .nullSecOrWH:
            return "0.0或虫洞"
        }
    }
    
    /// 获取带安全等级修正的建筑加成
    /// - Parameters:
    ///   - structureTypeId: 建筑类型ID
    ///   - isReaction: 是否为反应类型
    ///   - systemId: 星系ID
    /// - Returns: 建筑加成结构体
    static func getStructureBonusesWithSecurity(structureTypeId: Int, isReaction: Bool, systemId: Int) -> StructureBonuses {
        // 1. 一次性获取建筑的所有属性（包括安全等级修正系数）
        let structureAttributes = getStructureAttributes(structureTypeId: structureTypeId, isReaction: isReaction)
        
        // 2. 获取星系安全等级信息
        let systemInfo = getSystemInfo(systemId: systemId, databaseManager: DatabaseManager.shared)
        guard let security = systemInfo.security else {
            Logger.warning("无法获取星系ID \(systemId) 的安全等级，使用原始加成")
            return StructureBonuses(materialBonus: structureAttributes.materialBonus, timeBonus: structureAttributes.timeBonus)
        }
        
        let securityClass = getSecurityClass(trueSec: security)
        Logger.info("星系ID \(systemId) 安全等级: \(security), 类别: \(getSecurityClassName(securityClass))")
        
        // 3. 根据安全类别选择对应的修正系数
        let securityModifier: Double
        switch securityClass {
        case .highSec:
            securityModifier = structureAttributes.highSecModifier
        case .lowSec:
            securityModifier = structureAttributes.lowSecModifier
        case .nullSecOrWH:
            securityModifier = structureAttributes.nullSecModifier
        }
        
        Logger.info("建筑ID \(structureTypeId) 在\(getSecurityClassName(securityClass))的修正系数: \(securityModifier)")
        
        // 4. 应用修正
        let rawMaterialBonus = (structureAttributes.materialBonus - 1.0) * 100.0
        let rawTimeBonus = (structureAttributes.timeBonus - 1.0) * 100.0
        
        let modifiedMaterialBonus = rawMaterialBonus * securityModifier
        let modifiedTimeBonus = rawTimeBonus * securityModifier
        
        // 转换回乘数
        let finalMaterialMultiplier = 1.0 + (modifiedMaterialBonus / 100.0)
        let finalTimeMultiplier = 1.0 + (modifiedTimeBonus / 100.0)
        
        Logger.info("建筑ID \(structureTypeId) 安全等级修正:")
        Logger.info("  原始材料加成: \(String(format: "%.1f", rawMaterialBonus))%, 修正后: \(String(format: "%.1f", modifiedMaterialBonus))%")
        Logger.info("  原始时间加成: \(String(format: "%.1f", rawTimeBonus))%, 修正后: \(String(format: "%.1f", modifiedTimeBonus))%")
        
        return StructureBonuses(materialBonus: finalMaterialMultiplier, timeBonus: finalTimeMultiplier)
    }
    
    /// 获取带安全等级修正的插件加成
    /// - Parameters:
    ///   - rigIds: 插件ID列表
    ///   - structureTypeId: 建筑类型ID
    ///   - isReaction: 是否为反应类型
    ///   - systemId: 星系ID
    /// - Returns: 插件加成结构体
    static func getRigBonusesWithSecurity(rigIds: [Int], structureTypeId: Int, isReaction: Bool, systemId: Int) -> StructureBonuses {
        guard !rigIds.isEmpty else {
            return StructureBonuses()
        }
        
        // 1. 一次性获取所有插件的属性（包括安全等级修正系数）
        let rigAttributes = getRigAttributes(rigIds: rigIds, structureTypeId: structureTypeId, isReaction: isReaction)
        
        // 2. 获取星系安全等级信息
        let systemInfo = getSystemInfo(systemId: systemId, databaseManager: DatabaseManager.shared)
        guard let security = systemInfo.security else {
            Logger.warning("无法获取星系ID \(systemId) 的安全等级，使用原始插件加成")
            return getRigBonuses(rigIds: rigIds, structureTypeId: structureTypeId, isReaction: isReaction)
        }
        
        let securityClass = getSecurityClass(trueSec: security)
        
        var materialBonus: Double = 1.0
        var timeBonus: Double = 1.0
        
        // 3. 对每个插件应用安全等级修正
        for rig in rigAttributes {
            // 根据安全类别选择对应的修正系数
            let securityModifier: Double
            switch securityClass {
            case .highSec:
                securityModifier = rig.highSecModifier
            case .lowSec:
                securityModifier = rig.lowSecModifier
            case .nullSecOrWH:
                securityModifier = rig.nullSecModifier
            }
            
            Logger.info("插件ID \(rig.rigId) 在\(getSecurityClassName(securityClass))的修正系数: \(securityModifier)")
            
            // 应用时间效率修正
            if rig.timeBonus != 0.0 {
                let modifiedValue = rig.timeBonus * securityModifier
                let percentageReduction = abs(modifiedValue)
                let multiplier = 1.0 - (percentageReduction / 100.0)
                timeBonus *= multiplier
                Logger.info("插件ID \(rig.rigId) 时间效率: 原始\(rig.timeBonus)% → 修正后\(String(format: "%.1f", modifiedValue))% (乘数: \(String(format: "%.3f", multiplier)))")
            }
            
            // 应用材料效率修正
            if rig.materialBonus != 0.0 {
                let modifiedValue = rig.materialBonus * securityModifier
                let percentageReduction = abs(modifiedValue)
                let multiplier = 1.0 - (percentageReduction / 100.0)
                materialBonus *= multiplier
                Logger.info("插件ID \(rig.rigId) 材料效率: 原始\(rig.materialBonus)% → 修正后\(String(format: "%.1f", modifiedValue))% (乘数: \(String(format: "%.3f", multiplier)))")
            }
        }
        
        return StructureBonuses(materialBonus: materialBonus, timeBonus: timeBonus)
    }
    
    // MARK: - 蓝图基础数据获取方法
    
    /// 从数据库获取蓝图的基础材料需求
    /// - Parameter blueprintId: 蓝图ID
    /// - Returns: 材料需求列表，如果获取失败返回nil
    static func getBlueprintMaterials(blueprintId: Int) -> [MaterialRequirement]? {
        let query = """
            SELECT bm.typeID, bm.typeName, bm.typeIcon, bm.quantity, t.en_name as typeEnName
            FROM blueprint_manufacturing_materials bm
            LEFT JOIN types t ON bm.typeID = t.type_id
            WHERE bm.blueprintTypeID = ?
        """
        
        guard case let .success(rows) = DatabaseManager.shared.executeQuery(query, parameters: [blueprintId]) else {
            Logger.info("获取蓝图材料需求失败: 查询数据库出错")
            return nil
        }
        
        guard !rows.isEmpty else {
            Logger.info("获取蓝图材料需求失败: 未找到蓝图ID \(blueprintId) 的材料需求")
            return nil
        }
        
        var materials: [MaterialRequirement] = []
        
        for row in rows {
            guard let typeId = row["typeID"] as? Int,
                  let typeName = row["typeName"] as? String,
                  let typeIcon = row["typeIcon"] as? String,
                  let quantity = row["quantity"] as? Int else {
                Logger.info("解析材料需求数据失败: 数据格式错误")
                continue
            }
            
            // 获取英文名称，如果为空则使用中文名称
            let typeEnName = (row["typeEnName"] as? String) ?? typeName
            
            let isQuantityOne = quantity == 1
            
            let material = MaterialRequirement(
                typeId: typeId,
                typeName: typeName,
                typeEnName: typeEnName,
                typeIcon: typeIcon,
                originalQuantity: quantity,
                finalQuantity: quantity, // 临时设置，将在后续计算中更新
                isQuantityOne: isQuantityOne
            )
            
            materials.append(material)
            Logger.info("材料需求: \(typeName) (ID: \(typeId)), 数量: \(quantity)\(isQuantityOne ? " [不受加成影响]" : "")")
        }
        
        Logger.info("成功获取蓝图ID \(blueprintId) 的材料需求，共 \(materials.count) 种材料")
        return materials
    }
    
    /// 从数据库获取蓝图的基础时间需求
    /// - Parameter blueprintId: 蓝图ID
    /// - Returns: 时间需求信息，如果获取失败返回nil
    static func getBlueprintTime(blueprintId: Int) -> Int? {
        let query = """
            SELECT manufacturing_time
            FROM blueprint_process_time
            WHERE blueprintTypeID = ?
        """
        
        guard case let .success(rows) = DatabaseManager.shared.executeQuery(query, parameters: [blueprintId]) else {
            Logger.info("获取蓝图时间需求失败: 查询数据库出错")
            return nil
        }
        
        guard let row = rows.first,
              let manufacturingTime = row["manufacturing_time"] as? Int else {
            Logger.info("获取蓝图时间需求失败: 未找到蓝图ID \(blueprintId) 的时间需求")
            return nil
        }
        
        Logger.info("蓝图ID \(blueprintId) 制造时间: \(manufacturingTime) 秒每流程")
        return manufacturingTime
    }
    
    // MARK: - 最终计算方法
    
    /// 计算最终材料需求（应用加成和流程数）
    /// - Parameters:
    ///   - baseMaterials: 基础材料需求
    ///   - runs: 流程数
    ///   - materialMultiplier: 材料效率乘数
    /// - Returns: 最终材料需求列表
    static func calculateFinalMaterials(
        baseMaterials: [MaterialRequirement],
        runs: Int,
        materialMultiplier: Double
    ) -> [MaterialRequirement] {
        Logger.info("开始计算最终材料需求:")
        Logger.info("  流程数: \(runs)")
        Logger.info("  材料效率乘数: \(String(format: "%.3f", materialMultiplier))")
        
        var finalMaterials: [MaterialRequirement] = []
        
        for material in baseMaterials {
            let finalQuantity: Int
            
            if material.isQuantityOne {
                // 数量为1的材料不受加成影响
                finalQuantity = material.originalQuantity * runs
                Logger.info("  \(material.typeName): \(material.originalQuantity) × \(runs) = \(finalQuantity) [不受加成影响]")
            } else {
                // 应用材料效率加成，然后向上取整
                let exactQuantity = Double(material.originalQuantity) * materialMultiplier * Double(runs)
                finalQuantity = Int(ceil(exactQuantity))
                Logger.info("  \(material.typeName): \(material.originalQuantity) × \(String(format: "%.3f", materialMultiplier)) × \(runs) = \(String(format: "%.2f", exactQuantity)) → \(finalQuantity) [向上取整]")
            }
            
            let finalMaterial = MaterialRequirement(
                typeId: material.typeId,
                typeName: material.typeName,
                typeEnName: material.typeEnName,
                typeIcon: material.typeIcon,
                originalQuantity: material.originalQuantity,
                finalQuantity: finalQuantity,
                isQuantityOne: material.isQuantityOne
            )
            
            finalMaterials.append(finalMaterial)
        }
        
        Logger.info("材料需求计算完成，共 \(finalMaterials.count) 种材料")
        return finalMaterials
    }
    
    /// 计算最终时间需求（应用加成和流程数）
    /// - Parameters:
    ///   - baseTime: 基础时间（秒每流程）
    ///   - runs: 流程数
    ///   - timeMultiplier: 时间效率乘数
    /// - Returns: 最终时间需求
    static func calculateFinalTime(
        baseTime: Int,
        runs: Int,
        timeMultiplier: Double
    ) -> TimeRequirement {
        Logger.info("开始计算最终时间需求:")
        Logger.info("  基础时间: \(baseTime) 秒每流程")
        Logger.info("  流程数: \(runs)")
        Logger.info("  时间效率乘数: \(String(format: "%.3f", timeMultiplier))")
        
        let finalTime = Double(baseTime) * timeMultiplier * Double(runs)
        
        Logger.info("  总时间计算: \(baseTime) × \(String(format: "%.3f", timeMultiplier)) × \(runs) = \(String(format: "%.2f", finalTime)) 秒")
        
        let timeRequirement = TimeRequirement(
            manufacturingTime: baseTime,
            finalTime: finalTime
        )
        
        // 格式化时间显示
        let totalSeconds = Int(finalTime)
        let days = totalSeconds / 86400
        let hours = (totalSeconds % 86400) / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        let timeString: String
        if days > 0 {
            timeString = "\(days)天 \(String(format: "%02d:%02d:%02d", hours, minutes, seconds))"
        } else {
            timeString = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        
        Logger.info("[Bonus Result] 最终制造时间: \(String(format: "%.2f", finalTime)) 秒 (\(timeString))")
        
        return timeRequirement
    }
    
    // MARK: - 手续费计算相关
    
    /// 手续费计算参数结构体
    struct FacilityCostParams {
        let materials: [MaterialRequirement]  // 材料需求列表
        let solarSystemId: Int               // 星系ID
        let facilityTax: Double              // 设施税率（小数形式）
        let isReaction: Bool                 // 是否为反应类型
        let scc: Double = 0.04               // SCC费用，固定为4%
        
        init(materials: [MaterialRequirement], solarSystemId: Int, facilityTax: Double, isReaction: Bool) {
            self.materials = materials
            self.solarSystemId = solarSystemId
            self.facilityTax = facilityTax
            self.isReaction = isReaction
        }
    }
    
    /// 计算设施手续费
    /// - Parameter params: 手续费计算参数
    /// - Returns: 设施费用
    static func calculateFacilityCost(params: FacilityCostParams) -> Double {
        Logger.info("开始计算设施手续费:")
        Logger.info("  星系ID: \(params.solarSystemId)")
        Logger.info("  设施税率: \(String(format: "%.4f", params.facilityTax)) (\(String(format: "%.2f", params.facilityTax * 100))%)")
        Logger.info("  是否为反应: \(params.isReaction)")
        Logger.info("  SCC费用: \(String(format: "%.4f", params.scc)) (\(String(format: "%.2f", params.scc * 100))%)")
        
        // 1. 计算EIV（输入物品的市场估价总和）
        let eiv = calculateEIV(materials: params.materials)
        Logger.info("  EIV计算: \(String(format: "%.2f", eiv)) ISK")
        
        // 2. 获取星系成本指数
        let costIndex = getSystemCostIndex(solarSystemId: params.solarSystemId, isReaction: params.isReaction)
        Logger.info("  星系成本指数: \(String(format: "%.4f", costIndex)) (\(String(format: "%.2f", costIndex * 100))%)")
        
        // 3. 计算最终手续费
        let facilityCost = eiv * (costIndex + params.facilityTax + params.scc)
        
        Logger.info("  手续费计算: \(String(format: "%.2f", eiv)) × (\(String(format: "%.4f", costIndex)) + \(String(format: "%.4f", params.facilityTax)) + \(String(format: "%.4f", params.scc))) = \(String(format: "%.2f", facilityCost)) ISK")
        Logger.info("[Bonus Result] 设施手续费: \(String(format: "%.2f", facilityCost)) ISK")
        
        return facilityCost
    }
    
    /// 计算EIV（输入物品的市场估价总和）
    /// - Parameter materials: 材料需求列表
    /// - Returns: EIV总值
    static func calculateEIV(materials: [MaterialRequirement]) -> Double {
        Logger.info("开始计算EIV（输入物品市场估价总和）:")
        
        // 收集所有材料的类型ID
        let typeIds = materials.map { $0.typeId }
        
        // 使用Task同步等待异步结果
        var prices: [Int: Double] = [:]
        let semaphore = DispatchSemaphore(value: 0)
        
        Task {
            prices = await MarketPriceUtil.getMarketPrices(typeIds: typeIds)
            semaphore.signal()
        }
        
        semaphore.wait()
        Logger.info("  获取到 \(prices.count) 个物品的市场价格")
        
        var totalEIV: Double = 0.0
        
        for material in materials {
            let unitPrice = prices[material.typeId] ?? 0.0
            let materialCost = unitPrice * Double(material.finalQuantity)
            
            Logger.info("    材料 \(material.typeName) (ID: \(material.typeId)): \(material.finalQuantity) × \(String(format: "%.2f", unitPrice)) = \(String(format: "%.2f", materialCost)) ISK")
            
            totalEIV += materialCost
        }
        
        Logger.info("  EIV总计: \(String(format: "%.2f", totalEIV)) ISK")
        return totalEIV
    }
    
    /// 获取星系成本指数
    /// - Parameters:
    ///   - solarSystemId: 星系ID
    ///   - isReaction: 是否为反应类型
    /// - Returns: 成本指数
    static func getSystemCostIndex(solarSystemId: Int, isReaction: Bool) -> Double {
        // 获取所有星系的成本指数
        let systems = fetchIndustrySystems()
        
        // 查找指定星系
        if let system = systems.first(where: { $0.solar_system_id == solarSystemId }) {
            // 根据类型查找对应的成本指数
            let activityType = isReaction ? "reaction" : "manufacturing"
            if let costIndex = system.cost_indices.first(where: { $0.activity == activityType })?.cost_index {
                Logger.info("  找到星系 \(solarSystemId) 的\(activityType)成本指数: \(String(format: "%.4f", costIndex))")
                return costIndex
            }
        }
        
        // 找不到则使用默认值
        let defaultCostIndex = 0.0014 // 0.14%
        Logger.info("  未找到星系 \(solarSystemId) 的成本指数，使用默认值: \(String(format: "%.4f", defaultCostIndex))")
        return defaultCostIndex
    }
    
    /// 获取所有星系的成本指数
    /// - Returns: 星系成本指数列表
    static func fetchIndustrySystems() -> [IndustrySystem] {
        Logger.info("获取星系成本指数数据...")
        
        // 使用Task同步等待异步结果
        var systems: [IndustrySystem] = []
        let semaphore = DispatchSemaphore(value: 0)
        
        Task {
            do {
                systems = try await IndustrySystemsAPI.shared.fetchIndustrySystems()
                Logger.info("  成功获取 \(systems.count) 个星系的成本指数")
            } catch {
                Logger.error("  获取星系成本指数失败: \(error)")
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        return systems
    }
} 
