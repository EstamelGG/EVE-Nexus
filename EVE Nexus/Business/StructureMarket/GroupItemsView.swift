import SwiftUI

// MARK: - 分组物品视图

struct GroupItemsView: View {
    let group: GroupOrderData
    let structureId: Int64
    let characterId: Int
    let orderType: MarketOrderType

    @State private var itemData: [GroupItemInfo] = []
    @State private var isLoading = false
    @State private var hasLoaded = false // 标记是否已加载过数据
    @State private var jitaPriceLoadingProgress: (current: Int, total: Int)? = nil

    var body: some View {
        List {
            if isLoading {
                Section {
                    VStack(spacing: 12) {
                        ProgressView()
                            .frame(maxWidth: .infinity)

                        // 显示加载Jita价格的进度
                        if let progress = jitaPriceLoadingProgress {
                            Text(
                                String(
                                    format: NSLocalizedString(
                                        "Structure_Market_Loading_Jita_Price_Progress",
                                        comment: "正在加载 Jita 价格 %d/%d"
                                    ),
                                    progress.current,
                                    progress.total
                                )
                            )
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                }
            } else {
                // 物品列表 - 每个物品一个Section
                if !itemData.isEmpty {
                    ForEach(itemData) { item in
                        Section {
                            GroupItemRowView(item: item, orderType: orderType)
                        } footer: {
                            // 百分比差异在footer右侧显示
                            if let structurePrice = item.structurePrice,
                               let jitaPrice = item.jitaPrice,
                               jitaPrice > 0
                            {
                                HStack {
                                    Spacer()

                                    let percentage = calculatePercentage(
                                        structurePrice: structurePrice,
                                        jitaPrice: jitaPrice,
                                        orderType: orderType
                                    )
                                    let (text, color) = formatPercentage(
                                        percentage: percentage,
                                        orderType: orderType
                                    )

                                    // 如果差异 < 0.5%，使用次要颜色
                                    let displayColor = abs(percentage) < 0.5 ? Color.secondary : color

                                    Text(text)
                                        .font(.caption)
                                        .foregroundColor(displayColor)
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("\(group.name) (Top 10)")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // 只在首次加载时执行
            if !hasLoaded {
                hasLoaded = true
                await loadItemData()
            }
        }
    }

    private func loadItemData() async {
        // 避免重复加载
        guard !isLoading else { return }

        await MainActor.run {
            isLoading = true
        }

        do {
            // 加载订单数据
            let orders = try await StructureMarketManager.shared.getStructureOrders(
                structureId: structureId,
                characterId: characterId,
                forceRefresh: false
            )

            // 过滤订单类型
            let filteredOrders = orders.filter { order in
                orderType == .buy ? order.isBuyOrder : !order.isBuyOrder
            }

            // 计算该组内物品的订单数和物品数
            var items = await calculateGroupItems(orders: filteredOrders, groupID: group.id, orderType: orderType)

            // 批量获取Jita价格
            let typeIds = items.map { $0.typeId }
            let totalCount = typeIds.count

            // 初始化进度（只有在有物品需要加载时才显示）
            if totalCount > 0 {
                await MainActor.run {
                    jitaPriceLoadingProgress = (current: 0, total: totalCount)
                }
            }

            if orderType == .sell {
                // 卖单：获取Jita空间站卖价
                let regionID = MarketManager.theForgeRegionID // The Forge (Jita所在星域)
                let systemID = 30_000_142 // Jita星系ID
                let stationID = 60_003_760 // Jita 4-4 空间站 ID

                var loadedCount = 0
                let marketOrders = await MarketOrdersUtil.loadRegionOrders(
                    typeIds: typeIds,
                    regionID: regionID,
                    forceRefresh: false,
                    itemCallback: { _, _ in
                        loadedCount += 1
                        Task { @MainActor in
                            jitaPriceLoadingProgress = (current: loadedCount, total: totalCount)
                        }
                    }
                )

                for index in items.indices {
                    let typeId = items[index].typeId
                    if let orders = marketOrders[typeId] {
                        let price = MarketOrdersUtil.calculatePrice(
                            from: orders,
                            orderType: .sell,
                            quantity: nil,
                            systemId: systemID,
                            stationID: stationID
                        ).price
                        items[index].jitaPrice = price
                    }
                    items[index].structureId = structureId
                }
            } else {
                // 买单：获取Jita空间站买价
                let regionID = MarketManager.theForgeRegionID // The Forge (Jita所在星域)
                let systemID = 30_000_142 // Jita星系ID
                let stationID = 60_003_760 // Jita 4-4 空间站 ID

                var loadedCount = 0
                let marketOrders = await MarketOrdersUtil.loadRegionOrders(
                    typeIds: typeIds,
                    regionID: regionID,
                    forceRefresh: false,
                    itemCallback: { _, _ in
                        loadedCount += 1
                        Task { @MainActor in
                            jitaPriceLoadingProgress = (current: loadedCount, total: totalCount)
                        }
                    }
                )

                for index in items.indices {
                    let typeId = items[index].typeId
                    if let orders = marketOrders[typeId] {
                        let price = MarketOrdersUtil.calculatePrice(
                            from: orders,
                            orderType: .buy,
                            quantity: nil,
                            systemId: systemID,
                            stationID: stationID
                        ).price
                        items[index].jitaPrice = price
                    }
                    items[index].structureId = structureId
                }
            }

            // 清除进度
            await MainActor.run {
                jitaPriceLoadingProgress = nil
            }

            await MainActor.run {
                itemData = items
                isLoading = false
            }
        } catch {
            Logger.error("加载物品数据失败: \(error)")
            await MainActor.run {
                itemData = []
                isLoading = false
                jitaPriceLoadingProgress = nil
            }
        }
    }

    /// 计算指定组内物品的订单数和物品数
    private func calculateGroupItems(orders: [StructureMarketOrder], groupID: Int, orderType: MarketOrderType) async -> [GroupItemInfo] {
        guard !orders.isEmpty else {
            return []
        }

        // 获取所有唯一的 typeId（用于内存过滤）
        let orderTypeIds = Set(orders.map { $0.typeId })

        guard !orderTypeIds.isEmpty else {
            return []
        }

        // 统计每个typeId的订单数、物品数和价格
        var typeIdOrderCount: [Int: Int] = [:]
        var typeIdTotalVolume: [Int: Int] = [:]
        var typeIdOrders: [Int: [StructureMarketOrder]] = [:]
        for order in orders {
            typeIdOrderCount[order.typeId, default: 0] += 1
            typeIdTotalVolume[order.typeId, default: 0] += order.volumeRemain
            typeIdOrders[order.typeId, default: []].append(order)
        }

        // 统计该组内各物品的订单数和物品数
        var itemInfoMap: [Int: (typeId: Int, name: String, iconFileName: String, orderCount: Int, totalVolume: Int, structurePrice: Double?)] = [:]

        // 内存索引获取该组内物品
        for (typeId, info) in SDEMemoryStore.types where info.groupID == groupID {
            // 只处理订单中存在的 typeId
            guard orderTypeIds.contains(typeId),
                  let orderCount = typeIdOrderCount[typeId],
                  let totalVolume = typeIdTotalVolume[typeId],
                  let itemOrders = typeIdOrders[typeId]
            else { continue }

            // 计算价格：卖单显示最低价，买单显示最高价
            let structurePrice: Double?
            if orderType == .sell {
                structurePrice = itemOrders.map { $0.price }.min()
            } else {
                structurePrice = itemOrders.map { $0.price }.max()
            }

            itemInfoMap[typeId] = (
                typeId: typeId,
                name: info.name,
                iconFileName: info.iconFilename,
                orderCount: orderCount,
                totalVolume: totalVolume,
                structurePrice: structurePrice
            )
        }

        // 转换为数组，按订单数降序排序，取前10个
        let items = itemInfoMap.values
            .sorted { $0.orderCount > $1.orderCount }
            .prefix(10)
            .map { itemInfo in
                GroupItemInfo(
                    typeId: itemInfo.typeId,
                    name: itemInfo.name,
                    iconFileName: itemInfo.iconFileName,
                    orderCount: itemInfo.orderCount,
                    totalVolume: itemInfo.totalVolume,
                    structurePrice: itemInfo.structurePrice
                )
            }

        return Array(items)
    }

    /// 计算百分比
    private func calculatePercentage(structurePrice: Double, jitaPrice: Double, orderType: MarketOrderType) -> Double {
        guard jitaPrice > 0 else { return 0 }

        if orderType == .sell {
            // 卖单：最低价 vs Jita卖价
            // 如果最低价 < Jita卖价，显示负数（绿色）
            // 如果最低价 > Jita卖价，显示正数（红色）
            return ((structurePrice - jitaPrice) / jitaPrice) * 100
        } else {
            // 买单：最高价 vs Jita买价
            // 如果最高价 > Jita买价，显示正数（绿色）
            // 如果最高价 < Jita买价，显示负数（红色）
            return ((structurePrice - jitaPrice) / jitaPrice) * 100
        }
    }

    /// 格式化百分比显示（不带括号）
    private func formatPercentage(percentage: Double, orderType: MarketOrderType) -> (String, Color) {
        let sign = percentage >= 0 ? "+" : ""
        let text = String(format: "\(sign)%.1f%%", percentage)

        let color: Color
        if orderType == .sell {
            // 卖单：负数（更低）为绿色，正数（更高）为红色
            color = percentage < 0 ? .green : .red
        } else {
            // 买单：正数（更高）为绿色，负数（更低）为红色
            color = percentage > 0 ? .green : .red
        }

        return (text, color)
    }
}
