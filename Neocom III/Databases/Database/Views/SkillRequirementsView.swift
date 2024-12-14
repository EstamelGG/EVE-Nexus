import SwiftUI

// 单个技能要求行
struct SkillRequirementRow: View {
    let skillID: Int
    let level: Int
    let timeMultiplier: Double?
    @ObservedObject var databaseManager: DatabaseManager
    
    // 技能等级对应的基础点数
    private let levelBasePoints = [250, 1415, 8000, 45255, 256000]
    
    private var skillPointsText: String {
        guard let multiplier = timeMultiplier,
              level > 0 && level <= levelBasePoints.count else {
            return ""
        }
        let points = Int(Double(levelBasePoints[level - 1]) * multiplier)
        return "\(NumberFormatUtil.format(Double(points))) SP"
    }
    
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
                    
                    VStack(alignment: .leading) {
                        // 技能名称
                        Text(skillName)
                            .font(.body)
                        
                        // 所需技能点数
                        if !skillPointsText.isEmpty {
                            Text(skillPointsText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
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
                        timeMultiplier: skill.timeMultiplier,
                        databaseManager: databaseManager
                    )
                }
            }
        }
    }
} 
