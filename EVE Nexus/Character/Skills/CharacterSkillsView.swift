import SwiftUI

struct CharacterSkillsView: View {
    let characterId: Int
    @State private var skillQueue: [SkillQueueItem] = []
    @State private var skillNames: [Int: String] = [:]
    
    var body: some View {
        List {
            // 第一个列表 - 两个可点击单元格
            Section {
                NavigationLink(destination: Text("技能详情")) {
                    Text("技能详情")
                }
                NavigationLink(destination: Text("技能组详情")) {
                    Text("技能组详情")
                }
            }
            
            // 第二个列表 - 技能队列
            Section(header: Text("技能队列")) {
                ForEach(skillQueue.filter { $0.finish_date?.timeIntervalSinceNow ?? -1 > 0 }
                    .sorted { $0.queue_position < $1.queue_position }, id: \.queue_position) { item in
                    VStack(alignment: .leading) {
                        HStack {
                            Text(skillNames[item.skill_id] ?? "未知技能")
                                .font(.headline)
                            Spacer()
                            Text("Lv\(item.finished_level)")
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            // 显示技能点进度
                            if let progress = calculateProgress(item) {
                                Text("\(Int(progress.current))SP/\(progress.total)SP")
                                    .font(.caption)
                                Spacer()
                                if let remainingTime = item.remainingTime {
                                    Text(formatTimeInterval(remainingTime))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        // 进度条
                        if let progress = calculateProgress(item) {
                            ProgressView(value: progress.percentage)
                                .progressViewStyle(LinearProgressViewStyle())
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .onAppear {
            loadSkillQueue()
        }
    }
    
    private func loadSkillQueue() {
        Task {
            do {
                // 加载技能队列
                skillQueue = try await CharacterSkillsAPI.shared.fetchSkillQueue(characterId: characterId)
                
                // 加载技能名称
                for item in skillQueue {
                    let query = "SELECT itemName FROM invTypes WHERE typeID = ?"
                    if case .success(let rows) = CharacterDatabaseManager.shared.executeQuery(query, parameters: [item.skill_id]),
                       let row = rows.first,
                       let name = row["itemName"] as? String {
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
        guard let startDate = item.start_date,
              let finishDate = item.finish_date,
              let levelStartSp = item.level_start_sp,
              let levelEndSp = item.level_end_sp,
              let trainingStartSp = item.training_start_sp else {
            return nil
        }
        
        let now = Date()
        let totalTrainingTime = finishDate.timeIntervalSince(startDate)
        let trainedTime = now.timeIntervalSince(startDate)
        let timeProgress = trainedTime / totalTrainingTime
        
        let remainingSP = levelEndSp - trainingStartSp
        let trainedSP = Double(remainingSP) * timeProgress
        let currentSP = Double(trainingStartSp) + trainedSP
        
        return ProgressInfo(
            current: currentSP,
            total: levelEndSp,
            percentage: currentSP / Double(levelEndSp)
        )
    }
    
    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        let days = Int(interval) / (24 * 3600)
        let hours = Int(interval) / 3600 % 24
        let minutes = Int(interval) / 60 % 60
        
        if days > 0 {
            return "\(days)天 \(hours)小时"
        } else if hours > 0 {
            return "\(hours)小时 \(minutes)分"
        } else {
            return "\(minutes)分"
        }
    }
}