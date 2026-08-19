import SwiftUI

extension OreRefineryCalculatorView {
    /// 根据建筑ID获取建筑信息
    func getStructureById(_ structureId: Int64) -> MarketStructure? {
        return MarketStructureManager.shared.structures.first { $0.structureId == Int(structureId) }
    }

    /// 加载物品列表
    func loadItems() {
        if !oreItems.isEmpty {
            // 内存索引批量构建（已按 id 升序）
            items = DatabaseListItem.listItems(
                for: oreItems.map(\.typeID),
                databaseManager: databaseManager
            )
            // 更新 itemQuantities
            itemQuantities = Dictionary(
                uniqueKeysWithValues: oreItems.map { ($0.typeID, $0.quantity) }
            )
            // 确保 oreItems 的顺序与加载的物品顺序一致
            oreItems = items.map { item in
                QuickbarItem(
                    typeID: item.id,
                    quantity: oreItems.first(where: { $0.typeID == item.id })?.quantity ?? 1
                )
            }
            // 加载物品体积信息
            loadItemVolumes()
        }
    }

    /// 加载物品体积信息
    func loadItemVolumes() {
        guard !items.isEmpty else { return }

        for item in items {
            if let volume = ItemInfoMap.typeInfo(for: item.id)?.volume {
                itemVolumes[item.id] = volume
            }
        }
    }

    /// 加载所有物品的市场订单
    func loadAllMarketOrders(forceRefresh: Bool = false) async {
        guard !items.isEmpty else { return }

        // 防止重复加载
        if isLoadingOrders, !forceRefresh {
            return
        }

        await MainActor.run {
            isLoadingOrders = true
        }

        defer {
            Task { @MainActor in
                isLoadingOrders = false
            }
        }

        await MainActor.run {
            marketOrders.removeAll()
        }

        let typeIds = items.map { $0.id }
        let newOrders = await loadOrdersForItems(
            typeIds: typeIds,
            regionID: selectedRegionID,
            forceRefresh: forceRefresh,
            progressCallback: { progress in
                Task { @MainActor in
                    structureOrdersProgress = progress
                }
            }
        )

        await MainActor.run {
            marketOrders = newOrders
        }
    }

    // MARK: - 通用订单加载方法

    func loadOrdersForItems(
        typeIds: [Int],
        regionID: Int,
        forceRefresh: Bool = false,
        progressCallback: ((StructureOrdersProgress) -> Void)? = nil
    ) async -> [Int: [MarketOrder]] {
        if StructureMarketManager.isStructureId(regionID) {
            // 建筑订单
            guard let structureId = StructureMarketManager.getStructureId(from: regionID),
                  let structure = getStructureById(structureId)
            else {
                Logger.error("无效的建筑ID或未找到建筑信息: \(regionID)")
                return [:]
            }

            do {
                Logger.info("开始加载建筑订单，物品数量: \(typeIds.count)")

                let batchOrders = try await StructureMarketManager.shared
                    .getBatchItemOrdersInStructure(
                        structureId: structureId,
                        characterId: structure.characterId,
                        typeIds: typeIds,
                        forceRefresh: forceRefresh,
                        progressCallback: progressCallback
                    )

                Logger.success("成功加载建筑订单，获得 \(batchOrders.count) 个物品的订单数据")
                return batchOrders
            } catch {
                Logger.error("批量加载建筑订单失败: \(error)")
                return [:]
            }
        } else {
            // 星域订单
            let concurrency = max(1, min(10, typeIds.count))
            Logger.info("开始加载星域订单，物品数量: \(typeIds.count)，并发数: \(concurrency)")

            var newOrders: [Int: [MarketOrder]] = [:]

            await withTaskGroup(of: (Int, [MarketOrder])?.self) { group in
                var pendingTypeIds = typeIds

                for _ in 0 ..< concurrency {
                    if !pendingTypeIds.isEmpty {
                        let typeId = pendingTypeIds.removeFirst()
                        group.addTask {
                            do {
                                let orders = try await MarketOrdersAPI.shared.fetchMarketOrders(
                                    typeID: typeId,
                                    regionID: regionID,
                                    forceRefresh: forceRefresh
                                )
                                return (typeId, orders)
                            } catch {
                                Logger.error("加载市场订单失败 (物品ID: \(typeId)): \(error)")
                                return nil
                            }
                        }
                    }
                }

                while let result = await group.next() {
                    if let (typeID, orders) = result {
                        newOrders[typeID] = orders
                    }

                    if !pendingTypeIds.isEmpty {
                        let typeId = pendingTypeIds.removeFirst()
                        group.addTask {
                            do {
                                let orders = try await MarketOrdersAPI.shared.fetchMarketOrders(
                                    typeID: typeId,
                                    regionID: regionID,
                                    forceRefresh: forceRefresh
                                )
                                return (typeId, orders)
                            } catch {
                                Logger.error("加载市场订单失败 (物品ID: \(typeId)): \(error)")
                                return nil
                            }
                        }
                    }
                }
            }

            Logger.info("完成星域订单加载，成功获取 \(newOrders.count) 个物品的订单数据")
            return newOrders
        }
    }
}
