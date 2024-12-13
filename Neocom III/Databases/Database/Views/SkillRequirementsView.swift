import SwiftUI

// 单个技能要求行
struct SkillRequirementRow: View {
    let skillID: Int
    let level: Int
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

struct SkillRequirementsView: View {
    let typeID: Int
    @ObservedObject var databaseManager: DatabaseManager
    
    // 获取所有技能要求（包括直接和间接技能）并去重
    private func getAllSkillRequirements() -> [(skillID: Int, level: Int)] {
        // 获取直接技能要求
        let directRequirements = databaseManager.getDirectSkillRequirements(for: typeID)
        
        // 获取所有间接技能要求
        let indirectRequirements = directRequirements.flatMap { requirement in
            SkillTreeManager.shared.getAllRequirements(for: requirement.skillID)
                .map { (skillID: $0.skillID, level: $0.level) }
        }
        
        // 合并所有技能要求并去重，保留最高等级
        var skillMap: [Int: Int] = [:]  // [skillID: maxLevel]
        
        // 处理所有技能要求
        (directRequirements + indirectRequirements).forEach { requirement in
            if let existingLevel = skillMap[requirement.skillID] {
                // 如果已存在该技能，保留更高等级的要求
                skillMap[requirement.skillID] = max(existingLevel, requirement.level)
            } else {
                skillMap[requirement.skillID] = requirement.level
            }
        }
        
        // 转换为数组并按等级排序
        return skillMap.map { (skillID: $0.key, level: $0.value) }
            .sorted { $0.level > $1.level }
    }
    
    var body: some View {
        let skills = getAllSkillRequirements()
        if !skills.isEmpty {
            Section(header: Text(NSLocalizedString("Main_Database_Skill_Requirements", comment: ""))) {
                ForEach(skills, id: \.skillID) { skill in
                    SkillRequirementRow(
                        skillID: skill.skillID,
                        level: skill.level,
                        databaseManager: databaseManager
                    )
                }
            }
        }
    }
} 
