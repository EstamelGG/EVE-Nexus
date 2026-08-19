import SwiftUI

/// 添加技能选择器视图
struct AddSkillSelectorView: View {
    @ObservedObject var databaseManager: DatabaseManager
    let onBatchSkillsSelected: ([(skillId: Int, skillName: String, level: Int)]) -> Void // 批量添加回调
    let onSkillLevelsRemoved: (Int, Int, Int) -> Void // 移除技能等级回调 (skillId, fromLevel, toLevel)
    let existingSkillLevels: [Int: Int] // [skillId: maxLevel] 计划中已有的技能最高等级
    @Binding var skillDependencies: [String: Set<String>] // 技能的后置依赖关系（使用 Binding）
    @Environment(\.dismiss) private var dismiss

    @State private var skillGroups: [SkillGroupInfo] = []
    @State private var isLoading = true
    @State private var searchText = "" // 添加搜索文本
    @State private var allSkills: [SkillInfo] = [] // 存储所有技能，用于搜索
    @State private var skillLevels: [Int: Int] = [:] // [skillId: level] 用于搜索结果的等级管理
    @State private var addedSkills: Set<Int> = [] // 已添加的技能ID集合

    /// 搜索结果
    private var filteredSkills: [SkillInfo] {
        if searchText.isEmpty {
            return []
        } else {
            return allSkills.filter { skill in
                skill.matches(searchText: searchText)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if !searchText.isEmpty {
                    // 显示搜索结果
                    if filteredSkills.isEmpty {
                        Text(NSLocalizedString("Misc_Not_Found", comment: ""))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        ForEach(filteredSkills) { skill in
                            HStack(alignment: .center, spacing: 12) {
                                // 左侧：技能名称和等级指示器
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(skill.name)
                                        .lineLimit(1)

                                    // 技能等级指示器
                                    SkillLevelIndicator(
                                        currentLevel: skillLevels[skill.id] ?? 0,
                                        trainingLevel: skillLevels[skill.id] ?? 0,
                                        isTraining: false
                                    )
                                }

                                Spacer()

                                // 右侧：技能等级选择器
                                SkillLevelSelector(
                                    skillId: skill.id,
                                    currentLevel: skillLevels[skill.id] ?? 0,
                                    minimumLevel: getMinimumLevel(for: skill.id),
                                    onLevelChanged: { newLevel in
                                        let oldLevel = skillLevels[skill.id] ?? 0

                                        if newLevel > oldLevel {
                                            // 升级：添加技能
                                            addSkillToPlan(skillId: skill.id, skillName: skill.name, level: newLevel)
                                        } else if newLevel < oldLevel {
                                            // 降级：移除高等级的技能
                                            removeSkillLevels(skillId: skill.id, fromLevel: newLevel + 1, toLevel: oldLevel)
                                        }
                                    }
                                )
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }
                } else if skillGroups.isEmpty {
                    Text("Skill Groups Not Found")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    // 显示技能组列表
                    ForEach(skillGroups.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })) { group in
                        NavigationLink {
                            SkillGroupSkillsView(
                                group: group,
                                databaseManager: databaseManager,
                                onBatchSkillsSelected: onBatchSkillsSelected,
                                onSkillLevelsRemoved: onSkillLevelsRemoved,
                                existingSkillLevels: existingSkillLevels,
                                skillDependencies: $skillDependencies
                            )
                        } label: {
                            SkillGroupRowView(group: group)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
            }
            .navigationTitle(NSLocalizedString("Main_Skills_Plan_Add_Skill", comment: "添加技能"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                // placement: .navigationBarDrawer(displayMode: .always),
                prompt: NSLocalizedString("Main_Search_Placeholder", comment: "")
            )
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Misc_Done", comment: "")) {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            loadSkillGroups()
        }
    }

    private func loadSkillGroups() {
        isLoading = true

        // 内存索引获取技能（categoryID = 16 且已发布）
        var groupDict: [Int: (name: String, skillCount: Int)] = [:]
        var tempAllSkills: [SkillInfo] = []

        for (typeId, info) in SDEMemoryStore.types where info.categoryID == 16 && info.published {
            guard let groupId = info.groupID else { continue }
            let groupName = SDEMemoryStore.group(for: groupId)?.name ?? ""

            tempAllSkills.append(SkillInfo(
                id: typeId,
                names: info.names,
                timeMultiplier: 1.0
            ))

            // 分组统计
            if groupDict[groupId] == nil {
                groupDict[groupId] = (name: groupName, skillCount: 0)
            }
            groupDict[groupId]?.skillCount += 1
        }

        let newSkillGroups: [SkillGroupInfo] = groupDict.map { groupId, groupInfo in
            SkillGroupInfo(
                id: groupId,
                name: groupInfo.name,
                skillCount: groupInfo.skillCount
            )
        }

        print("AddSkillSelectorView: 解析到 \(newSkillGroups.count) 个技能组")
        print("AddSkillSelectorView: 收集到 \(tempAllSkills.count) 个技能用于搜索")

        // 确保在主线程更新UI
        DispatchQueue.main.async {
            self.skillGroups = newSkillGroups
            self.allSkills = tempAllSkills

            // 初始化搜索结果的技能等级
            for skill in tempAllSkills {
                if let existingLevel = existingSkillLevels[skill.id] {
                    skillLevels[skill.id] = existingLevel
                    addedSkills.insert(skill.id)
                }
            }

            self.isLoading = false
        }
    }

    /// 添加技能到计划
    private func addSkillToPlan(skillId: Int, skillName: String, level: Int) {
        let skillsToAdd = SkillPlanHelper.collectSkillsToAdd(
            skillId: skillId,
            skillName: skillName,
            targetLevel: level,
            databaseManager: databaseManager,
            currentSkillLevels: skillLevels,
            addedSkills: &addedSkills,
            skillLevels: &skillLevels
        )

        // 批量添加所有技能（只调用一次）
        if !skillsToAdd.isEmpty {
            onBatchSkillsSelected(skillsToAdd)
        }
    }

    /// 移除技能的某些等级（降级时使用）
    private func removeSkillLevels(skillId: Int, fromLevel: Int, toLevel: Int) {
        guard fromLevel <= toLevel else { return }

        // Logger.debug("[降级] 移除技能 ID: \(skillId), 从等级 \(fromLevel) 到 \(toLevel)")

        // 更新本地状态
        if fromLevel == 1 {
            // 完全移除
            addedSkills.remove(skillId)
            skillLevels[skillId] = 0
        } else {
            // 降级到 fromLevel-1
            skillLevels[skillId] = fromLevel - 1
        }

        // 通知父视图移除这些技能等级
        onSkillLevelsRemoved(skillId, fromLevel, toLevel)
    }

    /// 检查技能等级是否有后置依赖
    private func hasPostDependencies(skillId: Int, level: Int) -> Bool {
        let key = "\(skillId)_\(level)"
        return !(skillDependencies[key]?.isEmpty ?? true)
    }

    /// 获取技能可以降级到的最低等级
    private func getMinimumLevel(for skillId: Int) -> Int {
        let currentLevel = skillLevels[skillId] ?? 0

        // 如果当前等级为0，无需检查
        guard currentLevel > 0 else {
            return 0
        }

        // 从当前等级往下检查，找到第一个有后置依赖的等级
        for level in (1 ... currentLevel).reversed() {
            if hasPostDependencies(skillId: skillId, level: level) {
                return level // 有依赖，不能低于这个等级
            }
        }

        return 0 // 无依赖，可以完全移除
    }
}

/// 技能组信息模型
struct SkillGroupInfo: Identifiable {
    let id: Int
    let name: String
    let skillCount: Int
}

/// 技能组行视图
struct SkillGroupRowView: View {
    let group: SkillGroupInfo
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            // 显示技能组图标
            Image(SkillGroupIconManager.shared.getIconName(for: group.id))
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 32)
                .cornerRadius(8)
                .modifier(SkillGroupIconModifier(colorScheme: colorScheme))

            VStack(alignment: .leading, spacing: 4) {
                Text(group.name)
                Text("\(group.skillCount) \(NSLocalizedString("Main_Skills_number", comment: ""))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

/// 技能组技能列表视图
struct SkillGroupSkillsView: View {
    let group: SkillGroupInfo
    @ObservedObject var databaseManager: DatabaseManager
    let onBatchSkillsSelected: ([(skillId: Int, skillName: String, level: Int)]) -> Void // 批量添加回调
    let onSkillLevelsRemoved: (Int, Int, Int) -> Void // 移除技能等级回调 (skillId, fromLevel, toLevel)
    let existingSkillLevels: [Int: Int] // [skillId: maxLevel] 计划中已有的技能最高等级
    @Binding var skillDependencies: [String: Set<String>] // 技能的后置依赖关系（使用 Binding）

    @State private var skills: [SkillInfo] = []
    @State private var isLoading = true
    @State private var skillLevels: [Int: Int] = [:] // [skillId: level]
    @State private var addedSkills: Set<Int> = [] // 已添加的技能ID集合

    var body: some View {
        List {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ForEach(skills.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })) { skill in
                    HStack(alignment: .center, spacing: 12) {
                        // 左侧：技能名称和等级指示器
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 2) {
                                Text(skill.name)
                                    .lineLimit(1)
                                if skill.timeMultiplier >= 1 {
                                    Text("(×\(String(format: "%.0f", skill.timeMultiplier)))")
                                }
                            }

                            // 技能等级指示器
                            SkillLevelIndicator(
                                currentLevel: skillLevels[skill.id] ?? 0,
                                trainingLevel: skillLevels[skill.id] ?? 0,
                                isTraining: false
                            )
                        }

                        Spacer()

                        // 右侧：技能等级选择器
                        SkillLevelSelector(
                            skillId: skill.id,
                            currentLevel: skillLevels[skill.id] ?? 0,
                            minimumLevel: getMinimumLevel(for: skill.id),
                            onLevelChanged: { newLevel in
                                let oldLevel = skillLevels[skill.id] ?? 0

                                if newLevel > oldLevel {
                                    // 升级：添加技能
                                    addSkillToPlan(skillId: skill.id, skillName: skill.name, level: newLevel)
                                } else if newLevel < oldLevel {
                                    // 降级：移除高等级的技能
                                    removeSkillLevels(skillId: skill.id, fromLevel: newLevel + 1, toLevel: oldLevel)
                                }
                            }
                        )
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            }
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadSkills()
        }
    }

    private func loadSkills() {
        isLoading = true

        let query = """
            SELECT t.type_id
            FROM types t
            WHERE t.published = 1 AND t.categoryID = 16 AND t.groupID = ?
            ORDER BY t.name
        """

        if case let .success(rows) = databaseManager.executeQuery(query, parameters: [group.id]) {
            skills = rows.compactMap { row in
                guard let typeId = row["type_id"] as? Int,
                      let type = SDEMemoryStore.type(for: typeId)
                else {
                    return nil
                }

                let timeMultiplier = SkillTreeManager.shared.trainingTimeMultiplier(for: typeId) ?? 1.0

                return SkillInfo(
                    id: typeId,
                    names: type.names,
                    timeMultiplier: timeMultiplier
                )
            }

            // 初始化技能等级：根据计划中已有的技能设置初始值
            for skill in skills {
                if let existingLevel = existingSkillLevels[skill.id] {
                    // 如果计划中已有该技能，初始化为已有的等级
                    skillLevels[skill.id] = existingLevel
                    addedSkills.insert(skill.id)
                    Logger.debug("[初始化] 技能 \(skill.name) (ID: \(skill.id)) 在计划中已存在，等级: \(existingLevel)")
                }
            }
        }

        isLoading = false
    }

    /// 添加技能到计划
    private func addSkillToPlan(skillId: Int, skillName: String, level: Int) {
        let skillsToAdd = SkillPlanHelper.collectSkillsToAdd(
            skillId: skillId,
            skillName: skillName,
            targetLevel: level,
            databaseManager: databaseManager,
            currentSkillLevels: skillLevels,
            addedSkills: &addedSkills,
            skillLevels: &skillLevels
        )

        // 批量添加所有技能（只调用一次）
        if !skillsToAdd.isEmpty {
            onBatchSkillsSelected(skillsToAdd)
        }
    }

    /// 移除技能的某些等级（降级时使用）
    private func removeSkillLevels(skillId: Int, fromLevel: Int, toLevel: Int) {
        guard fromLevel <= toLevel else { return }

        // Logger.debug("[降级] 移除技能 ID: \(skillId), 从等级 \(fromLevel) 到 \(toLevel)")

        // 更新本地状态
        if fromLevel == 1 {
            // 完全移除
            addedSkills.remove(skillId)
            skillLevels[skillId] = 0
        } else {
            // 降级到 fromLevel-1
            skillLevels[skillId] = fromLevel - 1
        }

        // 通知父视图移除这些技能等级
        onSkillLevelsRemoved(skillId, fromLevel, toLevel)
    }

    /// 检查技能等级是否有后置依赖
    private func hasPostDependencies(skillId: Int, level: Int) -> Bool {
        let key = "\(skillId)_\(level)"
        return !(skillDependencies[key]?.isEmpty ?? true)
    }

    /// 获取技能可以降级到的最低等级
    private func getMinimumLevel(for skillId: Int) -> Int {
        let currentLevel = skillLevels[skillId] ?? 0

        // 如果当前等级为0，无需检查
        guard currentLevel > 0 else {
            return 0
        }

        // 从当前等级往下检查，找到第一个有后置依赖的等级
        for level in (1 ... currentLevel).reversed() {
            if hasPostDependencies(skillId: skillId, level: level) {
                return level // 有依赖，不能低于这个等级
            }
        }

        return 0 // 无依赖，可以完全移除
    }
}

/// 技能信息模型
struct SkillInfo: Identifiable {
    let id: Int
    let names: LocalizedText
    let timeMultiplier: Double

    var name: String {
        names.resolved()
    }

    func matches(searchText: String) -> Bool {
        names.matchesSearch(searchText)
    }
}

/// 技能等级选择器
struct SkillLevelSelector: View {
    let skillId: Int
    let currentLevel: Int
    let minimumLevel: Int // 最低可降级到的等级
    let onLevelChanged: (Int) -> Void

    @State private var localLevel: Int

    init(skillId: Int, currentLevel: Int, minimumLevel: Int = 0, onLevelChanged: @escaping (Int) -> Void) {
        self.skillId = skillId
        self.currentLevel = currentLevel
        self.minimumLevel = minimumLevel
        self.onLevelChanged = onLevelChanged
        _localLevel = State(initialValue: currentLevel)
    }

    var body: some View {
        Stepper(value: $localLevel, in: minimumLevel ... 5) {}
            .onChange(of: localLevel) { _, newValue in
                onLevelChanged(newValue)
            }
            .onChange(of: currentLevel) { _, newValue in
                localLevel = newValue
            }
    }
}
