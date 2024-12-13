import SwiftUI

struct SkillRequirementsView: View {
    let typeID: Int
    @ObservedObject var databaseManager: DatabaseManager
    
    // 去重并保留最高等级的技能要求
    private func deduplicateSkillRequirements(_ requirements: [(skillID: Int, level: Int)], _ prerequisites: [SkillRequirement]) -> [(skillID: Int, level: Int)] {
        var highestLevels: [Int: Int] = [:]
        
        // 处理直接要求
        for requirement in requirements {
            highestLevels[requirement.skillID] = requirement.level
        }
        
        // 处理前置要求
        for prereq in prerequisites {
            if let existingLevel = highestLevels[prereq.skillID] {
                highestLevels[prereq.skillID] = max(existingLevel, prereq.level)
            } else {
                highestLevels[prereq.skillID] = prereq.level
            }
        }
        
        // 转换回数组并按等级排序
        return highestLevels.map { (skillID: $0.key, level: $0.value) }
            .sorted { $0.level > $1.level }
    }
    
    var body: some View {
        let directRequirements = databaseManager.getDirectSkillRequirements(for: typeID)
        if !directRequirements.isEmpty {
            Section(header: Text(NSLocalizedString("Main_Database_Skill_Requirements", comment: ""))) {
                // 收集所有前置技能
                let allPrerequisites = directRequirements.flatMap { requirement in
                    SkillTreeManager.shared.getAllRequirements(for: requirement.skillID)
                }
                
                // 对所有技能要求进行去重
                let deduplicatedRequirements = deduplicateSkillRequirements(directRequirements, allPrerequisites)
                
                // 显示所有技能要求
                ForEach(deduplicatedRequirements, id: \.skillID) { requirement in
                    SkillRequirementRow(
                        skillID: requirement.skillID,
                        level: requirement.level,
                        indentLevel: 0,
                        databaseManager: databaseManager
                    )
                }
            }
        }
    }
}

// 单个技能要求行
struct SkillRequirementRow: View {
    let skillID: Int
    let level: Int
    let indentLevel: Int
    @ObservedObject var databaseManager: DatabaseManager
    
    var body: some View {
        if let skillName = SkillTreeManager.shared.getSkillName(for: skillID) {
            NavigationLink {
                if let categoryID = databaseManager.getCategoryID(for: skillID) {
                    ItemInfoMap.getItemInfoView(
                        itemID: skillID,
                        categoryID: categoryID,
                        databaseManager: databaseManager
                    )
                }
            } label: {
                HStack {
                    if indentLevel > 0 {
                        Spacer()
                            .frame(width: CGFloat(indentLevel) * 20)
                    }
                    
                    // 技能图标
                    if let iconFileName = databaseManager.getItemIconFileName(for: skillID) {
                        IconManager.shared.loadImage(for: iconFileName)
                            .resizable()
                            .frame(width: 32, height: 32)
                            .cornerRadius(6)
                    }
                    
                    // 技能名称
                    Text(skillName)
                        .font(.body)
                    
                    Spacer()
                    
                    // 等级要求
                    Text("Lv \(level)")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
} 
