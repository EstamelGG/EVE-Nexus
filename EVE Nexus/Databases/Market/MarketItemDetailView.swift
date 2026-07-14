import Charts
import SwiftUI

struct MarketItemBasicInfoView: View {
    let itemDetails: ItemDetails
    let marketPath: [String]
    let onInfoTap: () -> Void

    @State private var itemNameShowsEnglish = false

    private var itemNameCanToggleEnglish: Bool {
        guard let en = itemDetails.en_name, !en.isEmpty else { return false }
        return en != itemDetails.name
    }

    private var itemTitleDisplayName: String {
        if itemNameCanToggleEnglish, itemNameShowsEnglish, let en = itemDetails.en_name {
            return en
        }
        return itemDetails.name
    }

    private var itemTitleAlternateName: String? {
        guard itemNameCanToggleEnglish, let en = itemDetails.en_name else { return nil }
        return itemNameShowsEnglish ? itemDetails.name : en
    }

    private static let itemNameToggleAnimation = Animation.spring(
        response: 0.38,
        dampingFraction: 0.82
    )

    private func toggleItemNameLanguageAnimated() {
        guard itemNameCanToggleEnglish else { return }
        withAnimation(Self.itemNameToggleAnimation) {
            itemNameShowsEnglish.toggle()
        }
    }

    var body: some View {
        HStack(alignment: .center) {
            IconManager.shared.loadImage(for: itemDetails.iconFileName)
                .resizable()
                .frame(width: 60, height: 60)
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 0) {
                    Text(itemTitleDisplayName)
                        .font(.title)
                        .multilineTextAlignment(.leading)
                        .contentTransition(.interpolate)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: toggleItemNameLanguageAnimated)
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = itemTitleDisplayName
                    } label: {
                        Label(
                            NSLocalizedString("Misc_Copy_Name", comment: ""),
                            systemImage: "doc.on.doc"
                        )
                    }
                    if let alt = itemTitleAlternateName {
                        Button {
                            UIPasteboard.general.string = alt
                        } label: {
                            Label(
                                NSLocalizedString("Misc_Copy_Trans", comment: ""),
                                systemImage: "translate"
                            )
                        }
                    }
                }
                Text(
                    "\(itemDetails.categoryName) / \(itemDetails.groupName) / ID:\(itemDetails.typeId)"
                )
                .font(.subheadline)
                .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onInfoTap) {
                Image(systemName: "info.circle")
                    .font(.system(size: 18))
            }
            .buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: itemDetails.typeId) { _, _ in
            itemNameShowsEnglish = false
        }
    }
}

/// 时间范围枚举
enum PriceHistoryTimeRange: String, CaseIterable {
    case oneMonth = "1M"
    case threeMonths = "3M"
    case oneYear = "1Y"

    var days: Int {
        switch self {
        case .oneMonth:
            return 30
        case .threeMonths:
            return 90
        case .oneYear:
            return 365
        }
    }

    var localizedName: String {
        switch self {
        case .oneMonth:
            return NSLocalizedString("Main_Market_Price_History_1M", comment: "")
        case .threeMonths:
            return NSLocalizedString("Main_Market_Price_History_3M", comment: "")
        case .oneYear:
            return NSLocalizedString("Main_Market_Price_History_1Y", comment: "")
        }
    }
}

struct MarketItemDetailView: View {
    /// 同一视图只能稳定呈现一个 sheet；用枚举合并，避免「presentation is in progress」与误 dismiss
    private enum ActiveSheet: String, Identifiable {
        case regionPicker
        case itemInfo

        var id: String {
            rawValue
        }
    }

    @ObservedObject var databaseManager: DatabaseManager
    let itemID: Int
    @State private var marketPath: [String] = []
    @State private var itemDetails: ItemDetails?
    @State private var lowestPrice: Double?
    @State private var isLoadingPrice: Bool = false
    @State private var marketOrders: [MarketOrder]?
    @State private var marketHistory: [MarketHistory]?
    @State private var isLoadingHistory: Bool = false
    @State private var isFromParent: Bool = true
    @State private var activeSheet: ActiveSheet?
    @State private var selectedRegionID: Int
    @State private var selectedRegionName: String = ""
    @State private var saveSelection: Bool = true
    @State private var structureOrdersProgress: StructureOrdersProgress? = nil // 建筑订单加载进度
    @State private var selectedTimeRange: PriceHistoryTimeRange = .oneYear // 默认选择近一年
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var chartHeight: CGFloat {
        // 根据设备类型和方向调整高度
        if horizontalSizeClass == .regular {
            // iPad 或大屏设备
            return 300
        } else {
            // iPhone 或小屏设备
            return UIScreen.main.bounds.height * 0.25 // 使用屏幕高度的 25%
        }
    }

    init(databaseManager: DatabaseManager, itemID: Int, selectedRegionID: Int = 0) {
        self.databaseManager = databaseManager
        self.itemID = itemID
        _selectedRegionID = State(initialValue: selectedRegionID)
    }

    /// 推迟到下一 run loop 再呈现，避免与 NavigationStack / List / 其它转场叠在一起
    private func presentSheet(_ sheet: ActiveSheet) {
        Task { @MainActor in
            await Task.yield()
            activeSheet = sheet
        }
    }

    var body: some View {
        List {
            // 基本信息部分
            Section {
                if let details = itemDetails {
                    MarketItemBasicInfoView(
                        itemDetails: details,
                        marketPath: marketPath,
                        onInfoTap: { presentSheet(.itemInfo) }
                    )
                }
            }

            // 价格信息部分
            Section {
                // 当前价格
                HStack {
                    IconManager.shared.loadImage(for: "icon_52996_64.png")
                        .resizable()
                        .frame(width: 40, height: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(NSLocalizedString("Main_Market_Current_Price", comment: ""))
                            Button(action: {
                                Task {
                                    await loadMarketData(forceRefresh: true)
                                }
                            }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                            Spacer()
                        }
                        HStack {
                            if isLoadingPrice {
                                if StructureMarketManager.isStructureId(selectedRegionID),
                                   let progress = structureOrdersProgress
                                {
                                    switch progress {
                                    case let .loading(currentPage, totalPages):
                                        HStack(spacing: 4) {
                                            ProgressView()
                                                .scaleEffect(0.7)
                                            Text("\(currentPage)/\(totalPages)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    case .completed:
                                        ProgressView()
                                            .scaleEffect(0.7)
                                    }
                                } else {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                }
                            } else if let price = lowestPrice {
                                Text(FormatUtil.formatMarketPrice(price))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("-")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .frame(height: 15)
                    }
                }

                // 市场订单按钮
                NavigationLink {
                    if let details = itemDetails {
                        MarketOrdersView(
                            itemID: itemID,
                            itemName: details.name,
                            regionID: selectedRegionID,
                            initialOrders: marketOrders ?? [],
                            databaseManager: databaseManager
                        )
                    }
                } label: {
                    HStack {
                        Text(NSLocalizedString("Main_Market_Show_market_orders", comment: ""))
                        Spacer()
                        if isLoadingPrice {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                    }
                }
                .disabled(isLoadingPrice)

                NavigationLink {
                    MarketQuickbarDestinationPickerView(
                        databaseManager: databaseManager,
                        typeID: itemID
                    )
                } label: {
                    HStack(alignment: .center) {
                        Image("searchmarket")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 32)
                            .cornerRadius(6)
                        Text(NSLocalizedString("Main_Market_Add_To_Watchlist_Button", comment: ""))
                            .foregroundColor(.primary)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
            }

            // 历史价格图表部分
            Section {
                VStack(alignment: .leading) {
                    HStack {
                        Text(NSLocalizedString("Main_Market_Price_History", comment: ""))
                            .font(.headline)
                        Spacer()
                        Picker("", selection: $selectedTimeRange) {
                            ForEach(PriceHistoryTimeRange.allCases, id: \.self) { range in
                                Text(range.localizedName).tag(range)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 200)
                    }

                    // 使用 ZStack 来保持固定高度
                    ZStack {
                        if isLoadingHistory {
                            ProgressView()
                        } else if let history = marketHistory, !history.isEmpty {
                            MarketHistoryChartView(
                                history: filteredHistory(for: history, timeRange: selectedTimeRange),
                                orders: marketOrders ?? []
                            )
                        } else {
                            Text("-")
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(height: chartHeight) // 使用动态高度
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("Main_Market", comment: "市场详情"))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    presentSheet(.regionPicker)
                }) {
                    Text(selectedRegionName)
                        .foregroundColor(.blue)
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .regionPicker:
                MarketRegionPickerView(
                    selectedRegionID: $selectedRegionID, selectedRegionName: $selectedRegionName,
                    saveSelection: $saveSelection,
                    databaseManager: databaseManager
                )
            case .itemInfo:
                NavigationStack {
                    ItemInfoMap.getItemInfoView(
                        itemID: itemID,
                        databaseManager: databaseManager
                    )
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(NSLocalizedString("Common_Done", comment: "完成")) {
                                activeSheet = nil
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: selectedRegionID) { _, _ in
            Task {
                await loadAllMarketData()
            }
        }
        .onAppear {
            let defaults = UserDefaultsManager.shared

            // 验证和设置selectedRegionID
            if selectedRegionID == 0 {
                let defaultRegionID = defaults.selectedRegionID
                // 验证默认选择的区域是否有效
                if isValidRegionID(defaultRegionID) {
                    selectedRegionID = defaultRegionID
                    selectedRegionName = getRegionName(for: defaultRegionID)
                } else {
                    // 如果默认区域无效，回退到Jita
                    Logger.warning("默认选择的区域ID \(defaultRegionID) 无效，回退到Jita")
                    selectedRegionID = MarketManager.theForgeRegionID // The Forge (Jita)
                    selectedRegionName = getRegionName(for: selectedRegionID)
                    // 更新默认设置
                    defaults.selectedRegionID = selectedRegionID
                }
            } else {
                // 验证当前选择的区域是否有效
                if isValidRegionID(selectedRegionID) {
                    selectedRegionName = getRegionName(for: selectedRegionID)
                } else {
                    Logger.warning("当前选择的区域ID \(selectedRegionID) 无效，回退到Jita")
                    selectedRegionID = MarketManager.theForgeRegionID // The Forge (Jita)
                    selectedRegionName = getRegionName(for: selectedRegionID)
                }
            }

            itemDetails = databaseManager.getItemDetails(for: itemID)

            if isFromParent {
                Task {
                    await loadAllMarketData()
                }
                isFromParent = false
            }
        }
    }

    private func loadMarketData(forceRefresh: Bool = false) async {
        guard !isLoadingPrice else { return }

        // 开始加载前清除旧数据
        marketOrders = nil
        lowestPrice = nil
        isLoadingPrice = true

        defer { isLoadingPrice = false }

        do {
            let orders: [MarketOrder]

            // 判断是否选择了建筑
            if StructureMarketManager.isStructureId(selectedRegionID) {
                // 选择了建筑，使用建筑订单API
                guard
                    let structureId = StructureMarketManager.getStructureId(from: selectedRegionID)
                else {
                    Logger.error("无效的建筑ID: \(selectedRegionID)")
                    marketOrders = []
                    lowestPrice = nil
                    return
                }

                // 获取建筑对应的角色ID
                guard let structure = getStructureById(structureId) else {
                    Logger.error("未找到建筑信息: \(structureId)")
                    marketOrders = []
                    lowestPrice = nil
                    return
                }

                orders = try await StructureMarketManager.shared.getItemOrdersInStructure(
                    structureId: structureId,
                    characterId: structure.characterId,
                    typeId: itemID,
                    forceRefresh: forceRefresh,
                    progressCallback: { progress in
                        Task { @MainActor in
                            structureOrdersProgress = progress
                        }
                    }
                )

                Logger.info("从建筑 \(structure.structureName) 获取到 \(orders.count) 个订单")
            } else {
                // 选择了星域，使用原有的API
                orders = try await MarketOrdersAPI.shared.fetchMarketOrders(
                    typeID: itemID,
                    regionID: selectedRegionID,
                    forceRefresh: forceRefresh
                )
            }

            // 更新UI
            marketOrders = orders
            let sellOrders = orders.filter { !$0.isBuyOrder }
            lowestPrice = sellOrders.map { $0.price }.min()
        } catch {
            Logger.error("加载市场订单失败: \(error)")
            marketOrders = []
            lowestPrice = nil
        }
    }

    private func loadHistoryData(forceRefresh: Bool = false) async {
        guard !isLoadingHistory else { return }

        // 开始加载前清除旧数据
        marketHistory = nil
        isLoadingHistory = true

        defer { isLoadingHistory = false }

        do {
            // 确定用于获取历史价格的星域ID
            let historyRegionID: Int

            // 判断是否选择了建筑
            if StructureMarketManager.isStructureId(selectedRegionID) {
                // 选择了建筑，获取建筑所属的星域ID
                guard let structureId = StructureMarketManager.getStructureId(from: selectedRegionID),
                      let structure = getStructureById(structureId)
                else {
                    Logger.error("未找到建筑信息，无法获取历史价格: \(selectedRegionID)")
                    marketHistory = []
                    return
                }
                historyRegionID = structure.regionId
                Logger.info("使用建筑 \(structure.structureName) 所属星域 \(historyRegionID) 获取历史价格")
            } else {
                // 选择了星域，直接使用星域ID
                historyRegionID = selectedRegionID
            }

            // 从 MarketHistoryAPI 获取数据
            let history = try await MarketHistoryAPI.shared.fetchMarketHistory(
                typeID: itemID,
                regionID: historyRegionID,
                forceRefresh: forceRefresh
            )

            // 更新UI
            marketHistory = history
        } catch {
            Logger.error("加载市场历史数据失败: \(error)")
            marketHistory = []
        }
    }

    /// 并发加载所有市场数据
    private func loadAllMarketData(forceRefresh: Bool = false) async {
        // 并发执行两个加载任务
        async let marketDataTask: () = loadMarketData(forceRefresh: forceRefresh)
        async let historyDataTask: () = loadHistoryData(forceRefresh: forceRefresh)

        // 等待两个任务都完成
        await _ = (marketDataTask, historyDataTask)
    }

    /// 根据区域ID获取区域名称的方法
    private func getRegionName(for regionID: Int) -> String {
        // 判断是否是建筑ID
        if StructureMarketManager.isStructureId(regionID) {
            guard let structureId = StructureMarketManager.getStructureId(from: regionID),
                  let structure = getStructureById(structureId)
            else {
                return "Unknown Structure"
            }
            return structure.structureName
        }

        // 区域名称走内存
        return SDEMemoryStore.regionName(for: regionID) ?? "Unknown Region"
    }

    /// 根据建筑ID获取建筑信息
    private func getStructureById(_ structureId: Int64) -> MarketStructure? {
        return MarketStructureManager.shared.structures.first { $0.structureId == Int(structureId) }
    }

    /// 根据时间范围过滤历史数据
    private func filteredHistory(for history: [MarketHistory], timeRange: PriceHistoryTimeRange) -> [MarketHistory] {
        let calendar = Calendar.current
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        guard let cutoffDate = calendar.date(byAdding: .day, value: -timeRange.days, to: Date()) else {
            return history
        }

        let filtered = history.filter { historyItem in
            guard let itemDate = dateFormatter.date(from: historyItem.date) else {
                return false
            }
            return itemDate >= cutoffDate
        }

        // 按日期排序，确保数据按时间顺序显示
        return filtered.sorted { item1, item2 in
            guard let date1 = dateFormatter.date(from: item1.date),
                  let date2 = dateFormatter.date(from: item2.date)
            else {
                return false
            }
            return date1 < date2
        }
    }

    /// 验证区域ID是否有效（星域或存在的建筑）
    private func isValidRegionID(_ regionID: Int) -> Bool {
        // 检查是否是建筑ID（负数表示建筑）
        if StructureMarketManager.isStructureId(regionID) {
            // 验证建筑是否存在
            guard let structureId = StructureMarketManager.getStructureId(from: regionID) else {
                return false
            }
            return getStructureById(structureId) != nil
        }

        // 检查是否是有效的星域ID
        if regionID > 0 && regionID < 11_000_000 {
            return SDEMemoryStore.regionNames[regionID] != nil
        }

        return false
    }
}

// MARK: - 市场建筑行视图

struct MarketStructureRow: View {
    let structure: MarketStructure
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // 建筑图标（按 typeId 查询）
            IconManager.shared.loadImage(for: structure.iconFileName)
                .resizable()
                .frame(width: 32, height: 32)
                .cornerRadius(6)

            // 建筑信息
            VStack(alignment: .leading, spacing: 2) {
                Text(structure.structureName)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(formatSystemSecurity(structure.security))
                        .foregroundColor(getSecurityColor(structure.security))
                        .font(.caption)

                    Text("\(structure.systemName)")
                        .foregroundColor(.secondary)
                        .font(.caption)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundColor(.blue)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}
