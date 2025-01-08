import SwiftUI

struct SkillPlan: Identifiable {
    let id: UUID
    var name: String
    var skills: [PlannedSkill]
    var totalTrainingTime: TimeInterval
    var totalSkillPoints: Int
}

struct PlannedSkill: Identifiable {
    let id: UUID
    let skillID: Int
    let skillName: String
    let currentLevel: Int
    let targetLevel: Int
    let trainingTime: TimeInterval
    let requiredSP: Int
    var prerequisites: [PlannedSkill]
}

struct SkillPlanView: View {
    let characterId: Int
    @ObservedObject var databaseManager: DatabaseManager
    @State private var skillPlans: [SkillPlan] = []
    @State private var isShowingAddAlert = false
    @State private var isShowingDeleteAlert = false
    @State private var selectedPlan: SkillPlan?
    @State private var newPlanName = ""
    
    var body: some View {
        List {
            if skillPlans.isEmpty {
                Text(NSLocalizedString("Main_Skills_Plan_Empty", comment: ""))
                    .foregroundColor(.secondary)
            } else {
                ForEach(skillPlans) { plan in
                    NavigationLink {
                        SkillPlanDetailView(plan: plan, characterId: characterId, databaseManager: databaseManager)
                    } label: {
                        planRowView(plan)
                    }
                }
                .onDelete(perform: deletePlan)
            }
        }
        .navigationTitle(NSLocalizedString("Main_Skills_Plan", comment: ""))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    newPlanName = ""
                    isShowingAddAlert = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert(NSLocalizedString("Main_Skills_Plan_Add", comment: ""), isPresented: $isShowingAddAlert) {
            TextField(NSLocalizedString("Main_Skills_Plan_Name", comment: ""), text: $newPlanName)
            Button(NSLocalizedString("Main_EVE_Mail_Cancel", comment: ""), role: .cancel) {
                newPlanName = ""
            }
            Button(NSLocalizedString("Main_EVE_Mail_Done", comment: "")) {
                if !newPlanName.isEmpty {
                    let newPlan = SkillPlan(
                        id: UUID(),
                        name: newPlanName,
                        skills: [],
                        totalTrainingTime: 0,
                        totalSkillPoints: 0
                    )
                    skillPlans.append(newPlan)
                    newPlanName = ""
                }
            }
            .disabled(newPlanName.isEmpty)
        } message: {
            Text(NSLocalizedString("Main_Skills_Plan_Name", comment: ""))
        }
    }
    
    private func planRowView(_ plan: SkillPlan) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(plan.name)
                .font(.headline)
            
            HStack {
                Text("\(plan.skills.count) \(NSLocalizedString("Main_Skills_Plan_Skills", comment: ""))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(formatTimeInterval(plan.totalTrainingTime))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func deletePlan(at offsets: IndexSet) {
        skillPlans.remove(atOffsets: offsets)
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

struct SkillPlanDetailView: View {
    let plan: SkillPlan
    let characterId: Int
    @ObservedObject var databaseManager: DatabaseManager
    
    var body: some View {
        List {
            Section(header: Text(NSLocalizedString("Main_Skills_Plan_Total_Time", comment: ""))) {
                Text(formatTimeInterval(plan.totalTrainingTime))
            }
            
            Section(header: Text(NSLocalizedString("Main_Skills_Plan_Total_SP", comment: ""))) {
                Text(FormatUtil.format(Double(plan.totalSkillPoints)))
            }
            
            Section(header: Text(NSLocalizedString("Main_Skills_Plan_Skills", comment: ""))) {
                ForEach(plan.skills) { skill in
                    skillRowView(skill)
                }
            }
        }
        .navigationTitle(plan.name)
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

struct AddSkillPlanView: View {
    let characterId: Int
    @ObservedObject var databaseManager: DatabaseManager
    let onAdd: (SkillPlan) -> Void
    
    @State private var planName = ""
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Form {
            Section {
                TextField(NSLocalizedString("Main_Skills_Plan_Name", comment: ""), text: $planName)
            }
        }
        .navigationTitle(NSLocalizedString("Main_Skills_Plan_Add", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(NSLocalizedString("Main_EVE_Mail_Cancel", comment: "")) {
                    dismiss()
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(NSLocalizedString("Main_EVE_Mail_Done", comment: "")) {
                    let newPlan = SkillPlan(
                        id: UUID(),
                        name: planName,
                        skills: [],
                        totalTrainingTime: 0,
                        totalSkillPoints: 0
                    )
                    onAdd(newPlan)
                }
                .disabled(planName.isEmpty)
            }
        }
    }
} 