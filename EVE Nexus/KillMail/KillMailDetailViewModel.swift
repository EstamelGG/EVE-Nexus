import Foundation

class KillMailDetailViewModel: ObservableObject {
    @Published var killMailDetails: [Int: KillMailDetail] = [:]
    @Published var isLoading = false
    private let concurrentLimit = 5
    private var taskQueue: [Task<Void, Never>] = []
    
    func fetchDetails(for killMails: [KillMailInfo]) {
        guard !isLoading else { return }
        isLoading = true
        
        // 清除之前的任务
        taskQueue.forEach { $0.cancel() }
        taskQueue.removeAll()
        
        // 按killmail_id排序，确保顺序一致
        let sortedKillMails = killMails.sorted { $0.killmail_id > $1.killmail_id }
        
        // 创建信号量来限制并发数
        let semaphore = DispatchSemaphore(value: concurrentLimit)
        
        for killMail in sortedKillMails {
            let task = Task {
                // 等待信号量
                await withCheckedContinuation { continuation in
                    DispatchQueue.global().async {
                        semaphore.wait()
                        continuation.resume()
                    }
                }
                
                defer {
                    // 释放信号量
                    semaphore.signal()
                }
                
                do {
                    let detail = try await ZKillMailsAPI.shared.fetchKillMailDetail(
                        killmailId: killMail.killmail_id,
                        killmailHash: killMail.killmail_hash
                    )
                    
                    await MainActor.run {
                        self.killMailDetails[killMail.killmail_id] = detail
                    }
                } catch {
                    Logger.error("获取击杀详情失败 - ID: \(killMail.killmail_id), 错误: \(error)")
                }
            }
            taskQueue.append(task)
        }
        
        // 等待所有任务完成
        Task {
            await withTaskGroup(of: Void.self) { group in
                for task in taskQueue {
                    group.addTask {
                        await task.value
                    }
                }
                await group.waitForAll()
            }
            
            await MainActor.run {
                self.isLoading = false
            }
        }
    }
    
    func getDetail(for killMailId: Int) -> KillMailDetail? {
        return killMailDetails[killMailId]
    }
    
    func cancelAllTasks() {
        taskQueue.forEach { $0.cancel() }
        taskQueue.removeAll()
    }
} 