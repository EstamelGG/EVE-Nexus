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
                Text(FormatUtil.format(Double(plan.totalSkillPoints)))
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
                    .font(.headline)
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
                Text(formatTimeInterval(skill.trainingTime))
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.top, 2)
        }
        .padding(.vertical, 2)
    }
    
    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        let days = Int(interval) / (24 * 3600)
        let hours = Int(interval) / 3600 % 24
        let minutes = Int(interval) / 60 % 60
        
        if days > 0 {
            if hours > 0 {
                return String(format: NSLocalizedString("Time_Days_Hours", comment: ""), days, hours)
            }
            return String(format: NSLocalizedString("Time_Days", comment: ""), days)
        } else if hours > 0 {
            if minutes > 0 {
                return String(format: NSLocalizedString("Time_Hours_Minutes", comment: ""), hours, minutes)
            }
            return String(format: NSLocalizedString("Time_Hours", comment: ""), hours)
        }
        return String(format: NSLocalizedString("Time_Minutes", comment: ""), minutes)
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
                
                // 批量加载新技能的倍增系数
                loadSkillTimeMultipliers(newSkillIds)
                
                // 更新计划数据
                var updatedPlan = plan
                let validSkills = result.skills.compactMap { skillString -> PlannedSkill? in
                    let components = skillString.split(separator: ":")
                    guard components.count == 2,
                          let typeId = Int(components[0]),
                          let level = Int(components[1]) else {
                        return nil
                    }
                    
                    // 检查是否已存在相同技能和等级
                    if updatedPlan.skills.contains(where: { $0.skillID == typeId && $0.targetLevel == level }) {
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
                        currentLevel: 0,
                        targetLevel: level,
                        trainingTime: 0,
                        requiredSP: 0,
                        prerequisites: []
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
                        prerequisites: skill.prerequisites
                    )
                }
                
                // 只有在有有效技能时才更新计划
                if !validSkills.isEmpty {
                    // 将新技能添加到现有技能列表末尾
                    updatedPlan.skills.append(contentsOf: validSkills)
                    
                    // 更新计划的总训练时间和总技能点
                    updatedPlan.totalTrainingTime = updatedPlan.skills.reduce(0) { $0 + $1.trainingTime }
                    updatedPlan.totalSkillPoints = updatedPlan.skills.reduce(0) { $0 + $1.requiredSP }
                    
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
        
        // 更新每个技能的训练时间和所需技能点
        updatedPlan.skills = updatedPlan.skills.map { skill in
            let (requiredSP, trainingTime) = calculateSkillRequirements(skill)
            
            totalTrainingTime += trainingTime
            totalSkillPoints += requiredSP
            
            return PlannedSkill(
                id: skill.id,
                skillID: skill.skillID,
                skillName: skill.skillName,
                currentLevel: skill.currentLevel,
                targetLevel: skill.targetLevel,
                trainingTime: trainingTime,
                requiredSP: requiredSP,
                prerequisites: skill.prerequisites
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
    
    private func calculateSkillRequirements(_ skill: PlannedSkill) -> (requiredSP: Int, trainingTime: TimeInterval) {
        let currentLevel = skill.currentLevel
        let targetLevel = skill.targetLevel
        var totalSP = 0
        var totalTime: TimeInterval = 0
        
        // 获取训练速度
        let trainingRate = trainingRates[skill.skillID] ?? 0
        
        // 获取技能的训练倍增系数
        let timeMultiplier = getSkillTimeMultiplier(skill.skillID)
        
        // 计算从当前等级到目标等级所需的技能点和时间
        for level in (currentLevel + 1)...targetLevel {
            if let baseSpForLevel = getBaseSkillPointsForLevel(level) {
                // 根据训练倍增系数计算实际所需技能点
                let spForLevel = Int(baseSpForLevel) * timeMultiplier
                totalSP += spForLevel
                if trainingRate > 0 {
                    totalTime += Double(spForLevel) / Double(trainingRate) * 3600 // 转换为秒
                }
            }
        }
        
        return (totalSP, totalTime)
    }
    
    private func getSkillPointRange(_ skill: PlannedSkill) -> (start: Int, end: Int) {
        let timeMultiplier = getSkillTimeMultiplier(skill.skillID)
        
        // 获取前一级的完成点数（作为起始点数）
        let startLevel = skill.targetLevel - 1
        let startSP = startLevel > 0 ? (getBaseSkillPointsForLevel(startLevel) ?? 0) * timeMultiplier : 0
        
        // 获取目标等级的完成点数
        let endSP = (getBaseSkillPointsForLevel(skill.targetLevel) ?? 0) * timeMultiplier
        
        return (startSP, endSP)
    }
    
    private func deleteSkill(at offsets: IndexSet) {
        var updatedPlan = plan
        updatedPlan.skills.remove(atOffsets: offsets)
        
        // 重新计算总时间和技能点
        updatedPlan.totalTrainingTime = updatedPlan.skills.reduce(0) { $0 + $1.trainingTime }
        updatedPlan.totalSkillPoints = updatedPlan.skills.reduce(0) { $0 + $1.requiredSP }
        
        // 保存更新后的计划
        SkillPlanFileManager.shared.saveSkillPlan(characterId: characterId, plan: updatedPlan)
        
        // 更新父视图中的计划列表
        if let index = skillPlans.firstIndex(where: { $0.id == plan.id }) {
            skillPlans[index] = updatedPlan
        }
    }
}
