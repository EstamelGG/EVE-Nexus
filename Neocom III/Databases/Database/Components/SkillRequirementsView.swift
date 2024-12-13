import SwiftUI

/// 技能需求视图项
struct SkillRequirementItemView: View {
    let skillID: Int
    let level: Int
    let indentLevel: Int
    @ObservedObject var databaseManager: DatabaseManager
    
    var body: some View {
        HStack {
            // 缩进空间
            if indentLevel > 0 {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: CGFloat(indentLevel) * 20)
            }
            
            // 技能图标（如果有的话）
            if let iconFileName = getSkillIcon(skillID: skillID) {
                IconManager.shared.loadImage(for: iconFileName)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)
            }
            
            // 技能名称和等级
            if let skillName = SkillTreeManager.shared.getSkillName(for: skillID) {
                Text(skillName)
                Spacer()
                Text("Level \(level)")
                    .foregroundColor(.secondary)
            } else {
                Text("Unknown Skill")
                    .foregroundColor(.red)
            }
        }
    }
    
    // 获取技能图标
    private func getSkillIcon(skillID: Int) -> String? {
        let query = """
            SELECT icon_filename
            FROM types
            WHERE type_id = \(skillID)
        """
        
        if case .success(let rows) = databaseManager.executeQuery(query),
           let row = rows.first,
           let iconFileName = row["icon_filename"] as? String {
            return iconFileName.isEmpty ? DatabaseConfig.defaultItemIcon : iconFileName
        }
        return nil
    }
}

/// 技能需求树视图
struct SkillRequirementsView: View {
    let attributeGroup: AttributeGroup
    let allAttributes: [Int: Double]
    @ObservedObject var databaseManager: DatabaseManager
    
    // 获取直接技能需求
    private var directRequirements: [SkillRequirement] {
        var requirements: [SkillRequirement] = []
        
        // 技能ID和等级的属性对
        let skillPairs = [
            (skillID: 182, levelID: 277),   // 主技能
            (skillID: 183, levelID: 278),   // 副技能
            (skillID: 184, levelID: 279),   // 三级技能
            (skillID: 1285, levelID: 1286), // 四级技能
            (skillID: 1289, levelID: 1287), // 五级技能
            (skillID: 1290, levelID: 1288)  // 六级技能
        ]
        
        // 遍历所有属性，找出技能需求
        for attribute in attributeGroup.attributes {
            for pair in skillPairs {
                if attribute.id == pair.skillID {
                    let skillID = attribute.intValue
                    if let levelValue = allAttributes[pair.levelID] {
                        let level = Int(levelValue)
                        requirements.append(SkillRequirement(skillID: skillID, level: level))
                    }
                }
            }
        }
        
        return requirements
    }
    
    // 获取完整的技能需求树（包括所有前置技能）
    private func getAllRequirements() -> [(skillID: Int, level: Int, indentLevel: Int)] {
        var result: [(skillID: Int, level: Int, indentLevel: Int)] = []
        var processed = Set<Int>()
        
        // 递归函数来构建需求树
        func addRequirements(for requirement: SkillRequirement, indentLevel: Int) {
            // 避免重复添加相同的技能
            if processed.contains(requirement.skillID) {
                return
            }
            
            // 添加当前技能
            result.append((requirement.skillID, requirement.level, indentLevel))
            processed.insert(requirement.skillID)
            
            // 获取并添加前置需求
            let prerequisites = SkillTreeManager.shared.getDirectPrerequisites(for: requirement.skillID)
            for prereq in prerequisites {
                addRequirements(for: prereq, indentLevel: indentLevel + 1)
            }
        }
        
        // 处理所有直接需求
        for requirement in directRequirements {
            addRequirements(for: requirement, indentLevel: 0)
        }
        
        return result
    }
    
    var body: some View {
        if !directRequirements.isEmpty {
            Section {
                ForEach(getAllRequirements(), id: \.skillID) { requirement in
                    SkillRequirementItemView(
                        skillID: requirement.skillID,
                        level: requirement.level,
                        indentLevel: requirement.indentLevel,
                        databaseManager: databaseManager
                    )
                }
            } header: {
                Text(NSLocalizedString("Item_Required_Skills", comment: ""))
                    .font(.headline)
            }
        }
    }
} 