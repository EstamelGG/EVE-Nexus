import Charts
import SwiftUI

// 星域数据模型
struct Region: Identifiable {
    let id: Int
    let name: String
}

struct MarketItemBasicInfoView: View {
    let itemDetails: ItemDetails
    let marketPath: [String]

    var body: some View {
        HStack {
            IconManager.shared.loadImage(for: itemDetails.iconFileName)
                .resizable()
                .frame(width: 60, height: 60)
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 4) {
                Text(itemDetails.name)
                    .font(.title)
                Text(
                    "\(itemDetails.categoryName) / \(itemDetails.groupName) / ID:\(itemDetails.typeId)"
                )
                .font(.subheadline)
                .foregroundColor(.gray)
            }
        }
    }
}

// 简单的选项模型
struct Option: Identifiable, Equatable {
    let id: Int
    let name: String
}

// 星域选择器视图
struct RegionPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedRegionID: Int
    @Binding var selectedRegionName: String
    let databaseManager: DatabaseManager
    @AppStorage("useEnglishSystemNames") private var useEnglishSystemNames: Bool = true

    @State private var isEditMode = false
    @State private var allRegions: [Region] = []
    @State private var pinnedRegions: [Region] = []

    private var unpinnedRegions: [Region] {
        allRegions.filter { region in
            !pinnedRegions.contains { $0.id == region.id }
        }
    }

    // 加载星域数据
    private func loadRegions() {
        let useEnglishSystemNames = UserDefaults.standard.bool(forKey: "useEnglishSystemNames")

        let query = """
                SELECT r.regionID, r.regionName, r.regionName_en
                FROM regions r
                WHERE r.regionID < 11000000
                ORDER BY r.regionName
            """

        if case let .success(rows) = databaseManager.executeQuery(query) {
            allRegions = rows.compactMap { row in
                guard let id = row["regionID"] as? Int,
                    let nameLocal = row["regionName"] as? String,
                    let nameEn = row["regionName_en"] as? String
                else {
                    return nil
                }
                let name = useEnglishSystemNames ? nameEn : nameLocal
                return Region(id: id, name: name)
            }

            // 从 UserDefaults 加载置顶的星域，保持用户设置的顺序
            let pinnedRegionIDs = UserDefaultsManager.shared.pinnedRegionIDs
            // 按照 pinnedRegionIDs 的顺序加载星域
            pinnedRegions = pinnedRegionIDs.compactMap { id in
                allRegions.first { $0.id == id }
            }

            // 如果当前选中的星域存在，确保它显示在正确的位置
            if let currentRegion = allRegions.first(where: { $0.id == selectedRegionID }) {
                if pinnedRegionIDs.contains(currentRegion.id) {
                    // 如果是置顶星域，确保它在置顶列表中
                    if !pinnedRegions.contains(where: { $0.id == currentRegion.id }) {
                        pinnedRegions.append(currentRegion)
                    }
                }
            }
        }
    }

    private func savePinnedRegions() {
        let pinnedIDs = pinnedRegions.map { $0.id }
        UserDefaultsManager.shared.pinnedRegionIDs = pinnedIDs
    }

    var body: some View {
        NavigationStack {
            List {
                // 置顶星域 Section
                Section(header: Text(NSLocalizedString("Main_Market_Pinned_Regions", comment: "")))
                {
                    if !pinnedRegions.isEmpty {
                        ForEach(pinnedRegions) { region in
                            RegionRow(
                                region: region,
                                isSelected: region.id == selectedRegionID,
                                isEditMode: isEditMode,
                                onSelect: {
                                    selectedRegionID = region.id
                                    selectedRegionName = region.name
                                    let defaults = UserDefaultsManager.shared
                                    defaults.selectedRegionID = region.id
                                    if !isEditMode {
                                        dismiss()
                                    }
                                },
                                onUnpin: {
                                    withAnimation {
                                        pinnedRegions.removeAll { $0.id == region.id }
                                        savePinnedRegions()
                                    }
                                }
                            )
                        }
                        .onMove { from, to in
                            pinnedRegions.move(fromOffsets: from, toOffset: to)
                            savePinnedRegions()
                        }
                    }

                    if !isEditMode {
                        Button(action: {
                            withAnimation {
                                isEditMode = true
                            }
                        }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.blue)
                                Text(NSLocalizedString("Main_Market_Add_Region", comment: ""))
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }

                // 所有星域 Section
                Section(
                    header: Text(
                        isEditMode
                            ? NSLocalizedString("Main_Market_Available_Regions", comment: "")
                            : NSLocalizedString("Main_Market_All_Regions", comment: ""))
                ) {
                    ForEach(unpinnedRegions) { region in
                        RegionRow(
                            region: region,
                            isSelected: region.id == selectedRegionID,
                            isEditMode: isEditMode,
                            onSelect: {
                                selectedRegionID = region.id
                                selectedRegionName = region.name
                                let defaults = UserDefaultsManager.shared
                                defaults.selectedRegionID = region.id
                                if !isEditMode {
                                    dismiss()
                                }
                            },
                            onPin: {
                                withAnimation {
                                    pinnedRegions.append(region)
                                    savePinnedRegions()
                                }
                            }
                        )
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(NSLocalizedString("Main_Market_Select_Region", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isEditMode {
                        Button(NSLocalizedString("Main_Market_Done", comment: "")) {
                            withAnimation {
                                isEditMode = false
                            }
                        }
                    }
                }
            }
            .environment(\.editMode, .constant(isEditMode ? .active : .inactive))
        }
        .onAppear {
            loadRegions()
        }
    }
}

// 星域行视图
struct RegionRow: View {
    let region: Region
    let isSelected: Bool
    let isEditMode: Bool
    let onSelect: () -> Void
    var onPin: (() -> Void)?
    var onUnpin: (() -> Void)?

    var body: some View {
        HStack {
            Text(region.name)
                .foregroundColor(isSelected ? .blue : .primary)

            Spacer()

            if isEditMode {
                if onUnpin != nil {
                    Button(role: .destructive, action: { onUnpin?() }) {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                } else if onPin != nil {
                    Button(action: { onPin?() }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.green)
                    }
                    .buttonStyle(.borderless)
                }
            } else {
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditMode {
                onSelect()
            }
        }
    }
}

extension Collection {
    /// 安全的下标访问
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

struct MarketItemDetailView: View {
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
    @State private var showRegionPicker = false
    @State private var selectedRegionID: Int = 0
    @State private var regions: [Region] = []
    @State private var groupedRegionsCache: [(key: String, regions: [Region])] = []
    @State private var selectedRegionName: String = ""
    @State private var searchText = ""
    @State private var isSearching = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("useEnglishSystemNames") private var useEnglishSystemNames: Bool = true
    private var chartHeight: CGFloat {
        // 根据设备类型和方向调整高度
        if horizontalSizeClass == .regular {
            // iPad 或大屏设备
            return 300
        } else {
            // iPhone 或小屏设备
            return UIScreen.main.bounds.height * 0.25  // 使用屏幕高度的 25%
        }
    }

    // 计算分组的星域列表
    private func calculateGroupedRegions() {
        let grouped = Dictionary(grouping: regions) { region in
            String(region.name.prefix(1)).uppercased()
        }
        groupedRegionsCache = grouped.map { (key: $0.key, regions: $0.value) }
            .sorted { $0.key < $1.key }
    }

    // 格式化价格显示
    private func formatPrice(_ price: Double) -> String {
        let billion = 1_000_000_000.0
        let million = 1_000_000.0

        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        numberFormatter.maximumFractionDigits = 2
        numberFormatter.minimumFractionDigits = 2

        let formattedFullPrice =
            numberFormatter.string(from: NSNumber(value: price)) ?? String(format: "%.2f", price)

        if price >= billion {
            let value = price / billion
            return String(format: "%.2fB (%@ ISK)", value, formattedFullPrice)
        } else if price >= million {
            let value = price / million
            return String(format: "%.2fM (%@ ISK)", value, formattedFullPrice)
        } else {
            return "\(formattedFullPrice) ISK"
        }
    }

    var body: some View {
        List {
            // 基本信息部分
            Section {
                if let details = itemDetails {
                    NavigationLink {
                        if let categoryID = itemDetails?.categoryID {
                            ItemInfoMap.getItemInfoView(
                                itemID: itemID,
                                categoryID: categoryID,
                                databaseManager: databaseManager
                            )
                        }
                    } label: {
                        MarketItemBasicInfoView(
                            itemDetails: details,
                            marketPath: marketPath
                        )
                    }
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
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else if let price = lowestPrice {
                                Text(formatPrice(price))
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
                    if let orders = marketOrders, let details = itemDetails {
                        MarketOrdersView(
                            itemID: itemID,
                            itemName: details.name,
                            orders: orders,
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
                .disabled(marketOrders == nil || isLoadingPrice || (marketOrders?.isEmpty ?? true))
            }

            // 历史价格图表部分
            Section {
                VStack(alignment: .leading) {
                    HStack {
                        Text(NSLocalizedString("Main_Market_Price_History", comment: ""))
                            .font(.headline)
                        if !isLoadingHistory {
                            Button(action: {
                                Task {
                                    await loadHistoryData(forceRefresh: true)
                                }
                            }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                    }

                    // 使用 ZStack 来保持固定高度
                    ZStack {
                        if isLoadingHistory {
                            ProgressView()
                        } else if let history = marketHistory, !history.isEmpty {
                            MarketHistoryChartView(
                                history: history,
                                orders: marketOrders ?? []
                            )
                        } else {
                            Text("-")
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(height: chartHeight)  // 使用动态高度
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showRegionPicker = true
                }) {
                    Text(selectedRegionName)
                        .foregroundColor(.blue)
                }
            }
        }
        .sheet(isPresented: $showRegionPicker) {
            RegionPickerView(
                selectedRegionID: $selectedRegionID, selectedRegionName: $selectedRegionName,
                databaseManager: databaseManager
            )
        }
        .onChange(of: selectedRegionID) { _, _ in
            Task {
                await loadAllMarketData(forceRefresh: true)
            }
        }
        .onAppear {
            let defaults = UserDefaultsManager.shared
            if selectedRegionID == 0 {
                selectedRegionID = defaults.selectedRegionID
                selectedRegionName = defaults.defaultRegionName
            }

            itemDetails = databaseManager.getItemDetails(for: itemID)
            loadRegions()

            if let region = regions.first(where: { $0.id == selectedRegionID }) {
                selectedRegionName = region.name
            }

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
            // 从 MarketOrdersAPI 获取数据
            let orders = try await MarketOrdersAPI.shared.fetchMarketOrders(
                typeID: itemID,
                regionID: selectedRegionID,
                forceRefresh: forceRefresh
            )

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
            // 从 MarketHistoryAPI 获取数据
            let history = try await MarketHistoryAPI.shared.fetchMarketHistory(
                typeID: itemID,
                regionID: selectedRegionID,
                forceRefresh: forceRefresh
            )

            // 更新UI
            marketHistory = history
        } catch {
            Logger.error("加载市场历史数据失败: \(error)")
            marketHistory = []
        }
    }

    private func loadRegions() {
        let useEnglishSystemNames = UserDefaults.standard.bool(forKey: "useEnglishSystemNames")

        let query = """
                SELECT r.regionID, r.regionName, r.regionName_en
                FROM regions r
                WHERE r.regionID < 11000000
                ORDER BY r.regionName
            """

        if case let .success(rows) = databaseManager.executeQuery(query) {
            for row in rows {
                if let regionId = row["regionID"] as? Int,
                    let regionNameLocal = row["regionName"] as? String,
                    let regionNameEn = row["regionName_en"] as? String
                {
                    let regionName = useEnglishSystemNames ? regionNameEn : regionNameLocal
                    regions.append(Region(id: regionId, name: regionName))
                }
            }
            calculateGroupedRegions()
        }
    }

    // 并发加载所有市场数据
    private func loadAllMarketData(forceRefresh: Bool = false) async {
        // 并发执行两个加载任务
        async let marketDataTask: () = loadMarketData(forceRefresh: forceRefresh)
        async let historyDataTask: () = loadHistoryData(forceRefresh: forceRefresh)

        // 等待两个任务都完成
        await _ = (marketDataTask, historyDataTask)
    }
}
