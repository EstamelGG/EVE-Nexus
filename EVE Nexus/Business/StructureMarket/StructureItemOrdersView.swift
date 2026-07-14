import SwiftUI

// MARK: - 建筑内物品订单列表视图（单一类型）

struct StructureItemOrdersView: View {
    let structureId: Int64
    let characterId: Int
    let itemID: Int
    let itemName: String
    let orderType: MarketOrderType // 订单类型：buy 或 sell

    @ObservedObject var databaseManager: DatabaseManager
    @State private var orders: [MarketOrder] = []
    @State private var locationInfos: [Int64: LocationInfoDetail] = [:]
    @State private var isLoadingOrders = false
    @State private var isLoadingLocations = false
    @State private var itemDetails: ItemDetails?
    @State private var lastLoadedItemID: Int? = nil // 跟踪上次加载的 itemID
    @State private var lastLoadedOrderType: MarketOrderType? = nil // 跟踪上次加载的 orderType
    @State private var jitaPrices: (buy: Double, sell: Double)? = nil // Jita 空间站市场价格
    @State private var isLoadingJitaPrices = false // 是否正在加载 Jita 价格
    @State private var hasLoadedJitaPrices = false // 是否已加载过 Jita 价格
    @State private var showJitaMarket = false // 显示 Jita 市场
    let locationInfoLoader: LocationInfoLoader

    init(
        structureId: Int64,
        characterId: Int,
        itemID: Int,
        itemName: String,
        orderType: MarketOrderType,
        databaseManager: DatabaseManager
    ) {
        self.structureId = structureId
        self.characterId = characterId
        self.itemID = itemID
        self.itemName = itemName
        self.orderType = orderType
        self.databaseManager = databaseManager

        // 从 UserDefaults 获取当前选择的角色ID
        let currentCharacterId = UserDefaults.standard.integer(forKey: "currentCharacterId")
        locationInfoLoader = LocationInfoLoader(
            databaseManager: databaseManager, characterId: Int64(currentCharacterId)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // 订单列表
            List {
                // 物品信息 Section
                if let details = itemDetails {
                    Section {
                        NavigationLink(destination: MarketItemDetailView(
                            databaseManager: databaseManager,
                            itemID: details.typeId
                        )) {
                            ItemInfoView(itemDetails: details)
                        }
                    }
                }

                // Jita 市场价格 Section
                if let prices = jitaPrices {
                    Section(header: Text(NSLocalizedString("Structure_Market_Jita_Prices", comment: "Jita 市场价格"))) {
                        // 买入价格（买单最高价）
                        HStack {
                            Text(NSLocalizedString("Main_Market_Order_Buy", comment: "买单"))
                                .foregroundColor(.secondary)
                            Spacer()
                            HStack(spacing: 4) {
                                Text(FormatUtil.formatISK(prices.buy))
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.blue)
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                            }
                            .contextMenu {
                                Button {
                                    UIPasteboard.general.string = FormatUtil.formatISK(prices.buy)
                                } label: {
                                    Label(
                                        NSLocalizedString("Misc_Copy", comment: ""),
                                        systemImage: "doc.on.doc"
                                    )
                                }
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            showJitaMarket = true
                        }

                        // 卖出价格（卖单最低价）
                        HStack {
                            Text(NSLocalizedString("Main_Market_Order_Sell", comment: "卖单"))
                                .foregroundColor(.secondary)
                            Spacer()
                            HStack(spacing: 4) {
                                Text(FormatUtil.formatISK(prices.sell))
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.green)
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                            }
                            .contextMenu {
                                Button {
                                    UIPasteboard.general.string = FormatUtil.formatISK(prices.sell)
                                } label: {
                                    Label(
                                        NSLocalizedString("Misc_Copy", comment: ""),
                                        systemImage: "doc.on.doc"
                                    )
                                }
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            showJitaMarket = true
                        }
                    }
                } else if isLoadingJitaPrices {
                    Section(header: Text(NSLocalizedString("Structure_Market_Jita_Prices", comment: "Jita 市场价格"))) {
                        HStack {
                            Spacer()
                            ProgressView()
                                .scaleEffect(0.7)
                            Text(NSLocalizedString("Loading_Jita_Prices", comment: "正在加载 Jita 价格..."))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                }

                // 订单列表 Section
                if sortedOrders.isEmpty && !isLoadingOrders {
                    Section {
                        NoDataSection()
                    }
                } else if !sortedOrders.isEmpty {
                    Section(header: Text(orderType == .buy
                            ? NSLocalizedString("Main_Market_Order_Buy", comment: "买单")
                            : NSLocalizedString("Main_Market_Order_Sell", comment: "卖单")))
                    {
                        ForEach(sortedOrders, id: \.orderId) { order in
                            OrderRow(
                                order: order,
                                locationInfo: locationInfos[order.locationId],
                                isLoadingLocation: isLoadingLocations,
                                hidesLocation: itemID == MarketManager.plexTypeID
                            )
                        }
                    }
                    .listSectionSpacing(.compact)
                }
            }
            .listStyle(.insetGrouped)

            // 加载状态指示器
            if isLoadingOrders || isLoadingLocations {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text(
                        isLoadingOrders
                            ? NSLocalizedString("Loading_Orders", comment: "正在加载订单...")
                            : NSLocalizedString("Loading_Location_Info", comment: "正在加载地点信息...")
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .background(Color(UIColor.systemGroupedBackground))
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(itemName)
        .navigationBarTitleDisplayMode(.inline)
        .ignoresSafeArea(edges: .bottom)
        .sheet(isPresented: $showJitaMarket) {
            NavigationStack {
                MarketItemDetailView(
                    databaseManager: databaseManager,
                    itemID: itemID,
                    selectedRegionID: MarketManager.theForgeRegionID
                )
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(NSLocalizedString("Common_Done", comment: "完成")) {
                            showJitaMarket = false
                        }
                    }
                }
            }
        }
        .task {
            // 检查参数是否改变
            let needsReload = lastLoadedItemID != itemID || lastLoadedOrderType != orderType

            // 加载物品详情
            itemDetails = databaseManager.getItemDetails(for: itemID)

            // 如果参数改变或订单为空，重新加载数据
            if needsReload || orders.isEmpty {
                // 参数改变时，清空旧数据
                if needsReload {
                    await MainActor.run {
                        orders = []
                        locationInfos = [:]
                        jitaPrices = nil
                        hasLoadedJitaPrices = false // 重置 Jita 价格加载标志
                    }
                }

                await loadOrdersData()

                // 更新跟踪的参数
                await MainActor.run {
                    lastLoadedItemID = itemID
                    lastLoadedOrderType = orderType
                }
            }

            // 加载位置信息
            await loadLocationInfo()

            // 加载 Jita 价格（只在首次加载或 itemID 改变时加载）
            if needsReload || !hasLoadedJitaPrices {
                await loadJitaPrices()
            }
        }
    }

    // MARK: - 计算属性

    private var sortedOrders: [MarketOrder] {
        let filteredOrders = orders.filter { order in
            orderType == .buy ? order.isBuyOrder : !order.isBuyOrder
        }

        return filteredOrders.sorted { order1, order2 -> Bool in
            if order1.isBuyOrder {
                return order1.price > order2.price // 买单按价格从高到低
            } else {
                return order1.price < order2.price // 卖单按价格从低到高
            }
        }
    }

    // MARK: - 数据加载方法

    private func loadOrdersData(forceRefresh: Bool = false) async {
        isLoadingOrders = true
        defer { isLoadingOrders = false }

        do {
            let newOrders = try await StructureMarketManager.shared.getItemOrdersInStructure(
                structureId: structureId,
                characterId: characterId,
                typeId: itemID,
                forceRefresh: forceRefresh
            )

            await MainActor.run {
                orders = newOrders
            }

            Logger.info("从建筑获取到 \(newOrders.count) 个订单")
        } catch {
            Logger.error("加载建筑市场订单失败: \(error)")
            await MainActor.run {
                orders = []
            }
        }
    }

    private func loadLocationInfo() async {
        // PLEX 走全球市场，位置信息不可解析，直接不显示
        guard itemID != MarketManager.plexTypeID, !orders.isEmpty else { return }

        isLoadingLocations = true
        defer { isLoadingLocations = false }

        // 收集所有订单的位置ID
        let locationIds = Set(orders.map { $0.locationId })

        // 按类型分组位置ID
        let groupedIds = Dictionary(grouping: locationIds) { LocationType.from(id: $0) }

        // 清空之前的位置信息
        await MainActor.run {
            locationInfos = [:]
        }

        // 1. 优先加载空间站信息（通常在本地数据库中，速度快）
        if let stationIds = groupedIds[.station], !stationIds.isEmpty {
            let stationInfos = await locationInfoLoader.loadLocationInfo(
                locationIds: Set(stationIds)
            )

            await MainActor.run {
                locationInfos.merge(stationInfos) { _, new in new }
            }
        }

        // 2. 优先加载星系信息（通常在本地数据库中，速度快）
        if let systemIds = groupedIds[.solarSystem], !systemIds.isEmpty {
            let systemInfos = await locationInfoLoader.loadLocationInfo(
                locationIds: Set(systemIds)
            )

            await MainActor.run {
                locationInfos.merge(systemInfos) { _, new in new }
            }
        }

        // 3. 最后加载建筑物信息（需要API查询，速度慢）
        if let structureIds = groupedIds[.structure], !structureIds.isEmpty {
            let structureInfos = await locationInfoLoader.loadLocationInfo(
                locationIds: Set(structureIds)
            )

            await MainActor.run {
                locationInfos.merge(structureInfos) { _, new in new }
            }
        }
    }

    // MARK: - 物品信息视图

    private struct ItemInfoView: View {
        let itemDetails: ItemDetails

        var body: some View {
            HStack {
                IconManager.shared.loadImage(for: itemDetails.iconFileName)
                    .resizable()
                    .frame(width: 60, height: 60)
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 4) {
                    Text(itemDetails.name)
                        .font(.title3)
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = itemDetails.name
                            } label: {
                                Label(
                                    NSLocalizedString("Misc_Copy_Item_Name", comment: ""),
                                    systemImage: "doc.on.doc"
                                )
                            }
                        }

                    Text("\(itemDetails.categoryName) / \(itemDetails.groupName) / ID:\(itemDetails.typeId)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
        }
    }

    // MARK: - 订单行视图

    private struct OrderRow: View {
        let order: MarketOrder
        let locationInfo: LocationInfoDetail?
        let isLoadingLocation: Bool
        let hidesLocation: Bool

        var body: some View {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(FormatUtil.formatMarketPrice(order.price))
                            .font(.headline)
                        Spacer()
                        Text("Qty: \(order.volumeRemain)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if !hidesLocation {
                        if let locationInfo = locationInfo {
                            LocationInfoView(
                                stationName: locationInfo.stationName,
                                solarSystemName: locationInfo.solarSystemName,
                                security: locationInfo.security,
                                font: .caption,
                                textColor: .secondary
                            )
                        } else if isLoadingLocation {
                            // 地点信息加载中的占位视图
                            HStack(spacing: 4) {
                                Text(NSLocalizedString("Loading_Location", comment: "加载中..."))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                ProgressView()
                                    .scaleEffect(0.5)
                            }
                        } else {
                            Text(NSLocalizedString("Assets_Unknown_Location", comment: ""))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Jita 价格加载

    private func loadJitaPrices() async {
        // 如果已经加载过，直接返回
        if hasLoadedJitaPrices {
            return
        }

        await MainActor.run {
            isLoadingJitaPrices = true
        }

        // 使用 ESI 获取 Jita 空间站市场价格
        let regionID = MarketManager.theForgeRegionID // The Forge (Jita所在星域)
        let systemID = 30_000_142 // Jita星系ID
        let stationID = 60_003_760 // Jita 4-4 空间站 ID

        // 加载市场订单
        let marketOrders = await MarketOrdersUtil.loadRegionOrders(
            typeIds: [itemID],
            regionID: regionID,
            forceRefresh: false
        )

        guard let orders = marketOrders[itemID] else {
            await MainActor.run {
                jitaPrices = nil
                isLoadingJitaPrices = false
                hasLoadedJitaPrices = true
            }
            return
        }

        // 计算卖价（卖单最低价，限制在 Jita 空间站）
        let sellPriceResult = MarketOrdersUtil.calculatePrice(
            from: orders,
            orderType: .sell,
            quantity: nil,
            systemId: systemID,
            stationID: stationID
        )
        let sellPrice = sellPriceResult.price ?? 0

        // 计算买价（买单最高价，限制在 Jita 空间站）
        let buyPriceResult = MarketOrdersUtil.calculatePrice(
            from: orders,
            orderType: .buy,
            quantity: nil,
            systemId: systemID,
            stationID: stationID
        )
        let buyPrice = buyPriceResult.price ?? 0

        await MainActor.run {
            if buyPrice > 0 || sellPrice > 0 {
                jitaPrices = (buy: buyPrice, sell: sellPrice)
            } else {
                jitaPrices = nil
            }
            isLoadingJitaPrices = false
            hasLoadedJitaPrices = true
        }

        Logger.debug("成功加载物品 \(itemID) 的 Jita 空间站价格（ESI）: buy=\(buyPrice), sell=\(sellPrice)")
    }
}
