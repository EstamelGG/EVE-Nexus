import BackgroundTasks
import Foundation

/// 后台任务协议，定义所有后台任务需要实现的方法
@MainActor
protocol BackgroundTaskProtocol {
    /// 任务标识符
    var identifier: String { get }

    /// 任务执行间隔（秒）
    var interval: TimeInterval { get }

    /// 执行任务
    func perform() async

    /// 处理任务被系统触发
    func handle(task: BGAppRefreshTask)
}

/// 处理任务协议，用于需要更长执行时间的后台任务
@MainActor
protocol ProcessingTaskProtocol {
    /// 任务标识符
    var identifier: String { get }

    /// 任务执行间隔（秒），BGProcessingTask 最小间隔为 15 分钟
    var interval: TimeInterval { get }

    /// 执行任务
    func perform() async

    /// 处理任务被系统触发
    func handle(task: BGProcessingTask)
}

/// 通用后台任务协议，用于统一管理不同类型的后台任务
@MainActor
protocol AnyBackgroundTask {
    /// 任务标识符
    var identifier: String { get }

    /// 取消任务
    func cancel()

    /// 安排任务
    func schedule()
}

/// 后台任务基类，提供通用功能
@MainActor
class BaseBackgroundTask: BackgroundTaskProtocol, AnyBackgroundTask {
    let identifier: String
    let interval: TimeInterval
    private var task: Task<Void, Never>?

    init(identifier: String, interval: TimeInterval) {
        self.identifier = identifier
        self.interval = interval
    }

    /// 执行任务（子类需要实现）
    func perform() async {
        fatalError("子类必须实现 perform() 方法")
    }

    /// 处理任务被系统触发
    func handle(task: BGAppRefreshTask) {
        Logger.notice("开始执行后台任务: \(identifier)")

        // 安排下一次任务
        schedule()

        // 创建执行任务
        self.task = Task {
            await perform()

            // 通知系统后台任务已完成
            task.setTaskCompleted(success: true)
            Logger.info("后台任务完成: \(identifier)")
        }

        // 提供过期处理器
        task.expirationHandler = {
            Logger.warning("后台任务已过期，取消任务: \(self.identifier)")
            self.task?.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    /// 安排任务
    func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)

        do {
            try BGTaskScheduler.shared.submit(request)

            // 格式化日期为本地时区显示
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .medium
            dateFormatter.timeZone = TimeZone.current
            dateFormatter.locale = Locale.current

            let formattedDate = request.earliestBeginDate.map { dateFormatter.string(from: $0) } ?? "未知"
            Logger.success("后台任务已安排: \(identifier) - \(formattedDate)")
        } catch {
            Logger.error("安排后台任务失败: \(identifier), 错误: \(error)")
        }
    }

    /// 取消任务
    func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        task?.cancel()
        Logger.warning("后台任务已取消: \(identifier)")
    }
}

/// 处理任务基类，提供更长的执行时间
/// 使用 BGProcessingTask 而不是 BGAppRefreshTask，可以获得更长的执行时间窗口
@MainActor
class BaseProcessingTask: ProcessingTaskProtocol, AnyBackgroundTask {
    let identifier: String
    let interval: TimeInterval
    private var task: Task<Void, Never>?

    init(identifier: String, interval: TimeInterval) {
        self.identifier = identifier
        // BGProcessingTask 最小间隔为 15 分钟，确保符合要求
        self.interval = max(interval, 15 * 60)
    }

    /// 执行任务（子类需要实现）
    func perform() async {
        fatalError("子类必须实现 perform() 方法")
    }

    /// 处理任务被系统触发
    func handle(task: BGProcessingTask) {
        Logger.notice("开始执行后台处理任务: \(identifier)")

        // 安排下一次任务
        schedule()

        // 创建执行任务
        self.task = Task {
            await perform()

            // 通知系统后台任务已完成
            task.setTaskCompleted(success: true)
            Logger.info("后台处理任务完成: \(identifier)")
        }

        // 提供过期处理器
        task.expirationHandler = {
            Logger.warning("后台处理任务已过期，取消任务: \(self.identifier)")
            self.task?.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    /// 安排任务
    func schedule() {
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        // 设置任务需要网络连接
        request.requiresNetworkConnectivity = true
        // 设置任务需要外部电源（可选，有助于获得更长的执行时间）
        request.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(request)

            // 格式化日期为本地时区显示
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .medium
            dateFormatter.timeZone = TimeZone.current
            dateFormatter.locale = Locale.current

            let formattedDate = request.earliestBeginDate.map { dateFormatter.string(from: $0) } ?? "未知"
            Logger.success("后台处理任务已安排: \(identifier) - \(formattedDate)")
        } catch {
            Logger.error("安排后台处理任务失败: \(identifier), 错误: \(error)")
        }
    }

    /// 取消任务
    func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        task?.cancel()
        Logger.warning("后台处理任务已取消: \(identifier)")
    }
}
