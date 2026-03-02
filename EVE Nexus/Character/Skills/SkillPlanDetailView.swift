import Foundation
import SwiftUI
import UniformTypeIdentifiers

private let kShowCompletedSkillsKey = "SkillPlan_ShowCompletedSkills"

struct SkillPlanDetailView: View {
    @State private var plan: SkillPlan
    let characterId: Int
    @ObservedObject var databaseManager: DatabaseManager
    @Binding var skillPlans: [SkillPlan]
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var characterAttributes: CharacterAttributes?
    @State private var implantBonuses: ImplantAttributes?
    @State private var trainingRates: [Int: Int] = [:] // [skillId: pointsPerHour]
    @State private var skillTimeMultipliers: [Int: Int] = [:] // [skillId: timeMultiplier]
    @State private var injectorCalculation: InjectorCalculation?
    @State private var injectorPrices: InjectorPriceManager.InjectorPrices =
        .init(large: nil, small: nil)
    @State private var isLoadingInjectors = true
    @State private var learnedSkills: [Int: CharacterSkill] = [:] // 添加缓存
    @State private var skillDependencies: [String: Set<String>] = [:] // [skillId_level: Set<依赖它的skillId_level>]
    @AppStorage(kShowCompletedSkillsKey) private var showCompletedSkills = true
    @State private var showAddSkillSheet = false
    @State private var showAddItemSheet = false
    @State private var showExportSuccessAlert = false

    init(
        plan: SkillPlan, characterId: Int, databaseManager: DatabaseManager,
        skillPlans: Binding<[SkillPlan]>
    ) {
        // 简化初始化，不进行同步数据加载
        _plan = State(initialValue: plan)
        self.characterId = characterId
        self.databaseManager = databaseManager
        _skillPlans = skillPlans
        _learnedSkills = State(initialValue: [:])
    }

    var body: some View {
        List {
            Section(header: Text(NSLocalizedString("Main_Skills_Points", comment: "技能点数"))) {
                HStack {
                    Text(NSLocalizedString("Main_Skills_To_Learn", comment: "需要学习"))
                    Spacer()
                    Text("\(FormatUtil.format(Double(plan.totalSkillPoints))) SP")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text(NSLocalizedString("Main_Skills_Required_Time", comment: "需要时间"))
                    Spacer()
                    Text(formatTimeInterval(plan.totalTrainingTime))
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text(NSLocalizedString("Main_Skills_All_Points", comment: "全部点数"))
                    Spacer()
                    Text("\(FormatUtil.format(Double(calculateAllSkillPoints()))) SP")
                        .foregroundColor(.secondary)
                }
            }

            // 添加注入器需求部分
            if !plan.skills.isEmpty && !isLoadingInjectors && filteredSkills.count > 0 {
                if let calculation = injectorCalculation,
                   calculation.largeInjectorCount + calculation.smallInjectorCount > 0
                {
                    Section(
                        header: Text(
                            NSLocalizedString("Main_Skills_Required_Injectors", comment: ""))
                    ) {
                        // 大型注入器
                        if let largeInfo = getInjectorInfo(
                            typeId: SkillInjectorCalculator.largeInjectorTypeId),
                            calculation.largeInjectorCount > 0
                        {
                            injectorItemView(
                                info: largeInfo, count: calculation.largeInjectorCount,
                                typeId: SkillInjectorCalculator.largeInjectorTypeId
                            )
                        }

                        // 小型注入器
                        if let smallInfo = getInjectorInfo(
                            typeId: SkillInjectorCalculator.smallInjectorTypeId),
                            calculation.smallInjectorCount > 0
                        {
                            injectorItemView(
                                info: smallInfo, count: calculation.smallInjectorCount,
                                typeId: SkillInjectorCalculator.smallInjectorTypeId
                            )
                        }

                        // 总计所需技能点和预计价格
                        injectorSummaryView(calculation: calculation)
                    }
                }
            }

            Section(
                header: HStack {
                    Text(skillPlanHeaderText)
                    Spacer()
                    Button {
                        showCompletedSkills.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(
                                systemName: showCompletedSkills
                                    ? "checkmark.circle.fill" : "circle"
                            )
                            Text(NSLocalizedString("Main_Skills_Plan_Show_Completed_Short", comment: ""))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            ) {
                if plan.skills.isEmpty {
                    // 队列为空
                    Text(NSLocalizedString("Main_Skills_Plan_Empty", comment: ""))
                        .foregroundColor(.secondary)
                } else if filteredSkills.count == 0 {
                    // 队列不为空，但所有技能都已完成（且不显示已完成技能）
                    Text(NSLocalizedString("Main_Skills_Plan_All_Completed", comment: ""))
                        .foregroundColor(.green)
                } else {
                    ForEach(filteredSkills) { skill in
                        skillRowView(skill)
                            .contextMenu {
                                // 只有无后置依赖的技能才能删除
                                if !hasPostDependencies(skillId: skill.skillID, level: skill.targetLevel) {
                                    Button(role: .destructive) {
                                        if let index = plan.skills.firstIndex(where: { $0.id == skill.id }) {
                                            deleteSkill(at: IndexSet(integer: index))
                                        }
                                    } label: {
                                        Label(NSLocalizedString("Misc_Delete", comment: ""), systemImage: "trash")
                                    }
                                } else {
                                    Text(NSLocalizedString("Main_Skills_Plan_Has_Dependencies", comment: "此技能被其他技能依赖，无法删除"))
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                }
                            }
                    }
                    .onDelete { indexSet in
                        // 检查是否所有要删除的技能都没有后置依赖
                        let skillsToDelete = indexSet.map { filteredSkills[$0] }
                        let hasAnyDependencies = skillsToDelete.contains { skill in
                            hasPostDependencies(skillId: skill.skillID, level: skill.targetLevel)
                        }

                        if !hasAnyDependencies {
                            deleteSkill(at: indexSet)
                        } else {
                            errorMessage = NSLocalizedString("Main_Skills_Plan_Cannot_Delete_Has_Dependencies", comment: "")
                            showErrorAlert = true
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
            }

            // 清空队列按钮 - 单独section
            if !plan.skills.isEmpty {
                Section {
                    Button {
                        clearAllSkills()
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                            Text(NSLocalizedString("Main_Skills_Plan_Clear_All", comment: "清空队列"))
                                .foregroundColor(.red)
                            Spacer()
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
            }
        }
        .navigationTitle(plan.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    // 导入按钮
                    Button {
                        Task {
                            await importSkillsFromClipboard()
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }

                    // 导出按钮
                    if isEnglishLanguage() {
                        Button {
                            Task {
                                await exportSkillPlan(useEnglishNames: true)
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    } else {
                        Menu {
                            Button {
                                Task {
                                    await exportSkillPlan(useEnglishNames: false)
                                }
                            } label: {
                                Label(NSLocalizedString("Main_Skills_Plan_Export_Localized", comment: "导出当前语言"), systemImage: "doc.text")
                            }

                            Button {
                                Task {
                                    await exportSkillPlan(useEnglishNames: true)
                                }
                            } label: {
                                Label(NSLocalizedString("Main_Skills_Plan_Export_English", comment: "导出英文"), systemImage: "doc.text")
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }

                    // 添加按钮
                    Menu {
                        Button {
                            showAddSkillSheet = true
                        } label: {
                            Label(NSLocalizedString("Main_Skills_Plan_Add_Skill", comment: "添加技能"), systemImage: "plus")
                        }

                        Divider()

                        Button {
                            showAddItemSheet = true
                        } label: {
                            Label(NSLocalizedString("Main_Skills_Plan_Add_Item", comment: "添加物品"), systemImage: "cube.box")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .alert(
            NSLocalizedString("Main_Skills_Plan_Import_Alert_Title", comment: ""),
            isPresented: $showErrorAlert
        ) {
            Button("OK", role: .cancel) {
                // 清理状态
            }
        } message: {
            Text(errorMessage)
        }
        .alert(
            NSLocalizedString("Main_Skills_Plan_Export_Success_Title", comment: "导出成功"),
            isPresented: $showExportSuccessAlert
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(NSLocalizedString("Main_Skills_Plan_Export_Success_Message", comment: "技能计划已复制到剪贴板"))
        }
        .onAppear {
            // 在视图出现时加载数据
            Task {
                await loadCharacterData()
                // 检查是否有装配页传来的待添加技能
                if let pending = PendingFittingSkillsManager.shared.consumePending(forPlanId: plan.id),
                   pending.characterId == characterId
                {
                    await addBatchSkillsToPlan(skills: pending.skills)
                }
                // 计算技能依赖关系
                calculateSkillDependencies()
            }
        }
        .onChange(of: plan.skills.count) { _, _ in
            // 技能数量变化时重新计算依赖
            calculateSkillDependencies()
        }
        .sheet(isPresented: $showAddSkillSheet) {
            AddSkillSelectorView(
                databaseManager: databaseManager,
                onBatchSkillsSelected: { skills in
                    Task {
                        await addBatchSkillsToPlan(skills: skills)
                    }
                },
                onSkillLevelsRemoved: { skillId, fromLevel, toLevel in
                    removeSkillLevels(skillId: skillId, fromLevel: fromLevel, toLevel: toLevel)
                },
                existingSkillLevels: getExistingSkillLevels(),
                skillDependencies: $skillDependencies
            )
        }
        .sheet(isPresented: $showAddItemSheet) {
            ItemSelectorView(
                databaseManager: databaseManager,
                onSelect: { item in
                    Task {
                        await addItemSkillsToPlan(itemId: item.id, itemName: item.name)
                    }
                }
            )
        }
    }

    private var filteredSkills: [PlannedSkill] {
        showCompletedSkills ? plan.skills : plan.skills.filter { !$0.isCompleted }
    }

    // 技能计划标题文本
    private var skillPlanHeaderText: String {
        let totalCount = plan.skills.count

        if showCompletedSkills {
            // 显示已完成：只显示总数
            return "\(NSLocalizedString("Main_Skills_Plan", comment: ""))(\(totalCount))"
        } else {
            // 不显示已完成：显示 未完成/总数
            let uncompletedCount = plan.skills.filter { !$0.isCompleted }.count
            return "\(NSLocalizedString("Main_Skills_Plan", comment: ""))(\(uncompletedCount)/\(totalCount))"
        }
    }

    private func skillRowView(_ skill: PlannedSkill) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 2) {
                Text(skill.skillName)
                    .lineLimit(1)
                Spacer()
                Text(
                    String(
                        format: NSLocalizedString("Misc_Level_Short", comment: ""),
                        skill.targetLevel
                    )
                )
                .foregroundColor(.secondary)
                .font(.caption)
                .padding(.trailing, 2)
                SkillLevelIndicator(
                    currentLevel: skill.targetLevel - 1, // 计划中的当前等级
                    trainingLevel: skill.targetLevel, // 计划中的目标等级
                    isTraining: false
                )
                .padding(.trailing, 2)
            }
            .contextMenu {
                Button {
                    UIPasteboard.general.string = skill.skillName
                } label: {
                    Label(NSLocalizedString("Misc_Copy", comment: ""), systemImage: "doc.on.doc")
                }
            }

            let spRange = getSkillPointRange(skill)
            HStack(spacing: 4) {
                if let rate = trainingRates[skill.skillID] {
                    Text(
                        "\(FormatUtil.format(Double(spRange.start)))/\(FormatUtil.format(Double(spRange.end))) SP (\(FormatUtil.format(Double(rate)))/h)"
                    )
                } else {
                    Text(
                        "\(FormatUtil.format(Double(spRange.start)))/\(FormatUtil.format(Double(spRange.end))) SP"
                    )
                }
                Spacer()
                if skill.isCompleted {
                    Text(NSLocalizedString("Main_Skills_Completed", comment: ""))
                        .foregroundColor(.green)
                } else {
                    Text(formatTimeInterval(skill.trainingTime))
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.top, 2)
        }
        .padding(.vertical, 2)
    }

    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        if interval < 1 {
            return String.localizedStringWithFormat(NSLocalizedString("Time_Seconds", comment: ""), 0)
        }

        let totalSeconds = interval
        let days = Int(totalSeconds) / (24 * 3600)
        var hours = Int(totalSeconds) / 3600 % 24
        var minutes = Int(totalSeconds) / 60 % 60
        let seconds = Int(totalSeconds) % 60

        // 当显示两个单位时，对第二个单位进行四舍五入
        if days > 0 {
            // 对小时进行四舍五入
            if minutes >= 30 {
                hours += 1
                if hours == 24 { // 如果四舍五入后小时数达到24
                    return String.localizedStringWithFormat(NSLocalizedString("Time_Days", comment: ""), days + 1)
                }
            }
            if hours > 0 {
                return String(
                    format: NSLocalizedString("Time_Days_Hours", comment: ""), days, hours
                )
            }
            return String.localizedStringWithFormat(NSLocalizedString("Time_Days", comment: ""), days)
        } else if hours > 0 {
            // 对分钟进行四舍五入
            if seconds >= 30 {
                minutes += 1
                if minutes == 60 { // 如果四舍五入后分钟数达到60
                    return String.localizedStringWithFormat(NSLocalizedString("Time_Hours", comment: ""), hours + 1)
                }
            }
            if minutes > 0 {
                return String(
                    format: NSLocalizedString("Time_Hours_Minutes", comment: ""), hours, minutes
                )
            }
            return String.localizedStringWithFormat(NSLocalizedString("Time_Hours", comment: ""), hours)
        } else if minutes > 0 {
            // 对秒进行四舍五入
            if seconds >= 30 {
                minutes += 1
            }
            if seconds > 0 {
                return String(
                    format: NSLocalizedString("Time_Minutes_Seconds", comment: ""), minutes, seconds
                )
            }
            return String.localizedStringWithFormat(NSLocalizedString("Time_Minutes", comment: ""), minutes)
        }
        return String.localizedStringWithFormat(NSLocalizedString("Time_Seconds", comment: ""), seconds)
    }

    private func importSkillsFromClipboard() async {
        // 检查剪贴板是否为空
        guard let clipboardString = UIPasteboard.general.string, !clipboardString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            await MainActor.run {
                errorMessage = NSLocalizedString("Main_Market_Clipboard_Empty", comment: "剪贴板为空")
                showErrorAlert = true
            }
            return
        }

        Logger.debug("从剪贴板读取内容: \(clipboardString)")
        let result = SkillPlanReaderTool.parseSkillPlan(
            from: clipboardString, databaseManager: databaseManager
        )

        // 继续处理成功解析的技能
        if !result.skills.isEmpty {
            Logger.debug("解析技能计划结果: \(result.skills)")

            // 1. 将解析结果转换为 (skillId, level) 列表
            let parsedSkills = result.skills.compactMap { skillString -> (skillId: Int, level: Int)? in
                let components = skillString.split(separator: ":")
                guard components.count == 2,
                      let typeId = Int(components[0]),
                      let targetLevel = Int(components[1])
                else {
                    return nil
                }
                return (skillId: typeId, level: targetLevel)
            }

            // 2. 使用修正工具类补齐前置依赖并去重
            Logger.debug("[导入] 修正前技能数量: \(parsedSkills.count)")
            let corrector = SkillQueueCorrector(databaseManager: databaseManager)
            let correctedSkills = corrector.correctSkillQueue(inputSkills: parsedSkills)
            Logger.debug("[导入] 修正后技能数量: \(correctedSkills.count)")

            // 获取所有技能的ID（用于批量加载数据）
            let allSkillIds = Array(Set(correctedSkills.map { $0.skillId }))

            // 获取新技能的已学习信息
            let newLearnedSkills = await getLearnedSkills(skillIds: allSkillIds)
            // 更新缓存
            learnedSkills.merge(newLearnedSkills) { current, _ in current }

            // 批量加载新技能的倍增系数
            loadSkillTimeMultipliers(allSkillIds)

            // 批量加载技能名称
            let skillNamesDict = loadSkillNames(skillIds: allSkillIds)

            // 更新计划数据
            var updatedPlan = plan
            let validSkills = correctedSkills.compactMap { skill -> PlannedSkill? in
                // 检查是否已存在相同技能和等级
                if updatedPlan.skills.contains(where: {
                    $0.skillID == skill.skillId && $0.targetLevel == skill.level
                }) {
                    return nil
                }

                // 获取技能名称
                let skillName = skillNamesDict[skill.skillId] ?? "Unknown Skill (\(skill.skillId))"

                // 获取已学习的技能信息
                let learnedSkill = learnedSkills[skill.skillId]
                let currentLevel = learnedSkill?.trained_skill_level ?? 0

                // 如果目标等级小于等于当前等级，说明已完成
                let isCompleted = skill.level <= currentLevel

                return createPlannedSkill(
                    typeId: skill.skillId,
                    skillName: skillName,
                    targetLevel: skill.level,
                    isCompleted: isCompleted
                )
            }

            // 只有在有有效技能时才更新计划
            if !validSkills.isEmpty {
                // 将新技能添加到现有技能列表末尾
                let allSkills = updatedPlan.skills + validSkills
                updatedPlan = updatePlanWithSkills(updatedPlan, skills: allSkills)

                // 保存更新后的计划
                SkillPlanFileManager.shared.saveSkillPlan(
                    characterId: characterId, plan: updatedPlan
                )

                // 在主线程中更新UI状态
                await MainActor.run {
                    // 更新当前视图的计划
                    plan = updatedPlan

                    // 更新父视图中的计划列表
                    if let index = skillPlans.firstIndex(where: { $0.id == plan.id }) {
                        skillPlans[index] = updatedPlan
                    }
                }

                // 重新加载所有数据并计算注入器需求
                await loadCharacterData()
            }

            // 构建提示消息
            var message = String(
                format: NSLocalizedString("Main_Skills_Plan_Import_Success", comment: ""),
                validSkills.count
            )

            if result.hasErrors {
                message += "\n\n"

                if !result.parseErrors.isEmpty {
                    message +=
                        NSLocalizedString("Main_Skills_Plan_Import_Parse_Failed", comment: "")
                        + "\n" + result.parseErrors.joined(separator: "\n")
                }

                if !result.notFoundSkills.isEmpty {
                    if !result.parseErrors.isEmpty {
                        message += "\n\n"
                    }
                    message +=
                        NSLocalizedString("Main_Skills_Plan_Import_Not_Found", comment: "")
                        + "\n" + result.notFoundSkills.joined(separator: "\n")
                }

                // 导入完成，显示结果
            }

            await MainActor.run {
                errorMessage = message
                showErrorAlert = true
            }
        } else if result.hasErrors {
            // 如果没有成功导入任何技能，但有错误
            var message = ""

            if !result.parseErrors.isEmpty {
                message +=
                    NSLocalizedString("Main_Skills_Plan_Import_Parse_Failed", comment: "")
                    + "\n" + result.parseErrors.joined(separator: "\n")
            }

            if !result.notFoundSkills.isEmpty {
                if !message.isEmpty {
                    message += "\n\n"
                }
                message +=
                    NSLocalizedString("Main_Skills_Plan_Import_Not_Found", comment: "") + "\n"
                    + result.notFoundSkills.joined(separator: "\n")
            }

            await MainActor.run {
                errorMessage = message
                showErrorAlert = true
            }
        }
    }

    private func getLearnedSkills(skillIds: [Int]) async -> [Int: CharacterSkill] {
        do {
            // 调用API获取技能数据
            let skillsResponse = try await CharacterSkillsAPI.shared.fetchCharacterSkills(
                characterId: characterId,
                forceRefresh: false
            )

            // 使用技能ID到技能信息的映射，只返回请求的技能ID对应的技能信息
            return skillsResponse.skillsMap.filter { skillIds.contains($0.key) }
        } catch {
            Logger.error("获取技能数据失败: \(error)")
            return [:]
        }
    }

    private func loadCharacterData() async {
        // 先加载已学习的技能数据
        if learnedSkills.isEmpty {
            learnedSkills = await getLearnedSkills(skillIds: plan.skills.map { $0.skillID })
        }

        // 加载技能名称
        var updatedSkills = plan.skills
        let skillIds = plan.skills.map { $0.skillID }
        let query = """
            SELECT type_id, name
            FROM types
            WHERE type_id IN (\(skillIds.sorted().map(String.init).joined(separator: ",")))
        """

        if case let .success(rows) = databaseManager.executeQuery(query) {
            let nameDict = Dictionary(
                uniqueKeysWithValues: rows.compactMap { row -> (Int, String)? in
                    guard let typeId = row["type_id"] as? Int,
                          let name = row["name"] as? String
                    else {
                        return nil
                    }
                    return (typeId, name)
                })

            // 更新技能名称
            updatedSkills = updatedSkills.map { skill in
                if let name = nameDict[skill.skillID] {
                    return PlannedSkill(
                        id: skill.id,
                        skillID: skill.skillID,
                        skillName: name,
                        currentLevel: skill.currentLevel,
                        targetLevel: skill.targetLevel,
                        trainingTime: skill.trainingTime,
                        requiredSP: skill.requiredSP,
                        prerequisites: skill.prerequisites,
                        currentSkillPoints: skill.currentSkillPoints,
                        isCompleted: skill.isCompleted
                    )
                }
                return skill
            }
        }

        // 加载角色属性
        characterAttributes = try? await CharacterSkillsAPI.shared.fetchAttributes(
            characterId: characterId)

        // 加载植入体加成
        implantBonuses = await SkillTrainingCalculator.getImplantBonuses(characterId: characterId)

        // 批量获取所有技能的倍增系数
        loadSkillTimeMultipliers(skillIds)

        // 批量获取所有技能的主副属性
        let attributesQuery = """
            SELECT type_id, attribute_id, value
            FROM typeAttributes
            WHERE type_id IN (\(skillIds.sorted().map(String.init).joined(separator: ",")))
            AND attribute_id IN (180, 181)
        """

        var skillAttributes: [Int: (primary: Int, secondary: Int)] = [:]
        if case let .success(rows) = databaseManager.executeQuery(attributesQuery) {
            // 按技能ID分组
            var groupedAttributes: [Int: [(attributeId: Int, value: Int)]] = [:]
            for row in rows {
                guard let typeId = row["type_id"] as? Int,
                      let attributeId = row["attribute_id"] as? Int,
                      let value = row["value"] as? Double
                else {
                    continue
                }
                groupedAttributes[typeId, default: []].append((attributeId, Int(value)))
            }

            // 处理每个技能的属性
            for (typeId, attributes) in groupedAttributes {
                var primary: Int?
                var secondary: Int?
                for attr in attributes {
                    if attr.attributeId == 180 {
                        primary = attr.value
                    } else if attr.attributeId == 181 {
                        secondary = attr.value
                    }
                }
                if let p = primary, let s = secondary {
                    skillAttributes[typeId] = (p, s)
                }
            }
        }

        // 计算所有技能的训练速度
        if let attrs = characterAttributes {
            for skill in updatedSkills {
                if let (primary, secondary) = skillAttributes[skill.skillID],
                   let rate = SkillTrainingCalculator.calculateTrainingRate(
                       primaryAttrId: primary,
                       secondaryAttrId: secondary,
                       attributes: attrs
                   )
                {
                    trainingRates[skill.skillID] = rate
                }
            }
        }

        // 更新计划中的技能
        let finalSkills = updatedSkills.map { skill in
            // 获取已学习的技能信息
            let learnedSkill = learnedSkills[skill.skillID]
            let currentLevel = learnedSkill?.trained_skill_level ?? 0

            // 如果目标等级小于等于当前等级，说明已完成
            let isCompleted = skill.targetLevel <= currentLevel

            return createPlannedSkill(
                typeId: skill.skillID,
                skillName: skill.skillName,
                targetLevel: skill.targetLevel,
                isCompleted: isCompleted
            )
        }

        let updatedPlan = updatePlanWithSkills(plan, skills: finalSkills)

        // 在主线程更新状态
        await MainActor.run {
            // 更新当前视图的计划
            plan = updatedPlan

            // 更新父视图中的计划列表
            if let index = skillPlans.firstIndex(where: { $0.id == plan.id }) {
                skillPlans[index] = updatedPlan
            }
        }

        // 计算注入器需求
        await calculateInjectors()
    }

    private func loadSkillTimeMultipliers(_ skillIds: [Int]) {
        guard !skillIds.isEmpty else { return }

        let query = """
            SELECT type_id, value
            FROM typeAttributes
            WHERE type_id IN (\(skillIds.sorted().map(String.init).joined(separator: ",")))
            AND attribute_id = 275
        """

        if case let .success(rows) = databaseManager.executeQuery(query) {
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                   let value = row["value"] as? Double
                {
                    skillTimeMultipliers[typeId] = Int(value)
                }
            }
        }
        // Logger.debug("\(skillTimeMultipliers)")
    }

    private func getSkillTimeMultiplier(_ skillId: Int) -> Int {
        return skillTimeMultipliers[skillId] ?? 1
    }

    private func getBaseSkillPointsForLevel(_ level: Int) -> Int? {
        switch level {
        case 1: return 250
        case 2: return 1415
        case 3: return 8000
        case 4: return 45255
        case 5: return 256_000
        default: return nil
        }
    }

    private func calculateSkillDetails(_ skill: PlannedSkill) -> (
        startSP: Int, endSP: Int, requiredSP: Int, trainingTime: TimeInterval
    ) {
        // 获取训练速度
        let trainingRate = trainingRates[skill.skillID] ?? 0

        // 获取技能的训练倍增系数
        let timeMultiplier = getSkillTimeMultiplier(skill.skillID)

        // 获取起始和目标等级的技能点数
        let startSP = (getBaseSkillPointsForLevel(skill.currentLevel) ?? 0) * timeMultiplier
        let endSP = (getBaseSkillPointsForLevel(skill.targetLevel) ?? 0) * timeMultiplier

        // 计算需要训练的技能点数
        let requiredSP = endSP - startSP

        // 计算训练时间（如果有训练速度）
        let trainingTime: TimeInterval =
            trainingRate > 0 ? Double(requiredSP) / Double(trainingRate) * 3600 : 0 // 转换为秒

        return (startSP, endSP, requiredSP, trainingTime)
    }

    private func calculateSkillRequirements(_ skill: PlannedSkill) -> (
        requiredSP: Int, trainingTime: TimeInterval
    ) {
        let details = calculateSkillDetails(skill)
        return (details.requiredSP, details.trainingTime)
    }

    private func getSkillPointRange(_ skill: PlannedSkill) -> (start: Int, end: Int) {
        let timeMultiplier = getSkillTimeMultiplier(skill.skillID)
        // 使用目标等级-1作为起始等级，目标等级作为结束等级
        let startLevel = skill.targetLevel - 1
        let endLevel = skill.targetLevel

        // 使用缓存的技能数据
        let actualSkillPoints = learnedSkills[skill.skillID]?.skillpoints_in_skill ?? 0
        let actualLevel = learnedSkills[skill.skillID]?.trained_skill_level ?? 0

        // 如果实际等级等于计划的起始等级，使用实际技能点数作为起始点
        let startSP =
            (actualLevel == startLevel)
                ? actualSkillPoints : (getBaseSkillPointsForLevel(startLevel) ?? 0) * timeMultiplier
        let endSP = (getBaseSkillPointsForLevel(endLevel) ?? 0) * timeMultiplier
        return (startSP, endSP)
    }

    private func deleteSkill(at offsets: IndexSet) {
        var updatedPlan = plan
        updatedPlan.skills.remove(atOffsets: offsets)

        // 使用通用函数更新计划
        updatedPlan = updatePlanWithSkills(updatedPlan, skills: updatedPlan.skills)

        // 保存更新后的计划
        SkillPlanFileManager.shared.saveSkillPlan(characterId: characterId, plan: updatedPlan)

        // 更新当前视图的计划
        plan = updatedPlan

        // 更新父视图中的计划列表
        if let index = skillPlans.firstIndex(where: { $0.id == plan.id }) {
            skillPlans[index] = updatedPlan
        }

        // 重新计算依赖关系
        calculateSkillDependencies()

        // 重新计算注入器需求
        Task {
            await calculateInjectors()
        }
    }

    // 移除技能的某些等级（从技能选择器降级时调用）
    private func removeSkillLevels(skillId: Int, fromLevel: Int, toLevel: Int) {
        // Logger.debug("[移除技能等级] skillId: \(skillId), 从等级 \(fromLevel) 到 \(toLevel)")

        var updatedPlan = plan

        // 移除指定范围的技能等级
        updatedPlan.skills.removeAll { skill in
            skill.skillID == skillId && skill.targetLevel >= fromLevel && skill.targetLevel <= toLevel
        }

        // 使用通用函数更新计划
        updatedPlan = updatePlanWithSkills(updatedPlan, skills: updatedPlan.skills)

        // 保存更新后的计划
        SkillPlanFileManager.shared.saveSkillPlan(characterId: characterId, plan: updatedPlan)

        // 更新当前视图的计划
        plan = updatedPlan

        // 更新父视图中的计划列表
        if let index = skillPlans.firstIndex(where: { $0.id == plan.id }) {
            skillPlans[index] = updatedPlan
        }

        // 重新计算依赖关系（移除后其他技能可能可以降级）
        calculateSkillDependencies()

        // 重新计算注入器需求
        Task {
            await calculateInjectors()
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

    private var totalInjectorCost: Double? {
        guard let calculation = injectorCalculation else {
            Logger.debug("计算总价失败 - 没有注入器计算结果")
            return nil
        }

        return InjectorPriceManager.shared.calculateTotalCost(
            calculation: calculation,
            prices: injectorPrices
        )
    }

    private func calculateInjectors() async {
        isLoadingInjectors = true
        defer { isLoadingInjectors = false }

        // 使用计划中已计算好的总技能点数
        let totalRequiredSP = plan.totalSkillPoints
        Logger.debug("计划总需求技能点: \(totalRequiredSP)")

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

    private func loadInjectorPrices() async {
        let prices = await InjectorPriceManager.shared.loadInjectorPrices()

        await MainActor.run {
            injectorPrices = prices
        }
    }

    private func getCharacterTotalSP() async -> Int {
        // 直接从API获取角色当前的总技能点数
        do {
            let skillsInfo = try await CharacterSkillsAPI.shared.fetchCharacterSkills(
                characterId: characterId, forceRefresh: false
            )
            let characterTotalSP = skillsInfo.total_sp + skillsInfo.unallocated_sp
            Logger.debug(
                "从API获取角色总技能点: \(characterTotalSP) (已分配: \(skillsInfo.total_sp), 未分配: \(skillsInfo.unallocated_sp))"
            )
            return characterTotalSP
        } catch {
            Logger.error("获取技能点数据失败: \(error)")
            return 0
        }
    }

    // 添加新的通用函数
    private func updatePlanWithSkills(_ currentPlan: SkillPlan, skills: [PlannedSkill]) -> SkillPlan {
        var updatedPlan = currentPlan
        updatedPlan.skills = skills

        // 更新计划的总训练时间和总技能点
        updatedPlan.totalTrainingTime = updatedPlan.skills.reduce(0) {
            $0 + ($1.isCompleted ? 0 : $1.trainingTime)
        }
        updatedPlan.totalSkillPoints = updatedPlan.skills.reduce(0) { total, skill in
            if skill.isCompleted {
                return total
            }
            let spRange = getSkillPointRange(skill)
            return total + (spRange.end - spRange.start)
        }

        return updatedPlan
    }

    private func createPlannedSkill(
        typeId: Int,
        skillName: String,
        targetLevel: Int,
        isCompleted: Bool
    ) -> PlannedSkill {
        let skill = PlannedSkill(
            id: UUID(),
            skillID: typeId,
            skillName: skillName,
            currentLevel: targetLevel - 1, // 计划中的当前等级始终是目标等级-1
            targetLevel: targetLevel,
            trainingTime: 0,
            requiredSP: 0,
            prerequisites: [],
            currentSkillPoints: getBaseSkillPointsForLevel(targetLevel - 1) ?? 0, // 使用计划等级的基础点数
            isCompleted: isCompleted
        )

        // 计算训练时间和所需技能点
        let (requiredSP, trainingTime) = calculateSkillRequirements(skill)

        return PlannedSkill(
            id: skill.id,
            skillID: skill.skillID,
            skillName: skill.skillName,
            currentLevel: skill.currentLevel,
            targetLevel: skill.targetLevel,
            trainingTime: trainingTime,
            requiredSP: requiredSP,
            prerequisites: skill.prerequisites,
            currentSkillPoints: skill.currentSkillPoints,
            isCompleted: isCompleted
        )
    }

    private func calculateAllSkillPoints() -> Int {
        // 计算所有技能点数，不考虑已学会的技能
        return plan.skills.reduce(0) { total, skill in
            let spRange = getSkillPointRange(skill)
            return total + (spRange.end - spRange.start)
        }
    }

    // 清空所有技能
    private func clearAllSkills() {
        var updatedPlan = plan
        updatedPlan.skills = []

        // 使用通用函数更新计划
        updatedPlan = updatePlanWithSkills(updatedPlan, skills: [])

        // 保存更新后的计划
        SkillPlanFileManager.shared.saveSkillPlan(characterId: characterId, plan: updatedPlan)

        // 更新当前视图的计划
        plan = updatedPlan

        // 更新父视图中的计划列表
        if let index = skillPlans.firstIndex(where: { $0.id == plan.id }) {
            skillPlans[index] = updatedPlan
        }

        // 重新计算依赖关系
        calculateSkillDependencies()

        // 重新计算注入器需求
        Task {
            await calculateInjectors()
        }
    }

    // 批量添加技能到计划（从 AddSkillSelectorView 回调）
    private func addBatchSkillsToPlan(skills: [(skillId: Int, skillName: String, level: Int)]) async {
        // 加载所有相关技能的数据
        let skillIds = Array(Set(skills.map { $0.skillId }))
        await ensureSkillsDataLoaded(skillIds: skillIds)

        // 批量添加技能
        addSkillLevelsToPlan(skills)
    }

    // 确保技能数据已加载
    private func ensureSkillsDataLoaded(skillIds: [Int]) async {
        // 1. 加载已学技能数据
        if learnedSkills.isEmpty {
            learnedSkills = await getLearnedSkills(skillIds: skillIds)
        } else {
            // 只加载缺失的技能数据
            let missingSkillIds = skillIds.filter { !learnedSkills.keys.contains($0) }
            if !missingSkillIds.isEmpty {
                let newSkills = await getLearnedSkills(skillIds: missingSkillIds)
                learnedSkills.merge(newSkills) { current, _ in current }
            }
        }

        // 2. 加载角色属性（如果尚未加载）
        if characterAttributes == nil {
            characterAttributes = try? await CharacterSkillsAPI.shared.fetchAttributes(
                characterId: characterId)
        }

        // 3. 加载植入体加成（如果尚未加载）
        if implantBonuses == nil {
            implantBonuses = await SkillTrainingCalculator.getImplantBonuses(characterId: characterId)
        }

        // 4. 批量加载技能倍增系数
        loadSkillTimeMultipliers(skillIds)

        // 5. 计算训练速度（如果有角色属性）
        if let attrs = characterAttributes {
            // 批量获取技能的主副属性
            let attributesQuery = """
                SELECT type_id, attribute_id, value
                FROM typeAttributes
                WHERE type_id IN (\(skillIds.sorted().map(String.init).joined(separator: ",")))
                AND attribute_id IN (180, 181)
            """

            var skillAttributes: [Int: (primary: Int, secondary: Int)] = [:]
            if case let .success(rows) = databaseManager.executeQuery(attributesQuery) {
                // 按技能ID分组
                var groupedAttributes: [Int: [(attributeId: Int, value: Int)]] = [:]
                for row in rows {
                    guard let typeId = row["type_id"] as? Int,
                          let attributeId = row["attribute_id"] as? Int,
                          let value = row["value"] as? Double
                    else {
                        continue
                    }
                    groupedAttributes[typeId, default: []].append((attributeId, Int(value)))
                }

                // 处理每个技能的属性
                for (typeId, attributes) in groupedAttributes {
                    var primary: Int?
                    var secondary: Int?
                    for attr in attributes {
                        if attr.attributeId == 180 {
                            primary = attr.value
                        } else if attr.attributeId == 181 {
                            secondary = attr.value
                        }
                    }
                    if let p = primary, let s = secondary {
                        skillAttributes[typeId] = (p, s)
                    }
                }
            }

            // 计算所有技能的训练速度
            for skillId in skillIds {
                // 如果已经计算过，跳过
                if trainingRates[skillId] != nil {
                    continue
                }

                if let (primary, secondary) = skillAttributes[skillId],
                   let rate = SkillTrainingCalculator.calculateTrainingRate(
                       primaryAttrId: primary,
                       secondaryAttrId: secondary,
                       attributes: attrs
                   )
                {
                    trainingRates[skillId] = rate
                }
            }
        }
    }

    // 批量添加技能等级到计划（内部使用）
    private func addSkillLevelsToPlan(_ skillsToAdd: [(skillId: Int, skillName: String, level: Int)]) {
        var updatedSkills = plan.skills
        var skillNamesToLoad: Set<Int> = []

        // 收集需要加载名称的技能ID
        for skill in skillsToAdd where skill.skillName.isEmpty {
            skillNamesToLoad.insert(skill.skillId)
        }

        // 批量加载技能名称
        let skillNamesDict = skillNamesToLoad.isEmpty ? [:] : loadSkillNames(skillIds: Array(skillNamesToLoad))

        // 先收集每个技能已存在的最高等级
        var existingMaxLevels: [Int: Int] = [:] // [skillId: maxLevel]
        for skill in updatedSkills {
            let currentMax = existingMaxLevels[skill.skillID] ?? 0
            existingMaxLevels[skill.skillID] = max(currentMax, skill.targetLevel)
        }

        // 收集要添加的新技能等级
        var newSkills: [PlannedSkill] = []
        var skillsToAddSet: Set<String> = [] // 用于去重，格式: "skillId_level"

        for skill in skillsToAdd {
            let skillName = skill.skillName.isEmpty ? (skillNamesDict[skill.skillId] ?? "Unknown Skill (\(skill.skillId))") : skill.skillName
            let key = "\(skill.skillId)_\(skill.level)"

            // 如果该技能等级已在待添加列表中，跳过
            if skillsToAddSet.contains(key) {
                continue
            }

            // 如果该技能的该等级已存在于计划中，跳过
            if updatedSkills.contains(where: { $0.skillID == skill.skillId && $0.targetLevel == skill.level }) {
                Logger.debug("  [=] 技能等级已存在: \(skillName) 等级 \(skill.level)")
                continue
            }

            // 如果已存在更高等级，跳过
            if let existingMax = existingMaxLevels[skill.skillId], existingMax >= skill.level {
                Logger.debug("  [=] 已存在更高或相同等级: \(skillName) (已有等级 \(existingMax) >= \(skill.level))")
                continue
            }

            // 检查技能是否已完成
            let learnedSkill = learnedSkills[skill.skillId]
            let currentLevel = learnedSkill?.trained_skill_level ?? 0
            let isCompleted = skill.level <= currentLevel

            // 创建新技能
            let newSkill = createPlannedSkill(
                typeId: skill.skillId,
                skillName: skillName,
                targetLevel: skill.level,
                isCompleted: isCompleted
            )

            newSkills.append(newSkill)
            skillsToAddSet.insert(key)
            // 更新记录的最高等级
            let currentMax = existingMaxLevels[skill.skillId] ?? 0
            existingMaxLevels[skill.skillId] = max(currentMax, skill.level)

            // let status = isCompleted ? "[完成]" : ""
            // Logger.debug("   将添加: \(skillName) 等级 \(skill.level) \(status)")
        }

        // 如果有新技能要添加
        if !newSkills.isEmpty {
            // 将新技能添加到计划中
            updatedSkills.append(contentsOf: newSkills)

            let updatedPlan = updatePlanWithSkills(plan, skills: updatedSkills)

            // 保存更新后的计划
            SkillPlanFileManager.shared.saveSkillPlan(characterId: characterId, plan: updatedPlan)

            // 更新UI状态
            plan = updatedPlan
            if let index = skillPlans.firstIndex(where: { $0.id == plan.id }) {
                skillPlans[index] = updatedPlan
            }

            // 重新计算依赖关系
            calculateSkillDependencies()

            // 重新计算注入器需求
            Task {
                await calculateInjectors()
            }

            Logger.debug("  [*] 批量添加完成，共添加 \(newSkills.count) 个技能等级")
        } else {
            Logger.debug("  [*] 没有新技能需要添加")
        }
    }

    // 添加物品的所有技能依赖到计划
    private func addItemSkillsToPlan(itemId: Int, itemName: String) async {
        Logger.debug(" 开始添加物品技能依赖到计划 - 物品: \(itemName) (ID: \(itemId))")

        // 获取物品的所有技能依赖
        let requirements = SkillTreeManager.shared.getDeduplicatedSkillRequirements(
            for: itemId,
            databaseManager: databaseManager
        )

        guard !requirements.isEmpty else {
            Logger.debug("[-] 物品 \(itemName) 没有技能依赖")
            return
        }

        Logger.debug(" 物品需要 \(requirements.count) 个技能:")
        for requirement in requirements {
            if let skillName = SkillTreeManager.shared.getSkillName(for: requirement.skillID) {
                Logger.debug("  - \(skillName) (ID: \(requirement.skillID)) 等级: \(requirement.level)")
            }
        }

        // 获取所有需要添加的技能ID（用于批量加载数据）
        let skillIds = requirements.map { $0.skillID }

        // 批量加载技能名称
        let skillNamesDict = loadSkillNames(skillIds: skillIds)

        // 批量加载技能倍增系数
        loadSkillTimeMultipliers(skillIds)

        // 收集所有需要添加的技能（包括前置技能）
        var skillsToAdd: [(skillId: Int, skillName: String, level: Int)] = []
        var allSkillIds: Set<Int> = []

        for requirement in requirements {
            let skillName = skillNamesDict[requirement.skillID] ?? "Unknown Skill (\(requirement.skillID))"

            // 收集前置技能
            let prerequisites = getAllPrerequisitesForSkill(skillId: requirement.skillID, requiredLevel: requirement.level)
            for prereq in prerequisites {
                skillsToAdd.append((skillId: prereq.skillId, skillName: "", level: prereq.requiredLevel))
                allSkillIds.insert(prereq.skillId)
            }

            // 收集目标技能的所有等级（从1到目标等级）
            for currentLevel in 1 ... requirement.level {
                skillsToAdd.append((skillId: requirement.skillID, skillName: skillName, level: currentLevel))
                allSkillIds.insert(requirement.skillID)
            }
        }

        // 加载所有相关技能的数据
        await ensureSkillsDataLoaded(skillIds: Array(allSkillIds))

        // 批量添加所有技能
        addSkillLevelsToPlan(skillsToAdd)

        Logger.debug(" 物品技能依赖添加完成")
    }

    // 获取技能的所有前置要求（递归，包括所有等级，从1级开始）
    private func getAllPrerequisitesForSkill(
        skillId: Int,
        requiredLevel _: Int
    ) -> [(skillId: Int, requiredLevel: Int)] {
        // 使用SkillTreeManager获取所有前置技能（已经递归处理）
        let requirements = SkillTreeManager.shared.getDeduplicatedSkillRequirements(
            for: skillId,
            databaseManager: databaseManager
        )

        var skillLevels: [Int: Int] = [:] // [skillId: maxLevel]

        // 收集每个技能需要的最高等级
        for requirement in requirements {
            let currentMax = skillLevels[requirement.skillID] ?? 0
            skillLevels[requirement.skillID] = max(currentMax, requirement.level)
        }

        // 计算每个技能的依赖深度（最底层=最大深度）
        var skillDepths: [Int: Int] = [:]
        for (prereqSkillId, _) in skillLevels {
            let depth = calculateSkillDepth(skillId: prereqSkillId)
            skillDepths[prereqSkillId] = depth
        }

        var allPrerequisites: [(skillId: Int, requiredLevel: Int)] = []

        // 将每个技能展开成从1到最高等级的所有等级
        for (prereqSkillId, maxLevel) in skillLevels {
            for level in 1 ... maxLevel {
                allPrerequisites.append((skillId: prereqSkillId, requiredLevel: level))
            }
        }

        // 按深度排序（深度小的先=最底层的前置优先）
        return allPrerequisites.sorted { first, second in
            let depth1 = skillDepths[first.skillId] ?? 0
            let depth2 = skillDepths[second.skillId] ?? 0

            if depth1 != depth2 {
                return depth1 < depth2 // 深度小的优先（最底层优先）
            } else if first.skillId == second.skillId {
                return first.requiredLevel < second.requiredLevel // 同一技能，等级从低到高
            } else {
                return first.skillId < second.skillId // 同深度，按 ID 排序
            }
        }
    }

    // 计算技能的依赖深度（递归）
    private func calculateSkillDepth(skillId: Int) -> Int {
        let directReqs = SkillTreeManager.shared.getDeduplicatedSkillRequirements(
            for: skillId, databaseManager: databaseManager
        )

        if directReqs.isEmpty {
            return 0 // 没有前置，深度为0
        }

        // 深度 = 1 + 所有前置技能的最大深度
        let maxPrereqDepth = directReqs.map { req in
            calculateSkillDepth(skillId: req.skillID)
        }.max() ?? 0

        return 1 + maxPrereqDepth
    }

    // 批量加载技能名称
    private func loadSkillNames(skillIds: [Int]) -> [Int: String] {
        guard !skillIds.isEmpty else { return [:] }

        let query = """
            SELECT type_id, name
            FROM types
            WHERE type_id IN (\(skillIds.sorted().map(String.init).joined(separator: ",")))
        """

        var skillNames: [Int: String] = [:]
        if case let .success(rows) = databaseManager.executeQuery(query) {
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                   let name = row["name"] as? String
                {
                    skillNames[typeId] = name
                }
            }
        }
        return skillNames
    }

    // 获取计划中已有技能的最高等级
    private func getExistingSkillLevels() -> [Int: Int] {
        var skillLevels: [Int: Int] = [:]
        for skill in plan.skills {
            let currentMax = skillLevels[skill.skillID] ?? 0
            skillLevels[skill.skillID] = max(currentMax, skill.targetLevel)
        }
        return skillLevels
    }

    // 计算技能的后置依赖关系
    private func calculateSkillDependencies() {
        var dependencies: [String: Set<String>] = [:]

        for skill in plan.skills {
            let skillKey = "\(skill.skillID)_\(skill.targetLevel)"

            // 1. 该技能的低等级被高等级依赖
            // 例如：Amarr Destroyer 3 依赖 Amarr Destroyer 2, 1
            if skill.targetLevel > 1 {
                for lowerLevel in 1 ..< skill.targetLevel {
                    let lowerKey = "\(skill.skillID)_\(lowerLevel)"
                    dependencies[lowerKey, default: []].insert(skillKey)
                }
            }

            // 2. 该技能依赖的前置技能
            // 例如：Amarr Destroyer 1 依赖 Amarr Frigate 3
            let prerequisites = SkillTreeManager.shared.getDeduplicatedSkillRequirements(
                for: skill.skillID,
                databaseManager: databaseManager
            )

            for prereq in prerequisites {
                let prereqKey = "\(prereq.skillID)_\(prereq.level)"
                dependencies[prereqKey, default: []].insert(skillKey)
            }
        }

        skillDependencies = dependencies
    }

    // 检查技能等级是否有后置依赖
    private func hasPostDependencies(skillId: Int, level: Int) -> Bool {
        let key = "\(skillId)_\(level)"
        return !(skillDependencies[key]?.isEmpty ?? true)
    }

    // 判断当前数据库语言是否为英文
    private func isEnglishLanguage() -> Bool {
        let dbLanguage = UserDefaults.standard.string(forKey: "selectedDatabaseLanguage") ?? "en"
        return dbLanguage == "en"
    }

    // 导出技能计划
    private func exportSkillPlan(useEnglishNames: Bool) async {
        guard !plan.skills.isEmpty else {
            await MainActor.run {
                errorMessage = NSLocalizedString("Main_Skills_Plan_Export_Empty", comment: "技能计划为空，无法导出")
                showErrorAlert = true
            }
            return
        }

        // 获取所有技能ID
        let skillIds = plan.skills.map { $0.skillID }

        // 从数据库批量获取技能名称
        let nameField = useEnglishNames ? "en_name" : "name"
        let query = """
            SELECT type_id, \(nameField) as skill_name
            FROM types
            WHERE type_id IN (\(skillIds.sorted().map(String.init).joined(separator: ",")))
        """

        var skillNamesDict: [Int: String] = [:]
        if case let .success(rows) = databaseManager.executeQuery(query) {
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                   let skillName = row["skill_name"] as? String
                {
                    skillNamesDict[typeId] = skillName
                }
            }
        }

        // 构建导出文本
        var exportLines: [String] = []
        for skill in plan.skills {
            if let skillName = skillNamesDict[skill.skillID] {
                exportLines.append("\(skillName) \(skill.targetLevel)")
            } else {
                // 如果找不到技能名称，使用ID作为后备
                exportLines.append("Unknown Skill (\(skill.skillID)) \(skill.targetLevel)")
            }
        }

        let exportText = exportLines.joined(separator: "\n")

        // 复制到剪贴板
        await MainActor.run {
            UIPasteboard.general.string = exportText
            showExportSuccessAlert = true
        }

        Logger.debug("导出技能计划完成，共 \(exportLines.count) 个技能")
    }
}
