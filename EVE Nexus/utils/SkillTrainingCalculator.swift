import Foundation

/// 技能训练速度计算器
struct SkillTrainingCalculator {
    /// 属性ID常量
    struct AttributeID {
        static let charisma = 164
        static let intelligence = 165
        static let memory = 166
        static let perception = 167
        static let willpower = 168
    }
    
    /// 植入体属性ID常量
    private struct ImplantAttributeID {
        // 植入体属性加成的属性ID
        static let charisma = 175      // 魅力加成
        static let intelligence = 176   // 智力加成
        static let memory = 177        // 记忆加成
        static let perception = 178     // 感知加成
        static let willpower = 179      // 意志加成
        
        // 验证属性ID是否存在
        static func validateAttributeIds() {
            let query = """
                SELECT attribute_id, attribute_name
                FROM attributeTypes
                WHERE attribute_id IN (175, 176, 177, 178, 179)
            """
            
            if case .success(let rows) = DatabaseManager().executeQuery(query) {
                Logger.debug("植入体属性ID验证结果:")
                for row in rows {
                    if let attrId = row["attribute_id"] as? Int,
                       let attrName = row["attribute_name"] as? String {
                        Logger.debug("属性ID: \(attrId), 名称: \(attrName)")
                    }
                }
            } else {
                Logger.error("无法验证植入体属性ID")
            }
        }
    }
    
    /// 最优属性分配结果
    public struct OptimalAttributes {
        public let charisma: Int
        public let intelligence: Int
        public let memory: Int
        public let perception: Int
        public let willpower: Int
        public let totalTrainingTime: TimeInterval
        public let currentTrainingTime: TimeInterval
    }
    
    /// 技能训练信息
    private struct SkillTrainingInfo {
        let skillId: Int
        let remainingSP: Int
        let primaryAttr: Int
        let secondaryAttr: Int
    }
    
    /// 添加缓存
    private static var skillAttributesCache: [Int: (primary: Int, secondary: Int)] = [:]
    
    /// 清除缓存
    public static func clearCache() {
        skillAttributesCache.removeAll()
    }
    
    /// 批量加载技能属性到缓存
    public static func preloadSkillAttributes(skillIds: [Int], databaseManager: DatabaseManager) {
        let attributesQuery = """
            SELECT type_id, attribute_id, value
            FROM typeAttributes
            WHERE type_id IN (\(skillIds.map { String($0) }.joined(separator: ",")))
            AND attribute_id IN (180, 181)
        """
        
        if case .success(let rows) = databaseManager.executeQuery(attributesQuery) {
            var groupedAttributes: [Int: [(attributeId: Int, value: Int)]] = [:]
            for row in rows {
                guard let typeId = row["type_id"] as? Int,
                      let attributeId = row["attribute_id"] as? Int,
                      let value = row["value"] as? Double else {
                    continue
                }
                groupedAttributes[typeId, default: []].append((attributeId, Int(value)))
            }
            
            for (typeId, attributes) in groupedAttributes {
                var primary: Int?
                var secondary: Int?
                for attr in attributes {
                    if attr.attributeId == 180 {
                        primary = attr.value
                    } else if attr.attributeId == 181 {
                        secondary = attr.value
                    }
                }
                if let p = primary, let s = secondary {
                    skillAttributesCache[typeId] = (p, s)
                }
            }
        }
    }
    
    /// 获取技能的训练属性（优先从缓存获取）
    static func getSkillAttributes(skillId: Int, databaseManager: DatabaseManager) -> (primary: Int, secondary: Int)? {
        // 先从缓存中查找
        if let cached = skillAttributesCache[skillId] {
            return cached
        }
        
        // 如果缓存中没有，则从数据库查询
        let query = """
            SELECT attribute_id, value
            FROM typeAttributes
            WHERE type_id = ? AND attribute_id IN (180, 181)
        """
        
        if case .success(let rows) = databaseManager.executeQuery(query, parameters: [skillId]) {
            var primaryAttrId: Int?
            var secondaryAttrId: Int?
            
            for row in rows {
                guard let attrId = row["attribute_id"] as? Int,
                      let value = row["value"] as? Double else { continue }
                
                switch attrId {
                case 180: primaryAttrId = Int(value)
                case 181: secondaryAttrId = Int(value)
                default: break
                }
            }
            
            if let primary = primaryAttrId, let secondary = secondaryAttrId {
                // 将结果存入缓存
                let result = (primary, secondary)
                skillAttributesCache[skillId] = result
                return result
            }
        }
        
        return nil
    }
    
    /// 获取植入体属性加成
    public static func getImplantBonuses(characterId: Int) async -> ImplantAttributes {
        // 验证植入体属性ID
        ImplantAttributeID.validateAttributeIds()
        
        var bonuses = ImplantAttributes()
        
        do {
            // 获取角色的植入体
            let implants = try await CharacterImplantsAPI.shared.fetchCharacterImplants(
                characterId: characterId,
                forceRefresh: false
            )
            
            Logger.debug("获取到植入体列表: \(implants)")
            
            // 如果有植入体，查询它们的属性加成
            if !implants.isEmpty {
                let query = """
                    SELECT type_id, attribute_id, value
                    FROM typeAttributes
                    WHERE type_id IN (\(implants.map { String($0) }.joined(separator: ",")))
                    AND attribute_id IN (\(ImplantAttributeID.charisma), \(ImplantAttributeID.intelligence), 
                                      \(ImplantAttributeID.memory), \(ImplantAttributeID.perception), 
                                      \(ImplantAttributeID.willpower))
                """
                
                Logger.debug("执行植入体属性查询: \(query)")
                
                if case .success(let rows) = DatabaseManager().executeQuery(query) {
                    Logger.debug("查询结果行数: \(rows.count)")
                    
                    // 为每个属性保存最大值
                    var maxBonuses: [Int: Int] = [:]
                    
                    for row in rows {
                        guard let attributeId = row["attribute_id"] as? Int,
                              let value = row["value"] as? Double else {
                            Logger.debug("无法解析行数据: \(row)")
                            continue
                        }
                        
                        // 将加成值转换为整数
                        let bonus = Int(value)
                        // Logger.debug("解析到植入体属性 - ID: \(attributeId), 值: \(bonus)")
                        
                        // 更新最大值
                        maxBonuses[attributeId] = max(maxBonuses[attributeId] ?? 0, bonus)
                    }
                    
                    // 设置最终的加成值
                    if let charismaBonus = maxBonuses[ImplantAttributeID.charisma] {
                        bonuses.charismaBonus = charismaBonus
                        // Logger.debug("设置最终魅力加成: \(charismaBonus)")
                    }
                    if let intelligenceBonus = maxBonuses[ImplantAttributeID.intelligence] {
                        bonuses.intelligenceBonus = intelligenceBonus
                        // Logger.debug("设置最终智力加成: \(intelligenceBonus)")
                    }
                    if let memoryBonus = maxBonuses[ImplantAttributeID.memory] {
                        bonuses.memoryBonus = memoryBonus
                        // Logger.debug("设置最终记忆加成: \(memoryBonus)")
                    }
                    if let perceptionBonus = maxBonuses[ImplantAttributeID.perception] {
                        bonuses.perceptionBonus = perceptionBonus
                        // Logger.debug("设置最终感知加成: \(perceptionBonus)")
                    }
                    if let willpowerBonus = maxBonuses[ImplantAttributeID.willpower] {
                        bonuses.willpowerBonus = willpowerBonus
                        // Logger.debug("设置最终意志加成: \(willpowerBonus)")
                    }
                } else {
                    Logger.debug("查询植入体属性失败")
                }
            } else {
                Logger.debug("未找到植入体")
            }
            
            // Logger.debug("最终植入体加成结果: 感知:\(bonuses.perceptionBonus), 记忆:\(bonuses.memoryBonus), 意志:\(bonuses.willpowerBonus), 智力:\(bonuses.intelligenceBonus), 魅力:\(bonuses.charismaBonus)")
        } catch {
            Logger.error("获取植入体信息失败: \(error)")
        }
        
        return bonuses
    }
    
    /// 计算最优属性分配
    /// - Parameters:
    ///   - skillQueue: 技能队列信息数组，每个元素包含：技能ID、剩余SP、开始训练时间、结束训练时间
    ///   - databaseManager: 数据库管理器
    ///   - currentAttributes: 当前角色属性
    ///   - characterId: 角色ID
    /// - Returns: 最优属性分配结果
    public static func calculateOptimalAttributes(
        skillQueue: [(skillId: Int, remainingSP: Int, startDate: Date?, finishDate: Date?)],
        databaseManager: DatabaseManager,
        currentAttributes: CharacterAttributes,
        characterId: Int
    ) async -> OptimalAttributes? {
        var skillTrainingInfo: [SkillTrainingInfo] = []
        
        // 批量获取所有技能的属性
        let skillIds = skillQueue.map { $0.skillId }
        let attributesQuery = """
            SELECT type_id, attribute_id, value
            FROM typeAttributes
            WHERE type_id IN (\(skillIds.map { String($0) }.joined(separator: ",")))
            AND attribute_id IN (180, 181)
        """
        
        var skillAttributes: [Int: (primary: Int, secondary: Int)] = [:]
        if case .success(let rows) = databaseManager.executeQuery(attributesQuery) {
            // 按技能ID分组
            var groupedAttributes: [Int: [(attributeId: Int, value: Int)]] = [:]
            for row in rows {
                guard let typeId = row["type_id"] as? Int,
                      let attributeId = row["attribute_id"] as? Int,
                      let value = row["value"] as? Double else {
                    continue
                }
                groupedAttributes[typeId, default: []].append((attributeId, Int(value)))
            }
            
            // 处理每个技能的属性
            for (typeId, attributes) in groupedAttributes {
                var primary: Int?
                var secondary: Int?
                for attr in attributes {
                    if attr.attributeId == 180 {
                        primary = attr.value
                    } else if attr.attributeId == 181 {
                        secondary = attr.value
                    }
                }
                if let p = primary, let s = secondary {
                    skillAttributes[typeId] = (p, s)
                }
            }
        }
        
        // 处理每个技能的训练信息
        for skill in skillQueue {
            guard let attrs = skillAttributes[skill.skillId] else {
                continue
            }
            
            var remainingSP = skill.remainingSP
            
            // 如果技能正在训练，计算实际剩余SP
            if let startDate = skill.startDate,
               let finishDate = skill.finishDate {
                let now = Date()
                if now > startDate && now < finishDate {
                    let totalTrainingTime = finishDate.timeIntervalSince(startDate)
                    let trainedTime = now.timeIntervalSince(startDate)
                    let progress = trainedTime / totalTrainingTime
                    remainingSP = Int(Double(remainingSP) * (1 - progress))
                }
            }
            
            skillTrainingInfo.append(SkillTrainingInfo(
                skillId: skill.skillId,
                remainingSP: remainingSP,
                primaryAttr: attrs.primary,
                secondaryAttr: attrs.secondary
            ))
        }
        
        // 如果没有需要训练的技能，返回nil
        if skillTrainingInfo.isEmpty {
            return nil
        }
        
        // 计算当前属性下的训练时间
        var currentTime: TimeInterval = 0
        for info in skillTrainingInfo {
            if let pointsPerHour = calculateTrainingRate(
                primaryAttrId: info.primaryAttr,
                secondaryAttrId: info.secondaryAttr,
                attributes: currentAttributes
            ) {
                let trainingTimeHours = Double(info.remainingSP) / Double(pointsPerHour)
                currentTime += trainingTimeHours * 3600 // 转换为秒
            }
        }
        
        // 定义属性范围和可用点数
        let minAttr = 17
        let maxAttr = 27
        let availablePoints = 14
        
        var bestAllocation: OptimalAttributes?
        var shortestTime: TimeInterval = .infinity
        
        // 使用回溯算法尝试所有可能的属性分配
        func tryAllocatePoints(
            perception: Int,
            memory: Int,
            willpower: Int,
            intelligence: Int,
            charisma: Int,
            remainingPoints: Int,
            currentAttr: Int
        ) {
            // 检查是否所有属性都在有效范围内
            if perception < minAttr || perception > maxAttr ||
               memory < minAttr || memory > maxAttr ||
               willpower < minAttr || willpower > maxAttr ||
               intelligence < minAttr || intelligence > maxAttr ||
               charisma < minAttr || charisma > maxAttr {
                return
            }
            
            // 如果已经分配完所有点数，计算训练时间
            if currentAttr > 4 {
                if remainingPoints == 0 {
                    let attributes = CharacterAttributes(
                        charisma: charisma,
                        intelligence: intelligence,
                        memory: memory,
                        perception: perception,
                        willpower: willpower,
                        bonus_remaps: 0,
                        accrued_remap_cooldown_date: nil,
                        last_remap_date: nil
                    )
                    
                    // 计算总训练时间
                    var totalTime: TimeInterval = 0
                    for info in skillTrainingInfo {
                        if let pointsPerHour = calculateTrainingRate(
                            primaryAttrId: info.primaryAttr,
                            secondaryAttrId: info.secondaryAttr,
                            attributes: attributes
                        ) {
                            let trainingTimeHours = Double(info.remainingSP) / Double(pointsPerHour)
                            totalTime += trainingTimeHours * 3600 // 转换为秒
                        }
                    }
                    
                    // 更新最佳分配
                    if totalTime < shortestTime {
                        shortestTime = totalTime
                        bestAllocation = OptimalAttributes(
                            charisma: charisma,
                            intelligence: intelligence,
                            memory: memory,
                            perception: perception,
                            willpower: willpower,
                            totalTrainingTime: totalTime,
                            currentTrainingTime: currentTime
                        )
                    }
                }
                return
            }
            
            // 递归尝试不同的属性分配
            var nextValue: Int
            switch currentAttr {
            case 0: // 感知
                for i in 0...min(remainingPoints, maxAttr - minAttr) {
                    nextValue = minAttr + i
                    tryAllocatePoints(
                        perception: nextValue,
                        memory: memory,
                        willpower: willpower,
                        intelligence: intelligence,
                        charisma: charisma,
                        remainingPoints: remainingPoints - (nextValue - minAttr),
                        currentAttr: currentAttr + 1
                    )
                }
            case 1: // 记忆
                for i in 0...min(remainingPoints, maxAttr - minAttr) {
                    nextValue = minAttr + i
                    tryAllocatePoints(
                        perception: perception,
                        memory: nextValue,
                        willpower: willpower,
                        intelligence: intelligence,
                        charisma: charisma,
                        remainingPoints: remainingPoints - (nextValue - minAttr),
                        currentAttr: currentAttr + 1
                    )
                }
            case 2: // 意志
                for i in 0...min(remainingPoints, maxAttr - minAttr) {
                    nextValue = minAttr + i
                    tryAllocatePoints(
                        perception: perception,
                        memory: memory,
                        willpower: nextValue,
                        intelligence: intelligence,
                        charisma: charisma,
                        remainingPoints: remainingPoints - (nextValue - minAttr),
                        currentAttr: currentAttr + 1
                    )
                }
            case 3: // 智力
                for i in 0...min(remainingPoints, maxAttr - minAttr) {
                    nextValue = minAttr + i
                    tryAllocatePoints(
                        perception: perception,
                        memory: memory,
                        willpower: willpower,
                        intelligence: nextValue,
                        charisma: charisma,
                        remainingPoints: remainingPoints - (nextValue - minAttr),
                        currentAttr: currentAttr + 1
                    )
                }
            case 4: // 魅力
                nextValue = minAttr + remainingPoints
                if nextValue <= maxAttr {
                    tryAllocatePoints(
                        perception: perception,
                        memory: memory,
                        willpower: willpower,
                        intelligence: intelligence,
                        charisma: nextValue,
                        remainingPoints: 0,
                        currentAttr: currentAttr + 1
                    )
                }
            default:
                break
            }
        }
        
        // 开始尝试分配点数
        tryAllocatePoints(
            perception: minAttr,
            memory: minAttr,
            willpower: minAttr,
            intelligence: minAttr,
            charisma: minAttr,
            remainingPoints: availablePoints,
            currentAttr: 0
        )
        
        if let best = bestAllocation {
            Logger.debug("找到最优分配方案:")
            Logger.debug("基础属性 - 感知: \(best.perception), 记忆: \(best.memory), 意志: \(best.willpower), 智力: \(best.intelligence), 魅力: \(best.charisma)")
            Logger.debug("训练时间 - 当前: \(formatTimeInterval(best.currentTrainingTime)), 最优: \(formatTimeInterval(best.totalTrainingTime)), 节省: \(formatTimeInterval(best.currentTrainingTime - best.totalTrainingTime))")
        }
        
        // 返回最优属性分配结果，不包含植入体加成
        return bestAllocation
    }
    
    /// 计算技能训练速度（每小时技能点数）
    /// - Parameters:
    ///   - primaryAttrId: 主属性ID
    ///   - secondaryAttrId: 副属性ID
    ///   - attributes: 角色属性
    /// - Returns: 每小时训练点数，如果属性无效则返回nil
    static func calculateTrainingRate(
        primaryAttrId: Int,
        secondaryAttrId: Int,
        attributes: CharacterAttributes
    ) -> Int? {
        func getAttributeValue(_ attrId: Int) -> Int {
            switch attrId {
            case AttributeID.charisma: return attributes.charisma
            case AttributeID.intelligence: return attributes.intelligence
            case AttributeID.memory: return attributes.memory
            case AttributeID.perception: return attributes.perception
            case AttributeID.willpower: return attributes.willpower
            default: return 0
            }
        }
        
        let primaryValue = getAttributeValue(primaryAttrId)
        let secondaryValue = getAttributeValue(secondaryAttrId)
        
        // 每分钟训练点数 = 主属性 + 副属性/2
        let pointsPerMinute = Double(primaryValue) + Double(secondaryValue) / 2.0
        // 转换为每小时
        return Int(pointsPerMinute * 60)
    }
    
    /// 格式化时间间隔
    private static func formatTimeInterval(_ interval: TimeInterval) -> String {
        let days = Int(interval) / (24 * 3600)
        let hours = Int(interval) / 3600 % 24
        let minutes = Int(interval) / 60 % 60
        
        if days > 0 {
            if hours > 0 {
                return "\(days)天\(hours)小时"
            } else {
                return "\(days)天"
            }
        } else if hours > 0 {
            if minutes > 0 {
                return "\(hours)小时\(minutes)分钟"
            } else {
                return "\(hours)小时"
            }
        } else {
            return "\(minutes)分钟"
        }
    }
} 
