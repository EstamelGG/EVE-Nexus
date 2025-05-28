import SwiftUI

// 单个技能要求行
struct SkillRequirementRow: View {
    let skillID: Int
    let level: Int
    let timeMultiplier: Double?
    @ObservedObject var databaseManager: DatabaseManager
    let icon: Image
    let currentLevel: Int?

    // 新：获取当前技能点数（直接查表，不累加）
    private func getCurrentSkillPointsSimple(for skillID: Int) -> Int {
        guard let currentLevel = currentLevel, let multiplier = timeMultiplier else { return 0 }
        if currentLevel <= 0 { return 0 }
        if currentLevel > SkillTreeManager.levelBasePoints.count { return 0 }
        return Int(Double(SkillTreeManager.levelBasePoints[currentLevel - 1]) * multiplier)
    }
    // 新：获取所需总点数（直接查表）
    private func getRequiredSkillPointsSimple(for level: Int) -> Int {
        guard let multiplier = timeMultiplier else { return 0 }
        if level <= 0 || level > SkillTreeManager.levelBasePoints.count { return 0 }
        return Int(Double(SkillTreeManager.levelBasePoints[level - 1]) * multiplier)
    }

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
                ItemInfoMap.getItemInfoView(
                    itemID: skillID,
                    databaseManager: databaseManager
                )
            } label: {
                HStack {
                    // 技能图标
                    if let currentLevel = currentLevel, currentLevel == -1 {
                        Image(systemName: "xmark.circle.fill")
                            .frame(width: 32, height: 32)
                            .foregroundColor(.red)
                    } else {
                        icon
                            .frame(width: 32, height: 32)
                            .foregroundColor((currentLevel ?? 0) >= level ? .green : .primary)
                    }

                    VStack(alignment: .leading) {
                        // 技能名称
                        Text(skillName)
                            .font(.body)

                        // 所需技能点数
                        // if !skillPointsText.isEmpty {
                        //     Text(skillPointsText)
                        //         .font(.caption)
                        //         .foregroundColor(.secondary)
                        // }
                        // 新增：显示缺失技能点数（直接查表方式）
                        if let currentLevel = currentLevel, currentLevel >= -1, currentLevel < level
                        {
                            let currentSP = getCurrentSkillPointsSimple(for: skillID)
                            let requiredSP = getRequiredSkillPointsSimple(for: level)
                            Text(
                                "\(FormatUtil.format(Double(currentSP)))/\(FormatUtil.format(Double(requiredSP))) SP"
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                        } else {
                            if !skillPointsText.isEmpty {
                                Text(skillPointsText)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Spacer()

                    // 等级要求
                    Text(String(format: NSLocalizedString("Misc_Level", comment: "lv%d"), level))
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// 技能要求组显示组件
struct SkillRequirementsView: View {
    let typeID: Int
    let groupName: String
    @ObservedObject var databaseManager: DatabaseManager
    @AppStorage("currentCharacterId") private var currentCharacterId: Int = 0
    
    // 存储所有技能等级的字典
    @State private var characterSkills: [Int: Int] = [:]

    private var requirements: [(skillID: Int, level: Int, timeMultiplier: Double?)] {
        SkillTreeManager.shared.getDeduplicatedSkillRequirements(
            for: typeID, databaseManager: databaseManager
        )
    }

    private var totalPoints: Int {
        requirements.reduce(0) { total, skill in
            guard let multiplier = skill.timeMultiplier,
                skill.level > 0 && skill.level <= SkillTreeManager.levelBasePoints.count
            else {
                return total
            }
            let points = Int(
                Double(SkillTreeManager.levelBasePoints[skill.level - 1]) * multiplier)
            return total + points
        }
    }

    // 计算缺少的技能点数
    private var missingPoints: Int {
        requirements.reduce(0) { total, skill in
            guard let multiplier = skill.timeMultiplier,
                skill.level > 0 && skill.level <= SkillTreeManager.levelBasePoints.count
            else {
                return total
            }

            let currentLevel = getCurrentSkillLevel(for: skill.skillID)
            if currentLevel >= skill.level {
                return total
            }

            let requiredPoints = Int(
                Double(SkillTreeManager.levelBasePoints[skill.level - 1]) * multiplier)
            let currentPoints =
                currentLevel > 0
                ? Int(Double(SkillTreeManager.levelBasePoints[currentLevel - 1]) * multiplier) : 0
            return total + (requiredPoints - currentPoints)
        }
    }

    // 获取技能图标
    private func getSkillIcon(for skillID: Int, requiredLevel: Int) -> Image {
        if currentCharacterId == 0 {
            // 未登录时显示技能图标
            return Image(systemName: "circle")
        } else {
            // 已登录时根据技能等级显示状态图标
            let currentLevel = getCurrentSkillLevel(for: skillID)
            if currentLevel >= requiredLevel {
                return Image(systemName: "checkmark.circle.fill")
            } else {
                return Image(systemName: "circle")
            }
        }
    }

    // 获取当前技能等级 - 从预加载的数据中获取
    private func getCurrentSkillLevel(for skillID: Int) -> Int {
        return characterSkills[skillID] ?? -1
    }
    
    // 加载所有技能等级
    private func loadAllSkills() {
        if currentCharacterId == 0 {
            characterSkills = [:]
            return
        }
        
        let skillsQuery = "SELECT skills_data FROM character_skills WHERE character_id = ?"
        
        guard
            case let .success(rows) = CharacterDatabaseManager.shared.executeQuery(
                skillsQuery, parameters: [currentCharacterId]),
            let row = rows.first,
            let skillsJson = row["skills_data"] as? String,
            let data = skillsJson.data(using: .utf8)
        else {
            characterSkills = [:]
            return
        }
        
        do {
            let decoder = JSONDecoder()
            let skillsResponse = try decoder.decode(CharacterSkillsResponse.self, from: data)
            
            // 将所有技能映射到字典中
            var skillsDict = [Int: Int]()
            for skill in skillsResponse.skills {
                skillsDict[skill.skill_id] = skill.trained_skill_level
            }
            characterSkills = skillsDict
        } catch {
            Logger.error("解析技能数据失败: \(error)")
            characterSkills = [:]
        }
    }

    var body: some View {
        if !requirements.isEmpty {
            Section(
                header: Text(groupName)
                    .font(.headline),
                footer: Text(
                    (currentCharacterId == 0 || missingPoints == 0)
                        ? "\(NSLocalizedString("Misc_InAll",comment: "")): \(FormatUtil.format(Double(totalPoints))) SP"
                        : "\(NSLocalizedString("Misc_InAll",comment: "")): \(FormatUtil.format(Double(totalPoints))) SP, \(NSLocalizedString("Misc_Need",comment: "")): \(FormatUtil.format(Double(missingPoints))) SP"
                )
                .font(.caption)
                .foregroundColor(.secondary)
            ) {
                ForEach(requirements, id: \.skillID) { requirement in
                    SkillRequirementRow(
                        skillID: requirement.skillID,
                        level: requirement.level,
                        timeMultiplier: requirement.timeMultiplier,
                        databaseManager: databaseManager,
                        icon: getSkillIcon(
                            for: requirement.skillID, requiredLevel: requirement.level),
                        currentLevel: currentCharacterId == 0
                            ? nil : getCurrentSkillLevel(for: requirement.skillID)
                    )
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            }
            .onAppear {
                loadAllSkills()
            }
        }
    }
}
