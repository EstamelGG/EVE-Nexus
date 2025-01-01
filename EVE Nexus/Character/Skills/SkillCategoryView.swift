import SwiftUI

// 技能组模型
struct SkillGroup: Identifiable {
    let id: Int  // groupID
    let name: String  // group_name
    var skills: [CharacterSkill]
    let totalSkillsInGroup: Int  // 该组中的总技能数
    
    var totalSkillPoints: Int {
        skills.reduce(0) { $0 + $1.skillpoints_in_skill }
    }
}

// 技能信息模型（扩展现有的CharacterSkill）
struct SkillInfo {
    let id: Int
    let name: String
    let groupID: Int
    let skillpoints_in_skill: Int
    let trained_skill_level: Int
}

// 扩展技能信息模型
struct DetailedSkillInfo {
    let name: String
    let timeMultiplier: Int
    let maxSkillPoints: Int  // 256000 * timeMultiplier
}

struct SkillCategoryView: View {
    let characterId: Int
    let databaseManager: DatabaseManager
    @StateObject private var characterDatabaseManager = CharacterDatabaseManager.shared
    @State private var skillGroups: [SkillGroup] = []
    @State private var isLoading = true
    
    var body: some View {
        List {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if skillGroups.isEmpty {
                Text(NSLocalizedString("Main_Skills_No_Skills", comment: ""))
                    .foregroundColor(.secondary)
            } else {
                ForEach(skillGroups.sorted(by: { $0.name < $1.name })) { group in
                    NavigationLink {
                        SkillGroupDetailView(group: group, databaseManager: databaseManager, characterId: characterId)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.name)
                            Text("\(group.skills.count)/\(group.totalSkillsInGroup) Skills - \(formatNumber(group.totalSkillPoints)) SP")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(height: 36)
                }
            }
        }
        .navigationTitle(NSLocalizedString("Main_Skills_Category", comment: ""))
        .onAppear {
            Task {
                await loadSkills()
            }
        }
    }
    
    private func loadSkills() async {
        isLoading = true
        defer { isLoading = false }
        
        // 1. 从character_skills表获取技能数据
        let skillsQuery = "SELECT skills_data FROM character_skills WHERE character_id = ?"
        
        guard case .success(let rows) = characterDatabaseManager.executeQuery(skillsQuery, parameters: [characterId]),
              let row = rows.first,
              let skillsJson = row["skills_data"] as? String,
              let data = skillsJson.data(using: .utf8) else {
            return
        }
        
        do {
            let decoder = JSONDecoder()
            let skillsResponse = try decoder.decode(CharacterSkillsResponse.self, from: data)
            
            // 2. 获取所有技能组的信息和总技能数
            let groupQuery = """
                SELECT t1.groupID, t1.group_name,
                       (SELECT COUNT(*) FROM types t2 WHERE t2.groupID = t1.groupID AND t2.published = 1) as total_skills
                FROM types t1
                WHERE t1.groupID IN (
                    SELECT DISTINCT groupID
                    FROM types
                    WHERE type_id IN (\(skillsResponse.skills.map { String($0.skill_id) }.joined(separator: ",")))
                )
                GROUP BY t1.groupID, t1.group_name
            """
            
            guard case .success(let groupRows) = databaseManager.executeQuery(groupQuery) else {
                return
            }
            
            var groupDict: [Int: (name: String, totalSkills: Int)] = [:]
            for row in groupRows {
                if let groupId = row["groupID"] as? Int,
                   let groupName = row["group_name"] as? String,
                   let totalSkills = row["total_skills"] as? Int {
                    groupDict[groupId] = (name: groupName, totalSkills: totalSkills)
                }
            }
            
            // 3. 获取所有技能的信息
            let skillQuery = """
                SELECT type_id, name, groupID
                FROM types
                WHERE type_id IN (\(skillsResponse.skills.map { String($0.skill_id) }.joined(separator: ",")))
            """
            
            guard case .success(let skillRows) = databaseManager.executeQuery(skillQuery) else {
                return
            }
            
            var skillInfoDict: [Int: SkillInfo] = [:]
            for row in skillRows {
                if let typeId = row["type_id"] as? Int,
                   let name = row["name"] as? String,
                   let groupId = row["groupID"] as? Int,
                   let skill = skillsResponse.skills.first(where: { $0.skill_id == typeId }) {
                    skillInfoDict[typeId] = SkillInfo(
                        id: typeId,
                        name: name,
                        groupID: groupId,
                        skillpoints_in_skill: skill.skillpoints_in_skill,
                        trained_skill_level: skill.trained_skill_level
                    )
                }
            }
            
            // 4. 按技能组组织数据
            var groups: [SkillGroup] = []
            for (groupId, groupInfo) in groupDict {
                let groupSkills = skillsResponse.skills.filter { skill in
                    skillInfoDict[skill.skill_id]?.groupID == groupId
                }
                
                if !groupSkills.isEmpty {
                    groups.append(SkillGroup(
                        id: groupId,
                        name: groupInfo.name,
                        skills: groupSkills,
                        totalSkillsInGroup: groupInfo.totalSkills
                    ))
                }
            }
            
            await MainActor.run {
                self.skillGroups = groups
            }
            
        } catch {
            Logger.error("解析技能数据失败: \(error)")
        }
    }
    
    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: number)) ?? String(number)
    }
}

// 技能组详情视图
struct SkillGroupDetailView: View {
    let group: SkillGroup
    let databaseManager: DatabaseManager
    let characterId: Int
    @State private var allSkills: [(
        typeId: Int,
        name: String,
        timeMultiplier: Double,
        currentSkillPoints: Int?,
        currentLevel: Int?,
        primaryAttribute: Int?,    // 主属性ID
        secondaryAttribute: Int?,  // 副属性ID
        trainingRate: Int?        // 每小时训练点数
    )] = []
    @State private var isLoading = true
    @State private var characterAttributes: CharacterAttributes?
    
    var body: some View {
        List {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ForEach(allSkills, id: \.typeId) { skill in
                    NavigationLink {
                        ShowItemInfo(
                            databaseManager: databaseManager,
                            itemID: skill.typeId
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(skill.name)
                                    .lineLimit(1)
                                if skill.timeMultiplier >= 1 {
                                    Text("(×\(String(format: "%.0f", skill.timeMultiplier)))")
                                }
                                Spacer()
                                if let currentLevel = skill.currentLevel {
                                    Text(String(format: NSLocalizedString("Main_Skills_Level", comment: ""), currentLevel))
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                        .padding(.trailing, 2)
                                    SkillLevelIndicator(
                                        currentLevel: currentLevel,
                                        trainingLevel: currentLevel,
                                        isTraining: false
                                    )
                                    .padding(.trailing, 4)
                                } else {
                                    Text(NSLocalizedString("Main_Skills_Not_Injected", comment: ""))
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                        .padding(.trailing, 4)
                                }
                            }
                            
                            let maxSkillPoints = Int(256000 * skill.timeMultiplier)
                            HStack {
                                Text(String(format: NSLocalizedString("Main_Skills_Points_Progress", comment: ""),
                                            formatNumber(skill.currentSkillPoints ?? 0),
                                            formatNumber(maxSkillPoints)))
                                if let rate = skill.trainingRate {
                                    Text("(\(formatNumber(rate))/h)")
                                }
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        .frame(height: 36)
                    }
                }
            }
        }
        .navigationTitle(group.name)
        .onAppear {
            Task {
                await loadCharacterAttributes()
                await loadAllSkills()
            }
        }
    }
    
    private func loadCharacterAttributes() async {
        do {
            characterAttributes = try await CharacterSkillsAPI.shared.fetchAttributes(characterId: characterId)
        } catch {
            Logger.error("获取角色属性失败: \(error)")
        }
    }
    
    private func calculateTrainingRate(primaryAttrId: Int, secondaryAttrId: Int) -> Int? {
        guard let attrs = characterAttributes else { return nil }
        
        func getAttributeValue(_ attrId: Int) -> Int {
            switch attrId {
            case 164: return attrs.charisma
            case 165: return attrs.intelligence
            case 166: return attrs.memory
            case 167: return attrs.perception
            case 168: return attrs.willpower
            default: return 0
            }
        }
        
        let primaryValue = getAttributeValue(primaryAttrId)
        let secondaryValue = getAttributeValue(secondaryAttrId)
        
        // 每分钟训练点数 = 主属性 + 副属性/2
        let pointsPerMinute = Double(primaryValue) + Double(secondaryValue) / 2.0
        // 转换为每小时
        return Int(pointsPerMinute * 60)
    }
    
    private func loadAllSkills() async {
        isLoading = true
        defer { isLoading = false }
        
        // 创建已学技能的查找字典
        let learnedSkills = Dictionary(uniqueKeysWithValues: group.skills.map { ($0.skill_id, $0) })
        
        // 获取该组所有技能
        let query = """
            SELECT type_id, name
            FROM types
            WHERE groupID = ? AND published = 1
            ORDER BY name
        """
        
        guard case .success(let rows) = databaseManager.executeQuery(query, parameters: [group.id]) else {
            return
        }
        
        var skills: [(typeId: Int, name: String, timeMultiplier: Double, currentSkillPoints: Int?, currentLevel: Int?, primaryAttribute: Int?, secondaryAttribute: Int?, trainingRate: Int?)] = []
        
        for row in rows {
            guard let typeId = row["type_id"] as? Int,
                  let name = row["name"] as? String else {
                continue
            }
            
            // 获取训练时间倍数和属性
            let attrQuery = """
                SELECT attribute_id, value
                FROM typeAttributes
                WHERE type_id = ? AND attribute_id IN (180, 181, 275)
            """
            
            var timeMultiplier: Double = 1.0
            var primaryAttrId: Int?
            var secondaryAttrId: Int?
            
            if case .success(let attrRows) = databaseManager.executeQuery(attrQuery, parameters: [typeId]) {
                for attrRow in attrRows {
                    guard let attrId = attrRow["attribute_id"] as? Int,
                          let value = attrRow["value"] as? Double else { continue }
                    
                    switch attrId {
                    case 275: timeMultiplier = value
                    case 180: primaryAttrId = Int(value)
                    case 181: secondaryAttrId = Int(value)
                    default: break
                    }
                }
            }
            
            // 获取已学习的技能信息（如果有）
            let learnedSkill = learnedSkills[typeId]
            
            // 计算训练速度
            var trainingRate: Int?
            if let primary = primaryAttrId, let secondary = secondaryAttrId {
                trainingRate = calculateTrainingRate(primaryAttrId: primary, secondaryAttrId: secondary)
            }
            
            skills.append((
                typeId: typeId,
                name: name,
                timeMultiplier: timeMultiplier,
                currentSkillPoints: learnedSkill?.skillpoints_in_skill,
                currentLevel: learnedSkill?.trained_skill_level,
                primaryAttribute: primaryAttrId,
                secondaryAttribute: secondaryAttrId,
                trainingRate: trainingRate
            ))
        }
        
        await MainActor.run {
            self.allSkills = skills
        }
    }
    
    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: number)) ?? String(number)
    }
}
