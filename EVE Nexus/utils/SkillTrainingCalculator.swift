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
    
    /// 最优属性分配结果
    public struct OptimalAttributes {
        public let perception: Int
        public let memory: Int
        public let willpower: Int
        public let intelligence: Int
        public let charisma: Int
        public let totalTrainingTime: TimeInterval
        public let currentTrainingTime: TimeInterval
        
        public var savedTime: TimeInterval {
            currentTrainingTime - totalTrainingTime
        }
        
        public var asArray: [Int] {
            [perception, memory, willpower, intelligence, charisma]
        }
    }
    
    /// 技能训练信息
    private struct SkillTrainingInfo {
        let skillId: Int
        let remainingSP: Int
        let primaryAttr: Int
        let secondaryAttr: Int
    }
    
    /// 计算最优属性分配
    /// - Parameters:
    ///   - skillQueue: 技能队列信息数组，每个元素包含：技能ID、剩余SP、开始训练时间、结束训练时间
    ///   - databaseManager: 数据库管理器
    ///   - currentAttributes: 当前角色属性
    /// - Returns: 最优属性分配结果
    public static func calculateOptimalAttributes(
        skillQueue: [(skillId: Int, remainingSP: Int, startDate: Date?, finishDate: Date?)],
        databaseManager: DatabaseManager,
        currentAttributes: CharacterAttributes
    ) -> OptimalAttributes? {
        var skillTrainingInfo: [SkillTrainingInfo] = []
        
        // 处理每个技能的训练信息
        for skill in skillQueue {
            guard let attrs = getSkillAttributes(skillId: skill.skillId, databaseManager: databaseManager) else {
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
                            perception: perception,
                            memory: memory,
                            willpower: willpower,
                            intelligence: intelligence,
                            charisma: charisma,
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
    
    /// 获取技能的训练属性
    /// - Parameters:
    ///   - skillId: 技能ID
    ///   - databaseManager: 数据库管理器
    /// - Returns: 主属性ID和副属性ID，如果查询失败则返回nil
    static func getSkillAttributes(skillId: Int, databaseManager: DatabaseManager) -> (primary: Int, secondary: Int)? {
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
                return (primary, secondary)
            }
        }
        
        return nil
    }
} 