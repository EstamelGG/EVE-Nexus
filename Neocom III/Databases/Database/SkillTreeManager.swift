import Foundation

/// 技能需求模型
struct SkillRequirement {
    let skillID: Int
    let level: Int
}

/// 技能节点模型
class SkillNode {
    let skillID: Int
    let name: String
    var requirements: [SkillRequirement]
    
    init(skillID: Int, name: String, requirements: [SkillRequirement] = []) {
        self.skillID = skillID
        self.name = name
        self.requirements = requirements
    }
}

/// 技能树管理器
class SkillTreeManager {
    // 单例模式
    static let shared = SkillTreeManager()
    private init() {}
    
    // 存储所有技能节点
    private var skillNodes: [Int: SkillNode] = [:]
    
    // 技能需求属性ID常量
    private struct RequiredSkillAttributes {
        static let skill1ID = 182
        static let skill2ID = 183
        static let skill3ID = 184
        static let skill4ID = 1285
        static let skill5ID = 1289
        static let skill6ID = 1290
        
        static let skill1Level = 277
        static let skill2Level = 278
        static let skill3Level = 279
        static let skill4Level = 1286
        static let skill5Level = 1287
        static let skill6Level = 1288
        
        static let allSkillIDs = [skill1ID, skill2ID, skill3ID, skill4ID, skill5ID, skill6ID]
        static let allLevelIDs = [skill1Level, skill2Level, skill3Level, skill4Level, skill5Level, skill6Level]
    }
    
    /// 初始化技能树
    /// - Parameter databaseManager: 数据库管理器实例
    func initializeSkillTree(databaseManager: DatabaseManager) {
        // 1. 获取所有技能（categoryID = 16）
        let skills = databaseManager.getAllSkills()
        
        // 2. 创建基础节点
        for skill in skills {
            skillNodes[skill.typeID] = SkillNode(skillID: skill.typeID, name: skill.name)
        }
        
        // 3. 获取并设置技能需求
        for skill in skills {
            let requirements = databaseManager.getSkillRequirements(for: skill.typeID)
            skillNodes[skill.typeID]?.requirements = requirements
        }
    }
    
    /// 获取指定技能的所有前置需求（递归）
    /// - Parameter skillID: 技能ID
    /// - Returns: 包含所有前置需求的数组，每个元素包含技能ID和所需等级
    func getAllPrerequisites(for skillID: Int) -> [(skillID: Int, level: Int)] {
        var prerequisites: [(skillID: Int, level: Int)] = []
        var visited = Set<Int>()
        
        func traverse(currentSkillID: Int) {
            guard !visited.contains(currentSkillID),
                  let node = skillNodes[currentSkillID] else {
                return
            }
            
            visited.insert(currentSkillID)
            
            for requirement in node.requirements {
                prerequisites.append((requirement.skillID, requirement.level))
                traverse(currentSkillID: requirement.skillID)
            }
        }
        
        traverse(currentSkillID: skillID)
        return prerequisites
    }
    
    /// 检查是否有循环依赖
    /// - Parameter skillID: 起始技能ID
    /// - Returns: 是否存在循环依赖
    func hasCircularDependency(for skillID: Int) -> Bool {
        var visited = Set<Int>()
        var recursionStack = Set<Int>()
        
        func checkCycle(_ currentSkillID: Int) -> Bool {
            if recursionStack.contains(currentSkillID) {
                return true
            }
            
            if visited.contains(currentSkillID) {
                return false
            }
            
            visited.insert(currentSkillID)
            recursionStack.insert(currentSkillID)
            
            if let node = skillNodes[currentSkillID] {
                for requirement in node.requirements {
                    if checkCycle(requirement.skillID) {
                        return true
                    }
                }
            }
            
            recursionStack.remove(currentSkillID)
            return false
        }
        
        return checkCycle(skillID)
    }
    
    /// 获取技能名称
    /// - Parameter skillID: 技能ID
    /// - Returns: 技能名称，如果不存在则返回nil
    func getSkillName(for skillID: Int) -> String? {
        return skillNodes[skillID]?.name
    }
    
    /// 获取直接前置需求
    /// - Parameter skillID: 技能ID
    /// - Returns: 直接前置需求数组
    func getDirectPrerequisites(for skillID: Int) -> [SkillRequirement] {
        return skillNodes[skillID]?.requirements ?? []
    }
    
    /// 清除所有数据
    func clear() {
        skillNodes.removeAll()
    }
}

// MARK: - DatabaseManager Extension
extension DatabaseManager {
    /// 获取所有技能
    /// - Returns: 技能数组
    func getAllSkills() -> [(typeID: Int, name: String)] {
        let query = """
            SELECT type_id, name 
            FROM types 
            WHERE category_id = 16 AND published = 1
            ORDER BY name
        """
        
        var skills: [(typeID: Int, name: String)] = []
        
        let result = executeQuery(query)
        if case .success(let rows) = result {
            for row in rows {
                if let typeID = row["type_id"] as? Int,
                   let name = row["name"] as? String {
                    skills.append((typeID: typeID, name: name))
                }
            }
        }
        
        return skills
    }
    
    /// 获取技能的需求
    /// - Parameter skillID: 技能ID
    /// - Returns: 技能需求数组
    func getSkillRequirements(for skillID: Int) -> [SkillRequirement] {
        var requirements: [SkillRequirement] = []
        
        // 构建查询条件
        let skillPairs = [
            (skillID: 182, levelID: 277),
            (skillID: 183, levelID: 278),
            (skillID: 184, levelID: 279),
            (skillID: 1285, levelID: 1286),
            (skillID: 1289, levelID: 1287),
            (skillID: 1290, levelID: 1288)
        ]
        
        let conditions = skillPairs.map { pair in
            """
            (ta1.attribute_id = \(pair.skillID) AND ta2.attribute_id = \(pair.levelID))
            """
        }.joined(separator: " OR ")
        
        let query = """
            SELECT ta1.value as required_skill_id, ta2.value as required_level
            FROM typeAttributes ta1
            JOIN typeAttributes ta2 ON ta1.type_id = ta2.type_id
            WHERE ta1.type_id = \(skillID) AND (\(conditions))
            ORDER BY ta1.attribute_id
        """
        
        let result = executeQuery(query)
        if case .success(let rows) = result {
            for row in rows {
                if let requiredSkillID = (row["required_skill_id"] as? NSNumber)?.doubleValue,
                   let requiredLevel = (row["required_level"] as? NSNumber)?.doubleValue {
                    requirements.append(SkillRequirement(
                        skillID: Int(requiredSkillID),
                        level: Int(requiredLevel)
                    ))
                }
            }
        }
        
        return requirements
    }
} 