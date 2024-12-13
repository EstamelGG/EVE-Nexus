import Foundation

/// 技能要求结构
struct SkillRequirement: Hashable {
    let skillID: Int          // 技能ID
    let name: String          // 技能名称
    let level: Int           // 需要的等级
    let parentSkillID: Int?   // 哪个技能需要这个技能
    
    // Hashable 实现
    func hash(into hasher: inout Hasher) {
        hasher.combine(skillID)
        hasher.combine(parentSkillID)
    }
    
    static func == (lhs: SkillRequirement, rhs: SkillRequirement) -> Bool {
        return lhs.skillID == rhs.skillID && lhs.parentSkillID == rhs.parentSkillID
    }
}

/// 技能树管理器
class SkillTreeManager {
    // 单例
    static let shared = SkillTreeManager()
    private init() {}
    
    // 存储所有技能的基本信息 [typeID: name]
    private var allSkills: [Int: String] = [:]
    
    // 存储所有技能要求关系 [skillID: [(requiredSkillID, level)]]
    private var directRequirements: [Int: [(skillID: Int, level: Int)]] = [:]
    
    // 技能要求的属性ID对应关系
    private let skillRequirementAttributes: [(skillID: Int, levelID: Int)] = [
        (skillID: 182, levelID: 277),   // 主技能
        (skillID: 183, levelID: 278),   // 副技能
        (skillID: 184, levelID: 279),   // 三级技能
        (skillID: 1285, levelID: 1286), // 四级技能
        (skillID: 1289, levelID: 1287), // 五级技能
        (skillID: 1290, levelID: 1288)  // 六级技能
    ]
    
    /// 初始化并加载所有技能数据
    func initialize(databaseManager: DatabaseManager) {
        // 1. 加载所有技能
        let skillQuery = """
            SELECT type_id, name 
            FROM types 
            WHERE categoryID = 16
        """
        
        if case .success(let rows) = databaseManager.executeQuery(skillQuery) {
            for row in rows {
                if let typeID = row["type_id"] as? Int,
                   let name = row["name"] as? String {
                    allSkills[typeID] = name
                }
            }
        }
        
        // 2. 加载所有技能要求关系
        let requirementPairs = skillRequirementAttributes.map { 
            "(ta1.attribute_id = \($0.skillID) AND ta2.attribute_id = \($0.levelID))"
        }.joined(separator: " OR ")
        
        let requirementQuery = """
            SELECT ta1.type_id, 
                   ta1.attribute_id as skill_attr_id,
                   ta1.value as required_skill_id,
                   ta2.value as required_level
            FROM typeAttributes ta1
            JOIN typeAttributes ta2 
            ON ta1.type_id = ta2.type_id
            WHERE ta1.type_id IN (SELECT type_id FROM types WHERE categoryID = 16)
            AND (\(requirementPairs))
        """
        
        if case .success(let rows) = databaseManager.executeQuery(requirementQuery) {
            for row in rows {
                guard let typeID = row["type_id"] as? Int,
                      let requiredSkillID = row["required_skill_id"] as? Double,
                      let requiredLevel = row["required_level"] as? Double else {
                    continue
                }
                
                let skillID = Int(requiredSkillID)
                let level = Int(requiredLevel)
                
                if directRequirements[typeID] == nil {
                    directRequirements[typeID] = []
                }
                directRequirements[typeID]?.append((skillID: skillID, level: level))
            }
        }
        
        Logger.debug("技能树加载完成 - 技能总数: \(allSkills.count), 有依赖关系的技能数: \(directRequirements.count)")
    }
    
    /// 获取技能的所有前置要求（包括递归依赖）
    func getAllRequirements(for skillID: Int) -> [SkillRequirement] {
        var result: [SkillRequirement] = []
        var visited = Set<Int>()
        
        func recursiveGetRequirements(for currentSkillID: Int, parentID: Int?) {
            // 防止循环依赖
            guard !visited.contains(currentSkillID) else { return }
            visited.insert(currentSkillID)
            
            // 获取直接依赖
            if let requirements = directRequirements[currentSkillID] {
                for (requiredSkillID, level) in requirements {
                    if let skillName = allSkills[requiredSkillID] {
                        let requirement = SkillRequirement(
                            skillID: requiredSkillID,
                            name: skillName,
                            level: level,
                            parentSkillID: parentID
                        )
                        result.append(requirement)
                        // 递归获取这个技能的前置要求
                        recursiveGetRequirements(for: requiredSkillID, parentID: currentSkillID)
                    }
                }
            }
        }
        
        recursiveGetRequirements(for: skillID, parentID: nil)
        return result
    }
    
    /// 检查是否已初始化
    var isInitialized: Bool {
        return !allSkills.isEmpty
    }
    
    /// 获取技能名称
    func getSkillName(for skillID: Int) -> String? {
        return allSkills[skillID]
    }
    
    /// 清理缓存数据
    func clearCache() {
        allSkills.removeAll()
        directRequirements.removeAll()
    }
} 