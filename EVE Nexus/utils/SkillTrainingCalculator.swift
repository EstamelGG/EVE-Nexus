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