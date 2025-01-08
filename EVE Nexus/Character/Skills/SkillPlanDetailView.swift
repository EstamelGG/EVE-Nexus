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
    }
    
    private func skillRowView(_ skill: PlannedSkill) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(skill.skillName)
                .font(.headline)
            
            HStack {
                Text("\(NSLocalizedString("Main_Skills_Plan_Current_Level", comment: "")): \(skill.currentLevel)")
                Text("→")
                Text("\(NSLocalizedString("Main_Skills_Plan_Target_Level", comment: "")): \(skill.targetLevel)")
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
            
            if !skill.prerequisites.isEmpty {
                Text(NSLocalizedString("Main_Skills_Plan_Prerequisites", comment: ""))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
                
                ForEach(skill.prerequisites) { prereq in
                    Text("• \(prereq.skillName) \(prereq.targetLevel)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            HStack {
                Text("\(NSLocalizedString("Main_Skills_Plan_Training_Time", comment: "")): \(formatTimeInterval(skill.trainingTime))")
                Spacer()
                Text("\(NSLocalizedString("Main_Skills_Plan_Required_SP", comment: "")): \(FormatUtil.format(Double(skill.requiredSP)))")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
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
                
                // 更新计划数据
                var updatedPlan = plan
                let validSkills = result.skills.compactMap { skillString -> PlannedSkill? in
                    let components = skillString.split(separator: ":")
                    guard components.count == 2,
                          let typeId = Int(components[0]),
                          let level = Int(components[1]) else {
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
                    
                    return PlannedSkill(
                        id: UUID(),
                        skillID: typeId,
                        skillName: skillName,
                        currentLevel: 0,
                        targetLevel: level,
                        trainingTime: 0,
                        requiredSP: 0,
                        prerequisites: []
                    )
                }
                
                // 只有在有有效技能时才更新计划
                if !validSkills.isEmpty {
                    // 将新技能添加到现有技能列表末尾
                    updatedPlan.skills.append(contentsOf: validSkills)
                    
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
}
