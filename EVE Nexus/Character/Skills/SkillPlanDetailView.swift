import SwiftUI
import Foundation
import UniformTypeIdentifiers

struct SkillPlanDetailView: View {
    let plan: SkillPlan
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
    
    var body: some View {
        List {
            Section(header: Text(NSLocalizedString("Main_Skills_Plan_Total_Time", comment: ""))) {
                Text(formatTimeInterval(plan.totalTrainingTime))
            }
            
            Section(header: Text(NSLocalizedString("Main_Skills_Plan_Total_SP", comment: ""))) {
                Text("\(FormatUtil.format(Double(plan.totalSkillPoints))) SP")
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
            // 加载角色属性和植入体加成
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
                    currentLevel: skill.currentLevel,
                    trainingLevel: skill.targetLevel,
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
                    if targetLevel <= currentLevel {
                        return PlannedSkill(
                            id: UUID(),
                            skillID: typeId,
                            skillName: skillName,
                            currentLevel: currentLevel,
                            targetLevel: targetLevel,
                            trainingTime: 0,
                            requiredSP: 0,
                            prerequisites: [],
                            isCompleted: true
                        )
                    }
                    
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
                    
                    let skill = PlannedSkill(
                        id: UUID(),
                        skillID: typeId,
                        skillName: skillName,
                        currentLevel: currentLevel,
                        targetLevel: targetLevel,
                        trainingTime: 0,
                        requiredSP: 0,
                        prerequisites: [],
                        currentSkillPoints: currentSkillPoints,
                        isCompleted: false
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
                        currentSkillPoints: currentSkillPoints,
                        isCompleted: false
                    )
                }
                
                // 只有在有有效技能时才更新计划
                if !validSkills.isEmpty {
                    // 将新技能添加到现有技能列表末尾
                    updatedPlan.skills.append(contentsOf: validSkills)
                    
                    // 更新计划的总训练时间和总技能点
                    updatedPlan.totalTrainingTime = updatedPlan.skills.reduce(0) { $0 + ($1.isCompleted ? 0 : $1.trainingTime) }
                    updatedPlan.totalSkillPoints = updatedPlan.skills.reduce(0) { $0 + ($1.isCompleted ? 0 : $1.requiredSP) }
                    
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
        
        // 更新技能计划
        updateSkillPlan()
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
    
    private func updateSkillPlan() {
        var updatedPlan = plan
        var totalTrainingTime: TimeInterval = 0
        var totalSkillPoints = 0
        
        // 获取已学习的技能信息
        let skillIds = updatedPlan.skills.map { $0.skillID }
        let learnedSkills = getLearnedSkills(skillIds: skillIds)
    
        // 更新每个技能的训练时间和所需技能点
        updatedPlan.skills = updatedPlan.skills.map { skill in
            // 获取已学习的技能信息
            let learnedSkill = learnedSkills[skill.skillID]
            let currentLevel = learnedSkill?.trained_skill_level ?? 0
            let currentSkillPoints = learnedSkill?.skillpoints_in_skill ?? 0
            
            // 如果目标等级小于等于当前等级，说明已完成
            if skill.targetLevel <= currentLevel {
                return PlannedSkill(
                    id: skill.id,
                    skillID: skill.skillID,
                    skillName: skill.skillName,
                    currentLevel: currentLevel,
                    targetLevel: skill.targetLevel,
                    trainingTime: 0,
                    requiredSP: 0,
                    prerequisites: skill.prerequisites,
                    currentSkillPoints: currentSkillPoints,
                    isCompleted: true
                )
            }
            
            let (requiredSP, trainingTime) = calculateSkillRequirements(PlannedSkill(
                id: skill.id,
                skillID: skill.skillID,
                skillName: skill.skillName,
                currentLevel: currentLevel,
                targetLevel: skill.targetLevel,
                trainingTime: 0,
                requiredSP: 0,
                prerequisites: skill.prerequisites,
                currentSkillPoints: currentSkillPoints,
                isCompleted: false
            ))
            
            if !skill.isCompleted {
                totalTrainingTime += trainingTime
                totalSkillPoints += requiredSP
            }
            
            return PlannedSkill(
                id: skill.id,
                skillID: skill.skillID,
                skillName: skill.skillName,
                currentLevel: currentLevel,
                targetLevel: skill.targetLevel,
                trainingTime: trainingTime,
                requiredSP: requiredSP,
                prerequisites: skill.prerequisites,
                currentSkillPoints: currentSkillPoints,
                isCompleted: skill.targetLevel <= currentLevel
            )
        }
        
        // 更新计划总时间和总技能点
        updatedPlan.totalTrainingTime = totalTrainingTime
        updatedPlan.totalSkillPoints = totalSkillPoints
        
        // 保存更新后的计划
        SkillPlanFileManager.shared.saveSkillPlan(characterId: characterId, plan: updatedPlan)
        
        // 更新父视图中的计划列表
        if let index = skillPlans.firstIndex(where: { $0.id == plan.id }) {
            skillPlans[index] = updatedPlan
        }
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
        
        // 获取目标等级的完成点数
        let endSP = (getBaseSkillPointsForLevel(skill.targetLevel) ?? 0) * timeMultiplier
        
        // 使用当前技能点数作为起始点数（如果有）
        let startSP = skill.currentSkillPoints ?? 0
        
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
        let details = calculateSkillDetails(skill)
        return (details.startSP, details.endSP)
    }
    
    private func deleteSkill(at offsets: IndexSet) {
        var updatedPlan = plan
        updatedPlan.skills.remove(atOffsets: offsets)
        
        // 重新计算总时间和技能点
        updatedPlan.totalTrainingTime = updatedPlan.skills.reduce(0) { $0 + ($1.isCompleted ? 0 : $1.trainingTime) }
        updatedPlan.totalSkillPoints = updatedPlan.skills.reduce(0) { $0 + ($1.isCompleted ? 0 : $1.requiredSP) }
        
        // 保存更新后的计划
        SkillPlanFileManager.shared.saveSkillPlan(characterId: characterId, plan: updatedPlan)
        
        // 更新父视图中的计划列表
        if let index = skillPlans.firstIndex(where: { $0.id == plan.id }) {
            skillPlans[index] = updatedPlan
        }
    }
}
