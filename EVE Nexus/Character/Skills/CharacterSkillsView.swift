import SwiftUI

struct CharacterSkillsView: View {
    let characterId: Int
    let databaseManager: DatabaseManager
    @State private var skillQueue: [SkillQueueItem] = []
    @State private var skillNames: [Int: String] = [:]
    
    private var activeSkills: [SkillQueueItem] {
        skillQueue
            .filter { $0.finish_date?.timeIntervalSinceNow ?? -1 > 0 }
            .sorted { $0.queue_position < $1.queue_position }
    }
    
    var body: some View {
        List {
            // 第一个列表 - 两个可点击单元格
            Section {
                NavigationLink {
                    Text(NSLocalizedString("Main_Skills_Details", comment: ""))
                } label: {
                    Text(NSLocalizedString("Main_Skills_Details", comment: ""))
                }
                NavigationLink {
                    Text(NSLocalizedString("Main_Skills_Groups", comment: ""))
                } label: {
                    Text(NSLocalizedString("Main_Skills_Groups", comment: ""))
                }
            } header: {
                Text(NSLocalizedString("Main_Skills_Categories", comment: ""))
            }
            
            // 第二个列表 - 技能队列
            Section {
                if skillQueue.isEmpty {
                    Text(NSLocalizedString("Main_Skills_Queue_Empty", comment: ""))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(activeSkills) { item in
                        VStack(alignment: .leading) {
                            HStack {
                                Text(skillNames[item.skill_id] ?? NSLocalizedString("Main_Database_Loading", comment: ""))
                                    .font(.headline)
                                Spacer()
                                Text(String(format: NSLocalizedString("Main_Skills_Level", comment: ""), item.finished_level))
                                    .foregroundColor(.secondary)
                                // 添加等级指示器
                                SkillLevelIndicator(
                                    currentLevel: item.training_start_level,
                                    trainingLevel: item.finished_level,
                                    isTraining: item.isCurrentlyTraining
                                )
                                .padding(.trailing, 4)
                            }
                            
                            if let progress = calculateProgress(item) {
                                HStack {
                                    Text(String(format: NSLocalizedString("Main_Skills_Points_Progress", comment: ""), 
                                              Int(progress.current), progress.total))
                                        .font(.caption)
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
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            } header: {
                Text(NSLocalizedString("Main_Skills_Queue", comment: ""))
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
            return String(format: NSLocalizedString("Time_Days_Hours_Minutes", comment: ""), 
                        components.days, components.hours, components.minutes)
        } else if components.hours > 0 {
            return String(format: NSLocalizedString("Time_Hours_Minutes", comment: ""), 
                        components.hours, components.minutes)
        } else {
            return String(format: NSLocalizedString("Time_Minutes", comment: ""), 
                        components.minutes)
        }
    }
}

#Preview {
    CharacterSkillsView(characterId: 0, databaseManager: DatabaseManager())
}
