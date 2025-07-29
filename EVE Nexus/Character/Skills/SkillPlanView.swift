import Foundation
import SwiftUI

struct SkillPlan: Identifiable {
    let id: UUID
    var name: String
    var skills: [PlannedSkill]
    var totalTrainingTime: TimeInterval
    var totalSkillPoints: Int
    var lastUpdated: Date
}

struct PlannedSkill: Identifiable {
    let id: UUID
    let skillID: Int
    let skillName: String
    let currentLevel: Int
    let targetLevel: Int
    var trainingTime: TimeInterval
    var requiredSP: Int
    var prerequisites: [PlannedSkill]
    var currentSkillPoints: Int?
    var isCompleted: Bool
}

struct SkillPlanData: Codable {
    let name: String
    let lastUpdated: Date
    var skills: [String]  // 格式: "type_id:level"
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
            try FileManager.default.createDirectory(
                at: skillPlansDirectory, withIntermediateDirectories: true
            )
        } catch {
            Logger.error("创建技能计划目录失败: \(error)")
        }
    }

    func saveSkillPlan(characterId: Int, plan: SkillPlan) {
        let fileName = "\(plan.id).json"
        let fileURL = skillPlansDirectory.appendingPathComponent(fileName)

        // 检查文件是否存在，如果存在则读取当前内容进行对比
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                let existingData = try Data(contentsOf: fileURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .formatted(DateFormatter.iso8601Full)
                let existingPlanData = try decoder.decode(SkillPlanData.self, from: existingData)

                // 创建新的计划数据，但保持原有的lastUpdated
                let newPlanData = SkillPlanData(
                    name: plan.name,
                    lastUpdated: existingPlanData.lastUpdated,  // 保持原有的lastUpdated
                    skills: plan.skills.map { "\($0.skillID):\($0.targetLevel)" }
                )

                // 比较内容是否相同（除了lastUpdated）
                if existingPlanData.name == newPlanData.name,
                    Set(existingPlanData.skills) == Set(newPlanData.skills)
                {
                    Logger.debug("技能计划内容未变化，跳过保存: \(fileName)")
                    return
                }
            } catch {
                Logger.error("读取现有技能计划失败: \(error)")
            }
        }

        // 如果文件不存在或内容有变化，则创建新的计划数据并保存
        let planData = SkillPlanData(
            name: plan.name,
            lastUpdated: Date(),  // 只有在内容真正变化时才更新时间
            skills: plan.skills.map { "\($0.skillID):\($0.targetLevel)" }
        )

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

    func loadSkillPlans(
        characterId: Int, databaseManager _: DatabaseManager,
        learnedSkills _: [Int: CharacterSkill] = [:]
    ) -> [SkillPlan] {
        let fileManager = FileManager.default

        do {
            Logger.debug("开始加载技能计划，角色ID: \(characterId)")
            let files = try fileManager.contentsOfDirectory(
                at: skillPlansDirectory, includingPropertiesForKeys: nil
            )
            Logger.debug("找到文件数量: \(files.count)")

            let plans = files.filter { url in
                return url.pathExtension == "json"
            }.compactMap { url -> SkillPlan? in
                do {
                    Logger.debug("尝试解析文件: \(url.lastPathComponent)")
                    let data = try Data(contentsOf: url)

                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .formatted(DateFormatter.iso8601Full)
                    let planData = try decoder.decode(SkillPlanData.self, from: data)

                    let fileName = url.lastPathComponent
                    let planIdString = fileName.replacingOccurrences(of: ".json", with: "")
                    
                    // 尝试解析UUID，支持新旧格式
                    var planId: UUID?
                    planId = UUID(uuidString: planIdString)
                    
                    // 如果无法解析，可能是旧格式文件，尝试提取UUID部分
                    if planId == nil {
                        let components = planIdString.split(separator: "_")
                        if components.count >= 2 {
                            let uuidPart = components.dropFirst().joined(separator: "_")
                            planId = UUID(uuidString: uuidPart)
                        }
                    }

                    guard let validPlanId = planId else {
                        Logger.error("无效的计划ID: \(planIdString)")
                        try? FileManager.default.removeItem(at: url)
                        return nil
                    }

                    // 在列表页面只创建基本的技能对象，不查询数据库
                    let skills = planData.skills.compactMap { skillString -> PlannedSkill? in
                        let components = skillString.split(separator: ":")
                        guard components.count == 2,
                            let typeId = Int(components[0]),
                            let level = Int(components[1])
                        else {
                            return nil
                        }

                        return PlannedSkill(
                            id: UUID(),
                            skillID: typeId,
                            skillName: "Unknown Skill (\(typeId))",  // 使用临时名称
                            currentLevel: 0,  // 使用默认值
                            targetLevel: level,
                            trainingTime: 0,
                            requiredSP: 0,
                            prerequisites: [],
                            currentSkillPoints: nil,
                            isCompleted: false
                        )
                    }

                    let plan = SkillPlan(
                        id: validPlanId,
                        name: planData.name,
                        skills: skills,
                        totalTrainingTime: 0,
                        totalSkillPoints: 0,
                        lastUpdated: planData.lastUpdated
                    )

                    Logger.debug("成功创建技能计划对象: \(plan.name)")
                    return plan

                } catch {
                    Logger.error("读取技能计划失败: \(error.localizedDescription)")
                    if let decodingError = error as? DecodingError {
                        switch decodingError {
                        case let .dataCorrupted(context):
                            Logger.error("数据损坏: \(context.debugDescription)")
                        case let .keyNotFound(key, context):
                            Logger.error("未找到键: \(key.stringValue), 路径: \(context.codingPath)")
                        case let .typeMismatch(type, context):
                            Logger.error("类型不匹配: 期望 \(type), 路径: \(context.codingPath)")
                        case let .valueNotFound(type, context):
                            Logger.error("值未找到: 类型 \(type), 路径: \(context.codingPath)")
                        @unknown default:
                            Logger.error("未知解码错误: \(decodingError)")
                        }
                    }
                    try? FileManager.default.removeItem(at: url)
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
        let fileName = "\(plan.id).json"
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
    @State private var newPlanName = ""
    @State private var searchText = ""
    @State private var learnedSkills: [Int: CharacterSkill] = [:]  // 添加已学习技能的状态变量

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
                        SkillPlanDetailView(
                            plan: plan,
                            characterId: characterId,
                            databaseManager: databaseManager,
                            skillPlans: $skillPlans
                        )
                    } label: {
                        planRowView(plan)
                    }
                }
                .onDelete(perform: deletePlan)
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            }
        }
        .navigationTitle(NSLocalizedString("Main_Skills_Plan", comment: ""))
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: NSLocalizedString("Main_Database_Search", comment: "")
        )
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
        .alert(
            NSLocalizedString("Main_Skills_Plan_Add", comment: ""), isPresented: $isShowingAddAlert
        ) {
            TextField(NSLocalizedString("Main_Skills_Plan_Name", comment: ""), text: $newPlanName)

            Button(NSLocalizedString("Main_Skills_Plan_Add", comment: "")) {
                if !newPlanName.isEmpty {
                    let newPlan = SkillPlan(
                        id: UUID(),
                        name: newPlanName,
                        skills: [],
                        totalTrainingTime: 0,
                        totalSkillPoints: 0,
                        lastUpdated: Date()
                    )
                    skillPlans.append(newPlan)
                    SkillPlanFileManager.shared.saveSkillPlan(
                        characterId: characterId, plan: newPlan
                    )
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
            // 先加载角色已学习的技能
            await loadLearnedSkills()
            // 然后加载已保存的技能计划
            skillPlans = SkillPlanFileManager.shared.loadSkillPlans(
                characterId: characterId,
                databaseManager: databaseManager,
                learnedSkills: learnedSkills  // 传入已学习的技能
            )
        }
    }

    private func planRowView(_ plan: SkillPlan) -> some View {
        HStack(alignment: .center, spacing: 8) {
            // 左侧：计划名称和更新时间
            VStack(alignment: .leading, spacing: 4) {
                Text(plan.name)
                    .font(.headline)
                    .lineLimit(1)

                Text(formatDate(plan.lastUpdated))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // 右侧：技能数量和训练时间
            VStack(alignment: .trailing, spacing: 4) {
                Text(
                    String(
                        format: "%d %@", plan.skills.count,
                        NSLocalizedString("Main_Skills_Plan_Skills", comment: "")
                    )
                )
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDate(_ date: Date) -> String {
        let now = Date()
        let components = Calendar.current.dateComponents(
            [.minute, .hour, .day], from: date, to: now
        )

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

    // 添加加载已学习技能的方法
    private func loadLearnedSkills() async {
        do {
            // 调用API获取技能数据
            let skillsResponse = try await CharacterSkillsAPI.shared.fetchCharacterSkills(
                characterId: characterId, 
                forceRefresh: false
            )

            // 创建技能ID到技能信息的映射
            learnedSkills = Dictionary(
                uniqueKeysWithValues: skillsResponse.skills.map { ($0.skill_id, $0) })
            Logger.debug("成功加载角色技能数量: \(learnedSkills.count)")
        } catch {
            Logger.error("获取技能数据失败: \(error)")
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
