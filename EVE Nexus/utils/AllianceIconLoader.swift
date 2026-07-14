import SwiftUI

/// 联盟图标加载器
class AllianceIconLoader: ObservableObject {
    @Published var icons: [Int: Image] = [:]
    @Published var loadingIconIds: Set<Int> = []
    private var tasks: [Int: Task<Void, Never>] = [:]
    private var pendingIds: [Int] = []
    private let maxConcurrentTasks = 5 // 最大并发

    func loadIcon(for id: Int) {
        guard !icons.keys.contains(id), !loadingIconIds.contains(id) else { return }

        // 如果已经有maxConcurrentTasks个任务在执行，则加入等待队列
        if loadingIconIds.count >= maxConcurrentTasks {
            if !pendingIds.contains(id) {
                pendingIds.append(id)
            }
            return
        }

        loadingIconIds.insert(id)

        let task = Task {
            do {
                let allianceImage = try await AllianceAPI.shared.fetchAllianceLogo(
                    allianceID: id,
                    size: 64,
                    forceRefresh: false
                )

                try Task.checkCancellation()

                _ = await MainActor.run {
                    icons[id] = Image(uiImage: allianceImage)
                    loadingIconIds.remove(id)

                    // 检查等待队列，继续加载下一个
                    checkPendingQueue()
                }
            } catch {
                if !Task.isCancelled {
                    Logger.error("加载联盟图标失败: \(error.localizedDescription)")
                    _ = await MainActor.run {
                        loadingIconIds.remove(id)

                        // 即使失败也要继续加载等待队列中的下一个
                        checkPendingQueue()
                    }
                }
            }
        }

        tasks[id] = task
    }

    private func checkPendingQueue() {
        // 从等待队列中取出下一个ID并加载
        if let nextId = pendingIds.first, loadingIconIds.count < maxConcurrentTasks {
            pendingIds.removeFirst()
            loadIcon(for: nextId)
        }
    }

    func loadIcons(for ids: [Int]) {
        for id in ids {
            loadIcon(for: id)
        }
    }

    func cancelAllTasks() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        pendingIds.removeAll()
        loadingIconIds.removeAll()
    }

    deinit {
        cancelAllTasks()
    }
}
