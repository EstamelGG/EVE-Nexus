import Combine
import Foundation

/// 删除缓存项，包含删除时间信息
struct DeletedFittingItem {
    let fittingId: Int
    let deletedAt: Date

    /// 检查是否已过期（超过5分钟）
    var isExpired: Bool {
        Date().timeIntervalSince(deletedAt) > 300 // 5分钟 = 300秒
    }
}

/// 删除缓存管理器 - 单例模式，在应用生命周期中持久化
@MainActor
final class FittingDeletionCacheManager: ObservableObject {
    static let shared = FittingDeletionCacheManager()

    /// 存储已删除配置的信息，按角色ID分组
    private var deletedFittingItems: [Int: [DeletedFittingItem]] = [:]

    private init() {}

    /// 添加已删除的配置ID
    func addDeletedFitting(fittingId: Int, characterId: Int) {
        let deletedItem = DeletedFittingItem(fittingId: fittingId, deletedAt: Date())

        if deletedFittingItems[characterId] == nil {
            deletedFittingItems[characterId] = []
        }

        // 移除已存在的相同ID（如果有的话）
        deletedFittingItems[characterId]?.removeAll { $0.fittingId == fittingId }

        // 添加新的删除记录
        deletedFittingItems[characterId]?.append(deletedItem)
    }

    /// 检查配置是否已被删除且未过期
    func isDeleted(fittingId: Int, characterId: Int) -> Bool {
        guard let items = deletedFittingItems[characterId] else {
            return false
        }

        // 先清理过期项
        cleanExpiredItems(for: characterId)

        // 查找匹配的删除记录，且未过期
        return items.contains { $0.fittingId == fittingId && !$0.isExpired }
    }

    /// 清理指定角色的过期缓存项
    private func cleanExpiredItems(for characterId: Int) {
        deletedFittingItems[characterId]?.removeAll { $0.isExpired }

        // 如果数组为空，移除整个角色的记录
        if deletedFittingItems[characterId]?.isEmpty == true {
            deletedFittingItems[characterId] = nil
        }
    }

    /// 获取缓存统计信息（用于调试）
    func getCacheStats() -> [Int: Int] {
        var stats: [Int: Int] = [:]
        for (characterId, _) in deletedFittingItems {
            // 先清理过期项
            cleanExpiredItems(for: characterId)

            // 获取清理后的有效项数量
            if let items = deletedFittingItems[characterId], !items.isEmpty {
                stats[characterId] = items.count
            }
        }
        return stats
    }

    /// 打印缓存统计信息（用于调试）
    func printCacheStats() {
        let stats = getCacheStats()
        if stats.isEmpty {
            Logger.debug("删除缓存为空")
        } else {
            for (characterId, count) in stats {
                Logger.debug("角色 \(characterId) 有 \(count) 个有效的删除缓存项")
            }
        }
    }
}

/// 配置来源类型
enum FittingSourceType {
    case local
    case online
}

/// 本地配置视图模型
@MainActor
final class LocalFittingViewModel: ObservableObject {
    /// 预构造导航树（唯一列表数据源）
    @Published private(set) var tree: [FittingGroupNode] = []
    /// 全量装配字典（详情零二次加载）
    @Published private(set) var fittingsByID: [UUID: LocalFitting] = [:]
    /// 无法解析的装配（仅提醒展示，不可打开）
    @Published private(set) var unreadableFittings: [UnreadableFitting] = []
    @Published private(set) var shipInfo: [Int: FittingShipInfo] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?
    let databaseManager: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    func loadLocalFittings(forceRefresh _: Bool = false) async {
        isLoading = true
        errorMessage = nil

        do {
            let result = try FitConvert.loadAllLocalFittings()
            apply(result.fittings, fileUnreadable: result.unreadable)
        } catch {
            Logger.error("加载本地配置失败: \(error)")
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// 由全量装配重建树与字典；SDE 查不到飞船的装配归入无法解析列表（文件保留）
    private func apply(
        _ localFittings: [LocalFitting], fileUnreadable: [UnreadableFitting] = []
    ) {
        var byID: [UUID: LocalFitting] = [:]
        var entries: [FittingCatalogEntry] = []
        for fitting in localFittings {
            byID[fitting.fitting_id] = fitting
            entries.append(
                (ref: .local(fitting.fitting_id), name: fitting.name, shipTypeId: fitting.ship_type_id)
            )
        }

        let catalog = FittingTreeBuilder.catalog(from: entries)

        // SDE 缺失该飞船：无法构建层级，标记提醒（不删除文件）
        let skippedUnreadable = catalog.skipped.compactMap { entry -> UnreadableFitting? in
            guard case let .local(uuid) = entry.ref else { return nil }
            return UnreadableFitting(
                fileName: "local_fitting_\(uuid.uuidString).json",
                name: entry.name,
                shipTypeId: entry.shipTypeId
            )
        }

        fittingsByID = byID
        shipInfo = catalog.shipInfo
        tree = FittingTreeBuilder.build(
            items: catalog.items, shipInfo: catalog.shipInfo, groupByType: catalog.groupByType
        )
        unreadableFittings = fileUnreadable + skippedUnreadable
    }

    /// 搜索：匹配飞船本地化名称 / 装配名称 / 飞船 typeID，按飞船名、装配名排序
    func searchMatches(query: String) -> [FittingItemNode] {
        FittingTreeBuilder.searchMatches(tree: tree, shipInfo: shipInfo, query: query)
    }

    /// 添加删除配置的方法
    func deleteFitting(fittingId: UUID) {
        deleteFiles(matchingFileNames: ["local_fitting_\(fittingId.uuidString).json"])
    }

    /// 删除无法解析的装配文件（按文件名定位；仅清列表不清正常数据）
    func deleteUnreadableFitting(fileName: String) {
        deleteFiles(matchingFileNames: [fileName])
    }

    /// 一键清除全部无法解析的装配文件
    func deleteAllUnreadableFittings() {
        deleteFiles(matchingFileNames: unreadableFittings.map(\.fileName))
    }

    /// 按文件名批量删除装配文件，随后重载列表
    private func deleteFiles(matchingFileNames fileNames: [String]) {
        guard !fileNames.isEmpty,
              let documentsDirectory = FileManager.default.urls(
                  for: .documentDirectory, in: .userDomainMask
              ).first
        else { return }

        let fittingsDirectory = documentsDirectory.appendingPathComponent("Fitting")
        var removeFailed = false
        for fileName in fileNames {
            do {
                try FileManager.default.removeItem(
                    at: fittingsDirectory.appendingPathComponent(fileName)
                )
            } catch {
                removeFailed = true
                Logger.error("删除装配文件失败 \(fileName): \(error.localizedDescription)")
            }
        }
        if removeFailed {
            errorMessage = NSLocalizedString("Error_Delete_Fitting", comment: "")
        }

        // 重载：正常装配与无法解析列表同步刷新
        do {
            let result = try FitConvert.loadAllLocalFittings()
            apply(result.fittings, fileUnreadable: result.unreadable)
        } catch {
            Logger.error("重载本地配置失败: \(error)")
        }
    }
}

/// 在线配置视图模型
@MainActor
final class OnlineFittingViewModel: ObservableObject {
    /// 预构造导航树（唯一列表数据源）
    @Published private(set) var tree: [FittingGroupNode] = []
    /// 全量装配字典（详情零二次加载、零竞态）
    @Published private(set) var fittingsByID: [Int: CharacterFitting] = [:]
    @Published private(set) var shipInfo: [Int: FittingShipInfo] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var initialLoadDone = false
    private var loadingTask: Task<Void, Never>?

    let characterId: Int?
    let databaseManager: DatabaseManager

    init(characterId: Int?, databaseManager: DatabaseManager) {
        self.characterId = characterId
        self.databaseManager = databaseManager

        // 在初始化时立即开始加载数据
        if characterId != nil {
            Task {
                await loadOnlineFittings()
            }
        }
    }

    deinit {
        loadingTask?.cancel()
    }

    func loadOnlineFittings(forceRefresh: Bool = false) async {
        // 如果已经加载过且不是强制刷新，则跳过
        if initialLoadDone, !forceRefresh {
            return
        }

        // 如果没有角色ID，则直接返回
        guard let characterId = characterId else {
            Logger.error("尝试加载在线配置但没有characterId")
            return
        }

        // 取消之前的加载任务
        loadingTask?.cancel()

        // 创建新的加载任务
        loadingTask = Task {
            isLoading = true
            errorMessage = nil

            do {
                // 获取在线配置数据（ESI 返回全量 items）
                let fittings = try await CharacterFittingAPI.getCharacterFittings(
                    characterID: characterId, forceRefresh: forceRefresh
                )

                if Task.isCancelled {
                    Logger.debug("配置加载任务被取消")
                    return
                }

                var byID: [Int: CharacterFitting] = [:]
                var entries: [FittingCatalogEntry] = []

                for fitting in fittings {
                    if FittingDeletionCacheManager.shared.isDeleted(
                        fittingId: fitting.fitting_id, characterId: characterId
                    ) {
                        Logger.debug("跳过已删除的配置 ID: \(fitting.fitting_id)")
                        continue
                    }

                    byID[fitting.fitting_id] = fitting
                    entries.append(
                        (ref: .online(fitting.fitting_id), name: fitting.name, shipTypeId: fitting.ship_type_id)
                    )
                }

                let catalog = FittingTreeBuilder.catalog(from: entries)

                if Task.isCancelled {
                    Logger.debug("配置分组任务被取消")
                    return
                }

                self.fittingsByID = byID
                self.shipInfo = catalog.shipInfo
                self.tree = FittingTreeBuilder.build(
                    items: catalog.items, shipInfo: catalog.shipInfo, groupByType: catalog.groupByType
                )

                // 打印缓存统计信息（调试用）
                FittingDeletionCacheManager.shared.printCacheStats()

                if !Task.isCancelled {
                    self.initialLoadDone = true
                }
            } catch {
                if !Task.isCancelled {
                    Logger.error("加载配置数据失败: \(error)")
                    self.errorMessage = error.localizedDescription
                } else {
                    Logger.debug("配置加载任务被取消")
                }
            }

            if !Task.isCancelled {
                self.isLoading = false
            }
        }

        // 等待任务完成
        await loadingTask?.value
    }

    /// 搜索：匹配飞船本地化名称 / 装配名称 / 飞船 typeID，按飞船名、装配名排序
    func searchMatches(query: String) -> [FittingItemNode] {
        FittingTreeBuilder.searchMatches(tree: tree, shipInfo: shipInfo, query: query)
    }

    /// 删除在线装配配置
    func deleteFitting(fittingId: Int) {
        guard let characterId = characterId else {
            Logger.error("尝试删除在线配置但没有characterId")
            return
        }

        // 异步执行删除请求
        Task {
            do {
                // 先调用远程API执行真正的删除操作
                try await CharacterFittingAPI.deleteCharacterFitting(
                    characterID: characterId,
                    fittingID: fittingId
                )

                // 删除成功后，添加到删除标记容器中
                FittingDeletionCacheManager.shared.addDeletedFitting(
                    fittingId: fittingId, characterId: characterId
                )

                // 立即刷新界面显示
                refreshDisplayedFittings()

                Logger.success("成功删除在线装配配置 - ID: \(fittingId)，已添加到5分钟删除缓存")
            } catch {
                Logger.error("删除在线装配配置失败: \(error)")
                // 删除失败时不添加删除标记，保持界面状态不变
            }
        }
    }

    /// 刷新显示的配置列表（基于删除标记过滤后重建树）
    func refreshDisplayedFittings() {
        guard let characterId = characterId else { return }

        let kept = fittingsByID.values.filter {
            !FittingDeletionCacheManager.shared.isDeleted(
                fittingId: $0.fitting_id, characterId: characterId
            )
        }

        let catalog = FittingTreeBuilder.catalog(
            from: kept.map {
                (ref: .online($0.fitting_id), name: $0.name, shipTypeId: $0.ship_type_id)
            }
        )

        var byID: [Int: CharacterFitting] = [:]
        for fitting in kept {
            byID[fitting.fitting_id] = fitting
        }

        fittingsByID = byID
        shipInfo = catalog.shipInfo
        tree = FittingTreeBuilder.build(
            items: catalog.items, shipInfo: catalog.shipInfo, groupByType: catalog.groupByType
        )
    }
}
