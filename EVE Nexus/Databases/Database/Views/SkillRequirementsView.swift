import SwiftUI

// 单个技能要求行
struct SkillRequirementRow: View {
    let skillID: Int
    let level: Int
    let timeMultiplier: Double?
    @ObservedObject var databaseManager: DatabaseManager

    private var skillPointsText: String {
        guard let multiplier = timeMultiplier,
            level > 0 && level <= SkillTreeManager.levelBasePoints.count
        else {
            return ""
        }
        let points = Int(Double(SkillTreeManager.levelBasePoints[level - 1]) * multiplier)
        return "\(FormatUtil.format(Double(points))) SP"
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
