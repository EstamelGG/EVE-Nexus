import SwiftUI

struct CharacterSkillsView: View {
    let characterId: Int
    let databaseManager: DatabaseManager
    @State private var skillQueue: [SkillQueueItem] = []
    @State private var skillNames: [Int: String] = [:]
    
    private var activeSkills: [SkillQueueItem] {
        skillQueue.sorted { $0.queue_position < $1.queue_position }
    }
    
    private var isQueuePaused: Bool {
        guard let firstSkill = activeSkills.first,
              firstSkill.isCurrentlyTraining else {
            return true
        }
        return false
    }
    
    private var totalRemainingTime: TimeInterval? {
        guard let lastSkill = activeSkills.last,
              let finishDate = lastSkill.finish_date,
              finishDate.timeIntervalSinceNow > 0 else {
            return nil
        }
        return finishDate.timeIntervalSinceNow
    }
    
    // 获取技能的当前等级（队列中最低等级-1）
    private func getCurrentLevel(for skillId: Int) -> Int {
        let minLevel = activeSkills
            .filter { $0.skill_id == skillId }
            .map { $0.finished_level }
            .min() ?? 1
        return minLevel - 1
    }
    
    var body: some View {
        List {
            // 第一个列表 - 两个可点击单元格
            Section {
                NavigationLink {
                    Text(NSLocalizedString("Main_Skills_Attribute", comment: ""))
                } label: {
                    Text(NSLocalizedString("Main_Skills_Attribute", comment: ""))
                }
                .frame(height: 36)
                
                NavigationLink {
                    Text(NSLocalizedString("Main_Skills_Groups", comment: ""))
                } label: {
                    Text(NSLocalizedString("Main_Skills_Groups", comment: ""))
                }
                .frame(height: 36)
            } header: {
                Text(NSLocalizedString("Main_Skills_Categories", comment: ""))
            }
            
            // 第二个列表 - 技能队列
            Section {
                if skillQueue.isEmpty {
                    Text(NSLocalizedString("Main_Skills_Queue_Empty", comment: ""))
                        .foregroundColor(.secondary)
                        .frame(height: 36)
                } else {
                    ForEach(activeSkills) { item in
                        NavigationLink {
                            // 跳转到物品信息页面
                            ShowItemInfo(
                                databaseManager: databaseManager,
                                itemID: item.skill_id
                            )
                        } label: {
                            HStack(spacing: 8) {
                                IconManager.shared.loadImage(for: "icon_2403_64.png")
                                    .resizable()
                                    .frame(width: 36, height: 36)
                                    .cornerRadius(6)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 2) {
                                        Text(skillNames[item.skill_id] ?? NSLocalizedString("Main_Database_Loading", comment: ""))
                                            .font(.headline)
                                            .lineLimit(1)
                                        Spacer()
                                        // 添加等级指示器
                                        Text(String(format: NSLocalizedString("Main_Skills_Level", comment: ""), item.finished_level))
                                            .foregroundColor(.secondary)
                                            .font(.caption)
                                            .padding(.trailing, 2)
                                        SkillLevelIndicator(
                                            currentLevel: getCurrentLevel(for: item.skill_id),
                                            trainingLevel: item.finished_level,
                                            isTraining: item.isCurrentlyTraining
                                        )
                                        .padding(.trailing, 4)
                                    }
                                    
                                    if let progress = calculateProgress(item) {
                                        HStack(spacing: 2) {
                                            Text(String(format: NSLocalizedString("Main_Skills_Points_Progress", comment: ""), 
                                                      formatNumber(Int(progress.current)), 
                                                      formatNumber(progress.total)))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Spacer()
                                            if item.isCurrentlyTraining {
                                                if let remainingTime = item.remainingTime {
                                                    Text(String(format: NSLocalizedString("Main_Skills_Time_Remaining", comment: ""), 
                                                              formatTimeInterval(remainingTime)))
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                            } else if let startDate = item.start_date,
                                                      let finishDate = item.finish_date {
                                                let trainingTime = finishDate.timeIntervalSince(startDate)
                                                Text(String(format: NSLocalizedString("Main_Skills_Time_Required", comment: ""), 
                                                          formatTimeInterval(trainingTime)))
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        
                                        // 只对正在训练的技能显示进度条
                                        if item.isCurrentlyTraining {
                                            ProgressView(value: progress.percentage)
                                                .progressViewStyle(LinearProgressViewStyle())
                                                .padding(.top, 1)
                                        }
                                    }
                                }
                            }
                        }
                        .frame(height: item.isCurrentlyTraining ? 44 : 36)
                    }
                }
            } header: {
                if skillQueue.isEmpty {
                    Text(String(format: NSLocalizedString("Main_Skills_Queue_Count", comment: ""), 0))
                } else if isQueuePaused {
                    Text(String(format: NSLocalizedString("Main_Skills_Queue_Count_Paused", comment: ""),
                              activeSkills.count))
                } else if let totalTime = totalRemainingTime {
                    Text(String(format: NSLocalizedString("Main_Skills_Queue_Count_Time", comment: ""),
                              activeSkills.count,
                              formatTimeInterval(totalTime)))
                } else {
                    Text(String(format: NSLocalizedString("Main_Skills_Queue_Count", comment: ""),
                              activeSkills.count))
                }
            }
        }
        .onAppear {
            loadSkillQueue()
        }
    }
    
    private func formatTimeComponents(_ interval: TimeInterval) -> (days: Int, hours: Int, minutes: Int) {
        let days = Int(interval) / (24 * 3600)
        let hours = Int(interval) / 3600 % 24
        let minutes = Int(interval) / 60 % 60
        return (days, hours, minutes)
    }
    
    private func loadSkillQueue() {
        Task {
            do {
                // 加载技能队列
                skillQueue = try await CharacterSkillsAPI.shared.fetchSkillQueue(characterId: characterId)
                
                // 加载技能名称
                for item in skillQueue {
                    let query = "SELECT name FROM types WHERE type_id = ?"
                    if case .success(let rows) = databaseManager.executeQuery(query, parameters: [item.skill_id]),
                       let row = rows.first,
                       let name = row["name"] as? String {
                        skillNames[item.skill_id] = name
                    }
                }
            } catch {
                Logger.error("加载技能队列失败: \(error)")
            }
        }
    }
    
    private struct ProgressInfo {
        let current: Double
        let total: Int
        let percentage: Double
    }
    
    private func calculateProgress(_ item: SkillQueueItem) -> ProgressInfo? {
        guard let levelEndSp = item.level_end_sp,
              let trainingStartSp = item.training_start_sp else {
            return nil
        }
        
        var currentSP = Double(trainingStartSp)
        
        // 如果技能正在训练中，计算当前进度
        if let startDate = item.start_date,
           let finishDate = item.finish_date {
            let now = Date()
            
            // 如果还没开始训练
            if now < startDate {
                currentSP = Double(trainingStartSp)
            }
            // 如果已经完成训练
            else if now > finishDate {
                currentSP = Double(levelEndSp)
            }
            // 正在训练中
            else {
                let totalTrainingTime = finishDate.timeIntervalSince(startDate)
                let trainedTime = now.timeIntervalSince(startDate)
                let timeProgress = trainedTime / totalTrainingTime
                
                let remainingSP = levelEndSp - trainingStartSp
                let trainedSP = Double(remainingSP) * timeProgress
                currentSP = Double(trainingStartSp) + trainedSP
            }
        }
        
        return ProgressInfo(
            current: currentSP,
            total: levelEndSp,
            percentage: currentSP / Double(levelEndSp)
        )
    }
    
    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        let components = formatTimeComponents(interval)
        
        if components.days > 0 {
            if components.hours > 0 {
                return String(format: NSLocalizedString("Time_Days_Hours", comment: ""), 
                            components.days, components.hours)
            } else {
                return String(format: NSLocalizedString("Time_Days", comment: ""), 
                            components.days)
            }
        } else if components.hours > 0 {
            if components.minutes > 0 {
                return String(format: NSLocalizedString("Time_Hours_Minutes", comment: ""), 
                            components.hours, components.minutes)
            } else {
                return String(format: NSLocalizedString("Time_Hours", comment: ""), 
                            components.hours)
            }
        } else {
            return String(format: NSLocalizedString("Time_Minutes", comment: ""), 
                        components.minutes)
        }
    }
    
    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: number)) ?? String(number)
    }
}
