import SwiftUI

struct SkillPointForLevelView: View {
    let skillId: Int
    let characterId: Int?
    let databaseManager: DatabaseManager
    @State private var characterAttributes: CharacterAttributes?
    
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
    
    private var skillAttributes: (primary: Int, secondary: Int)? {
        return SkillTrainingCalculator.getSkillAttributes(
            skillId: skillId,
            databaseManager: databaseManager
        )
    }
    
    private var skillPointsPerHour: Double {
        guard let attrs = skillAttributes else {
            return 0
        }
        
        let attributes = characterAttributes ?? Self.defaultAttributes
        return Double(SkillTrainingCalculator.calculateTrainingRate(
            primaryAttrId: attrs.primary,
            secondaryAttrId: attrs.secondary,
            attributes: attributes
        ) ?? 0)
    }
    
    private func getSkillPointsForLevel(_ level: Int) -> Int {
        Logger.debug("获取技能\(skillId)等级\(level)所需技能点")
        // 获取技能倍增系数
        let result = databaseManager.executeQuery(
            """
            SELECT value
            FROM typeAttributes
            WHERE type_id = ? AND attribute_id = 275
            """,
            parameters: [skillId]
        )
        
        var timeMultiplier: Double = 1.0
        if case .success(let rows) = result,
           let row = rows.first,
           let value = row["value"] as? Double {
            timeMultiplier = value
        }
        
        // 使用基准点数乘以倍增系数
        let basePoints = SkillProgressCalculator.baseSkillPoints[level - 1]
        let totalPoints = Int(Double(basePoints) * timeMultiplier)
        Logger.debug("基准点数: \(basePoints), 倍增系数: \(timeMultiplier), 总点数: \(totalPoints)")
        return totalPoints
    }
    
    private func formatTrainingTime(skillPoints: Int) -> String {
        Logger.debug("SkillPointsPerHour: \(skillPointsPerHour)")
        guard skillPointsPerHour > 0 else {
            return "N/A"
        }
        
        let hours = Double(skillPoints) / skillPointsPerHour
        
        if hours < 1 {
            let minutes = Int(hours * 60)
            return "\(minutes)分钟"
        } else if hours < 24 {
            let intHours = Int(hours)
            let minutes = Int((hours - Double(intHours)) * 60)
            if minutes > 0 {
                return "\(intHours)小时\(minutes)分钟"
            }
            return "\(intHours)小时"
        } else {
            let days = Int(hours / 24)
            let remainingHours = Int(hours.truncatingRemainder(dividingBy: 24))
            if remainingHours > 0 {
                return "\(days)天\(remainingHours)小时"
            }
            return "\(days)天"
        }
    }
    
    var body: some View {
        List {
            ForEach(1...5, id: \.self) { level in
                let requiredSP = getSkillPointsForLevel(level)
                
                HStack {
                    Text("等级 \(level)")
                        .frame(width: 60, alignment: .leading)
                    
                    Text("\(FormatUtil.format(Double(requiredSP)))点")
                        .frame(width: 80, alignment: .trailing)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(formatTrainingTime(skillPoints: requiredSP))
                        .foregroundColor(.secondary)
                }
                .font(.system(.body, design: .monospaced))
            }
        }
        .listStyle(.plain)
        .task {
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
