import SwiftUI

// 技能筛选条件
enum SkillFilter: String, CaseIterable {
    case all
    case completed
    case notInjected
    case trainable

    var localized: String {
        switch self {
        case .all:
            return NSLocalizedString("Misc_All", comment: "全部")
        case .completed:
            return NSLocalizedString("Main_Skills_Completed", comment: "已完成")
        case .notInjected:
            return NSLocalizedString("Main_Skills_Not_Injected", comment: "未吸收")
        case .trainable:
            return NSLocalizedString("Main_Skills_Trainable", comment: "可训练")
        }
    }
}

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
    let zh_name: String
    let en_name: String
    let groupID: Int
    let skillpoints_in_skill: Int
    let trained_skill_level: Int  // -1 表示未吸收，0-5 表示已吸收的等级
}

// 技能目录视图模型
@MainActor
class SkillCategoryViewModel: ObservableObject {
    @Published var skillGroups: [SkillGroup] = []
    @Published var isLoading = true
    @Published var searchText = ""
    @Published var selectedFilter: SkillFilter = .all

    private let characterId: Int
    private let databaseManager: DatabaseManager
    private let characterDatabaseManager: CharacterDatabaseManager

    // 修改 allSkillsDict 的类型
    var allSkillsDict:
        [Int: (
            name: String,
            zh_name: String,
            en_name: String,
            groupID: Int,
            timeMultiplier: Double,
            currentSkillPoints: Int,
            currentLevel: Int,
            trainingRate: Int?
        )] = [:]

    // 添加一个数组来存储所有技能组
    private var allSkillGroups: [SkillGroup] = []

    init(
        characterId: Int, databaseManager: DatabaseManager,
        characterDatabaseManager: CharacterDatabaseManager
    ) {
        self.characterId = characterId
        self.databaseManager = databaseManager
        self.characterDatabaseManager = characterDatabaseManager

        // 在初始化时就开始加载数据
        Task {
            await loadSkills()
        }
    }

    func loadSkills() async {
        isLoading = true
        defer { isLoading = false }

        // 1. 从character_skills表获取技能数据
        let skillsQuery = "SELECT skills_data FROM character_skills WHERE character_id = ?"

        guard
            case let .success(rows) = characterDatabaseManager.executeQuery(
                skillsQuery, parameters: [characterId]),
            let row = rows.first,
            let skillsJson = row["skills_data"] as? String,
            let data = skillsJson.data(using: .utf8)
        else {
            return
        }

        do {
            let decoder = JSONDecoder()
            let skillsResponse = try decoder.decode(CharacterSkillsResponse.self, from: data)

            // 创建已学习技能的查找字典
            let learnedSkills = Dictionary(
                uniqueKeysWithValues: skillsResponse.skills.map { ($0.skill_id, $0) })

            // 2. 获取所有技能组和技能信息
            let skillsQuery = """
                    SELECT 
                        t.type_id,
                        t.name,
                        t.zh_name,
                        t.en_name,
                        t.groupID,
                        t.group_name
                    FROM types t
                    WHERE t.published = 1 and t.categoryID = 16
                """

            guard case let .success(skillRows) = databaseManager.executeQuery(skillsQuery) else {
                return
            }

            // 3. 获取所有技能的训练时间倍数
            let skillIds = skillRows.compactMap { $0["type_id"] as? Int }
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

            // 4. 合并所有技能信息并计算技能组总数
            var groupDict: [Int: (name: String, skills: [Int])] = [:]
            for row in skillRows {
                guard let typeId = row["type_id"] as? Int,
                    let name = row["name"] as? String,
                    let zh_name = row["zh_name"] as? String,
                    let en_name = row["en_name"] as? String,
                    let groupId = row["groupID"] as? Int,
                    let groupName = row["group_name"] as? String
                else {
                    continue
                }

                // 保存技能组信息
                if groupDict[groupId] == nil {
                    groupDict[groupId] = (name: groupName, skills: [])
                }
                groupDict[groupId]?.skills.append(typeId)

                let timeMultiplier = timeMultipliers[typeId] ?? 1.0
                let learnedSkill = learnedSkills[typeId]

                allSkillsDict[typeId] = (
                    name: name,
                    zh_name: zh_name,
                    en_name: en_name,
                    groupID: groupId,
                    timeMultiplier: timeMultiplier,
                    currentSkillPoints: learnedSkill?.skillpoints_in_skill ?? 0,
                    currentLevel: learnedSkill?.trained_skill_level ?? -1,
                    trainingRate: nil
                )
            }

            // 获取角色属性
            do {
                let attributes = try await CharacterSkillsAPI.shared.fetchAttributes(
                    characterId: characterId)

                // 计算每个技能的训练速度
                for (typeId, _) in allSkillsDict {
                    if let (primary, secondary) = SkillTrainingCalculator.getSkillAttributes(
                        skillId: typeId, databaseManager: databaseManager
                    ) {
                        let trainingRate = SkillTrainingCalculator.calculateTrainingRate(
                            primaryAttrId: primary,
                            secondaryAttrId: secondary,
                            attributes: attributes
                        )
                        allSkillsDict[typeId]?.trainingRate = trainingRate
                    }
                }
            } catch {
                Logger.error("获取角色属性失败: \(error)")
            }

            // 5. 按技能组组织数据
            var groups: [SkillGroup] = []
            for (groupId, groupInfo) in groupDict {
                // 获取该组所有技能
                let groupSkills = allSkillsDict.filter { $0.value.groupID == groupId }

                // 转换为 CharacterSkill 数组，包含所有技能
                let allSkills = groupSkills.map { typeId, info in
                    CharacterSkill(
                        active_skill_level: info.currentLevel,
                        skill_id: typeId,
                        skillpoints_in_skill: info.currentSkillPoints,
                        trained_skill_level: info.currentLevel
                    )
                }

                if !allSkills.isEmpty {
                    groups.append(
                        SkillGroup(
                            id: groupId,
                            name: groupInfo.name,
                            skills: allSkills,
                            totalSkillsInGroup: groupSkills.count
                        ))
                }
            }

            await MainActor.run {
                self.allSkillGroups = groups
                self.updateFilteredGroups()
            }

        } catch {
            Logger.error("解析技能数据失败: \(error)")
        }
    }

    // 修改过滤方法
    func updateFilteredGroups() {
        if searchText.isEmpty {
            // 根据筛选条件过滤技能组
            skillGroups = allSkillGroups.map { group in
                // 根据筛选条件过滤技能
                let filteredSkills = group.skills.filter { skill in
                    switch selectedFilter {
                    case .all:
                        return true  // 显示所有技能
                    case .completed:
                        return skill.trained_skill_level == 5
                    case .notInjected:
                        return skill.trained_skill_level == -1
                    case .trainable:
                        return skill.trained_skill_level >= 0 && skill.trained_skill_level < 5
                    }
                }

                // 只返回包含过滤后技能的组
                return SkillGroup(
                    id: group.id,
                    name: group.name,
                    skills: filteredSkills,
                    totalSkillsInGroup: group.totalSkillsInGroup
                )
            }.filter { !$0.skills.isEmpty }  // 移除空组
        } else {
            // 搜索逻辑保持不变
            skillGroups = []
        }
    }

    // 修改搜索功能
    var filteredSkills:
        [(
            typeId: Int, name: String, timeMultiplier: Double, currentSkillPoints: Int?,
            currentLevel: Int?, trainingRate: Int?
        )]
    {
        if searchText.isEmpty {
            return []
        } else {
            // 根据当前筛选条件过滤技能
            let filteredByLevel = allSkillsDict.filter { typeId, info in
                switch selectedFilter {
                case .all:
                    return true
                case .completed:
                    return info.currentLevel == 5
                case .notInjected:
                    return info.currentLevel == -1
                case .trainable:
                    return info.currentLevel >= 0 && info.currentLevel < 5
                }
            }

            // 在过滤后的技能中搜索
            return
                filteredByLevel
                .filter { typeId, info in
                    info.zh_name.localizedCaseInsensitiveContains(searchText)
                        || info.en_name.localizedCaseInsensitiveContains(searchText)
                }
                .map { typeId, info in
                    (
                        typeId: typeId,
                        name: info.name,  // 显示时使用 name
                        timeMultiplier: info.timeMultiplier,
                        currentSkillPoints: info.currentSkillPoints,
                        currentLevel: info.currentLevel,
                        trainingRate: info.trainingRate
                    )
                }
                .sorted { $0.name < $1.name }
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

                // 处理技能等级显示
                if let currentLevel = skill.currentLevel, currentLevel >= 0 {
                    Text(
                        String(
                            format: NSLocalizedString("Misc_Level_Short", comment: ""),
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
                    if let currentLevel = skill.currentLevel,
                        currentLevel >= -1 && currentLevel < 5,  // 只有当前等级在-1 ~ 4之间时才显示
                        let rate = skill.trainingRate
                    {
                        let level = currentLevel == -1 ? 0 : currentLevel
                        let nextLevelPoints = Int(
                            Double(SkillTreeManager.levelBasePoints[level])
                                * skill.timeMultiplier)
                        let remainingSP = nextLevelPoints - (skill.currentSkillPoints ?? 0)
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
    @State private var isFirstAppear = true  // 添加一个状态来跟踪是否是首次出现

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
            )
        )
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
                    // 添加筛选器 Picker
                    Picker("Filter", selection: $viewModel.selectedFilter) {
                        ForEach(SkillFilter.allCases, id: \.self) { filter in
                            Text(filter.localized).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    //.padding(.horizontal)
                    .onChange(of: viewModel.selectedFilter) { _, _ in
                        viewModel.updateFilteredGroups()
                    }

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
                                        "\(group.skills.count) \(NSLocalizedString("Main_Skills_number", comment: "")) - \(formatNumber(group.totalSkillPoints)) SP"
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
            if isFirstAppear {
                Task {
                    await viewModel.loadSkills()
                    isFirstAppear = false
                }
            }
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
    @StateObject private var viewModel: SkillCategoryViewModel

    init(group: SkillGroup, databaseManager: DatabaseManager, characterId: Int) {
        self.group = group
        self.databaseManager = databaseManager
        self.characterId = characterId
        _viewModel = StateObject(
            wrappedValue: SkillCategoryViewModel(
                characterId: characterId,
                databaseManager: databaseManager,
                characterDatabaseManager: CharacterDatabaseManager.shared
            )
        )
    }

    var body: some View {
        List {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                // 使用传入的 group 数据
                ForEach(group.skills, id: \.skill_id) { skill in
                    if let skillInfo = viewModel.allSkillsDict[skill.skill_id] {
                        NavigationLink {
                            ShowItemInfo(
                                databaseManager: databaseManager,
                                itemID: skill.skill_id
                            )
                        } label: {
                            SkillCellView(
                                skill: (
                                    typeId: skill.skill_id,
                                    name: skillInfo.name,
                                    timeMultiplier: skillInfo.timeMultiplier,
                                    currentSkillPoints: skillInfo.currentSkillPoints,
                                    currentLevel: skillInfo.currentLevel,
                                    trainingRate: skillInfo.trainingRate
                                ))
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            }
        }
        .navigationTitle(group.name)
        .onAppear {
            Task {
                await viewModel.loadSkills()
            }
        }
    }
}
