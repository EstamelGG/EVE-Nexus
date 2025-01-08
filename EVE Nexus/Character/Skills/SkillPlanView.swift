import SwiftUI
import Foundation

struct SkillPlan: Identifiable {
    let id: UUID
    var name: String
    var skills: [PlannedSkill]
    var totalTrainingTime: TimeInterval
    var totalSkillPoints: Int
    var lastUpdated: Date
    var isPublic: Bool  // 添加是否为公共计划的标记
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

struct SkillPlanData: Codable {
    let name: String
    let lastUpdated: Date
    let skills: [Int]  // 技能ID列表，保持顺序
    let isPublic: Bool  // 添加是否为公共计划的标记
}

class SkillPlanFileManager {
    static let shared = SkillPlanFileManager()
    
    private init() {
        createSkillPlansDirectory()
    }
    
    private var skillPlansDirectory: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("SkillPlans", isDirectory: true)
    }
    
    private func createSkillPlansDirectory() {
        do {
            try FileManager.default.createDirectory(at: skillPlansDirectory, withIntermediateDirectories: true)
        } catch {
            Logger.error("创建技能计划目录失败: \(error)")
        }
    }
    
    func saveSkillPlan(characterId: Int, plan: SkillPlan) {
        let planData = SkillPlanData(
            name: plan.name,
            lastUpdated: Date(),
            skills: [],  // 目前为空列表，后续实现添加技能功能时会更新
            isPublic: plan.isPublic
        )
        
        let prefix = plan.isPublic ? "public" : "\(characterId)"
        let fileName = "\(prefix)_\(plan.id).json"
        let fileURL = skillPlansDirectory.appendingPathComponent(fileName)
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .formatted(DateFormatter.iso8601Full)
            let data = try encoder.encode(planData)
            try data.write(to: fileURL)
            Logger.debug("保存技能计划成功: \(fileName)")
        } catch {
            Logger.error("保存技能计划失败: \(error)")
        }
    }
    
    func loadSkillPlans(characterId: Int) -> [SkillPlan] {
        let fileManager = FileManager.default
        
        do {
            Logger.debug("开始加载技能计划，角色ID: \(characterId)")
            let files = try fileManager.contentsOfDirectory(at: skillPlansDirectory, includingPropertiesForKeys: nil)
            Logger.debug("找到文件数量: \(files.count)")
            
            let plans = files.filter { url in
                let fileName = url.lastPathComponent
                // 匹配角色ID开头或public开头的json文件
                return (fileName.hasPrefix("\(characterId)_") || fileName.hasPrefix("public_")) 
                    && url.pathExtension == "json"
            }.compactMap { url -> SkillPlan? in
                do {
                    Logger.debug("尝试解析文件: \(url.lastPathComponent)")
                    let data = try Data(contentsOf: url)
                    Logger.debug("文件内容: \(String(data: data, encoding: .utf8) ?? "无法读取")")
                    
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .formatted(DateFormatter.iso8601Full)
                    let planData = try decoder.decode(SkillPlanData.self, from: data)
                    Logger.debug("成功解析计划数据 - 名称: \(planData.name), 更新时间: \(planData.lastUpdated), 技能数量: \(planData.skills.count)")
                    
                    let fileName = url.lastPathComponent
                    let prefix = planData.isPublic ? "public" : "\(characterId)"
                    let planIdString = fileName
                        .replacingOccurrences(of: "\(prefix)_", with: "")
                        .replacingOccurrences(of: ".json", with: "")
                    Logger.debug("提取的计划ID: \(planIdString)")
                    
                    guard let planId = UUID(uuidString: planIdString) else {
                        Logger.error("无效的计划ID: \(planIdString)")
                        try? FileManager.default.removeItem(at: url)
                        Logger.debug("已删除无效ID的文件: \(url.lastPathComponent)")
                        return nil
                    }
                    
                    let plan = SkillPlan(
                        id: planId,
                        name: planData.name,
                        skills: [],
                        totalTrainingTime: 0,
                        totalSkillPoints: 0,
                        lastUpdated: planData.lastUpdated,
                        isPublic: planData.isPublic
                    )
                    Logger.debug("成功创建技能计划对象: \(plan.name)")
                    return plan
                    
                } catch {
                    Logger.error("读取技能计划失败: \(error.localizedDescription)")
                    if let decodingError = error as? DecodingError {
                        switch decodingError {
                        case .dataCorrupted(let context):
                            Logger.error("数据损坏: \(context.debugDescription)")
                        case .keyNotFound(let key, let context):
                            Logger.error("未找到键: \(key.stringValue), 路径: \(context.codingPath)")
                        case .typeMismatch(let type, let context):
                            Logger.error("类型不匹配: 期望 \(type), 路径: \(context.codingPath)")
                        case .valueNotFound(let type, let context):
                            Logger.error("值未找到: 类型 \(type), 路径: \(context.codingPath)")
                        @unknown default:
                            Logger.error("未知解码错误: \(decodingError)")
                        }
                    }
                    // 删除损坏的文件
                    try? FileManager.default.removeItem(at: url)
                    Logger.debug("已删除损坏的文件: \(url.lastPathComponent)")
                    return nil
                }
            }
            .sorted { $0.lastUpdated > $1.lastUpdated }
            
            Logger.debug("成功加载技能计划数量: \(plans.count)")
            return plans
            
        } catch {
            Logger.error("读取技能计划目录失败: \(error.localizedDescription)")
            return []
        }
    }
    
    func deleteSkillPlan(characterId: Int, plan: SkillPlan) {
        let prefix = plan.isPublic ? "public" : "\(characterId)"
        let fileName = "\(prefix)_\(plan.id).json"
        let fileURL = skillPlansDirectory.appendingPathComponent(fileName)
        
        do {
            try FileManager.default.removeItem(at: fileURL)
            Logger.debug("删除技能计划成功: \(fileName)")
        } catch {
            Logger.error("删除技能计划失败: \(error)")
        }
    }
}

struct SkillPlanView: View {
    let characterId: Int
    @ObservedObject var databaseManager: DatabaseManager
    @State private var skillPlans: [SkillPlan] = []
    @State private var isShowingAddAlert = false
    @State private var isShowingDeleteAlert = false
    @State private var selectedPlan: SkillPlan?
    @State private var newPlanName = ""
    @State private var searchText = ""  // 添加搜索文本状态
    @State private var isPublicPlan = false  // 添加是否为公共计划的状态
    
    // 添加过滤后的计划列表计算属性
    private var filteredPlans: [SkillPlan] {
        if searchText.isEmpty {
            return skillPlans
        } else {
            return skillPlans.filter { plan in
                plan.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        List {
            if filteredPlans.isEmpty {
                if searchText.isEmpty {
                    Text(NSLocalizedString("Main_Skills_Plan_Empty", comment: ""))
                        .foregroundColor(.secondary)
                } else {
                    Text(String(format: NSLocalizedString("Main_EVE_Mail_No_Results", comment: "")))
                        .foregroundColor(.secondary)
                }
            } else {
                ForEach(filteredPlans) { plan in
                    NavigationLink {
                        SkillPlanDetailView(plan: plan, characterId: characterId, databaseManager: databaseManager)
                    } label: {
                        planRowView(plan)
                    }
                }
                .onDelete(perform: deletePlan)
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            }
        }
        .navigationTitle(NSLocalizedString("Main_Skills_Plan", comment: ""))
        .searchable(text: $searchText, 
                   placement: .navigationBarDrawer(displayMode: .always),
                   prompt: NSLocalizedString("Main_Database_Search", comment: ""))
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
            
            Button(NSLocalizedString("Main_Skills_Plan_Save_As_Public", comment: "")) {
                if !newPlanName.isEmpty {
                    let newPlan = SkillPlan(
                        id: UUID(),
                        name: newPlanName,
                        skills: [],
                        totalTrainingTime: 0,
                        totalSkillPoints: 0,
                        lastUpdated: Date(),
                        isPublic: true
                    )
                    skillPlans.append(newPlan)
                    SkillPlanFileManager.shared.saveSkillPlan(characterId: characterId, plan: newPlan)
                    newPlanName = ""
                }
            }
            .disabled(newPlanName.isEmpty)
            
            Button(NSLocalizedString("Main_Skills_Plan_Save_As_Private", comment: "")) {
                if !newPlanName.isEmpty {
                    let newPlan = SkillPlan(
                        id: UUID(),
                        name: newPlanName,
                        skills: [],
                        totalTrainingTime: 0,
                        totalSkillPoints: 0,
                        lastUpdated: Date(),
                        isPublic: false
                    )
                    skillPlans.append(newPlan)
                    SkillPlanFileManager.shared.saveSkillPlan(characterId: characterId, plan: newPlan)
                    newPlanName = ""
                }
            }
            .disabled(newPlanName.isEmpty)
            
            Button(NSLocalizedString("Main_EVE_Mail_Cancel", comment: ""), role: .cancel) {
                newPlanName = ""
            }
        } message: {
            Text(NSLocalizedString("Main_Skills_Plan_Name", comment: ""))
        }
        .task {
            // 加载已保存的技能计划
            skillPlans = SkillPlanFileManager.shared.loadSkillPlans(characterId: characterId)
        }
    }
    
    private func planRowView(_ plan: SkillPlan) -> some View {
        HStack(alignment: .center, spacing: 8) {
            // 左侧：计划名称和更新时间
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(plan.isPublic ? "\(plan.name)\(NSLocalizedString("Main_Skills_Plan_Public_Tag", comment: ""))" : plan.name)
                        .font(.headline)
                        .lineLimit(1)
                }
                
                Text(formatDate(plan.lastUpdated))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // 右侧：技能数量和训练时间
            VStack(alignment: .trailing, spacing: 4) {
                Text(String(format: "%d %@", plan.skills.count, NSLocalizedString("Main_Skills_Plan_Skills", comment: "")))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text(formatTimeInterval(plan.totalTrainingTime))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatDate(_ date: Date) -> String {
        let now = Date()
        let components = Calendar.current.dateComponents([.minute, .hour, .day], from: date, to: now)
        
        if let days = components.day {
            if days > 30 {
                // 超过30天显示具体日期
                let formatter = DateFormatter()
                formatter.dateFormat = NSLocalizedString("Date_Format_Month_Day", comment: "")
                return formatter.string(from: date)
            } else if days > 0 {
                return String(format: NSLocalizedString("Time_Days_Ago", comment: ""), days)
            }
        }
        
        if let hours = components.hour, hours > 0 {
            return String(format: NSLocalizedString("Time_Hours_Ago", comment: ""), hours)
        } else if let minutes = components.minute, minutes > 0 {
            return String(format: NSLocalizedString("Time_Minutes_Ago", comment: ""), minutes)
        } else {
            return NSLocalizedString("Time_Just_Now", comment: "")
        }
    }
    
    private func deletePlan(at offsets: IndexSet) {
        let planIdsToDelete = offsets.map { filteredPlans[$0].id }
        skillPlans.removeAll { plan in
            if planIdsToDelete.contains(plan.id) {
                SkillPlanFileManager.shared.deleteSkillPlan(characterId: characterId, plan: plan)
                return true
            }
            return false
        }
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
    @State private var isPublic = false  // 添加isPublic状态
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Form {
            Section {
                TextField(NSLocalizedString("Main_Skills_Plan_Name", comment: ""), text: $planName)
                Toggle(NSLocalizedString("Main_Skills_Plan_Set_Public", comment: ""), isOn: $isPublic)
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
                        totalSkillPoints: 0,
                        lastUpdated: Date(),
                        isPublic: isPublic
                    )
                    onAdd(newPlan)
                }
                .disabled(planName.isEmpty)
            }
        }
    } 
}

extension DateFormatter {
    static let iso8601Full: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
