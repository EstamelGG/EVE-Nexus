import SwiftUI

// MARK: - 建筑市场详情视图

struct StructureMarketDetailView: View {
    let structure: MarketStructure

    @State private var cacheStatus: StructureMarketManager.CacheStatus = .noData
    @State private var lastUpdateDate: Date? = nil
    @State private var refreshStatus: CacheRefreshStatus = .invalidRefreshable
    @State private var isLoadingOrders = false
    @State private var structureOrdersProgress: StructureOrdersProgress? = nil
    @State private var updateTimer: Timer? = nil
    @State private var buyOrdersCount: Int? = nil
    @State private var sellOrdersCount: Int? = nil
    @State private var itemTypesCount: Int? = nil
    @StateObject private var allianceIconLoader = AllianceIconLoader()
    @State private var sovereigntyData: [SovereigntyData] = []
    @State private var systemAllianceMap: [Int: Int] = [:] // 星系ID -> 联盟ID
    @State private var topSellItems: [ItemOrderInfo] = [] // 最多卖单的物品（Top 3）
    @State private var topBuyItems: [ItemOrderInfo] = [] // 最多买单的物品（Top 3）
    @State private var topPremiumItems: [PremiumItemInfo] = [] // 最高溢价的物品（Top 3）
    @State private var allPremiumItems: [PremiumItemInfo] = [] // 所有溢价物品（用于传递给子视图）
    @State private var premiumSellOrders: [StructureMarketOrder] = [] // 溢价物品的卖单（用于传递给子视图）
    @State private var isLoadingPremium = false // 是否正在加载溢价数据
    @State private var isGitHubAPIUnavailable = false // GitHub Market Price API 是否不可用
    @State private var hasInitialized = false // 是否已初始化，避免从子页面返回时重复加载

    // 刷新冷却时间：20分钟
    private let refreshCooldownInterval: TimeInterval = 20 * 60 // 20分钟

    // 允许计算溢价的物品类别
    private let allowedCategories: Set<Int> = [2, 4, 6, 7, 8, 9, 17, 18, 20, 22, 24, 25, 32, 34, 35, 41, 42, 43, 46, 49, 65, 66, 87]

    var body: some View {
        List {
            // Section 1: 建筑基本信息
            structureInfoSection

            // Section 2: 最多卖单
            topSellItemsSection

            // Section 3: 最多买单
            topBuyItemsSection

            // Section 4: 最高溢价（始终显示）
            topPremiumItemsSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("Structure_Market_Orders_Overview", comment: "建筑订单总览"))
        .navigationBarTitleDisplayMode(.large)
        .conditionalRefreshable(isEnabled: refreshStatus != .validNotRefreshable) {
            // 下拉刷新，检查冷却时间
            await handlePullToRefresh()
        }
        .onAppear {
            // 更新缓存状态（每次都需要更新，用于显示刷新状态）
            updateCacheStatus()

            // 只在首次初始化时加载数据，从子页面返回时不会重新加载
            guard !hasInitialized else {
                // 已初始化，只启动定时器（如果还没有启动）
                if updateTimer == nil {
                    updateTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
                        updateCacheStatus()
                    }
                }
                return
            }

            // 首次加载数据
            Task {
                await loadLocalOrdersStatistics()
                await loadTopOrderItems()
            }
            // 加载溢价数据
            Task {
                await loadPremiumItems()
            }
            // 加载主权数据
            Task {
                await loadSovereigntyData()
            }
            // 启动定时器，每分钟更新一次状态（用于检查冷却期是否已过）
            updateTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
                updateCacheStatus()
            }

            hasInitialized = true
        }
        .onDisappear {
            updateTimer?.invalidate()
            updateTimer = nil
            allianceIconLoader.cancelAllTasks()
        }
    }

    // MARK: - 子视图组件

    // 建筑基本信息 Section
    @ViewBuilder
    private var structureInfoSection: some View {
        Section {
            // 行1: 建筑图标、名称、地点
            StructureInfoRowView(
                structure: structure,
                lastUpdateDate: lastUpdateDate,
                allianceIconLoader: allianceIconLoader,
                systemAllianceMap: systemAllianceMap,
                isLoading: isLoadingOrders,
                progress: structureOrdersProgress
            )

            // 订单统计信息
            ordersStatisticsView
        }
    }

    // 订单统计信息视图
    @ViewBuilder
    private var ordersStatisticsView: some View {
        if buyOrdersCount != nil || sellOrdersCount != nil || itemTypesCount != nil {
            // 买单总数
            if let buyCount = buyOrdersCount {
                if buyCount > 0 {
                    NavigationLink(destination: MarketOrdersVisualizationView(
                        structureId: Int64(structure.structureId),
                        characterId: structure.characterId,
                        orderType: .buy,
                        title: NSLocalizedString("Structure_Market_Buy_Orders_Count", comment: "买单总数")
                    )) {
                        OrdersStatisticsRowView(
                            title: NSLocalizedString("Structure_Market_Buy_Orders_Count", comment: "买单总数"),
                            value: "\(buyCount)"
                        )
                    }
                } else {
                    OrdersStatisticsRowView(
                        title: NSLocalizedString("Structure_Market_Buy_Orders_Count", comment: "买单总数"),
                        value: "\(buyCount)"
                    )
                }
            }

            // 卖单总数
            if let sellCount = sellOrdersCount {
                if sellCount > 0 {
                    NavigationLink(destination: MarketOrdersVisualizationView(
                        structureId: Int64(structure.structureId),
                        characterId: structure.characterId,
                        orderType: .sell,
                        title: NSLocalizedString("Structure_Market_Sell_Orders_Count", comment: "卖单总数")
                    )) {
                        OrdersStatisticsRowView(
                            title: NSLocalizedString("Structure_Market_Sell_Orders_Count", comment: "卖单总数"),
                            value: "\(sellCount)"
                        )
                    }
                } else {
                    OrdersStatisticsRowView(
                        title: NSLocalizedString("Structure_Market_Sell_Orders_Count", comment: "卖单总数"),
                        value: "\(sellCount)"
                    )
                }
            }

            // 物品类别
            if let typesCount = itemTypesCount {
                OrdersStatisticsRowView(
                    title: NSLocalizedString("Structure_Market_Item_Types_Count", comment: "物品类别"),
                    value: "\(typesCount)"
                )
            }
        }
    }

    // 最多卖单 Section
    @ViewBuilder
    private var topSellItemsSection: some View {
        if !topSellItems.isEmpty {
            Section(header: Text(NSLocalizedString("Structure_Market_Top_Sell_Orders", comment: "最多卖单"))) {
                ForEach(topSellItems) { item in
                    TopOrderItemRowView(
                        item: item,
                        structureId: Int64(structure.structureId),
                        characterId: structure.characterId
                    )
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            }
        }
    }

    // 最多买单 Section
    @ViewBuilder
    private var topBuyItemsSection: some View {
        if !topBuyItems.isEmpty {
            Section(header: Text(NSLocalizedString("Structure_Market_Top_Buy_Orders", comment: "最多买单"))) {
                ForEach(topBuyItems) { item in
                    TopOrderItemRowView(
                        item: item,
                        structureId: Int64(structure.structureId),
                        characterId: structure.characterId
                    )
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            }
        }
    }

    // 最高溢价 Section
    @ViewBuilder
    private var topPremiumItemsSection: some View {
        Section(header: Text(NSLocalizedString("Structure_Market_Top_Premium", comment: "最高溢价"))) {
            if isGitHubAPIUnavailable {
                premiumAPIUnavailableView
            } else if isLoadingPremium {
                premiumLoadingView
            } else if topPremiumItems.isEmpty {
                premiumEmptyView
            } else {
                premiumItemsListView
            }
        }
    }

    // GitHub API 不可用视图
    @ViewBuilder
    private var premiumAPIUnavailableView: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.orange)
            Text(NSLocalizedString("Structure_Market_GitHub_API_Unavailable", comment: "GitHub API不可达，请重试"))
                .foregroundColor(.secondary)
            Spacer()
            Button(NSLocalizedString("Main_Setting_Reset", comment: "重试")) {
                Task {
                    await loadPremiumItems()
                }
            }
            .buttonStyle(.bordered)
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
    }

    // 溢价加载中视图
    @ViewBuilder
    private var premiumLoadingView: some View {
        HStack {
            Spacer()
            ProgressView()
                .scaleEffect(0.7)
            Text(NSLocalizedString("Loading_Premium_Items", comment: "正在加载溢价物品..."))
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
    }

    // 溢价空状态视图
    @ViewBuilder
    private var premiumEmptyView: some View {
        HStack {
            Spacer()
            Text(NSLocalizedString("Structure_Market_No_Premium_Items", comment: "暂无溢价物品"))
                .foregroundColor(.secondary)
            Spacer()
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
    }

    // 溢价物品列表视图
    @ViewBuilder
    private var premiumItemsListView: some View {
        ForEach(topPremiumItems) { item in
            PremiumItemRowView(
                item: item,
                structureId: Int64(structure.structureId),
                characterId: structure.characterId
            )
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

        // 查看更多按钮
        if shouldShowViewMoreButton {
            NavigationLink(destination: PremiumItemsView(
                structureId: Int64(structure.structureId),
                characterId: structure.characterId,
                allPremiumItems: allPremiumItems,
                sellOrders: premiumSellOrders
            )) {
                HStack {
                    Spacer()
                    Text(NSLocalizedString("Structure_Market_View_More", comment: "查看更多"))
                        .foregroundColor(.blue)
                    Spacer()
                }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
        }
    }

    // 是否显示"查看更多"按钮
    private var shouldShowViewMoreButton: Bool {
        let uniqueTypeIdsCount = Set(premiumSellOrders.map { $0.typeId }).count
        return !topPremiumItems.isEmpty && uniqueTypeIdsCount > 10
    }

    // 更新缓存状态
    private func updateCacheStatus() {
        cacheStatus = StructureMarketManager.getCacheStatus(
            structureId: Int64(structure.structureId)
        )
        lastUpdateDate = StructureMarketManager.getLocalOrdersModificationDate(
            structureId: Int64(structure.structureId)
        )
        refreshStatus = calculateRefreshStatus()
    }

    // 计算刷新状态
    private func calculateRefreshStatus() -> CacheRefreshStatus {
        switch cacheStatus {
        case .valid:
            // 缓存有效，检查是否超过冷却期
            if let updateDate = lastUpdateDate {
                let timeSinceUpdate = Date().timeIntervalSince(updateDate)
                if timeSinceUpdate >= refreshCooldownInterval {
                    // 超过20分钟，可以刷新
                    return .validRefreshable
                } else {
                    // 不足20分钟，不可刷新
                    return .validNotRefreshable
                }
            } else {
                // 没有更新时间，当作可刷新
                return .validRefreshable
            }
        case .expired, .noData:
            // 缓存无效，可以刷新
            return .invalidRefreshable
        }
    }

    // 处理下拉刷新
    private func handlePullToRefresh() async {
        // 更新缓存状态
        updateCacheStatus()

        // 检查是否在冷却期内
        switch refreshStatus {
        case .validNotRefreshable:
            // 在冷却期内，不执行刷新
            Logger.debug("刷新冷却期内，跳过刷新操作")
            return
        case .validRefreshable, .invalidRefreshable:
            // 可以刷新，执行刷新操作
            await loadStructureOrders()
        }
    }

    // 加载建筑市场订单
    private func loadStructureOrders() async {
        isLoadingOrders = true
        structureOrdersProgress = nil

        do {
            let orders = try await StructureMarketManager.shared.getStructureOrders(
                structureId: Int64(structure.structureId),
                characterId: structure.characterId,
                forceRefresh: true,
                progressCallback: { progress in
                    Task { @MainActor in
                        structureOrdersProgress = progress
                    }
                }
            )

            let statistics = await StructureMarketManager.shared.getOrdersStatistics(orders: orders)

            // 计算物品类别数（不同的 typeId 数量）
            let uniqueItemTypes = Set(orders.map { $0.typeId }).count

            // 计算最多卖单和买单的物品
            let (topSell, topBuy) = await calculateTopOrderItems(orders: orders)

            await MainActor.run {
                buyOrdersCount = statistics.buyOrders
                sellOrdersCount = statistics.sellOrders
                itemTypesCount = uniqueItemTypes
                topSellItems = topSell
                topBuyItems = topBuy

                Logger.info(
                    "建筑 \(structure.structureName) 的市场订单已加载: 买单 \(statistics.buyOrders) 个, 卖单 \(statistics.sellOrders) 个, 总交易量 \(statistics.totalVolume), 物品类别 \(uniqueItemTypes) 个"
                )
            }
        } catch {
            Logger.error("加载建筑市场订单失败: \(error)")
        }

        // 更新缓存状态
        await MainActor.run {
            updateCacheStatus()
            isLoadingOrders = false
            structureOrdersProgress = nil
        }
    }

    // 加载本地订单统计信息
    private func loadLocalOrdersStatistics() async {
        // 检查缓存状态，判断是否需要从API获取数据
        let cacheStatus = StructureMarketManager.getCacheStatus(structureId: Int64(structure.structureId))
        let needsRefresh = cacheStatus == .expired || cacheStatus == .noData

        // 如果需要刷新，设置加载状态
        if needsRefresh {
            await MainActor.run {
                isLoadingOrders = true
                structureOrdersProgress = nil
            }
        }

        // 先检查是否有本地缓存文件（无论是否过期）
        let hasLocal = await StructureMarketManager.shared.hasLocalOrders(structureId: Int64(structure.structureId))
        guard hasLocal else {
            // 如果没有本地缓存，需要从API获取，但这里不处理，让getStructureOrders处理
            // 如果needsRefresh为true，已经设置了加载状态
            await MainActor.run {
                if !needsRefresh {
                    buyOrdersCount = nil
                    sellOrdersCount = nil
                    itemTypesCount = nil
                }
            }
            // 如果没有本地缓存且需要刷新，尝试从API获取
            if needsRefresh {
                do {
                    let orders = try await StructureMarketManager.shared.getStructureOrders(
                        structureId: Int64(structure.structureId),
                        characterId: structure.characterId,
                        forceRefresh: false,
                        progressCallback: { progress in
                            Task { @MainActor in
                                structureOrdersProgress = progress
                            }
                        }
                    )
                    await processOrdersData(orders: orders, needsRefresh: needsRefresh)
                } catch {
                    await MainActor.run {
                        buyOrdersCount = nil
                        sellOrdersCount = nil
                        itemTypesCount = nil
                        topSellItems = []
                        topBuyItems = []
                        isLoadingOrders = false
                        structureOrdersProgress = nil
                    }
                }
            }
            return
        }

        do {
            // 尝试从本地缓存加载订单数据（不强制刷新，优先使用本地缓存）
            let orders = try await StructureMarketManager.shared.getStructureOrders(
                structureId: Int64(structure.structureId),
                characterId: structure.characterId,
                forceRefresh: false,
                progressCallback: needsRefresh ? { progress in
                    Task { @MainActor in
                        structureOrdersProgress = progress
                    }
                } : nil
            )

            await processOrdersData(orders: orders, needsRefresh: needsRefresh)
        } catch {
            // 如果加载失败，清空统计信息
            await MainActor.run {
                buyOrdersCount = nil
                sellOrdersCount = nil
                itemTypesCount = nil
                topSellItems = []
                topBuyItems = []

                // 清除加载状态
                if needsRefresh {
                    isLoadingOrders = false
                    structureOrdersProgress = nil
                }
            }
        }
    }

    // 处理订单数据（提取公共逻辑）
    private func processOrdersData(orders: [StructureMarketOrder], needsRefresh: Bool) async {
        // 计算统计数据
        let statistics = await StructureMarketManager.shared.getOrdersStatistics(orders: orders)
        let uniqueItemTypes = Set(orders.map { $0.typeId }).count

        // 计算最多卖单和买单的物品
        let (topSell, topBuy) = await calculateTopOrderItems(orders: orders)

        await MainActor.run {
            buyOrdersCount = statistics.buyOrders
            sellOrdersCount = statistics.sellOrders
            itemTypesCount = uniqueItemTypes
            topSellItems = topSell
            topBuyItems = topBuy

            // 如果之前显示了加载状态，现在清除
            if needsRefresh {
                isLoadingOrders = false
                structureOrdersProgress = nil
                updateCacheStatus()
            }
        }
    }

    // 加载主权数据
    private func loadSovereigntyData() async {
        do {
            let data = try await SovereigntyDataAPI.shared.fetchSovereigntyData(forceRefresh: false)
            await MainActor.run {
                sovereigntyData = data
                // 建立星系到联盟的映射（优先联盟，如果没有联盟则使用派系）
                var map: [Int: Int] = [:]
                for item in data {
                    if let allianceId = item.allianceId {
                        map[item.systemId] = allianceId
                    } else if let factionId = item.factionId, map[item.systemId] == nil {
                        // 如果没有联盟但有派系，也记录派系ID（但派系图标从数据库加载）
                        map[item.systemId] = -factionId // 使用负数表示派系
                    }
                }
                systemAllianceMap = map

                // 只加载当前建筑所在星系的联盟图标
                if let currentSystemAllianceId = map[structure.systemId], currentSystemAllianceId > 0 {
                    allianceIconLoader.loadIcon(for: currentSystemAllianceId)
                }
            }
        } catch {
            Logger.error("加载主权数据失败: \(error)")
        }
    }

    // 加载最多订单的物品
    private func loadTopOrderItems() async {
        // 先检查是否有本地缓存文件
        let hasLocal = await StructureMarketManager.shared.hasLocalOrders(structureId: Int64(structure.structureId))
        guard hasLocal else {
            await MainActor.run {
                topSellItems = []
                topBuyItems = []
            }
            return
        }

        do {
            // 从本地缓存加载订单数据
            let orders = try await StructureMarketManager.shared.getStructureOrders(
                structureId: Int64(structure.structureId),
                characterId: structure.characterId,
                forceRefresh: false
            )

            // 计算最多卖单和买单的物品
            let (topSell, topBuy) = await calculateTopOrderItems(orders: orders)

            await MainActor.run {
                topSellItems = topSell
                topBuyItems = topBuy
            }
        } catch {
            await MainActor.run {
                topSellItems = []
                topBuyItems = []
            }
        }
    }

    // 计算最多订单的物品（Top 3，相同数量时按typeId排序）
    private func calculateTopOrderItems(orders: [StructureMarketOrder]) async -> ([ItemOrderInfo], [ItemOrderInfo]) {
        // 分别统计卖单和买单
        var sellOrderCount: [Int: Int] = [:]
        var buyOrderCount: [Int: Int] = [:]

        for order in orders {
            if order.isBuyOrder {
                buyOrderCount[order.typeId, default: 0] += 1
            } else {
                sellOrderCount[order.typeId, default: 0] += 1
            }
        }

        // 先确定 Top 3 的 typeId（按订单数降序，相同数量时按typeId升序）
        let topSellTypeIds = sellOrderCount
            .sorted { first, second in
                if first.value != second.value {
                    return first.value > second.value // 按订单数降序
                } else {
                    return first.key < second.key // 相同数量时按typeId升序
                }
            }
            .prefix(3)
            .map { $0.key }

        let topBuyTypeIds = buyOrderCount
            .sorted { first, second in
                if first.value != second.value {
                    return first.value > second.value // 按订单数降序
                } else {
                    return first.key < second.key // 相同数量时按typeId升序
                }
            }
            .prefix(3)
            .map { $0.key }

        // 合并需要查询的 typeId（最多 6 个）
        let allTypeIds = Set(topSellTypeIds).union(Set(topBuyTypeIds))

        guard !allTypeIds.isEmpty else {
            return ([], [])
        }

        // 只查询 Top 3 物品的信息
        let placeholders = String(repeating: "?,", count: allTypeIds.count).dropLast()
        let query = """
            SELECT type_id, name, icon_filename
            FROM types
            WHERE type_id IN (\(placeholders))
        """

        var itemInfoMap: [Int: (name: String, iconFileName: String)] = [:]

        if case let .success(rows) = DatabaseManager.shared.executeQuery(query, parameters: Array(allTypeIds)) {
            for row in rows {
                guard let typeId = row["type_id"] as? Int,
                      let name = row["name"] as? String,
                      let iconFileName = row["icon_filename"] as? String
                else {
                    continue
                }
                itemInfoMap[typeId] = (name: name, iconFileName: iconFileName.isEmpty ? DatabaseConfig.defaultItemIcon : iconFileName)
            }
        }

        // 构建最多卖单的物品（Top 3）
        let topSellItems = topSellTypeIds.compactMap { typeId -> ItemOrderInfo? in
            guard let orderCount = sellOrderCount[typeId],
                  let itemInfo = itemInfoMap[typeId]
            else {
                return nil
            }
            return ItemOrderInfo(
                id: typeId,
                typeId: typeId,
                name: itemInfo.name,
                iconFileName: itemInfo.iconFileName,
                orderCount: orderCount,
                orderType: .sell
            )
        }

        // 构建最多买单的物品（Top 3）
        let topBuyItems = topBuyTypeIds.compactMap { typeId -> ItemOrderInfo? in
            guard let orderCount = buyOrderCount[typeId],
                  let itemInfo = itemInfoMap[typeId]
            else {
                return nil
            }
            return ItemOrderInfo(
                id: typeId,
                typeId: typeId,
                name: itemInfo.name,
                iconFileName: itemInfo.iconFileName,
                orderCount: orderCount,
                orderType: .buy
            )
        }

        return (topSellItems, topBuyItems)
    }

    // 加载最高溢价的物品
    private func loadPremiumItems() async {
        await MainActor.run {
            isLoadingPremium = true
            isGitHubAPIUnavailable = false
            topPremiumItems = []
        }

        do {
            // 步骤1: 并行加载建筑订单和预加载 GitHub 市场数据
            // 注意：不检查 hasLocal，直接调用 getStructureOrders，它会自动处理缓存和 API 获取
            // 预加载时不传 typeIds，会先检查缓存，如果有缓存会立即返回
            async let ordersTask = StructureMarketManager.shared.getStructureOrders(
                structureId: Int64(structure.structureId),
                characterId: structure.characterId,
                forceRefresh: false
            )
            async let gitHubPricesTask: Task<[Int: (buy: Double, sell: Double)], Error> = Task {
                // 预加载所有 GitHub 市场数据（不传 typeIds，会先检查缓存）
                try await GitHubMarketPriceAPI.shared.fetchMarketPrices(
                    typeIds: nil, // 不传 typeIds，获取所有数据（或从缓存加载）
                    forceRefresh: false
                )
            }

            // 等待建筑订单完成
            let orders = try await ordersTask

            // 尝试获取 GitHub 价格数据，如果失败则跳过溢价计算
            let gitHubPrices: [Int: (buy: Double, sell: Double)]
            do {
                gitHubPrices = try await gitHubPricesTask.value
            } catch {
                Logger.debug("GitHub Market Price API 不可用，跳过溢价计算: \(error.localizedDescription)")
                await MainActor.run {
                    isGitHubAPIUnavailable = true
                    isLoadingPremium = false
                    topPremiumItems = []
                }
                return
            }

            // 步骤3: 处理订单数据
            let sellOrders = orders.filter { !$0.isBuyOrder }
            let buyOrders = orders.filter { $0.isBuyOrder }

            guard !sellOrders.isEmpty else {
                await MainActor.run {
                    topPremiumItems = []
                    isLoadingPremium = false
                    isGitHubAPIUnavailable = false
                }
                return
            }

            // 收集价格数据
            var structureSellPrices: [Int: Double] = [:]
            var structureBuyPrices: [Int: Double] = [:]
            var typeIds = Set<Int>()

            for order in sellOrders {
                let currentPrice = structureSellPrices[order.typeId] ?? Double.infinity
                if order.price < currentPrice {
                    structureSellPrices[order.typeId] = order.price
                }
                typeIds.insert(order.typeId)
            }

            for order in buyOrders {
                let currentPrice = structureBuyPrices[order.typeId] ?? 0.0
                if order.price > currentPrice {
                    structureBuyPrices[order.typeId] = order.price
                }
                typeIds.insert(order.typeId)
            }

            // 步骤4: 查询允许的类别
            let typeIdsArray = Array(typeIds)
            guard !typeIdsArray.isEmpty else {
                await MainActor.run {
                    topPremiumItems = []
                    isLoadingPremium = false
                    isGitHubAPIUnavailable = false
                }
                return
            }

            let placeholders = String(repeating: "?,", count: typeIdsArray.count).dropLast()
            let categoryQuery = """
                SELECT type_id, categoryID
                FROM types
                WHERE type_id IN (\(placeholders))
            """

            var allowedTypeIds = Set<Int>()
            if case let .success(rows) = DatabaseManager.shared.executeQuery(categoryQuery, parameters: typeIdsArray) {
                for row in rows {
                    guard let typeId = row["type_id"] as? Int,
                          let categoryId = row["categoryID"] as? Int,
                          allowedCategories.contains(categoryId)
                    else {
                        continue
                    }
                    allowedTypeIds.insert(typeId)
                }
            }

            guard !allowedTypeIds.isEmpty else {
                await MainActor.run {
                    topPremiumItems = []
                    isLoadingPremium = false
                    isGitHubAPIUnavailable = false
                }
                return
            }

            // 步骤5: 过滤出需要的 typeIds 的价格
            let allJitaPrices = gitHubPrices
            // 过滤出我们需要的 typeIds 的价格
            var jitaPrices: [Int: (buy: Double, sell: Double)] = [:]
            for typeId in allowedTypeIds {
                if let price = allJitaPrices[typeId] {
                    jitaPrices[typeId] = price
                }
            }

            // 步骤6: 计算溢价（所有数据已就绪）
            var premiumItems: [PremiumItemInfo] = []

            for typeId in allowedTypeIds {
                guard let structureSellPrice = structureSellPrices[typeId],
                      let jitaData = jitaPrices[typeId],
                      jitaData.sell > 0 // Jita 有卖价
                else {
                    continue
                }

                let jitaSellPrice = jitaData.sell
                // 计算卖价价格比例
                let sellPriceRatio = structureSellPrice / jitaSellPrice
                // 计算卖价溢价百分比（用于显示）
                let sellPremiumPercentage = (sellPriceRatio - 1.0) * 100

                // 计算买价溢价（如果存在）
                var structureBuyPrice: Double? = structureBuyPrices[typeId]
                var jitaBuyPrice: Double? = jitaData.buy > 0 ? jitaData.buy : nil
                var buyPremiumPercentage: Double? = nil

                if let buyPrice = structureBuyPrice, let jitaBuy = jitaBuyPrice, jitaBuy > 0 {
                    // 计算买价价格比例
                    let buyPriceRatio = buyPrice / jitaBuy
                    // 计算买价溢价百分比
                    buyPremiumPercentage = (buyPriceRatio - 1.0) * 100
                } else {
                    structureBuyPrice = nil
                    jitaBuyPrice = nil
                }

                premiumItems.append(
                    PremiumItemInfo(
                        typeId: typeId,
                        structureSellPrice: structureSellPrice,
                        jitaSellPrice: jitaSellPrice,
                        sellPremiumPercentage: sellPremiumPercentage,
                        structureBuyPrice: structureBuyPrice,
                        jitaBuyPrice: jitaBuyPrice,
                        buyPremiumPercentage: buyPremiumPercentage
                    )
                )
            }

            // 7. 保存所有溢价物品（用于传递给子视图）
            // 按价格比例与1的差值绝对值降序排序（偏离Jita价格越远的排在前面）
            let allPremiumItemsSorted = premiumItems
                .sorted { abs($0.sellPremiumPercentage) > abs($1.sellPremiumPercentage) }

            // 8. 按溢价百分比降序排序，取 Top 10
            let topPremium = allPremiumItemsSorted.prefix(10)

            // 9. 查询 Top 10 物品的详细信息
            let topTypeIds = Array(topPremium.map { $0.typeId })
            guard !topTypeIds.isEmpty else {
                await MainActor.run {
                    topPremiumItems = []
                    isLoadingPremium = false
                    isGitHubAPIUnavailable = false
                }
                return
            }

            let itemPlaceholders = String(repeating: "?,", count: topTypeIds.count).dropLast()
            let itemQuery = """
                SELECT type_id, name, icon_filename
                FROM types
                WHERE type_id IN (\(itemPlaceholders))
            """

            var itemInfoMap: [Int: (name: String, iconFileName: String)] = [:]

            if case let .success(rows) = DatabaseManager.shared.executeQuery(itemQuery, parameters: topTypeIds) {
                for row in rows {
                    guard let typeId = row["type_id"] as? Int,
                          let name = row["name"] as? String,
                          let iconFileName = row["icon_filename"] as? String
                    else {
                        continue
                    }
                    itemInfoMap[typeId] = (
                        name: name,
                        iconFileName: iconFileName.isEmpty ? DatabaseConfig.defaultItemIcon : iconFileName
                    )
                }
            }

            // 10. 构建 Top 10 最终结果
            let finalItems = topPremium.compactMap { premiumItem -> PremiumItemInfo? in
                guard let itemInfo = itemInfoMap[premiumItem.typeId] else {
                    return nil
                }
                var item = premiumItem
                item.name = itemInfo.name
                item.iconFileName = itemInfo.iconFileName
                return item
            }

            // 11. 查询所有溢价物品的详细信息（用于传递给子视图）
            let allPremiumTypeIds = Array(allPremiumItemsSorted.map { $0.typeId })
            let allItemPlaceholders = String(repeating: "?,", count: allPremiumTypeIds.count).dropLast()
            let allItemQuery = """
                SELECT type_id, name, icon_filename
                FROM types
                WHERE type_id IN (\(allItemPlaceholders))
            """

            var allItemInfoMap: [Int: (name: String, iconFileName: String)] = [:]
            if case let .success(allRows) = DatabaseManager.shared.executeQuery(allItemQuery, parameters: allPremiumTypeIds) {
                for row in allRows {
                    guard let typeId = row["type_id"] as? Int,
                          let name = row["name"] as? String,
                          let iconFileName = row["icon_filename"] as? String
                    else {
                        continue
                    }
                    allItemInfoMap[typeId] = (
                        name: name,
                        iconFileName: iconFileName.isEmpty ? DatabaseConfig.defaultItemIcon : iconFileName
                    )
                }
            }

            // 12. 构建所有溢价物品的最终结果
            let allFinalItems = allPremiumItemsSorted.compactMap { premiumItem -> PremiumItemInfo? in
                guard let itemInfo = allItemInfoMap[premiumItem.typeId] else {
                    return nil
                }
                var item = premiumItem
                item.name = itemInfo.name
                item.iconFileName = itemInfo.iconFileName
                return item
            }

            await MainActor.run {
                topPremiumItems = finalItems
                allPremiumItems = allFinalItems
                premiumSellOrders = sellOrders
                isLoadingPremium = false
                isGitHubAPIUnavailable = false
            }

            Logger.info("成功计算 \(finalItems.count) 个最高溢价物品")
        } catch {
            Logger.error("加载溢价物品失败: \(error)")
            await MainActor.run {
                topPremiumItems = []
                isLoadingPremium = false
                isGitHubAPIUnavailable = false
            }
        }
    }
}

// MARK: - 溢价物品信息模型

struct PremiumItemInfo: Identifiable, Equatable {
    let id: Int
    let typeId: Int
    var name: String = ""
    var iconFileName: String = ""
    let structureSellPrice: Double // 建筑市场卖价（最低价）
    let jitaSellPrice: Double // Jita 卖价
    let sellPremiumPercentage: Double // 卖价溢价百分比
    let structureBuyPrice: Double? // 建筑市场买价（最高价，可选）
    let jitaBuyPrice: Double? // Jita 买价（可选）
    let buyPremiumPercentage: Double? // 买价溢价百分比（可选）

    init(
        typeId: Int,
        structureSellPrice: Double,
        jitaSellPrice: Double,
        sellPremiumPercentage: Double,
        structureBuyPrice: Double? = nil,
        jitaBuyPrice: Double? = nil,
        buyPremiumPercentage: Double? = nil
    ) {
        id = typeId
        self.typeId = typeId
        self.structureSellPrice = structureSellPrice
        self.jitaSellPrice = jitaSellPrice
        self.sellPremiumPercentage = sellPremiumPercentage
        self.structureBuyPrice = structureBuyPrice
        self.jitaBuyPrice = jitaBuyPrice
        self.buyPremiumPercentage = buyPremiumPercentage
    }

    // Equatable 实现
    static func == (lhs: PremiumItemInfo, rhs: PremiumItemInfo) -> Bool {
        return lhs.id == rhs.id &&
            lhs.typeId == rhs.typeId &&
            lhs.name == rhs.name &&
            lhs.iconFileName == rhs.iconFileName &&
            lhs.structureSellPrice == rhs.structureSellPrice &&
            lhs.jitaSellPrice == rhs.jitaSellPrice &&
            lhs.sellPremiumPercentage == rhs.sellPremiumPercentage &&
            lhs.structureBuyPrice == rhs.structureBuyPrice &&
            lhs.jitaBuyPrice == rhs.jitaBuyPrice &&
            lhs.buyPremiumPercentage == rhs.buyPremiumPercentage
    }
}

// MARK: - 顶部订单物品行视图

struct TopOrderItemRowView: View {
    let item: ItemOrderInfo
    let structureId: Int64
    let characterId: Int

    var body: some View {
        NavigationLink(destination: StructureItemOrdersView(
            structureId: structureId,
            characterId: characterId,
            itemID: item.typeId,
            itemName: item.name,
            orderType: item.orderType,
            databaseManager: DatabaseManager.shared
        )) {
            HStack(spacing: 12) {
                // 物品图标
                IconManager.shared.loadImage(for: item.iconFileName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)

                // 物品名称
                Text(item.name)
                    .font(.body)
                    .foregroundColor(.primary)
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = item.name
                        } label: {
                            Label(
                                NSLocalizedString("Misc_Copy_Item_Name", comment: ""),
                                systemImage: "doc.on.doc"
                            )
                        }
                    }

                Spacer()

                // 订单数
                Text("\(item.orderCount)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - 溢价物品行视图

struct PremiumItemRowView: View {
    let item: PremiumItemInfo
    let structureId: Int64
    let characterId: Int

    var body: some View {
        NavigationLink(destination: StructureItemOrdersView(
            structureId: structureId,
            characterId: characterId,
            itemID: item.typeId,
            itemName: item.name,
            orderType: .sell,
            databaseManager: DatabaseManager.shared
        )) {
            HStack(spacing: 12) {
                // 物品图标
                IconManager.shared.loadImage(for: item.iconFileName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)

                // 物品名称
                Text(item.name)
                    .font(.body)
                    .foregroundColor(.primary)
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = item.name
                        } label: {
                            Label(
                                NSLocalizedString("Misc_Copy_Item_Name", comment: ""),
                                systemImage: "doc.on.doc"
                            )
                        }
                    }

                Spacer()

                // 溢价百分比
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(String(format: "%.1f", item.sellPremiumPercentage))%")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(item.sellPremiumPercentage > 0 ? .red : .green)
                        .fontWeight(.semibold)
                    Text("\(FormatUtil.formatISK(item.structureSellPrice))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}
