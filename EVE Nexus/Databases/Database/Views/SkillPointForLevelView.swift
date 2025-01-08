import SwiftUI

struct SkillPointForLevelView: View {
    let skillId: Int
    let characterId: Int?
    let databaseManager: DatabaseManager
    @State private var characterAttributes: CharacterAttributes?
    @State private var timeMultiplier: Int = 1
    @State private var skillPrimaryAttr: Int = 0
    @State private var skillSecondaryAttr: Int = 0
    
    private static let defaultAttributes = CharacterAttributes(
        charisma: 19,
        intelligence: 20,
        memory: 20,
        perception: 20,
        willpower: 20,
        bonus_remaps: 0,
        accrued_remap_cooldown_date: nil,
        last_remap_date: nil
    )
    
    private var skillPointsPerHour: Double {
        guard skillPrimaryAttr > 0 && skillSecondaryAttr > 0 else {
            return 0
        }
        
        let attributes = characterAttributes ?? Self.defaultAttributes
        return Double(SkillTrainingCalculator.calculateTrainingRate(
            primaryAttrId: skillPrimaryAttr,
            secondaryAttrId: skillSecondaryAttr,
            attributes: attributes
        ) ?? 0)
    }
    
    private func getSkillPointsForLevel(_ level: Int) -> Int {
        let basePoints = SkillProgressCalculator.baseSkillPoints[level - 1]
        return basePoints * timeMultiplier
    }
    
    private func formatTrainingTime(skillPoints: Int) -> String {
        guard skillPointsPerHour > 0 else {
            return NSLocalizedString("Main_Database_Not_Available", comment: "N/A")
        }
        
        let hours = Double(skillPoints) / skillPointsPerHour
        
        if hours < 1 {
            let minutes = Int(hours * 60)
            return String(format: NSLocalizedString("Time_Minutes", comment: "%dm"), minutes)
        } else if hours < 24 {
            let intHours = Int(hours)
            let minutes = Int((hours - Double(intHours)) * 60)
            if minutes > 0 {
                return String(format: NSLocalizedString("Time_Hours_Minutes", comment: "%dh %dm"), intHours, minutes)
            }
            return String(format: NSLocalizedString("Time_Hours", comment: "%dh"), intHours)
        } else {
            let days = Int(hours / 24)
            let remainingHours = Int(hours.truncatingRemainder(dividingBy: 24))
            if remainingHours > 0 {
                return String(format: NSLocalizedString("Time_Days_Hours", comment: "%dd %dh"), days, remainingHours)
            }
            return String(format: NSLocalizedString("Time_Days", comment: "%dd"), days)
        }
    }
    
    var body: some View {
        Section(header: Text(NSLocalizedString("Main_Database_Skill_Level_Detail", comment: "")).font(.headline)) {
            ForEach(1...5, id: \.self) { level in
                let requiredSP = getSkillPointsForLevel(level)
                
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(FormatUtil.format(Double(requiredSP))) SP")
                            .font(.body)
                        Text("\(formatTrainingTime(skillPoints: requiredSP)) (\(FormatUtil.format(skillPointsPerHour))/h)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("Lv0 → Lv\(level)")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
        }
        .task {
            // 获取技能倍增系数
            let result = databaseManager.executeQuery(
                """
                SELECT value
                FROM typeAttributes
                WHERE type_id = ? AND attribute_id = 275
                """,
                parameters: [skillId]
            )
            
            if case .success(let rows) = result,
               let row = rows.first,
               let value = row["value"] as? Double {
                timeMultiplier = Int(value)
            }
            
            // 获取技能主副属性
            if let attrs = SkillTrainingCalculator.getSkillAttributes(
                skillId: skillId,
                databaseManager: databaseManager
            ) {
                skillPrimaryAttr = attrs.primary
                skillSecondaryAttr = attrs.secondary
            }
            
            // 获取角色属性
            if let characterId = characterId {
                do {
                    characterAttributes = try await CharacterSkillsAPI.shared.fetchAttributes(characterId: characterId)
                } catch {
                    Logger.error("获取角色属性失败: \(error)")
                }
            }
        }
    }
} 
