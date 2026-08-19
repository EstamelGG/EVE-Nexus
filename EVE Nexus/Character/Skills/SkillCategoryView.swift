import SwiftUI

/// 技能筛选条件
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

/// 技能组模型
struct SkillGroup: Identifiable {
    let id: Int // groupID
    let name: String // group_name
    var skills: [CharacterSkill]
    let totalSkillsInGroup: Int // 该组中的总技能数
    let maxTotalSkillPoints: Int // 该组所有技能满级时的总点数
    let learnedTotalSkillPoints: Int // 该组已学技能的总点数

    var totalSkillPoints: Int {
        skills.reduce(0) { $0 + $1.skillpoints_in_skill }
    }
}

/// 技能目录视图模型
@MainActor
class SkillCategoryViewModel: ObservableObject {
    @Published var skillGroups: [SkillGroup] = []
    @Published var isLoading = true
    @Published var searchText = ""
    @Published var selectedFilter: SkillFilter = .all
    @Published var isRefreshing = false // 添加下拉刷新状态

    private let characterId: Int
    private let databaseManager: DatabaseManager
    private let characterDatabaseManager: CharacterDatabaseManager

    /// 修改 allSkillsDict 的类型
    var allSkillsDict:
        [Int: (
            names: LocalizedText,
            groupID: Int,
            timeMultiplier: Double,
            currentSkillPoints: Int,
            currentLevel: Int,
            trainingRate: Int?
        )] = [:]

    /// 添加一个数组来存储所有技能组
    private var allSkillGroups: [SkillGroup] = []

    /// 存储技能队列
    private var skillQueue: [SkillQueueItem] = []

    /// 判断单个技能组是否满了
    func isGroupCompleted(_ group: SkillGroup) -> Bool {
        return group.maxTotalSkillPoints > 0 &&
            group.learnedTotalSkillPoints >= group.maxTotalSkillPoints
    }

    /// 获取指定技能组中在队列中的技能数量（仅未完成的，按技能ID去重）
    func getQueueCount(for group: SkillGroup) -> Int {
        let groupSkillIds = Set(group.skills.map { $0.skill_id })
        return groupSkillIds.filter { hasActiveQueueItem($0) }.count
    }

    /// 获取指定技能组中队列中技能的点数总和
    func getQueueSkillPoints(for group: SkillGroup) -> Int {
        let groupSkillIds = Set(group.skills.map { $0.skill_id })
        let queueSkillsInGroup = skillQueue.filter { groupSkillIds.contains($0.skill_id) }
            .sorted { $0.queue_position < $1.queue_position } // 按队列位置排序

        // 用于跟踪每个技能当前应该从哪个等级开始计算
        var skillCurrentLevels: [Int: Int] = [:]

        var totalQueuePoints = 0
        for queueItem in queueSkillsInGroup {
            // 获取技能的当前等级和倍增系数
            guard let skillInfo = allSkillsDict[queueItem.skill_id] else { continue }

            // 确定起始等级：如果这个技能在队列中第一次出现，使用实际当前等级
            // 否则使用队列中前一个等级的目标等级
            let startLevel: Int
            if let previousLevel = skillCurrentLevels[queueItem.skill_id] {
                // 这个技能在队列中已经出现过，从前一个目标等级开始
                startLevel = previousLevel
            } else {
                // 这个技能第一次在队列中出现，从实际当前等级开始
                startLevel = max(0, skillInfo.currentLevel)
            }

            let targetLevel = queueItem.finished_level
            let timeMultiplier = skillInfo.timeMultiplier

            // 如果目标等级 <= 起始等级，跳过
            if targetLevel <= startLevel {
                continue
            }

            // 确保目标等级在有效范围内（1-5）
            guard targetLevel >= 1 && targetLevel <= 5 else {
                continue
            }

            // 计算从起始等级到目标等级需要的点数
            let targetLevelPoints = SkillTreeManager.skillPoints(
                level: targetLevel,
                multiplier: timeMultiplier
            ) ?? 0
            let startLevelPoints = SkillTreeManager.skillPoints(
                level: startLevel,
                multiplier: timeMultiplier
            ) ?? 0

            totalQueuePoints += targetLevelPoints - startLevelPoints

            // 更新这个技能的下一个起始等级为当前目标等级
            skillCurrentLevels[queueItem.skill_id] = targetLevel
        }

        return totalQueuePoints
    }

    /// 检查技能是否有未完成的队列项（用于"队列中"section，排除已全部完成的技能）
    /// 已完成：finish_date <= now
    func hasActiveQueueItem(_ skillId: Int) -> Bool {
        let now = Date()
        return skillQueue.contains { item in
            guard item.skill_id == skillId else { return false }
            if let finishDate = item.finish_date {
                return finishDate > now
            }
            return true // 无 finish_date 视为暂停，仍算在队列中
        }
    }

    /// 检查技能是否正在训练
    func isSkillCurrentlyTraining(_ skillId: Int) -> Bool {
        return skillQueue.first { $0.skill_id == skillId && $0.isCurrentlyTraining } != nil
    }

    /// 获取技能在队列中的等级集合（排除正在训练的等级）
    func getQueuedLevels(for skillId: Int) -> Set<Int> {
        return Set(skillQueue.filter {
            $0.skill_id == skillId && !$0.isCurrentlyTraining
        }.map { $0.finished_level })
    }

    /// 获取技能正在训练的等级（如果正在训练）
    func getTrainingLevel(for skillId: Int) -> Int? {
        return skillQueue.first { $0.skill_id == skillId && $0.isCurrentlyTraining }?.finished_level
    }

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

    func loadSkills(forceRefresh: Bool = false) async {
        if forceRefresh {
            isRefreshing = true
        } else if allSkillsDict.isEmpty {
            // 已有数据时不显示全屏加载，避免从子页面返回时列表被替换导致滚动位置丢失
            isLoading = true
        }

        defer {
            isLoading = false
            isRefreshing = false
        }

        do {
            // 1. 一次调用获取技能数据和技能队列（API 内部并行请求）
            let (skillsResponse, queue) = try await CharacterSkillsAPI.shared.fetchCharacterSkillsAndQueue(
                characterId: characterId,
                forceRefresh: forceRefresh
            )

            // 合并队列中已完成的部分到技能等级，解决刚训练完的技能无法参与计算的问题
            let baseSkills = Dictionary(uniqueKeysWithValues: skillsResponse.skillsMap.map { ($0.key, $0.value.trained_skill_level) })
            let mergedSkillLevels = CharacterSkillsUtils.mergeCompletedQueueIntoSkills(
                baseSkills: baseSkills,
                queue: queue
            )

            // 使用已学习技能的查找字典（mergedSkillLevels 用于等级显示和计算）
            let learnedSkills = skillsResponse.skillsMap

            let skillsQuery = """
                SELECT 
                    t.type_id,
                    t.groupID,
                    t.group_name
                FROM types t
                WHERE t.published = 1 and t.categoryID = 16
            """

            guard case let .success(skillRows) = databaseManager.executeQuery(skillsQuery) else {
                return
            }

            // 3. 合并所有技能信息并计算技能组总数
            var groupDict: [Int: (name: String, skills: [Int])] = [:]
            for row in skillRows {
                guard let typeId = row["type_id"] as? Int,
                      let groupId = row["groupID"] as? Int,
                      let groupName = row["group_name"] as? String,
                      let type = SDEMemoryStore.type(for: typeId)
                else {
                    continue
                }

                // 保存技能组信息
                if groupDict[groupId] == nil {
                    groupDict[groupId] = (name: groupName, skills: [])
                }
                groupDict[groupId]?.skills.append(typeId)

                let timeMultiplier = SkillTreeManager.shared.trainingTimeMultiplier(for: typeId) ?? 1.0
                let learnedSkill = learnedSkills[typeId]
                // 使用合并后的等级（含队列中已完成的），确保刚训练完的技能正确参与计算
                let currentLevel = mergedSkillLevels[typeId] ?? learnedSkill?.trained_skill_level ?? -1

                allSkillsDict[typeId] = (
                    names: type.names,
                    groupID: groupId,
                    timeMultiplier: timeMultiplier,
                    currentSkillPoints: learnedSkill?.skillpoints_in_skill ?? 0,
                    currentLevel: currentLevel,
                    trainingRate: nil
                )
            }

            // 获取角色属性
            do {
                let attributes = try await CharacterSkillsAPI.shared.fetchAttributes(
                    characterId: characterId
                )

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

                // 计算该组所有已发布技能满级时的总点数（包括未注入的技能）
                let maxTotalSP = groupSkills.reduce(0) { total, item in
                    let maxSP = Int(256_000 * item.value.timeMultiplier)
                    return total + maxSP
                }

                // 计算该组已学技能的总点数
                let learnedTotalSP = groupSkills.reduce(0) { total, item in
                    total + item.value.currentSkillPoints
                }

                if !allSkills.isEmpty {
                    groups.append(
                        SkillGroup(
                            id: groupId,
                            name: groupInfo.name,
                            skills: allSkills,
                            totalSkillsInGroup: groupSkills.count,
                            maxTotalSkillPoints: maxTotalSP,
                            learnedTotalSkillPoints: learnedTotalSP
                        )
                    )
                }
            }

            // 技能队列已在步骤1中并行加载
            await MainActor.run {
                self.skillQueue = queue
            }

            await MainActor.run {
                self.allSkillGroups = groups
                self.updateFilteredGroups()
            }

        } catch {
            Logger.error("加载技能数据失败: \(error)")
        }
    }

    /// 修改过滤方法
    func updateFilteredGroups() {
        if searchText.isEmpty {
            // 根据筛选条件过滤技能组
            skillGroups = allSkillGroups.map { group in
                // 根据筛选条件过滤技能
                let filteredSkills = group.skills.filter { skill in
                    switch selectedFilter {
                    case .all:
                        return true // 显示所有技能
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
                    totalSkillsInGroup: group.totalSkillsInGroup,
                    maxTotalSkillPoints: group.maxTotalSkillPoints,
                    learnedTotalSkillPoints: group.learnedTotalSkillPoints
                )
            }.filter { !$0.skills.isEmpty } // 移除空组
        } else {
            // 搜索逻辑保持不变
            skillGroups = []
        }
    }

    /// 修改搜索功能
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
            let filteredByLevel = allSkillsDict.filter { _, info in
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
            return filteredByLevel
                .filter { _, info in
                    info.names.matchesSearch(searchText)
                }
                .map { typeId, info in
                    (
                        typeId: typeId,
                        name: info.names.resolved(),
                        timeMultiplier: info.timeMultiplier,
                        currentSkillPoints: info.currentSkillPoints,
                        currentLevel: info.currentLevel,
                        trainingRate: info.trainingRate
                    )
                }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }
}

/// 通用技能单元格视图
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
    let viewModel: SkillCategoryViewModel?

    init(
        skill: (
            typeId: Int, name: String, timeMultiplier: Double, currentSkillPoints: Int?,
            currentLevel: Int?, trainingRate: Int?
        ),
        viewModel: SkillCategoryViewModel? = nil
    ) {
        self.skill = skill
        self.viewModel = viewModel
    }

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

                    // 检查是否正在训练
                    let isTraining = viewModel?.isSkillCurrentlyTraining(skill.typeId) ?? false
                    let trainingLevel = viewModel?.getTrainingLevel(for: skill.typeId) ?? currentLevel
                    let queuedLevels = viewModel?.getQueuedLevels(for: skill.typeId) ?? []

                    SkillLevelIndicator(
                        currentLevel: currentLevel,
                        trainingLevel: trainingLevel,
                        isTraining: isTraining,
                        queuedLevels: queuedLevels
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
                    let pointsText = String(
                        format: NSLocalizedString("Main_Skills_Points_Progress", comment: ""),
                        FormatUtil.formatInteger(currentPoints),
                        FormatUtil.formatInteger(maxSkillPoints)
                    )

                    Text(pointsText)

                    if let rate = skill.trainingRate {
                        Text("(\(FormatUtil.formatInteger(rate))/h)")
                    }
                    Spacer()

                    // 添加下一级训练时间显示
                    if let currentLevel = skill.currentLevel,
                       currentLevel >= -1 && currentLevel < 5, // 只有当前等级在-1 ~ 4之间时才显示
                       let rate = skill.trainingRate
                    {
                        let level = currentLevel == -1 ? 0 : currentLevel
                        let nextLevelPoints = Int(
                            Double(SkillTreeManager.levelBasePoints[level])
                                * skill.timeMultiplier
                        )
                        let remainingSP = nextLevelPoints - (skill.currentSkillPoints ?? 0)
                        let trainingTimeHours = Double(remainingSP) / Double(rate)
                        let trainingTime = trainingTimeHours * 3600 // 转换为秒
                        Text(
                            String(
                                format: NSLocalizedString("Main_Skills_Time_Required", comment: ""),
                                FormatUtil.formatCompactDuration(trainingTime, rounding: .ceil)
                            )
                        )
                    }
                }

                // 检查技能状态，在新的一行显示（仅未完成的队列项显示"队列中"）
                let isTraining = viewModel?.isSkillCurrentlyTraining(skill.typeId) ?? false
                let hasActiveQueue = viewModel?.hasActiveQueueItem(skill.typeId) ?? false

                if isTraining {
                    HStack {
                        Text(NSLocalizedString("Main_Skills_Training", comment: ""))
                            .foregroundColor(.green)
                        Spacer()
                    }
                } else if hasActiveQueue {
                    HStack {
                        Text(NSLocalizedString("Main_Skills_In_Queue", comment: ""))
                            .foregroundColor(.cyan)
                        Spacer()
                    }
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }.contextMenu {
            Button {
                UIPasteboard.general.string = skill.name
            } label: {
                Label(NSLocalizedString("Misc_Copy", comment: ""), systemImage: "doc.on.doc")
            }
        }
    }
}

struct SkillCategoryView: View {
    let characterId: Int
    let databaseManager: DatabaseManager
    @StateObject private var viewModel: SkillCategoryViewModel
    @State private var isFirstAppear = true // 添加一个状态来跟踪是否是首次出现
    @Environment(\.colorScheme) private var colorScheme

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
            } else {
                if viewModel.searchText.isEmpty {
                    // 添加筛选器 Picker（始终显示，即使没有技能）
                    Picker("Filter", selection: $viewModel.selectedFilter) {
                        ForEach(SkillFilter.allCases, id: \.self) { filter in
                            Text(filter.localized).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    // .padding(.horizontal)
                    .onChange(of: viewModel.selectedFilter) { _, _ in
                        viewModel.updateFilteredGroups()
                    }

                    // 显示技能组列表或空状态
                    if viewModel.skillGroups.isEmpty {
                        Text(NSLocalizedString("Main_Skills_No_Skills", comment: ""))
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(
                            viewModel.skillGroups.sorted(by: {
                                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                            })
                        ) { group in
                            NavigationLink {
                                SkillGroupDetailView(
                                    group: group, databaseManager: databaseManager,
                                    characterId: characterId
                                )
                            } label: {
                                HStack(spacing: 8) {
                                    // 显示技能组图标
                                    Image(SkillGroupIconManager.shared.getIconName(for: group.id))
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 32, height: 32)
                                        .cornerRadius(8)
                                        .modifier(SkillGroupIconModifier(colorScheme: colorScheme))

                                    VStack(alignment: .leading) {
                                        HStack(spacing: 4) {
                                            Text(group.name)
                                            // 如果全部完成，显示绿色对勾图标
                                            if group.maxTotalSkillPoints > 0,
                                               group.learnedTotalSkillPoints >= group.maxTotalSkillPoints
                                            {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(.green)
                                                    .font(.caption)
                                            }
                                        }
                                        let queueCount = viewModel.getQueueCount(for: group)
                                        let baseText = "\(group.skills.count) \(NSLocalizedString("Main_Skills_number", comment: "")) - \(FormatUtil.formatInteger(group.totalSkillPoints)) SP"

                                        if queueCount > 0 {
                                            let queueText = String(format: NSLocalizedString("Main_Skills_Queue_Count", comment: ""), queueCount)
                                            (Text(baseText) + Text(" - ") + Text(queueText).foregroundColor(.cyan))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        } else {
                                            Text(baseText)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                            .listRowBackground(
                                group.maxTotalSkillPoints > 0
                                    ? GeometryReader { geometry in
                                        let learnedProgress = Double(group.learnedTotalSkillPoints) / Double(group.maxTotalSkillPoints)
                                        let learnedWidth = geometry.size.width * min(max(learnedProgress, 0), 1)

                                        // 获取队列中技能的点数
                                        let queueSkillPoints = viewModel.getQueueSkillPoints(for: group)
                                        let queueProgress = Double(queueSkillPoints) / Double(group.maxTotalSkillPoints)
                                        let queueWidthRaw = geometry.size.width * min(max(queueProgress, 0), 1)

                                        // 确保队列宽度不会超出总宽度（从已学部分的结束位置开始）
                                        let remainingWidth = max(0, geometry.size.width - learnedWidth)
                                        let queueWidth = min(queueWidthRaw, remainingWidth)

                                        // 判断当前组是否满了
                                        let isCompleted = viewModel.isGroupCompleted(group)

                                        // 如果组满了，使用浅绿色；否则使用蓝色
                                        let backgroundColor = isCompleted
                                            ? Color.green.opacity(0.3)
                                            : Color.blue.opacity(0.2)

                                        // 队列中技能的点数使用青色
                                        let queueColor = Color.cyan.opacity(0.3)

                                        ZStack(alignment: .leading) {
                                            // 使用系统背景色作为底层，保持默认的白色
                                            Color(UIColor.systemBackground)
                                                .frame(width: geometry.size.width, height: geometry.size.height)

                                            // 已学技能部分的背景，覆盖在默认行背景上
                                            backgroundColor
                                                .frame(width: learnedWidth, height: geometry.size.height)

                                            // 队列中技能的点数，从已学部分的结束位置开始
                                            if queueWidth > 0 {
                                                queueColor
                                                    .frame(width: queueWidth, height: geometry.size.height)
                                                    .offset(x: learnedWidth)
                                            }
                                        }
                                    }
                                    : nil
                            )
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }
                } else {
                    // 显示搜索结果
                    if viewModel.filteredSkills.isEmpty {
                        Text(NSLocalizedString("Main_Search_No_Results", comment: ""))
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(viewModel.filteredSkills, id: \.typeId) { skill in
                            NavigationLink {
                                ShowItemInfo(
                                    databaseManager: databaseManager,
                                    itemID: skill.typeId
                                )
                            } label: {
                                SkillCellView(skill: skill, viewModel: viewModel)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Main_Skills_Category", comment: ""))
        .searchable(
            text: $viewModel.searchText,
            // placement: .navigationBarDrawer(displayMode: .always),
            prompt: NSLocalizedString("Main_Search_Placeholder", comment: "")
        )
        .refreshable {
            // 下拉刷新功能
            await viewModel.loadSkills(forceRefresh: true)
        }
        .onAppear {
            if isFirstAppear {
                Task {
                    await viewModel.loadSkills()
                    isFirstAppear = false
                }
            }
        }
    }
}

/// 技能组详情视图
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
                // 将技能分为队列中的技能和其他技能
                let sortedSkills = group.skills.sorted { skill1, skill2 in
                    let name1 = viewModel.allSkillsDict[skill1.skill_id]?.names.resolved() ?? ""
                    let name2 = viewModel.allSkillsDict[skill2.skill_id]?.names.resolved() ?? ""
                    return name1.localizedCaseInsensitiveCompare(name2) == .orderedAscending
                }

                // 队列中的技能（仅未完成的：正在训练或等待中，排除已全部完成的）
                let queuedSkills = sortedSkills.filter { skill in
                    viewModel.hasActiveQueueItem(skill.skill_id)
                }

                // 其他技能（不在活跃队列中的）
                let otherSkills = sortedSkills.filter { skill in
                    !viewModel.hasActiveQueueItem(skill.skill_id)
                }

                // 将队列中的技能排序：正在训练的技能排在第一个，其他按名称排序
                let sortedQueuedSkills = queuedSkills.sorted { skill1, skill2 in
                    let isTraining1 = viewModel.isSkillCurrentlyTraining(skill1.skill_id)
                    let isTraining2 = viewModel.isSkillCurrentlyTraining(skill2.skill_id)

                    // 如果一个是正在训练的，另一个不是，正在训练的排在前面
                    if isTraining1 && !isTraining2 {
                        return true
                    }
                    if !isTraining1 && isTraining2 {
                        return false
                    }

                    // 如果都是或都不是正在训练的，按名称排序
                    let name1 = viewModel.allSkillsDict[skill1.skill_id]?.names.resolved() ?? ""
                    let name2 = viewModel.allSkillsDict[skill2.skill_id]?.names.resolved() ?? ""
                    return name1.localizedCaseInsensitiveCompare(name2) == .orderedAscending
                }

                // 如果有队列中的技能，显示"队列中"section
                if !sortedQueuedSkills.isEmpty {
                    Section(header: Text(NSLocalizedString("Main_Skills_In_Queue", comment: ""))) {
                        ForEach(sortedQueuedSkills, id: \.skill_id) { skill in
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
                                            name: skillInfo.names.resolved(),
                                            timeMultiplier: skillInfo.timeMultiplier,
                                            currentSkillPoints: skillInfo.currentSkillPoints,
                                            currentLevel: skillInfo.currentLevel,
                                            trainingRate: skillInfo.trainingRate
                                        ),
                                        viewModel: viewModel
                                    )
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }
                }

                // 显示其他技能
                if !otherSkills.isEmpty {
                    ForEach(otherSkills, id: \.skill_id) { skill in
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
                                        name: skillInfo.names.resolved(),
                                        timeMultiplier: skillInfo.timeMultiplier,
                                        currentSkillPoints: skillInfo.currentSkillPoints,
                                        currentLevel: skillInfo.currentLevel,
                                        trainingRate: skillInfo.trainingRate
                                    ),
                                    viewModel: viewModel
                                )
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
            }
        }
        .navigationTitle(group.name)
        .refreshable {
            // 下拉刷新功能
            await viewModel.loadSkills(forceRefresh: true)
        }
    }
}

/// 技能组图标修饰符，在浅色模式下反色
struct SkillGroupIconModifier: ViewModifier {
    let colorScheme: ColorScheme

    func body(content: Content) -> some View {
        if colorScheme == .light {
            content.colorInvert()
        } else {
            content
        }
    }
}
