import SwiftUI
import Foundation
import UniformTypeIdentifiers

struct SkillPlanDetailView: View {
    let plan: SkillPlan
    let characterId: Int
    @ObservedObject var databaseManager: DatabaseManager
    @State private var isShowingEditSheet = false
    
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
                        if let clipboardString = UIPasteboard.general.string {
                            Logger.debug("从剪贴板读取内容: \(clipboardString)")
                        }
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
}
