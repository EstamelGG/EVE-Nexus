import BackgroundTasks
import Foundation

/// 后台任务管理器
/// 负责注册、调度和管理所有后台任务
@MainActor
class BackgroundTaskManager: ObservableObject {
    static let shared = BackgroundTaskManager()

    // 后台任务实例
    private let dataRefreshTask: DataRefreshTask
    private let assetJsonRefreshTask: AssetJsonRefreshTask
    private let contractRefreshTask: ContractRefreshTask
    private let structureOrdersRefreshTask: StructureOrdersRefreshTask
    private let industryRefreshTask: IndustryRefreshTask
    private let walletRefreshTask: WalletRefreshTask

    private init() {
        // 初始化任务实例
        dataRefreshTask = DataRefreshTask()
        assetJsonRefreshTask = AssetJsonRefreshTask()
        contractRefreshTask = ContractRefreshTask()
        structureOrdersRefreshTask = StructureOrdersRefreshTask()
        industryRefreshTask = IndustryRefreshTask()
        walletRefreshTask = WalletRefreshTask()

        // 注册所有后台任务
        registerBackgroundTasks()
    }

    /// 注册所有后台任务
    private func registerBackgroundTasks() {
        // 注册数据刷新任务
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: DataRefreshTask.identifier,
            using: nil
        ) { task in
            Logger.info("数据刷新任务被系统触发")
            Task { @MainActor in
                self.dataRefreshTask.handle(task: task as! BGAppRefreshTask)
            }
        }

        // 注册资产JSON更新任务（使用 BGProcessingTask 以获得更长的执行时间）
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: AssetJsonRefreshTask.identifier,
            using: nil
        ) { task in
            Logger.info("资产JSON更新任务被系统触发")
            Task { @MainActor in
                self.assetJsonRefreshTask.handle(task: task as! BGProcessingTask)
            }
        }

        // 注册合同数据更新任务（使用 BGProcessingTask 以获得更长的执行时间）
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: ContractRefreshTask.identifier,
            using: nil
        ) { task in
            Logger.info("合同数据更新任务被系统触发")
            Task { @MainActor in
                self.contractRefreshTask.handle(task: task as! BGProcessingTask)
            }
        }

        // 注册建筑市场订单更新任务（使用 BGProcessingTask 以获得更长的执行时间）
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: StructureOrdersRefreshTask.identifier,
            using: nil
        ) { task in
            Logger.info("建筑市场订单更新任务被系统触发")
            Task { @MainActor in
                self.structureOrdersRefreshTask.handle(task: task as! BGProcessingTask)
            }
        }

        // 注册工业项目数据更新任务（使用 BGProcessingTask 以获得更长的执行时间）
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: IndustryRefreshTask.identifier,
            using: nil
        ) { task in
            Logger.info("工业项目数据更新任务被系统触发")
            Task { @MainActor in
                self.industryRefreshTask.handle(task: task as! BGProcessingTask)
            }
        }

        // 注册钱包数据更新任务（使用 BGProcessingTask 以获得更长的执行时间）
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: WalletRefreshTask.identifier,
            using: nil
        ) { task in
            Logger.info("钱包数据更新任务被系统触发")
            Task { @MainActor in
                self.walletRefreshTask.handle(task: task as! BGProcessingTask)
            }
        }

        Logger.info("后台任务注册完成，标识符: \(DataRefreshTask.identifier), \(AssetJsonRefreshTask.identifier), \(ContractRefreshTask.identifier), \(StructureOrdersRefreshTask.identifier), \(IndustryRefreshTask.identifier), \(WalletRefreshTask.identifier)")
    }

    /// 安排数据刷新任务
    func scheduleDataRefresh() {
        dataRefreshTask.schedule()
    }

    /// 安排资产JSON更新任务
    func scheduleAssetJsonRefresh() {
        assetJsonRefreshTask.schedule()
    }

    /// 安排合同数据更新任务
    func scheduleContractRefresh() {
        contractRefreshTask.schedule()
    }

    /// 安排建筑市场订单更新任务
    func scheduleStructureOrdersRefresh() {
        structureOrdersRefreshTask.schedule()
    }

    /// 安排工业项目数据更新任务
    func scheduleIndustryRefresh() {
        industryRefreshTask.schedule()
    }

    /// 安排钱包数据更新任务
    func scheduleWalletRefresh() {
        walletRefreshTask.schedule()
    }
}
