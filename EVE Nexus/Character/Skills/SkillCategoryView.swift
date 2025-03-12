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

// 技能目录视图模型
@MainActor
class SkillCategoryViewModel: ObservableObject {
    @Published var skillGroups: [SkillGroup] = []
    @Published var isLoading = true
    @Published var searchText = ""

    private let characterId: Int
    private let databaseManager: DatabaseManager
    private let characterDatabaseManager: CharacterDatabaseManager

    // 搜索结果的技能列表
    var filteredSkills:
        [(
            typeId: Int,
            name: String,
            timeMultiplier: Double,
            currentSkillPoints: Int?,
            currentLevel: Int?,
            trainingRate: Int?
        )]
    {
        if searchText.isEmpty {
            return []
        } else {
            // 1. 先搜索所有已学习的技能
            let learnedSkills = skillGroups.flatMap { group in
                group.skills.compactMap { characterSkill in
                    if let info = skillInfoDict[characterSkill.skill_id],
                        info.name.localizedCaseInsensitiveContains(searchText)
                    {
                        return (characterSkill.skill_id, info, characterSkill)
                    }
                    return nil
                }
            }

            // 2. 搜索所有技能（包括未学习的）
            let query = """
                    SELECT t.type_id, t.name, t.groupID
                    FROM types t
                    WHERE t.published = 1
                    AND t.groupID IN (
                        SELECT DISTINCT groupID
                        FROM types
                        WHERE type_id IN (\(skillGroups.flatMap { $0.skills }.map { String($0.skill_id) }.joined(separator: ",")))
                    )
                    AND t.name LIKE '%\(searchText)%'
                """

            var allMatchedSkills: [(Int, String)] = []
            if case let .success(rows) = databaseManager.executeQuery(query) {
                allMatchedSkills = rows.compactMap { row in
                    if let typeId = row["type_id"] as? Int,
                        let name = row["name"] as? String
                    {
                        return (typeId, name)
                    }
                    return nil
                }
            }

            // 3. 获取所有技能的训练时间倍数
            let allSkillIds = allMatchedSkills.map { $0.0 }
            let timeMultiplierQuery = """
                    SELECT type_id, value
                    FROM typeAttributes
                    WHERE type_id IN (\(allSkillIds.sorted().map { String($0) }.joined(separator: ",")))
                    AND attribute_id = 275
                """

            var timeMultipliers: [Int: Double] = [:]
            if case let .success(attrRows) = databaseManager.executeQuery(timeMultiplierQuery) {
                for row in attrRows {
                    if let typeId = row["type_id"] as? Int,
                        let value = row["value"] as? Double
                    {
                        timeMultipliers[typeId] = value
                    }
                }
            }

            // 4. 合并结果，已学习的技能显示详细信息，未学习的显示基本信息
            return allMatchedSkills.map { typeId, name in
                let learnedSkill = learnedSkills.first { $0.0 == typeId }
                return (
                    typeId: typeId,
                    name: name,
                    timeMultiplier: timeMultipliers[typeId] ?? 1.0,
                    currentSkillPoints: learnedSkill?.2.skillpoints_in_skill,
                    currentLevel: learnedSkill?.2.trained_skill_level,
                    trainingRate: nil
                )
            }.sorted { $0.name < $1.name }
        }
    }

    // 添加一个字典来存储技能ID到技能信息的映射
    private var skillInfoDict: [Int: SkillInfo] = [:]

    init(
        characterId: Int, databaseManager: DatabaseManager,
        characterDatabaseManager: CharacterDatabaseManager
    ) {
        self.characterId = characterId
        self.databaseManager = databaseManager
        self.characterDatabaseManager = characterDatabaseManager
    }

    func loadSkills() async {
        isLoading = true
        defer { isLoading = false }

        // 如果已经加载过数据，就不再重新加载
        if !skillGroups.isEmpty {
            return
        }

        // 1. 从character_skills表获取技能数据
        let skillsQuery = "SELECT skills_data FROM character_skills WHERE character_id = ?"

        guard
            case let .success(rows) = characterDatabaseManager.executeQuery(
                skillsQuery, parameters: [characterId]
            ),
            let row = rows.first,
            let skillsJson = row["skills_data"] as? String,
            let data = skillsJson.data(using: .utf8)
        else {
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

            guard case let .success(groupRows) = databaseManager.executeQuery(groupQuery) else {
                return
            }

            var groupDict: [Int: (name: String, totalSkills: Int)] = [:]
            for row in groupRows {
                if let groupId = row["groupID"] as? Int,
                    let groupName = row["group_name"] as? String,
                    let totalSkills = row["total_skills"] as? Int
                {
                    groupDict[groupId] = (name: groupName, totalSkills: totalSkills)
                }
            }

            // 3. 获取所有技能的信息
            let skillQuery = """
                    SELECT type_id, name, groupID
                    FROM types
                    WHERE type_id IN (\(skillsResponse.skills.map { String($0.skill_id) }.joined(separator: ",")))
                """

            guard case let .success(skillRows) = databaseManager.executeQuery(skillQuery) else {
                return
            }

            var skillInfoDict: [Int: SkillInfo] = [:]
            for row in skillRows {
                if let typeId = row["type_id"] as? Int,
                    let name = row["name"] as? String,
                    let groupId = row["groupID"] as? Int,
                    let skill = skillsResponse.skills.first(where: { $0.skill_id == typeId })
                {
                    skillInfoDict[typeId] = SkillInfo(
                        id: typeId,
                        name: name,
                        groupID: groupId,
                        skillpoints_in_skill: skill.skillpoints_in_skill,
                        trained_skill_level: skill.trained_skill_level
                    )
                }
            }

            // 保存技能信息字典以供搜索使用
            self.skillInfoDict = skillInfoDict

            // 4. 按技能组组织数据
            var groups: [SkillGroup] = []
            for (groupId, groupInfo) in groupDict {
                let groupSkills = skillsResponse.skills.filter { skill in
                    skillInfoDict[skill.skill_id]?.groupID == groupId
                }

                if !groupSkills.isEmpty {
                    groups.append(
                        SkillGroup(
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
}

// 通用技能单元格视图
struct SkillCellView: View {
    let skill:
        (
            typeId: Int,
            name: String,
            timeMultiplier: Double,
            currentSkillPoints: Int?,
            currentLevel: Int?,
            trainingRate: Int?
        )

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 2) {
                Text(skill.name)
                    .lineLimit(1)
                if skill.timeMultiplier >= 1 {
                    Text("(×\(String(format: "%.0f", skill.timeMultiplier)))")
                }
                Spacer()
                if let currentLevel = skill.currentLevel {
                    Text(
                        String(
                            format: NSLocalizedString("Main_Skills_Level", comment: ""),
                            currentLevel
                        )
                    )
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

            VStack(spacing: 2) {
                HStack(spacing: 2) {
                    let maxSkillPoints = Int(256_000 * skill.timeMultiplier)
                    let currentPoints = skill.currentSkillPoints ?? 0
                    Text(
                        String(
                            format: NSLocalizedString("Main_Skills_Points_Progress", comment: ""),
                            formatNumber(currentPoints),
                            formatNumber(maxSkillPoints)
                        ))
                    if let rate = skill.trainingRate {
                        Text("(\(formatNumber(rate))/h)")
                    }
                    Spacer()

                    // 添加下一级训练时间显示
                    let currentLevel = skill.currentLevel ?? 0
                    if currentLevel < 5,  // 只有当前等级小于5时才显示
                        let rate = skill.trainingRate
                    {
                        let nextLevelPoints = Int(
                            Double(SkillTreeManager.levelBasePoints[currentLevel])
                                * skill.timeMultiplier)
                        let remainingSP = nextLevelPoints - currentPoints
                        let trainingTimeHours = Double(remainingSP) / Double(rate)
                        let trainingTime = trainingTimeHours * 3600  // 转换为秒

                        Text(
                            String(
                                format: NSLocalizedString("Main_Skills_Time_Required", comment: ""),
                                formatTimeInterval(trainingTime)
                            ))
                    }
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }

    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: number)) ?? String(number)
    }

    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        // 先转换为分钟
        let totalMinutes = Int(ceil(interval / 60))
        let days = totalMinutes / (24 * 60)
        let remainingMinutes = totalMinutes % (24 * 60)
        let hours = remainingMinutes / 60
        let minutes = remainingMinutes % 60

        if days > 0 {
            // 如果有剩余分钟，小时数要加1
            let adjustedHours = (remainingMinutes % 60 > 0) ? hours + 1 : hours
            if adjustedHours > 0 {
                return String(
                    format: NSLocalizedString("Time_Days_Hours", comment: ""),
                    days, adjustedHours
                )
            }
            return String(format: NSLocalizedString("Time_Days", comment: ""), days)
        } else if hours > 0 {
            // 如果有剩余分钟，分钟数要向上取整
            if minutes > 0 {
                return String(
                    format: NSLocalizedString("Time_Hours_Minutes", comment: ""),
                    hours, minutes
                )
            }
            return String(format: NSLocalizedString("Time_Hours", comment: ""), hours)
        }
        // 分钟数已经在一开始就向上取整了
        return String(format: NSLocalizedString("Time_Minutes", comment: ""), minutes)
    }
}

struct SkillCategoryView: View {
    let characterId: Int
    let databaseManager: DatabaseManager
    @StateObject private var viewModel: SkillCategoryViewModel

    // 技能组图标映射
    private let skillGroupIcons: [Int: String] = [
        255: "1_42",  // 射击学
        256: "1_48",  // 导弹
        257: "1_26",  // 飞船操控学
        258: "1_36",  // 舰队支援
        266: "1_12",  // 军团管理
        268: "1_25",  // 生产
        269: "1_37",  // 改装件
        270: "1_49",  // 科学
        272: "1_24",  // 电子系统
        273: "1_18",  // 无人机
        274: "1_50",  // 贸易学
        275: "1_05",  // 导航学
        278: "1_20",  // 社会学
        1209: "1_14",  // 护盾
        1210: "1_03",  // 装甲
        1213: "1_44",  // 锁定系统
        1216: "1_30",  // 工程学
        1217: "1_43",  // 扫描
        1218: "1_31",  // 资源处理
        1220: "1_13",  // 神经增强
        1240: "1_38",  // 子系统
        1241: "1_19",  // 行星管理
        1545: "1_32",  // 建筑管理
        4734: "1_07",  // 排序
    ]

    init(characterId: Int, databaseManager: DatabaseManager) {
        self.characterId = characterId
        self.databaseManager = databaseManager
        _viewModel = StateObject(
            wrappedValue: SkillCategoryViewModel(
                characterId: characterId,
                databaseManager: databaseManager,
                characterDatabaseManager: CharacterDatabaseManager.shared
            ))
    }

    var body: some View {
        List {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if viewModel.skillGroups.isEmpty {
                Text(NSLocalizedString("Main_Skills_No_Skills", comment: ""))
                    .foregroundColor(.secondary)
            } else {
                if viewModel.searchText.isEmpty {
                    // 显示技能组列表
                    ForEach(viewModel.skillGroups.sorted(by: { $0.id < $1.id })) { group in
                        NavigationLink {
                            SkillGroupDetailView(
                                group: group, databaseManager: databaseManager,
                                characterId: characterId
                            )
                        } label: {
                            HStack(spacing: 12) {
                                // 显示技能组图标
                                if let iconName = skillGroupIcons[group.id] {
                                    Image(iconName)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 36, height: 32)
                                        .cornerRadius(8)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(group.name)
                                    Text(
                                        "\(group.skills.count)/\(group.totalSkillsInGroup) Skills - \(formatNumber(group.totalSkillPoints)) SP"
                                    )
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                } else {
                    // 显示搜索结果
                    ForEach(viewModel.filteredSkills, id: \.typeId) { skill in
                        NavigationLink {
                            ShowItemInfo(
                                databaseManager: databaseManager,
                                itemID: skill.typeId
                            )
                        } label: {
                            SkillCellView(skill: skill)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
            }
        }
        .navigationTitle(NSLocalizedString("Main_Skills_Category", comment: ""))
        .searchable(
            text: $viewModel.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: NSLocalizedString("Main_Search_Placeholder", comment: "")
        )
        .onAppear {
            Task {
                await viewModel.loadSkills()
            }
        }
    }

    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: number)) ?? String(number)
    }

    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        // 先转换为分钟
        let totalMinutes = Int(ceil(interval / 60))
        let days = totalMinutes / (24 * 60)
        let remainingMinutes = totalMinutes % (24 * 60)
        let hours = remainingMinutes / 60
        let minutes = remainingMinutes % 60

        if days > 0 {
            // 如果有剩余分钟，小时数要加1
            let adjustedHours = (remainingMinutes % 60 > 0) ? hours + 1 : hours
            if adjustedHours > 0 {
                return String(
                    format: NSLocalizedString("Time_Days_Hours", comment: ""),
                    days, adjustedHours
                )
            }
            return String(format: NSLocalizedString("Time_Days", comment: ""), days)
        } else if hours > 0 {
            // 如果有剩余分钟，分钟数要向上取整
            if minutes > 0 {
                return String(
                    format: NSLocalizedString("Time_Hours_Minutes", comment: ""),
                    hours, minutes
                )
            }
            return String(format: NSLocalizedString("Time_Hours", comment: ""), hours)
        }
        // 分钟数已经在一开始就向上取整了
        return String(format: NSLocalizedString("Time_Minutes", comment: ""), minutes)
    }
}

// 技能组详情视图
struct SkillGroupDetailView: View {
    let group: SkillGroup
    let databaseManager: DatabaseManager
    let characterId: Int
    @State private var allSkills:
        [(
            typeId: Int,
            name: String,
            timeMultiplier: Double,
            currentSkillPoints: Int?,
            currentLevel: Int?,
            trainingRate: Int?  // 每小时训练点数
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
                        SkillCellView(skill: skill)
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
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
            characterAttributes = try await CharacterSkillsAPI.shared.fetchAttributes(
                characterId: characterId)
        } catch {
            Logger.error("获取角色属性失败: \(error)")
        }
    }

    private func loadAllSkills() async {
        // 如果已经加载过数据，就不再重新加载
        if !allSkills.isEmpty {
            return
        }

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

        guard case let .success(rows) = databaseManager.executeQuery(query, parameters: [group.id])
        else {
            return
        }

        // 收集所有技能ID
        let skillIds = rows.compactMap { row -> Int? in
            return row["type_id"] as? Int
        }

        // 批量查询所有技能的训练时间倍数
        let timeMultiplierQuery = """
                SELECT type_id, value
                FROM typeAttributes
                WHERE type_id IN (\(skillIds.map { String($0) }.joined(separator: ",")))
                AND attribute_id = 275
            """

        var timeMultipliers: [Int: Double] = [:]
        if case let .success(attrRows) = databaseManager.executeQuery(timeMultiplierQuery) {
            for row in attrRows {
                if let typeId = row["type_id"] as? Int,
                    let value = row["value"] as? Double
                {
                    timeMultipliers[typeId] = value
                }
            }
        }

        // 预加载所有技能属性到缓存
        SkillTrainingCalculator.preloadSkillAttributes(
            skillIds: skillIds, databaseManager: databaseManager
        )

        var skills:
            [(
                typeId: Int, name: String, timeMultiplier: Double, currentSkillPoints: Int?,
                currentLevel: Int?, trainingRate: Int?
            )] = []

        for row in rows {
            guard let typeId = row["type_id"] as? Int,
                let name = row["name"] as? String
            else {
                continue
            }

            let timeMultiplier = timeMultipliers[typeId] ?? 1.0
            let learnedSkill = learnedSkills[typeId]

            // 计算训练速度
            var trainingRate: Int?
            if let attrs = characterAttributes,
                let (primary, secondary) = SkillTrainingCalculator.getSkillAttributes(
                    skillId: typeId, databaseManager: databaseManager
                )
            {
                trainingRate = SkillTrainingCalculator.calculateTrainingRate(
                    primaryAttrId: primary,
                    secondaryAttrId: secondary,
                    attributes: attrs
                )
            }

            skills.append(
                (
                    typeId: typeId,
                    name: name,
                    timeMultiplier: timeMultiplier,
                    currentSkillPoints: learnedSkill?.skillpoints_in_skill,
                    currentLevel: learnedSkill?.trained_skill_level,
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

    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        // 先转换为分钟
        let totalMinutes = Int(ceil(interval / 60))
        let days = totalMinutes / (24 * 60)
        let remainingMinutes = totalMinutes % (24 * 60)
        let hours = remainingMinutes / 60
        let minutes = remainingMinutes % 60

        if days > 0 {
            // 如果有剩余分钟，小时数要加1
            let adjustedHours = (remainingMinutes % 60 > 0) ? hours + 1 : hours
            if adjustedHours > 0 {
                return String(
                    format: NSLocalizedString("Time_Days_Hours", comment: ""),
                    days, adjustedHours
                )
            }
            return String(format: NSLocalizedString("Time_Days", comment: ""), days)
        } else if hours > 0 {
            // 如果有剩余分钟，分钟数要向上取整
            if minutes > 0 {
                return String(
                    format: NSLocalizedString("Time_Hours_Minutes", comment: ""),
                    hours, minutes
                )
            }
            return String(format: NSLocalizedString("Time_Hours", comment: ""), hours)
        }
        // 分钟数已经在一开始就向上取整了
        return String(format: NSLocalizedString("Time_Minutes", comment: ""), minutes)
    }
}
