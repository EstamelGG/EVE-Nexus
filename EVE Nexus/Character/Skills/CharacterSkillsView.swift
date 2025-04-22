import Foundation
import SwiftUI

/// 植入体属性加成
struct ImplantAttributes {
    var charismaBonus: Int = 0
    var intelligenceBonus: Int = 0
    var memoryBonus: Int = 0
    var perceptionBonus: Int = 0
    var willpowerBonus: Int = 0
}

struct CharacterSkillsView: View {
    let characterId: Int
    let databaseManager: DatabaseManager
    @State private var skillQueue: [SkillQueueItem] = []
    @State private var skillNames: [Int: String] = [:]
    @State private var isRefreshing = false
    @State private var isLoading = true
    @State private var isLoadingInjectors = true
    @State private var skillIcon: Image?
    @State private var injectorCalculation: InjectorCalculation?
    @State private var injectorPrices: (large: Double?, small: Double?) = (nil, nil)
    @State private var characterAttributes: CharacterAttributes?
    @State private var implantBonuses: ImplantAttributes?
    @State private var trainingRates: [Int: Int] = [:]  // [skillId: pointsPerHour]
    @State private var optimalAttributes: OptimalAttributeAllocation?
    @State private var attributeComparisons:
        [(name: String, icon: String, current: Int, optimal: Int, diff: Int)] = []
    @State private var isDataReady = false  // 新增：用于控制整体内容的显示
    @State private var hasInitialized = false  // 追踪是否已执行初始化
    @State private var currentLoadTask: Task<Void, Never>?  // 追踪当前加载任务

    private func updateAttributeComparisons() {
        guard let attrs = characterAttributes,
            let optimal = optimalAttributes,
            implantBonuses != nil
        else {
            attributeComparisons = []
            return
        }

        let minAttr = 17  // 基础属性值

        // 只添加需要分配点数的属性
        var comparisons: [(name: String, icon: String, current: Int, optimal: Int, diff: Int)] = []

        let attributes = [
            (
                NSLocalizedString("Character_Attribute_Perception", comment: ""), "perception",
                attrs.perception, optimal.perception, optimal.perception - minAttr
            ),
            (
                NSLocalizedString("Character_Attribute_Memory", comment: ""), "memory",
                attrs.memory, optimal.memory, optimal.memory - minAttr
            ),
            (
                NSLocalizedString("Character_Attribute_Willpower", comment: ""), "willpower",
                attrs.willpower, optimal.willpower, optimal.willpower - minAttr
            ),
            (
                NSLocalizedString("Character_Attribute_Intelligence", comment: ""), "intelligence",
                attrs.intelligence, optimal.intelligence, optimal.intelligence - minAttr
            ),
            (
                NSLocalizedString("Character_Attribute_Charisma", comment: ""), "charisma",
                attrs.charisma, optimal.charisma, optimal.charisma - minAttr
            ),
        ]

        // 只添加有分配点数的属性
        for attr in attributes {
            if attr.4 > 0 {  // 只显示分配了点数的属性
                comparisons.append(attr)
            }
        }

        attributeComparisons = comparisons
    }

    private var activeSkills: [SkillQueueItem] {
        let now = Date()

        // 检查队列是否暂停
        let isPaused = isQueuePaused

        // 根据队列状态过滤技能
        let activeQueue =
            skillQueue
            .filter { skill in
                // 如果队列暂停，显示所有技能
                if isPaused {
                    return true
                }

                // 如果队列在训练，只显示正在训练和等待训练的技能
                guard let startDate = skill.start_date,
                    let finishDate = skill.finish_date
                else {
                    return false
                }
                return (now >= startDate && now <= finishDate) || startDate > now
            }
            .sorted { $0.queue_position < $1.queue_position }

        // 将正在训练的技能移到第一位
        if let trainingIndex = activeQueue.firstIndex(where: { $0.isCurrentlyTraining }) {
            var reorderedQueue = activeQueue
            let trainingSkill = reorderedQueue.remove(at: trainingIndex)
            reorderedQueue.insert(trainingSkill, at: 0)
            return reorderedQueue
        }

        return activeQueue
    }

    private var isQueuePaused: Bool {
        guard let firstSkill = skillQueue.first,
            firstSkill.start_date != nil,
            firstSkill.finish_date != nil
        else {
            return true
        }
        return false
    }

    private var totalRemainingTime: TimeInterval? {
        guard let lastSkill = activeSkills.last,
            let finishDate = lastSkill.finish_date,
            finishDate.timeIntervalSinceNow > 0
        else {
            return nil
        }
        return finishDate.timeIntervalSinceNow
    }

    // 获取技能的当前等级（队列中最低等级-1）
    private func getCurrentLevel(for skillId: Int) -> Int {
        let minLevel =
            activeSkills
            .filter { $0.skill_id == skillId }
            .map { $0.finished_level }
            .min() ?? 1
        return minLevel - 1
    }

    // 计算注入器总价值
    private var totalInjectorCost: Double? {
        guard let calculation = injectorCalculation else {
            Logger.debug("计算总价失败 - 没有注入器计算结果")
            return nil
        }
        guard let largePrice = injectorPrices.large else {
            Logger.debug("计算总价失败 - 没有大型注入器价格")
            return nil
        }
        guard let smallPrice = injectorPrices.small else {
            Logger.debug("计算总价失败 - 没有小型注入器价格")
            return nil
        }

        return Double(calculation.largeInjectorCount) * largePrice + Double(
            calculation.smallInjectorCount) * smallPrice
    }

    var body: some View {
        List {
            if isLoading || !isDataReady {
                Section(NSLocalizedString("Main_Skills_Categories", comment: "")) {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } else {
                // 第一个列表 - 属性和技能目录导航
                navigationSection

                // 第二个列表 - 技能队列
                skillQueueSection

                // 第三个列表 - 注入器需求
                injectorSection

                // 第四个列表 - 属性对比
                attributeComparisonSection
            }
        }
        .navigationTitle(NSLocalizedString("Main_Skills", comment: ""))
        .refreshable {
            currentLoadTask?.cancel()
            let task = Task {
                guard !isRefreshing else { return }
                await refreshSkillQueue()
            }
            currentLoadTask = task
            await task.value
        }
        .onAppear {
            loadInitialDataIfNeeded()
        }
        .onDisappear {
            currentLoadTask?.cancel()
        }
    }

    @ViewBuilder
    private var navigationSection: some View {
        Section {
            NavigationLink {
                CharacterAttributesView(characterId: characterId)
            } label: {
                HStack {
                    Image("attributes")
                        .resizable()
                        .frame(width: 36, height: 36)
                        .cornerRadius(6)
                        .drawingGroup()
                    Text(NSLocalizedString("Main_Skills_Attribute", comment: ""))
                }
            }

            NavigationLink {
                SkillCategoryView(characterId: characterId, databaseManager: databaseManager)
            } label: {
                HStack {
                    Image("skills")
                        .resizable()
                        .frame(width: 36, height: 36)
                        .cornerRadius(6)
                        .drawingGroup()
                    Text(NSLocalizedString("Main_Skills_Category", comment: ""))
                }
            }

            NavigationLink {
                SkillPlanView(characterId: characterId, databaseManager: databaseManager)
            } label: {
                HStack {
                    Image("notegroup")
                        .resizable()
                        .frame(width: 32, height: 36)
                        .foregroundColor(.blue)
                    Text(NSLocalizedString("Main_Skills_Plan", comment: ""))
                }
            }
        } header: {
            Text(NSLocalizedString("Main_Skills_Categories", comment: ""))
        }
    }

    @ViewBuilder
    private var skillQueueSection: some View {
        Section {
            if skillQueue.isEmpty {
                Text(
                    NSLocalizedString("Main_Skills_Queue_Empty", comment: "").replacingOccurrences(
                        of: "$num", with: "0")
                )
                .foregroundColor(.secondary)
            } else {
                ForEach(activeSkills) { item in
                    NavigationLink {
                        ShowItemInfo(
                            databaseManager: databaseManager,
                            itemID: item.skill_id
                        )
                    } label: {
                        skillQueueItemView(item)
                    }
                }
            }
        } header: {
            skillQueueHeader
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
    }

    @ViewBuilder
    private var injectorSection: some View {
        if !skillQueue.isEmpty, !isLoadingInjectors, let calculation = injectorCalculation {
            Section {
                // 大型注入器
                if let largeInfo = getInjectorInfo(
                    typeId: SkillInjectorCalculator.largeInjectorTypeId)
                {
                    injectorItemView(
                        info: largeInfo, count: calculation.largeInjectorCount,
                        typeId: SkillInjectorCalculator.largeInjectorTypeId
                    )
                }

                // 小型注入器
                if let smallInfo = getInjectorInfo(
                    typeId: SkillInjectorCalculator.smallInjectorTypeId)
                {
                    injectorItemView(
                        info: smallInfo, count: calculation.smallInjectorCount,
                        typeId: SkillInjectorCalculator.smallInjectorTypeId
                    )
                }

                // 总计所需技能点和预计价格
                injectorSummaryView(calculation: calculation)
            } header: {
                Text(NSLocalizedString("Main_Skills_Required_Injectors", comment: ""))
            }
        }
    }

    @ViewBuilder
    private var attributeComparisonSection: some View {
        if !attributeComparisons.isEmpty {
            Section {
                ForEach(attributeComparisons, id: \.name) { attr in
                    attributeComparisonItemView(attr)
                }

                if let optimal = optimalAttributes {
                    VStack(alignment: .leading, spacing: 4) {
                        if optimal.savedTime > 0 {
                            Text(
                                String(
                                    format: NSLocalizedString(
                                        "Main_Skills_Optimal_Attributes_Time_Saved", comment: ""
                                    ),
                                    formatTimeInterval(optimal.savedTime)
                                )
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                        } else {
                            Text(
                                NSLocalizedString(
                                    "Main_Skills_Optimal_Attributes_Already_Optimal", comment: ""
                                )
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        Text(NSLocalizedString("Main_Skills_Optimal_Attributes_Note", comment: ""))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text(NSLocalizedString("Main_Skills_Optimal_Attributes", comment: ""))
            }
        }
    }

    @ViewBuilder
    private var skillQueueHeader: some View {
        if skillQueue.isEmpty {
            Text(String(format: NSLocalizedString("Main_Skills_Queue_Count", comment: ""), 0))
        } else if isQueuePaused {
            Text(
                String(
                    format: NSLocalizedString("Main_Skills_Queue_Count_Paused", comment: ""),
                    activeSkills.count
                ))
        } else if let totalTime = totalRemainingTime {
            Text(
                String(
                    format: NSLocalizedString("Main_Skills_Queue_Count_Time", comment: ""),
                    activeSkills.count,
                    formatTimeInterval(totalTime)
                ))
        } else {
            Text(
                String(
                    format: NSLocalizedString("Main_Skills_Queue_Count", comment: ""),
                    activeSkills.count
                ))
        }
    }

    @ViewBuilder
    private func skillQueueItemView(_ item: SkillQueueItem) -> some View {
        HStack(spacing: 8) {
            if let icon = skillIcon {
                icon
                    .resizable()
                    .frame(width: 36, height: 36)
                    .cornerRadius(6)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 2) {
                    Text(
                        skillNames[item.skill_id]
                            ?? NSLocalizedString("Main_Database_Loading", comment: "")
                    )
                    .lineLimit(1)
                    Spacer()
                    Text(
                        String(
                            format: NSLocalizedString("Misc_Level_Short", comment: ""),
                            item.finished_level
                        )
                    )
                    .foregroundColor(.secondary)
                    .font(.caption)
                    .padding(.trailing, 2)
                    SkillLevelIndicator(
                        currentLevel: getCurrentLevel(for: item.skill_id),
                        trainingLevel: item.finished_level,
                        isTraining: item.isCurrentlyTraining
                    )
                    .padding(.trailing, 4)
                }

                if let progress = calculateProgress(item) {
                    skillProgressView(item: item, progress: progress)
                }
            }
        }
    }

    @ViewBuilder
    private func skillProgressView(item: SkillQueueItem, progress: ProgressInfo) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                Text(
                    String(
                        format: NSLocalizedString("Main_Skills_Points_Progress", comment: ""),
                        formatNumber(Int(progress.current)),
                        formatNumber(progress.total)
                    )
                )
                .font(.caption)
                .foregroundColor(.secondary)
                if let rate = trainingRates[item.skill_id] {
                    Text("(\(formatNumber(rate))/h)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                skillTimeView(item: item, progress: progress)
            }

            if item.isCurrentlyTraining {
                ProgressView(value: progress.percentage)
                    .progressViewStyle(LinearProgressViewStyle())
                    .padding(.top, 1)
            }
        }
    }

    @ViewBuilder
    private func skillTimeView(item: SkillQueueItem, progress: ProgressInfo) -> some View {
        if item.isCurrentlyTraining {
            if let remainingTime = item.remainingTime {
                Text(
                    String(
                        format: NSLocalizedString("Main_Skills_Time_Remaining", comment: ""),
                        formatTimeInterval(remainingTime)
                    )
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }
        } else if let startDate = item.start_date,
            let finishDate = item.finish_date
        {
            // 如果有服务器时间，使用服务器时间
            let trainingTime = finishDate.timeIntervalSince(startDate)
            Text(
                String(
                    format: NSLocalizedString("Main_Skills_Time_Required", comment: ""),
                    formatTimeInterval(trainingTime)
                )
            )
            .font(.caption)
            .foregroundColor(.secondary)
        } else if isQueuePaused {
            // 如果队列暂停且没有服务器时间，才使用计算的时间
            if let rate = trainingRates[item.skill_id] {
                let remainingSP = progress.total - Int(progress.current)
                let trainingTimeHours = Double(remainingSP) / Double(rate)
                let trainingTime = trainingTimeHours * 3600  // 转换为秒

                Text(
                    String(
                        format: NSLocalizedString("Main_Skills_Time_Required", comment: ""),
                        formatTimeInterval(trainingTime)
                    )
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func injectorItemView(info: InjectorInfo, count: Int, typeId: Int) -> some View {
        NavigationLink {
            ShowItemInfo(
                databaseManager: databaseManager,
                itemID: typeId
            )
        } label: {
            HStack {
                IconManager.shared.loadImage(for: info.iconFilename)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)
                Text(info.name)
                Spacer()
                Text("\(count)")
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func injectorSummaryView(calculation: InjectorCalculation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(
                String(
                    format: NSLocalizedString("Main_Skills_Total_Required_SP", comment: ""),
                    FormatUtil.format(Double(calculation.totalSkillPoints))
                ))
            if let totalCost = totalInjectorCost {
                Text(
                    String(
                        format: NSLocalizedString("Main_Skills_Total_Injector_Cost", comment: ""),
                        FormatUtil.formatISK(totalCost)
                    ))
            }
        }
        .font(.caption)
        .foregroundColor(.secondary)
    }

    @ViewBuilder
    private func attributeComparisonItemView(
        _ attr: (name: String, icon: String, current: Int, optimal: Int, diff: Int)
    ) -> some View {
        HStack {
            Image(attr.icon)
                .resizable()
                .frame(width: 32, height: 32)
                .cornerRadius(4)
            Text(attr.name)
            Spacer()
            if attr.diff != 0 {
                Text("+\(attr.diff)")
                    .foregroundColor(.green)
            }
        }
    }

    private func loadInitialDataIfNeeded() {
        guard !hasInitialized else { return }

        hasInitialized = true

        Task {
            await loadSkillQueue()
        }
    }

    private func loadSkillQueue(forceRefresh: Bool = false) async {
        isLoading = true
        isDataReady = false  // 开始加载时重置数据准备状态

        do {
            // 声明变量来存储任务组的结果
            var loadedAttributes: CharacterAttributes?
            var loadedImplants: ImplantAttributes?
            var loadedQueue: [SkillQueueItem] = []

            // 使用任务组来管理并发加载
            try await withThrowingTaskGroup(of: Void.self) { group in
                // 加载属性
                group.addTask {
                    loadedAttributes = try await CharacterSkillsAPI.shared.fetchAttributes(
                        characterId: characterId)
                }

                // 加载植入体信息
                group.addTask {
                    loadedImplants = await SkillTrainingCalculator.getImplantBonuses(
                        characterId: characterId)
                }

                // 加载技能队列
                group.addTask {
                    loadedQueue = try await CharacterSkillsAPI.shared.fetchSkillQueue(
                        characterId: characterId, forceRefresh: forceRefresh)
                }

                // 等待所有任务完成
                try await group.waitForAll()
            }

            // 确保所有必要的数据都已加载
            guard let attributes = loadedAttributes,
                let implants = loadedImplants
            else {
                throw NSError(
                    domain: "CharacterSkillsView", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "加载数据失败"])
            }

            // 收集所有技能ID
            let skillIds = loadedQueue.map { $0.skill_id }

            // 批量加载技能名称
            let nameQuery = """
                    SELECT type_id, name
                    FROM types
                    WHERE type_id IN (\(skillIds.sorted().map { String($0) }.joined(separator: ",")))
                """

            var names: [Int: String] = [:]
            if case let .success(rows) = databaseManager.executeQuery(nameQuery) {
                for row in rows {
                    if let typeId = row["type_id"] as? Int,
                        let name = row["name"] as? String
                    {
                        names[typeId] = name
                    }
                }
            }

            // 预加载所有技能属性到缓存
            SkillTrainingCalculator.preloadSkillAttributes(
                skillIds: skillIds, databaseManager: databaseManager
            )

            // 计算训练速度
            var rates: [Int: Int] = [:]
            for skillId in skillIds {
                if let (primary, secondary) = SkillTrainingCalculator.getSkillAttributes(
                    skillId: skillId, databaseManager: databaseManager
                ),
                    let rate = SkillTrainingCalculator.calculateTrainingRate(
                        primaryAttrId: primary,
                        secondaryAttrId: secondary,
                        attributes: attributes
                    )
                {
                    rates[skillId] = rate
                }
            }

            // 计算最优属性分配
            var optimal: OptimalAttributeAllocation?
            let queueInfo = loadedQueue.compactMap {
                item -> (skillId: Int, remainingSP: Int, startDate: Date?, finishDate: Date?)? in
                guard let levelEndSp = item.level_end_sp,
                    let trainingStartSp = item.training_start_sp
                else {
                    return nil
                }
                return (
                    skillId: item.skill_id,
                    remainingSP: levelEndSp - trainingStartSp,
                    startDate: item.start_date,
                    finishDate: item.finish_date
                )
            }

            optimal = await SkillTrainingCalculator.calculateOptimalAttributes(
                skillQueue: queueInfo,
                databaseManager: databaseManager,
                currentAttributes: attributes,
                characterId: characterId
            ).map { result in
                OptimalAttributeAllocation(
                    charisma: result.charisma,
                    intelligence: result.intelligence,
                    memory: result.memory,
                    perception: result.perception,
                    willpower: result.willpower,
                    totalTrainingTime: result.totalTrainingTime,
                    currentTrainingTime: result.currentTrainingTime
                )
            }

            // 一次性更新所有状态
            await MainActor.run {
                self.characterAttributes = attributes
                self.implantBonuses = implants
                self.skillQueue = loadedQueue
                self.skillNames = names
                self.trainingRates = rates
                self.optimalAttributes = optimal
                updateAttributeComparisons()

                // 所有数据都准备好后，更新状态
                self.isLoading = false
                self.isDataReady = true
            }

            // 异步加载注入器数据
            Task {
                await calculateInjectors()
            }

        } catch {
            Logger.error("加载技能数据失败: \(error)")
            await MainActor.run {
                self.isLoading = false
                self.isDataReady = true
            }
        }
    }

    private func refreshSkillQueue() async {
        guard !Task.isCancelled else { return }

        await MainActor.run {
            isRefreshing = true
            isDataReady = false  // 刷新时重置数据准备状态
        }

        await loadSkillQueue(forceRefresh: true)

        // 确保在主线程上设置状态
        if !Task.isCancelled {
            await MainActor.run {
                isRefreshing = false
                isDataReady = true
            }
        }

        // 添加延迟以防止快速连续刷新
        if !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5秒
        }
    }

    /// 计算注入器需求并加载价格
    private func calculateInjectors() async {
        isLoadingInjectors = true
        defer { isLoadingInjectors = false }

        // 计算队列中所需的总技能点数
        var totalRequiredSP = 0
        for item in skillQueue {
            if let endSP = item.level_end_sp,
                let startSP = item.training_start_sp
            {
                if item.isCurrentlyTraining {
                    // 对于正在训练的技能，从当前训练进度开始计算
                    if let finishDate = item.finish_date,
                        let startDate = item.start_date
                    {
                        let now = Date()
                        let totalTrainingTime = finishDate.timeIntervalSince(startDate)
                        let trainedTime = now.timeIntervalSince(startDate)
                        let progress = trainedTime / totalTrainingTime
                        let totalSP = endSP - startSP
                        let trainedSP = Int(Double(totalSP) * progress)
                        let remainingSP = totalSP - trainedSP
                        totalRequiredSP += remainingSP
                        Logger.debug(
                            "正在训练的技能 \(item.skill_id) - 总需求: \(totalSP), 已训练: \(trainedSP), 剩余: \(remainingSP)"
                        )
                    }
                } else {
                    // 对于未开始训练的技能，计算全部所需点数
                    let requiredSP = endSP - startSP
                    totalRequiredSP += requiredSP
                    Logger.debug("未训练的技能 \(item.skill_id) - 需要: \(requiredSP)")
                }
            }
        }
        Logger.debug("队列总需求技能点: \(totalRequiredSP)")

        // 获取角色总技能点数
        let characterTotalSP = await getCharacterTotalSP()

        // 计算注入器需求
        injectorCalculation = SkillInjectorCalculator.calculate(
            requiredSkillPoints: totalRequiredSP,
            characterTotalSP: characterTotalSP
        )
        if let calc = injectorCalculation {
            Logger.debug(
                "计算结果 - 大型注入器: \(calc.largeInjectorCount), 小型注入器: \(calc.smallInjectorCount)")
        }

        // 获取注入器价格
        await loadInjectorPrices()
    }

    /// 获取角色总技能点数
    private func getCharacterTotalSP() async -> Int {
        // 从数据库获取角色当前的总技能点数
        let query = """
                SELECT total_sp, unallocated_sp
                FROM character_skills
                WHERE character_id = ?
            """
        if case let .success(rows) = CharacterDatabaseManager.shared.executeQuery(
            query, parameters: [characterId]
        ),
            let row = rows.first
        {
            // 处理total_sp
            let totalSP: Int
            if let value = row["total_sp"] as? Int {
                totalSP = value
            } else if let value = row["total_sp"] as? Int64 {
                totalSP = Int(value)
            } else {
                totalSP = 0
                Logger.error("无法解析total_sp")
            }

            // 处理unallocated_sp
            let unallocatedSP: Int
            if let value = row["unallocated_sp"] as? Int {
                unallocatedSP = value
            } else if let value = row["unallocated_sp"] as? Int64 {
                unallocatedSP = Int(value)
            } else {
                unallocatedSP = 0
                Logger.error("无法解析unallocated_sp")
            }

            let characterTotalSP = totalSP + unallocatedSP
            Logger.debug("角色总技能点: \(characterTotalSP) (已分配: \(totalSP), 未分配: \(unallocatedSP))")
            return characterTotalSP
        }

        // 如果无法从数据库获取，尝试从API获取
        do {
            let skillsInfo = try await CharacterSkillsAPI.shared.fetchCharacterSkills(
                characterId: characterId, forceRefresh: true
            )
            let characterTotalSP = skillsInfo.total_sp + skillsInfo.unallocated_sp
            Logger.debug("从API获取角色总技能点: \(characterTotalSP)")
            return characterTotalSP
        } catch {
            Logger.error("获取技能点数据失败: \(error)")
            return 0
        }
    }

    private func loadInjectorPrices() async {
        Logger.debug(
            "开始加载注入器价格 - 大型注入器ID: \(SkillInjectorCalculator.largeInjectorTypeId), 小型注入器ID: \(SkillInjectorCalculator.smallInjectorTypeId)"
        )

        // 获取大型和小型注入器的价格
        let prices = await MarketPriceUtil.getMarketPrices(typeIds: [
            SkillInjectorCalculator.largeInjectorTypeId,
            SkillInjectorCalculator.smallInjectorTypeId,
        ])

        Logger.debug("获取到价格数据: \(prices)")

        // 确保两个价格都有值才更新
        if let largePrice = prices[SkillInjectorCalculator.largeInjectorTypeId],
            let smallPrice = prices[SkillInjectorCalculator.smallInjectorTypeId]
        {
            // 在主线程一次性更新两个价格
            await MainActor.run {
                injectorPrices = (large: largePrice, small: smallPrice)
            }
        } else {
            Logger.debug(
                "价格数据不完整 - large: \(prices[SkillInjectorCalculator.largeInjectorTypeId] as Any), small: \(prices[SkillInjectorCalculator.smallInjectorTypeId] as Any)"
            )
        }
    }

    private struct InjectorInfo {
        let name: String
        let iconFilename: String
    }

    private func getInjectorInfo(typeId: Int) -> InjectorInfo? {
        let query = """
                SELECT name, icon_filename
                FROM types
                WHERE type_id = ?
            """
        if case let .success(rows) = databaseManager.executeQuery(query, parameters: [typeId]),
            let row = rows.first,
            let name = row["name"] as? String,
            let iconFilename = row["icon_filename"] as? String
        {
            return InjectorInfo(name: name, iconFilename: iconFilename)
        }
        return nil
    }

    private struct ProgressInfo {
        let current: Double
        let total: Int
        let percentage: Double
    }

    private func calculateProgress(_ item: SkillQueueItem) -> ProgressInfo? {
        // 1. 检查必要数据，增加 level_start_sp 的检查
        guard let levelEndSp = item.level_end_sp,
            let trainingStartSp = item.training_start_sp,
            let levelStartSp = item.level_start_sp
        else {
            return nil
        }

        var currentSP = Double(trainingStartSp)

        // 2. 计算实时进度
        if let startDate = item.start_date,
            let finishDate = item.finish_date
        {
            let now = Date()

            if now < startDate {
                // 2.1 还未开始训练
                currentSP = Double(trainingStartSp)
            } else if now > finishDate {
                // 2.2 已完成训练
                currentSP = Double(levelEndSp)
            } else {
                // 2.3 正在训练中，使用时间比例计算当前进度
                let totalTrainingTime = finishDate.timeIntervalSince(startDate)
                let trainedTime = now.timeIntervalSince(startDate)
                let timeProgress = trainedTime / totalTrainingTime

                let remainingSP = levelEndSp - trainingStartSp
                let trainedSP = Double(remainingSP) * timeProgress
                currentSP = Double(trainingStartSp) + trainedSP
            }
        }

        // 3. 修改进度计算逻辑，只计算当前等级的进度
        let levelTotalSP = levelEndSp - levelStartSp  // 该等级需要的总技能点
        let levelCurrentSP = currentSP - Double(levelStartSp)  // 在该等级已获得的技能点

        return ProgressInfo(
            current: currentSP,
            total: levelEndSp,
            percentage: levelCurrentSP / Double(levelTotalSP)  // 计算该等级的实际进度
        )
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

    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: number)) ?? String(number)
    }

    private struct OptimalAttributeAllocation {
        let charisma: Int
        let intelligence: Int
        let memory: Int
        let perception: Int
        let willpower: Int
        let totalTrainingTime: TimeInterval
        let currentTrainingTime: TimeInterval

        var savedTime: TimeInterval {
            currentTrainingTime - totalTrainingTime
        }
    }
}
