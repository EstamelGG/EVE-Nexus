import SwiftUI
import Foundation
import UniformTypeIdentifiers

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
    @State private var injectorPrices: (large: Double?, small: Double?) = (nil, nil)
    @State private var isLoadingInjectors = true
    
    init(plan: SkillPlan, characterId: Int, databaseManager: DatabaseManager, skillPlans: Binding<[SkillPlan]>) {
        _plan = State(initialValue: plan)
        self.characterId = characterId
        self.databaseManager = databaseManager
        self._skillPlans = skillPlans
    }
    
    var body: some View {
        List {
            Section(header: Text(NSLocalizedString("Main_Skills_Plan_Total_SP", comment: ""))) {
                Text("\(FormatUtil.format(Double(plan.totalSkillPoints))) SP(\(formatTimeInterval(plan.totalTrainingTime)))")
            }
            
            // 添加注入器需求部分
            if !plan.skills.isEmpty && !isLoadingInjectors {
                if let calculation = injectorCalculation {
                    Section(header: Text(NSLocalizedString("Main_Skills_Required_Injectors", comment: ""))) {
                        // 大型注入器
                        if let largeInfo = getInjectorInfo(typeId: SkillInjectorCalculator.largeInjectorTypeId) {
                            injectorItemView(info: largeInfo, count: calculation.largeInjectorCount, typeId: SkillInjectorCalculator.largeInjectorTypeId)
                        }
                        
                        // 小型注入器
                        if let smallInfo = getInjectorInfo(typeId: SkillInjectorCalculator.smallInjectorTypeId) {
                            injectorItemView(info: smallInfo, count: calculation.smallInjectorCount, typeId: SkillInjectorCalculator.smallInjectorTypeId)
                        }
                        
                        // 总计所需技能点和预计价格
                        injectorSummaryView(calculation: calculation)
                    }
                }
            }
            
            Section(header: Text("\(NSLocalizedString("Main_Skills_Plan", comment:""))(\(plan.skills.count))")) {
                if plan.skills.isEmpty {
                    Text(NSLocalizedString("Main_Skills_Plan_Empty", comment: ""))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(plan.skills) { skill in
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
                    NavigationLink {
                        // 占位1
                    } label: {
                        Text("占位1")
                    }
                    
                    NavigationLink {
                        // 占位2
                    } label: {
                        Text("占位2")
                    }
                    
                    Button {
                        importSkillsFromClipboard()
                    } label: {
                        Text(NSLocalizedString("Main_Skills_Plan_Import_From_Clipboard", comment: ""))
                    }
                }
                .navigationTitle(NSLocalizedString("Main_Skills_Plan_Edit", comment: ""))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            isShowingEditSheet = false
                        } label: {
                            Text(NSLocalizedString("Main_EVE_Mail_Done", comment: ""))
                        }
                    }
                }
                .alert(NSLocalizedString("Main_Skills_Plan_Import_Alert_Title", comment: ""), isPresented: $showErrorAlert) {
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
        .task {
            // 加载角色属性和植入体加成，并计算技能点数
            await loadCharacterData()
        }
    }
    
    private func skillRowView(_ skill: PlannedSkill) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 2) {
                Text(skill.skillName)
                    .lineLimit(1)
                Spacer()
                Text(String(format: NSLocalizedString("Main_Skills_Level", comment: ""), skill.targetLevel))
                    .foregroundColor(.secondary)
                    .font(.caption)
                    .padding(.trailing, 2)
                SkillLevelIndicator(
                    currentLevel: skill.targetLevel - 1,  // 计划中的当前等级
                    trainingLevel: skill.targetLevel,     // 计划中的目标等级
                    isTraining: false
                )
                .padding(.trailing, 2)
            }
            
            let spRange = getSkillPointRange(skill)
            HStack(spacing: 4) {
                if let rate = trainingRates[skill.skillID] {
                    Text("\(FormatUtil.format(Double(spRange.start)))/\(FormatUtil.format(Double(spRange.end))) SP (\(FormatUtil.format(Double(rate)))/h)")
                } else {
                    Text("\(FormatUtil.format(Double(spRange.start)))/\(FormatUtil.format(Double(spRange.end))) SP")
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
                if hours == 24 { // 如果四舍五入后小时数达到24
                    return String(format: NSLocalizedString("Time_Days", comment: ""), days + 1)
                }
            }
            if hours > 0 {
                return String(format: NSLocalizedString("Time_Days_Hours", comment: ""), days, hours)
            }
            return String(format: NSLocalizedString("Time_Days", comment: ""), days)
        } else if hours > 0 {
            // 对分钟进行四舍五入
            if seconds >= 30 {
                minutes += 1
                if minutes == 60 { // 如果四舍五入后分钟数达到60
                    return String(format: NSLocalizedString("Time_Hours", comment: ""), hours + 1)
                }
            }
            if minutes > 0 {
                return String(format: NSLocalizedString("Time_Hours_Minutes", comment: ""), hours, minutes)
            }
            return String(format: NSLocalizedString("Time_Hours", comment: ""), hours)
        } else if minutes > 0 {
            // 对秒进行四舍五入
            if seconds >= 30 {
                minutes += 1
            }
            if seconds > 0 {
                return String(format: NSLocalizedString("Time_Minutes_Seconds", comment: ""), minutes, seconds)
            }
            return String(format: NSLocalizedString("Time_Minutes", comment: ""), minutes)
        }
        return String(format: NSLocalizedString("Time_Seconds", comment: ""), seconds)
    }
    
    private func importSkillsFromClipboard() {
        if let clipboardString = UIPasteboard.general.string {
            Logger.debug("从剪贴板读取内容: \(clipboardString)")
            let result = SkillPlanReaderTool.parseSkillPlan(from: clipboardString, databaseManager: databaseManager)
            
            // 继续处理成功解析的技能
            if !result.skills.isEmpty {
                Logger.debug("解析技能计划结果: \(result.skills)")
                
                // 获取所有新技能的ID
                let newSkillIds = result.skills.compactMap { skillString -> Int? in
                    let components = skillString.split(separator: ":")
                    return components.count == 2 ? Int(components[0]) : nil
                }
                
                // 获取已学习的技能信息
                let learnedSkills = getLearnedSkills(skillIds: newSkillIds)
                
                // 批量加载新技能的倍增系数
                loadSkillTimeMultipliers(newSkillIds)
                
                // 更新计划数据
                var updatedPlan = plan
                let validSkills = result.skills.compactMap { skillString -> PlannedSkill? in
                    let components = skillString.split(separator: ":")
                    guard components.count == 2,
                          let typeId = Int(components[0]),
                          let targetLevel = Int(components[1]) else {
                        return nil
                    }
                    
                    // 检查是否已存在相同技能和等级
                    if updatedPlan.skills.contains(where: { $0.skillID == typeId && $0.targetLevel == targetLevel }) {
                        return nil
                    }
                    
                    // 从数据库获取技能名称
                    let query = "SELECT name FROM types WHERE type_id = \(typeId)"
                    let queryResult = databaseManager.executeQuery(query)
                    var skillName = "Unknown Skill (\(typeId))"
                    
                    switch queryResult {
                    case .success(let rows):
                        if let row = rows.first,
                           let name = row["name"] as? String {
                            skillName = name
                        }
                    case .error(let error):
                        Logger.error("获取技能名称失败: \(error)")
                    }
                    
                    // 获取已学习的技能信息
                    let learnedSkill = learnedSkills[typeId]
                    let currentLevel = learnedSkill?.trained_skill_level ?? 0
                    let currentSkillPoints = learnedSkill?.skillpoints_in_skill ?? 0
                    
                    // 如果目标等级小于等于当前等级，说明已完成
                    let isCompleted = targetLevel <= currentLevel
                    
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
                    
                    // 计算训练速度（如果还没有）
                    if trainingRates[typeId] == nil,
                       let attrs = characterAttributes,
                       let (primary, secondary) = SkillTrainingCalculator.getSkillAttributes(
                           skillId: typeId,
                           databaseManager: databaseManager
                       ),
                       let rate = SkillTrainingCalculator.calculateTrainingRate(
                           primaryAttrId: primary,
                           secondaryAttrId: secondary,
                           attributes: attrs
                       ) {
                        trainingRates[typeId] = rate
                    }
                    
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
                        currentSkillPoints: currentSkillPoints,
                        isCompleted: isCompleted
                    )
                }
                
                // 只有在有有效技能时才更新计划
                if !validSkills.isEmpty {
                    // 将新技能添加到现有技能列表末尾
                    updatedPlan.skills.append(contentsOf: validSkills)
                    
                    // 更新计划的总训练时间和总技能点
                    updatedPlan.totalTrainingTime = updatedPlan.skills.reduce(0) { $0 + ($1.isCompleted ? 0 : $1.trainingTime) }
                    updatedPlan.totalSkillPoints = updatedPlan.skills.reduce(0) { total, skill in
                        if skill.isCompleted {
                            return total
                        }
                        let spRange = getSkillPointRange(skill)
                        return total + (spRange.end - spRange.start)
                    }
                    
                    // 保存更新后的计划
                    SkillPlanFileManager.shared.saveSkillPlan(characterId: characterId, plan: updatedPlan)
                    
                    // 更新父视图中的计划列表
                    if let index = skillPlans.firstIndex(where: { $0.id == plan.id }) {
                        skillPlans[index] = updatedPlan
                    }
                }
                
                // 构建提示消息
                var message = String(format: NSLocalizedString("Main_Skills_Plan_Import_Success", comment: ""), validSkills.count)
                
                if result.hasErrors {
                    message += "\n\n"
                    
                    if !result.parseErrors.isEmpty {
                        message += NSLocalizedString("Main_Skills_Plan_Import_Parse_Failed", comment: "") + "\n" + result.parseErrors.joined(separator: "\n")
                    }
                    
                    if !result.notFoundSkills.isEmpty {
                        if !result.parseErrors.isEmpty {
                            message += "\n\n"
                        }
                        message += NSLocalizedString("Main_Skills_Plan_Import_Not_Found", comment: "") + "\n" + result.notFoundSkills.joined(separator: "\n")
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
                    message += NSLocalizedString("Main_Skills_Plan_Import_Parse_Failed", comment: "") + "\n" + result.parseErrors.joined(separator: "\n")
                }
                
                if !result.notFoundSkills.isEmpty {
                    if !message.isEmpty {
                        message += "\n\n"
                    }
                    message += NSLocalizedString("Main_Skills_Plan_Import_Not_Found", comment: "") + "\n" + result.notFoundSkills.joined(separator: "\n")
                }
                
                errorMessage = message
                showErrorAlert = true
                shouldDismissSheet = false
            }
        }
    }
    
    private func getLearnedSkills(skillIds: [Int]) -> [Int: CharacterSkill] {
        // 从character_skills表获取技能数据
        let skillsQuery = "SELECT skills_data FROM character_skills WHERE character_id = ?"
        
        guard case .success(let rows) = CharacterDatabaseManager.shared.executeQuery(skillsQuery, parameters: [characterId]),
              let row = rows.first,
              let skillsJson = row["skills_data"] as? String,
              let data = skillsJson.data(using: .utf8) else {
            return [:]
        }
        
        do {
            let decoder = JSONDecoder()
            let skillsResponse = try decoder.decode(CharacterSkillsResponse.self, from: data)
            
            // 创建技能ID到技能信息的映射
            let skillsDict = Dictionary(uniqueKeysWithValues: skillsResponse.skills.map { ($0.skill_id, $0) })
            
            // 只返回请求的技能ID对应的技能信息
            return skillsDict.filter { skillIds.contains($0.key) }
        } catch {
            Logger.error("解析技能数据失败: \(error)")
            return [:]
        }
    }
    
    private func loadCharacterData() async {
        // 加载角色属性
        characterAttributes = try? await CharacterSkillsAPI.shared.fetchAttributes(characterId: characterId)
        
        // 加载植入体加成
        implantBonuses = await SkillTrainingCalculator.getImplantBonuses(characterId: characterId)
        
        // 批量获取所有技能的倍增系数
        let skillIds = plan.skills.map { $0.skillID }
        loadSkillTimeMultipliers(skillIds)
        
        // 计算所有技能的训练速度
        if let attrs = characterAttributes {
            for skill in plan.skills {
                if let (primary, secondary) = SkillTrainingCalculator.getSkillAttributes(
                    skillId: skill.skillID,
                    databaseManager: databaseManager
                ) {
                    if let rate = SkillTrainingCalculator.calculateTrainingRate(
                        primaryAttrId: primary,
                        secondaryAttrId: secondary,
                        attributes: attrs
                    ) {
                        trainingRates[skill.skillID] = rate
                    }
                }
            }
        }
        
        // 更新计划中每个技能的训练时间和技能点数
        var updatedPlan = plan
        updatedPlan.totalTrainingTime = 0
        updatedPlan.totalSkillPoints = 0
        
        updatedPlan.skills = plan.skills.map { skill in
            let details = calculateSkillDetails(skill)
            let isCompleted = skill.isCompleted
            
            if !isCompleted {
                updatedPlan.totalTrainingTime += details.trainingTime
                updatedPlan.totalSkillPoints += details.requiredSP
            }
            
            return PlannedSkill(
                id: skill.id,
                skillID: skill.skillID,
                skillName: skill.skillName,
                currentLevel: skill.currentLevel,
                targetLevel: skill.targetLevel,
                trainingTime: details.trainingTime,
                requiredSP: details.requiredSP,
                prerequisites: skill.prerequisites,
                currentSkillPoints: skill.currentSkillPoints,
                isCompleted: isCompleted
            )
        }
        
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
            WHERE type_id IN (\(skillIds.map(String.init).joined(separator: ",")))
            AND attribute_id = 275
        """
        
        if case .success(let rows) = databaseManager.executeQuery(query) {
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                   let value = row["value"] as? Double {
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
        case 2: return 1_415
        case 3: return 8_000
        case 4: return 45_255
        case 5: return 256_000
        default: return nil
        }
    }
    
    private func getSkillRank(_ skillId: Int) -> Int {
        let query = """
            SELECT rank
            FROM types
            WHERE type_id = ?
        """
        if case .success(let rows) = databaseManager.executeQuery(query, parameters: [skillId]),
           let row = rows.first,
           let rank = row["rank"] as? Int {
            return rank
        }
        return 1 // 默认返回1，避免除以0
    }
    
    private func calculateSkillDetails(_ skill: PlannedSkill) -> (startSP: Int, endSP: Int, requiredSP: Int, trainingTime: TimeInterval) {
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
        let trainingTime: TimeInterval = trainingRate > 0 ? Double(requiredSP) / Double(trainingRate) * 3600 : 0 // 转换为秒
        
        return (startSP, endSP, requiredSP, trainingTime)
    }
    
    private func calculateSkillRequirements(_ skill: PlannedSkill) -> (requiredSP: Int, trainingTime: TimeInterval) {
        let details = calculateSkillDetails(skill)
        return (details.requiredSP, details.trainingTime)
    }
    
    private func getSkillPointRange(_ skill: PlannedSkill) -> (start: Int, end: Int) {
        let timeMultiplier = getSkillTimeMultiplier(skill.skillID)
        // 使用目标等级-1作为起始等级，目标等级作为结束等级
        let startLevel = skill.targetLevel - 1
        let endLevel = skill.targetLevel
        let startSP = (getBaseSkillPointsForLevel(startLevel) ?? 0) * timeMultiplier
        let endSP = (getBaseSkillPointsForLevel(endLevel) ?? 0) * timeMultiplier
        return (startSP, endSP)
    }
    
    private func deleteSkill(at offsets: IndexSet) {
        var updatedPlan = plan
        updatedPlan.skills.remove(atOffsets: offsets)
        
        // 重新计算总时间和技能点
        updatedPlan.totalTrainingTime = updatedPlan.skills.reduce(0) { $0 + ($1.isCompleted ? 0 : $1.trainingTime) }
        updatedPlan.totalSkillPoints = updatedPlan.skills.reduce(0) { total, skill in
            if skill.isCompleted {
                return total
            }
            let spRange = getSkillPointRange(skill)
            return total + (spRange.end - spRange.start)
        }
        
        // 保存更新后的计划
        SkillPlanFileManager.shared.saveSkillPlan(characterId: characterId, plan: updatedPlan)
        
        // 更新父视图中的计划列表
        if let index = skillPlans.firstIndex(where: { $0.id == plan.id }) {
            skillPlans[index] = updatedPlan
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
            Text(String(format: NSLocalizedString("Main_Skills_Total_Required_SP", comment: ""), 
                      FormatUtil.format(Double(calculation.totalSkillPoints))))
            if let totalCost = totalInjectorCost {
                Text(String(format: NSLocalizedString("Main_Skills_Total_Injector_Cost", comment: ""), 
                          FormatUtil.formatISK(totalCost)))
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
        if case .success(let rows) = databaseManager.executeQuery(query, parameters: [typeId]),
           let row = rows.first,
           let name = row["name"] as? String,
           let iconFilename = row["icon_filename"] as? String {
            return InjectorInfo(name: name, iconFilename: iconFilename)
        }
        return nil
    }
    
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
        
        return Double(calculation.largeInjectorCount) * largePrice + 
               Double(calculation.smallInjectorCount) * smallPrice
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
            Logger.debug("计算结果 - 大型注入器: \(calc.largeInjectorCount), 小型注入器: \(calc.smallInjectorCount)")
        }
        
        // 获取注入器价格
        await loadInjectorPrices()
    }
    
    private func getCharacterTotalSP() async -> Int {
        // 从数据库获取角色当前的总技能点数
        let query = """
            SELECT total_sp, unallocated_sp
            FROM character_skills
            WHERE character_id = ?
        """
        if case .success(let rows) = CharacterDatabaseManager.shared.executeQuery(query, parameters: [characterId]),
           let row = rows.first {
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
            let skillsInfo = try await CharacterSkillsAPI.shared.fetchCharacterSkills(characterId: characterId, forceRefresh: true)
            let characterTotalSP = skillsInfo.total_sp + skillsInfo.unallocated_sp
            Logger.debug("从API获取角色总技能点: \(characterTotalSP)")
            return characterTotalSP
        } catch {
            Logger.error("获取技能点数据失败: \(error)")
            return 0
        }
    }
    
    private func loadInjectorPrices() async {
        Logger.debug("开始加载注入器价格 - 大型注入器ID: \(SkillInjectorCalculator.largeInjectorTypeId), 小型注入器ID: \(SkillInjectorCalculator.smallInjectorTypeId)")
        
        // 获取大型和小型注入器的价格
        let prices = await MarketPriceUtil.getMarketPrices(typeIds: [
            SkillInjectorCalculator.largeInjectorTypeId,
            SkillInjectorCalculator.smallInjectorTypeId
        ])
        
        Logger.debug("获取到价格数据: \(prices)")
        
        // 确保两个价格都有值才更新
        if let largePrice = prices[SkillInjectorCalculator.largeInjectorTypeId],
           let smallPrice = prices[SkillInjectorCalculator.smallInjectorTypeId] {
            // 在主线程一次性更新两个价格
            await MainActor.run {
                injectorPrices = (large: largePrice, small: smallPrice)
            }
        } else {
            Logger.debug("价格数据不完整 - large: \(prices[SkillInjectorCalculator.largeInjectorTypeId] as Any), small: \(prices[SkillInjectorCalculator.smallInjectorTypeId] as Any)")
        }
    }
}
