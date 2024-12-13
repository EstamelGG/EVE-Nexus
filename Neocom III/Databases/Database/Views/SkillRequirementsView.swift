import SwiftUI

struct SkillRequirementsView: View {
    let typeID: Int
    @ObservedObject var databaseManager: DatabaseManager
    
    var body: some View {
        let directRequirements = databaseManager.getDirectSkillRequirements(for: typeID)
        if !directRequirements.isEmpty {
            Section(header: Text(NSLocalizedString("Main_Database_Skill_Requirements", comment: ""))) {
                ForEach(directRequirements, id: \.skillID) { requirement in
                    // 获取该技能的所有前置技能
                    let allRequirements = SkillTreeManager.shared.getAllRequirements(for: requirement.skillID)
                    
                    // 显示直接技能要求
                    SkillRequirementRow(
                        skillID: requirement.skillID,
                        level: requirement.level,
                        indentLevel: 0,
                        databaseManager: databaseManager
                    )
                    
                    // 显示前置技能要求
                    ForEach(allRequirements, id: \.self) { prereq in
                        SkillRequirementRow(
                            skillID: prereq.skillID,
                            level: prereq.level,
                            indentLevel: 1,
                            databaseManager: databaseManager
                        )
                    }
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
