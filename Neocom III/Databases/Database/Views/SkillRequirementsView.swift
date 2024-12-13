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
    
    var body: some View {
        let skills = SkillTreeManager.shared.getDeduplicatedSkillRequirements(for: typeID, databaseManager: databaseManager)
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
