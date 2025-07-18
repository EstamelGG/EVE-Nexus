import SwiftUI

// 单个技能要求行
struct SkillRequirementRow: View {
    let skillID: Int
    let level: Int
    let timeMultiplier: Double?
    @ObservedObject var databaseManager: DatabaseManager
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
                    } else if let currentLevel = currentLevel, currentLevel >= level {
                        Image(systemName: "checkmark.circle.fill")
                            .frame(width: 32, height: 32)
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: "circle")
                            .frame(width: 32, height: 32)
                            .foregroundColor(.primary)
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
    // 新增：存储角色属性点数
    @State private var characterAttributes: CharacterAttributes?

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

    // 获取当前技能等级 - 从预加载的数据中获取
    private func getCurrentSkillLevel(for skillID: Int) -> Int {
        return characterSkills[skillID] ?? -1
    }
    
    // 新增：计算缺失技能的预计训练时间
    private var estimatedTrainingTime: TimeInterval {
        guard let attributes = characterAttributes, missingPoints > 0 else {
            return 0
        }
        
        // 获取所有未满足技能的属性（批量查询，优化性能）
        let skillAttributesMap = unmetSkillAttributes
        
        var totalTime: TimeInterval = 0
        
        for requirement in requirements {
            let currentLevel = getCurrentSkillLevel(for: requirement.skillID)
            if currentLevel >= requirement.level {
                continue // 技能已满足要求，跳过
            }
            
            // 从预加载的属性映射中获取技能的主副属性ID
            guard let skillAttrs = skillAttributesMap[requirement.skillID] else {
                continue
            }
            
            // 使用现有的 SkillTrainingCalculator.calculateTrainingRate 函数
            guard let pointsPerHour = SkillTrainingCalculator.calculateTrainingRate(
                primaryAttrId: skillAttrs.primary,
                secondaryAttrId: skillAttrs.secondary,
                attributes: attributes
            ) else {
                continue
            }
            
            // 计算该技能缺失的技能点数
            guard let multiplier = requirement.timeMultiplier,
                requirement.level > 0 && requirement.level <= SkillTreeManager.levelBasePoints.count
            else {
                continue
            }
            
            let requiredPoints = Int(
                Double(SkillTreeManager.levelBasePoints[requirement.level - 1]) * multiplier)
            let currentPoints =
                currentLevel > 0
                ? Int(Double(SkillTreeManager.levelBasePoints[currentLevel - 1]) * multiplier) : 0
            let missingSkillPoints = requiredPoints - currentPoints
            
            if missingSkillPoints > 0 && pointsPerHour > 0 {
                // 计算该技能的训练时间（小时）然后转换为秒
                let trainingTimeHours = Double(missingSkillPoints) / Double(pointsPerHour)
                totalTime += trainingTimeHours * 3600 // 转换为秒
            }
        }
        
        return totalTime
    }
    
    // 新增：批量获取未满足技能的主副属性
    private var unmetSkillAttributes: [Int: (primary: Int, secondary: Int)] {
        // 首先找出所有未满足要求的技能ID
        let unmetSkillIDs = requirements.compactMap { requirement -> Int? in
            let currentLevel = getCurrentSkillLevel(for: requirement.skillID)
            return currentLevel < requirement.level ? requirement.skillID : nil
        }
        
        guard !unmetSkillIDs.isEmpty else {
            return [:]
        }
        
        // 批量查询这些技能的主副属性
        let query = """
            SELECT type_id, attribute_id, value
            FROM typeAttributes
            WHERE type_id IN (\(unmetSkillIDs.map(String.init).joined(separator: ","))) 
            AND attribute_id IN (180, 181)
        """
        
        guard case let .success(rows) = databaseManager.executeQuery(query) else {
            return [:]
        }
        
        // 按技能ID分组处理属性
        var groupedAttributes: [Int: [(attributeId: Int, value: Int)]] = [:]
        for row in rows {
            guard let typeId = row["type_id"] as? Int,
                let attributeId = row["attribute_id"] as? Int,
                let value = row["value"] as? Double
            else { continue }
            
            groupedAttributes[typeId, default: []].append((attributeId, Int(value)))
        }
        
        // 构建最终的属性映射
        var skillAttributes: [Int: (primary: Int, secondary: Int)] = [:]
        for (typeId, attributes) in groupedAttributes {
            var primary: Int?
            var secondary: Int?
            
            for attr in attributes {
                switch attr.attributeId {
                case 180: primary = attr.value
                case 181: secondary = attr.value
                default: break
                }
            }
            
            if let p = primary, let s = secondary {
                skillAttributes[typeId] = (p, s)
            }
        }
        
        return skillAttributes
    }
    
    // 新增：格式化时间显示（复用现有逻辑）
    private func formatTrainingTime(_ timeInterval: TimeInterval) -> String {
        if timeInterval < 1 {
            return String(format: NSLocalizedString("Time_Seconds", comment: ""), 0)
        }

        let totalSeconds = timeInterval
        let days = Int(totalSeconds) / (24 * 3600)
        var hours = Int(totalSeconds) / 3600 % 24
        var minutes = Int(totalSeconds) / 60 % 60
        let seconds = Int(totalSeconds) % 60

        // 当显示两个单位时，对第二个单位进行四舍五入
        if days > 0 {
            // 对小时进行四舍五入
            if minutes >= 30 {
                hours += 1
                if hours == 24 {  // 如果四舍五入后小时数达到24
                    return String(format: NSLocalizedString("Time_Days", comment: ""), days + 1)
                }
            }
            if hours > 0 {
                return String(
                    format: NSLocalizedString("Time_Days_Hours", comment: ""), days, hours
                )
            }
            return String(format: NSLocalizedString("Time_Days", comment: ""), days)
        } else if hours > 0 {
            // 对分钟进行四舍五入
            if seconds >= 30 {
                minutes += 1
                if minutes == 60 {  // 如果四舍五入后分钟数达到60
                    return String(format: NSLocalizedString("Time_Hours", comment: ""), hours + 1)
                }
            }
            if minutes > 0 {
                return String(
                    format: NSLocalizedString("Time_Hours_Minutes", comment: ""), hours, minutes
                )
            }
            return String(format: NSLocalizedString("Time_Hours", comment: ""), hours)
        } else if minutes > 0 {
            // 对秒进行四舍五入
            if seconds >= 30 {
                minutes += 1
            }
            return String(format: NSLocalizedString("Time_Minutes", comment: ""), minutes)
        }
        // 只有秒
        return String(format: NSLocalizedString("Time_Seconds", comment: ""), Int(totalSeconds))
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
        
        // 新增：加载角色属性点数
        loadCharacterAttributes()
    }
    
    // 新增：加载角色属性点数（从本地数据库）
    private func loadCharacterAttributes() {
        guard currentCharacterId != 0 else {
            characterAttributes = nil
            return
        }
        
        // 直接从数据库读取角色属性，不关心缓存时间
        let query = """
            SELECT charisma, intelligence, memory, perception, willpower,
                   bonus_remaps, accrued_remap_cooldown_date, last_remap_date
            FROM character_attributes 
            WHERE character_id = ?
        """
        
        guard
            case let .success(rows) = CharacterDatabaseManager.shared.executeQuery(
                query, parameters: [currentCharacterId]),
            let row = rows.first
        else {
            characterAttributes = nil
            return
        }
        
        // 使用 NSNumber 转换来处理不同的数字类型
        let charisma = (row["charisma"] as? NSNumber)?.intValue ?? 19
        let intelligence = (row["intelligence"] as? NSNumber)?.intValue ?? 20
        let memory = (row["memory"] as? NSNumber)?.intValue ?? 20
        let perception = (row["perception"] as? NSNumber)?.intValue ?? 20
        let willpower = (row["willpower"] as? NSNumber)?.intValue ?? 20
        let bonusRemaps = (row["bonus_remaps"] as? NSNumber)?.intValue ?? 0
        
        characterAttributes = CharacterAttributes(
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
        if !requirements.isEmpty {
            Section(
                header: HStack {
                    Text(groupName)
                        .font(.headline)
                    
                    // 新增：显示预计训练时间
                    if currentCharacterId != 0 && missingPoints > 0 && estimatedTrainingTime > 0 {
                        Spacer()
                        Text("(\(formatTrainingTime(estimatedTrainingTime)))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                },
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
