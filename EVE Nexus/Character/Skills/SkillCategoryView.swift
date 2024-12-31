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
                        SkillGroupDetailView(group: group)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.name)
                                .font(.headline)
                            Text("\(group.skills.count)/\(group.totalSkillsInGroup) - \(formatNumber(group.totalSkillPoints)) SP")
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
            
            // 2. 获取所有技能的详细信息
            var skillInfoDict: [Int: SkillInfo] = [:]
            var groupDict: [Int: (name: String, totalSkills: Int)] = [:]
            
            // 先获取所有技能组的总技能数
            for skill in skillsResponse.skills {
                let query = """
                    SELECT t1.name, t1.groupID, t1.group_name,
                           (SELECT COUNT(*) FROM types t2 WHERE t2.groupID = t1.groupID AND t2.published = 1) as total_skills
                    FROM types t1
                    WHERE t1.type_id = ?
                """
                
                if case .success(let typeRows) = databaseManager.executeQuery(query, parameters: [skill.skill_id]),
                   let typeRow = typeRows.first,
                   let name = typeRow["name"] as? String,
                   let groupId = typeRow["groupID"] as? Int,
                   let groupName = typeRow["group_name"] as? String,
                   let totalSkills = typeRow["total_skills"] as? Int {
                    
                    skillInfoDict[skill.skill_id] = SkillInfo(
                        id: skill.skill_id,
                        name: name,
                        groupID: groupId,
                        skillpoints_in_skill: skill.skillpoints_in_skill,
                        trained_skill_level: skill.trained_skill_level
                    )
                    
                    groupDict[groupId] = (name: groupName, totalSkills: totalSkills)
                }
            }
            
            // 3. 按技能组组织数据
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

// 技能组详情视图（稍后实现）
struct SkillGroupDetailView: View {
    let group: SkillGroup
    
    var body: some View {
        Text(group.name)
    }
} 
