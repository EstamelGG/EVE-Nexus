import Foundation

/// 建筑市场订单更新后台任务
/// 负责每小时更新一次市场建筑订单数据，按优先级更新
/// 使用 BGProcessingTask 以获得更长的执行时间
@MainActor
class StructureOrdersRefreshTask: BaseProcessingTask {
    static let identifier = "com.evenexus.structureordersrefresh"
    static let interval: TimeInterval = 60 * 60 // 1小时

    /// 用于记录上次更新的建筑ID，实现轮询更新
    private static let lastUpdatedStructureIdKey = "lastUpdatedStructureOrdersId"

    init() {
        super.init(identifier: Self.identifier, interval: Self.interval)
    }

    override func perform() async {
        Logger.notice("开始执行后台建筑市场订单更新")

        // 确保建筑列表已加载
        await MainActor.run {
            MarketStructureManager.shared.loadStructures()
        }

        // 获取所有市场建筑
        let structures = await MainActor.run {
            MarketStructureManager.shared.structures
        }

        guard !structures.isEmpty else {
            Logger.info("没有需要更新的市场建筑")
            return
        }

        // 检查任务是否被取消
        if Task.isCancelled {
            Logger.warning("建筑市场订单更新任务被取消")
            return
        }

        // 按优先级排序建筑
        let prioritizedStructures = await prioritizeStructures(structures)

        guard let structureToUpdate = prioritizedStructures.first else {
            Logger.info("没有需要更新的建筑")
            return
        }

        // 检查角色是否存在且token未过期
        guard let characterAuth = EVELogin.shared.getCharacterByID(structureToUpdate.characterId) else {
            Logger.warning("找不到建筑对应的角色: \(structureToUpdate.characterId)")
            return
        }

        if characterAuth.character.refreshTokenExpired {
            Logger.warning("建筑对应角色token已过期，跳过更新: \(structureToUpdate.structureName)")
            return
        }

        // 检查任务是否被取消
        if Task.isCancelled {
            Logger.warning("建筑市场订单更新任务被取消")
            return
        }

        do {
            // 更新建筑市场订单
            _ = try await StructureMarketManager.shared.getStructureOrders(
                structureId: Int64(structureToUpdate.structureId),
                characterId: structureToUpdate.characterId,
                forceRefresh: true
            )

            // 记录本次更新的建筑ID
            UserDefaults.standard.set(structureToUpdate.structureId, forKey: Self.lastUpdatedStructureIdKey)

            Logger.success("成功更新建筑市场订单: \(structureToUpdate.structureName) (ID: \(structureToUpdate.structureId))")
        } catch let error as NetworkError {
            // 检查是否是403权限错误
            if case let .httpError(statusCode, message) = error, statusCode == 403 {
                // 403错误表示没有市场访问权限，记录并跳过
                Logger.warning("建筑市场订单更新被拒绝（无访问权限）: \(structureToUpdate.structureName) (ID: \(structureToUpdate.structureId))")
                if let errorMessage = message, errorMessage.contains("Market access denied") {
                    Logger.warning("错误详情: Market access denied")
                }
                // 记录本次更新的建筑ID，即使失败也跳过，避免重复尝试
                UserDefaults.standard.set(structureToUpdate.structureId, forKey: Self.lastUpdatedStructureIdKey)
            } else {
                // 其他网络错误，记录日志但不跳过（下次可能成功）
                Logger.error("更新建筑市场订单失败: \(structureToUpdate.structureName), 错误: \(error)")
            }
        } catch {
            // 其他类型的错误
            Logger.error("更新建筑市场订单失败: \(structureToUpdate.structureName), 错误: \(error)")
        }
    }

    /// 按优先级排序建筑
    /// 优先级：1. 无缓存的建筑优先（按添加时间，先添加的优先）
    ///         2. 有缓存的建筑，按最后更新时间升序（最久没更新的优先）
    private func prioritizeStructures(_ structures: [MarketStructure]) async -> [MarketStructure] {
        // 获取上次更新的建筑ID
        let lastUpdatedId = UserDefaults.standard.integer(forKey: Self.lastUpdatedStructureIdKey)

        // 分离无缓存和有缓存的建筑
        var noCacheStructures: [(structure: MarketStructure, addedDate: Date)] = []
        var cachedStructures: [(structure: MarketStructure, lastUpdateDate: Date)] = []

        for structure in structures {
            let cacheStatus = StructureMarketManager.getCacheStatus(structureId: Int64(structure.structureId))

            switch cacheStatus {
            case .noData:
                // 无缓存，按添加时间排序
                noCacheStructures.append((structure: structure, addedDate: structure.addedDate))
            case .expired, .valid:
                // 有缓存，获取最后更新时间
                if let lastUpdateDate = StructureMarketManager.getLocalOrdersModificationDate(
                    structureId: Int64(structure.structureId)
                ) {
                    cachedStructures.append((structure: structure, lastUpdateDate: lastUpdateDate))
                } else {
                    // 如果无法获取更新时间，当作无缓存处理
                    noCacheStructures.append((structure: structure, addedDate: structure.addedDate))
                }
            }
        }

        // 排序无缓存建筑：按添加时间升序（先添加的优先）
        noCacheStructures.sort { $0.addedDate < $1.addedDate }

        // 排序有缓存建筑：按最后更新时间升序（最久没更新的优先）
        cachedStructures.sort { $0.lastUpdateDate < $1.lastUpdateDate }

        // 如果上次更新的建筑存在，将其移到对应组的末尾（实现轮询）
        if lastUpdatedId != 0 {
            if let noCacheIndex = noCacheStructures.firstIndex(where: { $0.structure.structureId == lastUpdatedId }) {
                let item = noCacheStructures.remove(at: noCacheIndex)
                noCacheStructures.append(item)
            } else if let cachedIndex = cachedStructures.firstIndex(where: { $0.structure.structureId == lastUpdatedId }) {
                let item = cachedStructures.remove(at: cachedIndex)
                cachedStructures.append(item)
            }
        }

        // 合并结果：无缓存在前，有缓存在后
        return noCacheStructures.map { $0.structure } + cachedStructures.map { $0.structure }
    }
}
