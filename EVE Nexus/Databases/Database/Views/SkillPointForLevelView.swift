import SwiftUI

struct SkillPointForLevelView: View {
    let skillId: Int
    let characterId: Int?
    let databaseManager: DatabaseManager
    
    private static let defaultAttributes: [Int: Int] = [
        3: 20, // 感知
        4: 20, // 记忆
        1: 20, // 毅力
        2: 20, // 智力
        5: 19  // 魅力
    ]
    
    private var skillAttributes: (primary: Int, secondary: Int, timeModifier: Int)? {
        let result = databaseManager.executeQuery(
            "SELECT primary_attribute, secondary_attribute, time_modifier FROM types WHERE type_id = ?",
            parameters: [skillId]
        )
        
        if case .success(let rows) = result,
           let row = rows.first,
           let primary = row["primary_attribute"] as? Int,
           let secondary = row["secondary_attribute"] as? Int,
           let timeModifier = row["time_modifier"] as? Int {
            return (primary, secondary, timeModifier)
        }
        return nil
    }
    
    private var characterAttributes: [Int: Int] {
        // 如果没有角色ID或查询失败，直接返回默认值
        guard let characterId = characterId else {
            return Self.defaultAttributes
        }
        
        let result = CharacterDatabaseManager.shared.executeQuery(
            "SELECT attribute_id, value FROM character_attributes WHERE character_id = ?",
            parameters: [characterId]
        )
        
        var attributes: [Int: Int] = [:]
        if case .success(let rows) = result {
            for row in rows {
                if let attributeId = row["attribute_id"] as? Int,
                   let value = row["value"] as? Int {
                    attributes[attributeId] = value
                }
            }
        }
        
        return attributes.isEmpty ? Self.defaultAttributes : attributes
    }
    
    private var skillPointsPerHour: Double {
        guard let attrs = skillAttributes,
              let primary = characterAttributes[attrs.primary],
              let secondary = characterAttributes[attrs.secondary] else {
            return 0
        }
        
        return Double(primary * 60 + secondary * 30) / Double(attrs.timeModifier)
    }
    
    private func getSkillPointsForLevel(_ level: Int) -> Int {
        let result = databaseManager.executeQuery(
            "SELECT sp_level\(level) as sp FROM skill_points WHERE type_id = ?",
            parameters: [skillId]
        )
        
        if case .success(let rows) = result,
           let row = rows.first,
           let sp = row["sp"] as? Int {
            return sp
        }
        return 0
    }
    
    private func formatTrainingTime(skillPoints: Int) -> String {
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
    }
} 