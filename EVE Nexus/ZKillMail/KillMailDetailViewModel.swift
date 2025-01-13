import Foundation

@MainActor
class KillMailDetailViewModel: ObservableObject {
    @Published private(set) var killMailDetails: [Int: KillMailDetail] = [:]
    @Published private(set) var loadingIds: Set<Int> = []
    private let concurrentLimit = 5
    private var taskQueue: [Task<Void, Never>] = []
    private var pendingKillMails: [KillMailInfo] = []
    private var isProcessingQueue = false
    
    // 取消所有正在进行的任务
    func cancelAllTasks() {
        taskQueue.forEach { $0.cancel() }
        taskQueue.removeAll()
        pendingKillMails.removeAll()
        isProcessingQueue = false
        loadingIds.removeAll()
    }
    
    // 请求加载指定的击杀记录详情
    func requestDetails(for killMails: [KillMailInfo]) {
        // 过滤掉已经有详情的记录
        let newKillMails = killMails.filter { killMailId in
            !killMailDetails.keys.contains(killMailId.killmail_id) &&
            !loadingIds.contains(killMailId.killmail_id)
        }
        
        // 将新的请求添加到待处理队列
        pendingKillMails.append(contentsOf: newKillMails)
        
        // 如果没有正在处理队列，则开始处理
        if !isProcessingQueue {
            processQueue()
        }
    }
    
    // 处理待处理队列
    private func processQueue() {
        guard !isProcessingQueue else { return }
        isProcessingQueue = true
        
        Task {
            while !pendingKillMails.isEmpty {
                // 如果当前加载数量已达到限制，等待一段时间后继续检查
                if loadingIds.count >= concurrentLimit {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
                    continue
                }
                
                // 从队列中取出一个记录
                guard let killMail = pendingKillMails.first else { break }
                pendingKillMails.removeFirst()
                
                // 再次检查是否已经有详情或正在加载
                guard !killMailDetails.keys.contains(killMail.killmail_id),
                      !loadingIds.contains(killMail.killmail_id) else {
                    continue
                }
                
                // 创建加载任务
                let task = Task {
                    loadingIds.insert(killMail.killmail_id)
                    
                    do {
                        let detail = try await ZKillMailsAPI.shared.fetchKillMailDetail(
                            killmailId: killMail.killmail_id,
                            killmailHash: killMail.killmail_hash
                        )
                        
                        if !Task.isCancelled {
                            killMailDetails[killMail.killmail_id] = detail
                            loadingIds.remove(killMail.killmail_id)
                        }
                    } catch {
                        Logger.error("获取击杀详情失败 - ID: \(killMail.killmail_id), 错误: \(error)")
                        loadingIds.remove(killMail.killmail_id)
                    }
                }
                
                taskQueue.append(task)
            }
            
            // 等待所有任务完成
            for task in taskQueue {
                await task.value
            }
            
            taskQueue.removeAll()
            isProcessingQueue = false
        }
    }
    
    // 获取指定ID的详情
    func getDetail(for killMailId: Int) -> KillMailDetail? {
        return killMailDetails[killMailId]
    }
    
    // 检查指定ID是否正在加载
    func isLoading(for killMailId: Int) -> Bool {
        return loadingIds.contains(killMailId)
    }
} 