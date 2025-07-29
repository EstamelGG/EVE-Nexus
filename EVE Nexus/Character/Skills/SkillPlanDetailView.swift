import Foundation
import SwiftUI
import UniformTypeIdentifiers

private let kShowCompletedSkillsKey = "SkillPlan_ShowCompletedSkills"

struct SkillPlanDetailView: View {
    @State private var plan: SkillPlan
    let characterId: Int
    @ObservedObject var databaseManager: DatabaseManager
    @Binding var skillPlans: [SkillPlan]
    @State private var isShowingEditSheet = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var shouldDismissSheet = false
    @State private var characterAttributes: CharacterAttributes?
    @State private var implantBonuses: ImplantAttributes?
    @State private var trainingRates: [Int: Int] = [:]  // [skillId: pointsPerHour]
    @State private var skillTimeMultipliers: [Int: Int] = [:]  // [skillId: timeMultiplier]
    @State private var injectorCalculation: InjectorCalculation?
    @State private var injectorPrices: InjectorPriceManager.InjectorPrices = InjectorPriceManager.InjectorPrices(large: nil, small: nil)
    @State private var isLoadingInjectors = true
    @State private var learnedSkills: [Int: CharacterSkill] = [:]  // 添加缓存
    @AppStorage(kShowCompletedSkillsKey) private var showCompletedSkills = true

    init(
        plan: SkillPlan, characterId: Int, databaseManager: DatabaseManager,
        skillPlans: Binding<[SkillPlan]>
    ) {
        // 在初始化时同步更新技能完成状态
        let learnedSkills = Self.getLearnedSkillsSync(skillIds: plan.skills.map { $0.skillID }, characterId: characterId)
        let updatedSkills = plan.skills.map { skill in
            let learnedSkill = learnedSkills[skill.skillID]
            let currentLevel = learnedSkill?.trained_skill_level ?? 0
            let isCompleted = skill.targetLevel <= currentLevel
            
            return PlannedSkill(
                id: skill.id,
                skillID: skill.skillID,
                skillName: skill.skillName,
                currentLevel: skill.currentLevel,
                targetLevel: skill.targetLevel,
                trainingTime: skill.trainingTime,
                requiredSP: skill.requiredSP,
                prerequisites: skill.prerequisites,
                currentSkillPoints: skill.currentSkillPoints,
                isCompleted: isCompleted
            )
        }
        
        var updatedPlan = plan
        updatedPlan.skills = updatedSkills
        
        _plan = State(initialValue: updatedPlan)
        self.characterId = characterId
        self.databaseManager = databaseManager
        _skillPlans = skillPlans
        _learnedSkills = State(initialValue: learnedSkills)
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
                if let calculation = injectorCalculation, calculation.largeInjectorCount + calculation.smallInjectorCount > 0 {
                    Section(
                        header: Text(
                            NSLocalizedString("Main_Skills_Required_Injectors", comment: ""))
                    ) {
                        // 大型注入器
                        if let largeInfo = getInjectorInfo(
                            typeId: SkillInjectorCalculator.largeInjectorTypeId), calculation.largeInjectorCount > 0
                        {
                            injectorItemView(
                                info: largeInfo, count: calculation.largeInjectorCount,
                                typeId: SkillInjectorCalculator.largeInjectorTypeId
                            )
                        }

                        // 小型注入器
                        if let smallInfo = getInjectorInfo(
                            typeId: SkillInjectorCalculator.smallInjectorTypeId), calculation.smallInjectorCount > 0
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
                header: Text(
                    "\(NSLocalizedString("Main_Skills_Plan", comment: ""))(\(filteredSkills.count))"
                )
            ) {
                if plan.skills.isEmpty || filteredSkills.count == 0 {
                    Text(NSLocalizedString("Main_Skills_Plan_Empty", comment: ""))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(filteredSkills) { skill in
                        skillRowView(skill)
                    }
                    .onDelete(perform: deleteSkill)
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
            }
        }
        .navigationTitle(plan.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    isShowingEditSheet = true
                } label: {
                    Text(NSLocalizedString("Main_Skills_Plan_Edit", comment: ""))
                }
            }
        }
        .sheet(isPresented: $isShowingEditSheet) {
            NavigationView {
                List {
                    Toggle(
                        NSLocalizedString("Main_Skills_Plan_Show_Completed", comment: ""),
                        isOn: $showCompletedSkills
                    )

                    Button {
                        importSkillsFromClipboard()
                    } label: {
                        Text(
                            NSLocalizedString("Main_Skills_Plan_Import_From_Clipboard", comment: "")
                        )
                    }
                }
                .navigationTitle(NSLocalizedString("Main_Skills_Plan_Edit", comment: ""))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            isShowingEditSheet = false
                        } label: {
                            Text(NSLocalizedString("Misc_Done", comment: ""))
                        }
                    }
                }
                .alert(
                    NSLocalizedString("Main_Skills_Plan_Import_Alert_Title", comment: ""),
                    isPresented: $showErrorAlert
                ) {
                    Button("OK", role: .cancel) {
                        if shouldDismissSheet {
                            isShowingEditSheet = false
                            shouldDismissSheet = false
                        }
                    }
                } message: {
                    Text(errorMessage)
                }
            }
        }
        .onAppear {
            // 在视图出现时加载数据
            Task {
                await loadCharacterData()
            }
        }
    }

    private var filteredSkills: [PlannedSkill] {
        showCompletedSkills ? plan.skills : plan.skills.filter { !$0.isCompleted }
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
                    currentLevel: skill.targetLevel - 1,  // 计划中的当前等级
                    trainingLevel: skill.targetLevel,  // 计划中的目标等级
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
            return String(format: NSLocalizedString("Time_Seconds", comment: ""), 0)
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
            if seconds > 0 {
                return String(
                    format: NSLocalizedString("Time_Minutes_Seconds", comment: ""), minutes, seconds
                )
            }
            return String(format: NSLocalizedString("Time_Minutes", comment: ""), minutes)
        }
        return String(format: NSLocalizedString("Time_Seconds", comment: ""), seconds)
    }

    private func importSkillsFromClipboard() {
        if let clipboardString = UIPasteboard.general.string {
            Logger.debug("从剪贴板读取内容: \(clipboardString)")
            let result = SkillPlanReaderTool.parseSkillPlan(
                from: clipboardString, databaseManager: databaseManager
            )

            // 继续处理成功解析的技能
            if !result.skills.isEmpty {
                Logger.debug("解析技能计划结果: \(result.skills)")

                // 获取所有新技能的ID
                let newSkillIds = result.skills.compactMap { skillString -> Int? in
                    let components = skillString.split(separator: ":")
                    return components.count == 2 ? Int(components[0]) : nil
                }

                // 获取新技能的已学习信息
                let newLearnedSkills = getLearnedSkills(skillIds: newSkillIds)
                // 更新缓存
                learnedSkills.merge(newLearnedSkills) { current, _ in current }

                // 批量加载新技能的倍增系数
                loadSkillTimeMultipliers(newSkillIds)

                // 更新计划数据
                var updatedPlan = plan
                let validSkills = result.skills.compactMap { skillString -> PlannedSkill? in
                    let components = skillString.split(separator: ":")
                    guard components.count == 2,
                        let typeId = Int(components[0]),
                        let targetLevel = Int(components[1])
                    else {
                        return nil
                    }

                    // 检查是否已存在相同技能和等级
                    if updatedPlan.skills.contains(where: {
                        $0.skillID == typeId && $0.targetLevel == targetLevel
                    }) {
                        return nil
                    }

                    // 从数据库获取技能名称
                    let query = "SELECT name FROM types WHERE type_id = \(typeId)"
                    let queryResult = databaseManager.executeQuery(query)
                    var skillName = "Unknown Skill (\(typeId))"

                    switch queryResult {
                    case let .success(rows):
                        if let row = rows.first,
                            let name = row["name"] as? String
                        {
                            skillName = name
                        }
                    case let .error(error):
                        Logger.error("获取技能名称失败: \(error)")
                    }

                    // 获取已学习的技能信息
                    let learnedSkill = learnedSkills[typeId]
                    let currentLevel = learnedSkill?.trained_skill_level ?? 0

                    // 如果目标等级小于等于当前等级，说明已完成
                    let isCompleted = targetLevel <= currentLevel

                    return createPlannedSkill(
                        typeId: typeId,
                        skillName: skillName,
                        targetLevel: targetLevel,
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
                    DispatchQueue.main.async {
                        // 更新当前视图的计划
                        plan = updatedPlan

                        // 更新父视图中的计划列表
                        if let index = skillPlans.firstIndex(where: { $0.id == plan.id }) {
                            skillPlans[index] = updatedPlan
                        }

                        // 重新加载所有数据并计算注入器需求
                        Task {
                            await loadCharacterData()
                        }
                    }
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

                    shouldDismissSheet = false
                } else {
                    shouldDismissSheet = true
                }

                errorMessage = message
                showErrorAlert = true
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

                errorMessage = message
                showErrorAlert = true
                shouldDismissSheet = false
            }
        }
    }

    private func getLearnedSkills(skillIds: [Int]) -> [Int: CharacterSkill] {
        return Self.getLearnedSkillsSync(skillIds: skillIds, characterId: characterId)
    }
    
    private static func getLearnedSkillsSync(skillIds: [Int], characterId: Int) -> [Int: CharacterSkill] {
        // 使用同步方式调用异步API（在后台队列中执行）
        let semaphore = DispatchSemaphore(value: 0)
        var result: [Int: CharacterSkill] = [:]
        
        Task {
            do {
                // 调用API获取技能数据
                let skillsResponse = try await CharacterSkillsAPI.shared.fetchCharacterSkills(
                    characterId: characterId, 
                    forceRefresh: false
                )
                
                // 创建技能ID到技能信息的映射
                let skillsDict = Dictionary(
                    uniqueKeysWithValues: skillsResponse.skills.map { ($0.skill_id, $0) })
                
                // 只返回请求的技能ID对应的技能信息
                result = skillsDict.filter { skillIds.contains($0.key) }
            } catch {
                Logger.error("获取技能数据失败: \(error)")
                result = [:]
            }
            
            semaphore.signal()
        }
        
        // 等待异步操作完成
        semaphore.wait()
        return result
    }

    private func loadCharacterData() async {
        // 先加载已学习的技能数据
        if learnedSkills.isEmpty {
            learnedSkills = getLearnedSkills(skillIds: plan.skills.map { $0.skillID })
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
            trainingRate > 0 ? Double(requiredSP) / Double(trainingRate) * 3600 : 0  // 转换为秒

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
            Logger.debug("从API获取角色总技能点: \(characterTotalSP) (已分配: \(skillsInfo.total_sp), 未分配: \(skillsInfo.unallocated_sp))")
            return characterTotalSP
        } catch {
            Logger.error("获取技能点数据失败: \(error)")
            return 0
        }
    }

    // 添加新的通用函数
    private func updatePlanWithSkills(_ currentPlan: SkillPlan, skills: [PlannedSkill]) -> SkillPlan
    {
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
            currentLevel: targetLevel - 1,  // 计划中的当前等级始终是目标等级-1
            targetLevel: targetLevel,
            trainingTime: 0,
            requiredSP: 0,
            prerequisites: [],
            currentSkillPoints: getBaseSkillPointsForLevel(targetLevel - 1) ?? 0,  // 使用计划等级的基础点数
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
}
