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
        return Double(
            SkillTrainingCalculator.calculateTrainingRate(
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
                return String(
                    format: NSLocalizedString("Time_Hours_Minutes", comment: "%dh %dm"), intHours,
                    minutes
                )
            }
            return String(format: NSLocalizedString("Time_Hours", comment: "%dh"), intHours)
        } else {
            let days = Int(hours / 24)
            let remainingHours = Int(hours.truncatingRemainder(dividingBy: 24))
            if remainingHours > 0 {
                return String(
                    format: NSLocalizedString("Time_Days_Hours", comment: "%dd %dh"), days,
                    remainingHours
                )
            }
            return String(format: NSLocalizedString("Time_Days", comment: "%dd"), days)
        }
    }

    // 新增：从本地数据库加载角色属性
    private func loadAttributesFromDatabase(characterId: Int) -> CharacterAttributes? {
        let query = """
            SELECT charisma, intelligence, memory, perception, willpower,
                   bonus_remaps, accrued_remap_cooldown_date, last_remap_date
            FROM character_attributes 
            WHERE character_id = ?
        """
        
        guard
            case let .success(rows) = CharacterDatabaseManager.shared.executeQuery(
                query, parameters: [characterId]),
            let row = rows.first
        else {
            return nil
        }
        
        // 使用 NSNumber 转换来处理不同的数字类型
        let charisma = (row["charisma"] as? NSNumber)?.intValue ?? 19
        let intelligence = (row["intelligence"] as? NSNumber)?.intValue ?? 20
        let memory = (row["memory"] as? NSNumber)?.intValue ?? 20
        let perception = (row["perception"] as? NSNumber)?.intValue ?? 20
        let willpower = (row["willpower"] as? NSNumber)?.intValue ?? 20
        let bonusRemaps = (row["bonus_remaps"] as? NSNumber)?.intValue ?? 0
        
        return CharacterAttributes(
            charisma: charisma,
            intelligence: intelligence,
            memory: memory,
            perception: perception,
            willpower: willpower,
            bonus_remaps: bonusRemaps,
            accrued_remap_cooldown_date: row["accrued_remap_cooldown_date"] as? String,
            last_remap_date: row["last_remap_date"] as? String
        )
    }

    var body: some View {
        Section(
            header: Text(NSLocalizedString("Main_Database_Skill_Level_Detail", comment: "")).font(
                .headline)
        ) {
            ForEach(1...5, id: \.self) { level in
                let requiredSP = getSkillPointsForLevel(level)

                HStack {
                    VStack(alignment: .leading) {
                        Text("\(FormatUtil.format(Double(requiredSP))) SP")
                            .font(.body)
                        Text(
                            "\(formatTrainingTime(skillPoints: requiredSP)) (\(FormatUtil.format(skillPointsPerHour))/h)"
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(
                        String(format: NSLocalizedString("Misc_Level_Short", comment: "lv%d"), 0)
                            + " → "
                            + String(
                                format: NSLocalizedString("Misc_Level_Short", comment: "lv%d"),
                                level)
                    )
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

            if case let .success(rows) = result,
                let row = rows.first,
                let value = row["value"] as? Double
            {
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

            // 获取角色属性（从本地数据库）
            if let characterId = characterId {
                characterAttributes = loadAttributesFromDatabase(characterId: characterId)
                if characterAttributes != nil {
                    Logger.debug("从本地数据库加载角色属性成功")
                } else {
                    Logger.debug("本地数据库中未找到角色属性，使用默认值")
                }
            }
        }
    }
}
