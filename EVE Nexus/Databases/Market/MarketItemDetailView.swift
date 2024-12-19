import SwiftUI
import Charts

// 星域数据模型
struct Region: Identifiable {
    let id: Int
    let name: String
}

struct MarketHistoryChartView: View {
    let history: [MarketHistory]
    let orders: [MarketOrder]
    
    // 格式化价格显示（简化版）
    private func formatPriceSimple(_ price: Double) -> String {
        let billion = 1_000_000_000.0
        let million = 1_000_000.0
        
        if price >= billion {
            let value = price / billion
            if value >= 100 {
                return String(format: "%.0fB", value)
            } else if value >= 10 {
                return String(format: "%.1fB", value)
            } else {
                return String(format: "%.2fB", value)
            }
        } else if price >= million {
            let value = price / million
            if value >= 100 {
                return String(format: "%.0fM", value)
            } else if value >= 10 {
                return String(format: "%.1fM", value)
            } else {
                return String(format: "%.2fM", value)
            }
        } else {
            if price >= 100 {
                return String(format: "%.0f", price)
            } else if price >= 10 {
                return String(format: "%.1f", price)
            } else {
                return String(format: "%.2f", price)
            }
        }
    }
    
    // 格式化日期显示（只显示月份）
    private func formatMonth(_ dateString: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US")
        guard let date = dateFormatter.date(from: dateString) else { return "" }
        
        dateFormatter.dateFormat = "MMM"
        return dateFormatter.string(from: date).uppercased()
    }
    
    // 获取当前总交易量
    private var totalVolume: Int {
        orders.filter { !$0.isBuyOrder }.reduce(0) { $0 + $1.volumeTotal }
    }
    
    var body: some View {
        let priceValues = history.map { $0.average }
        let volumeValues = history.map { Double($0.volume) }
        let maxVolume = volumeValues.max() ?? 1
        
        Chart {
            ForEach(history, id: \.date) { item in
                // 成交量柱状图 - 归一化处理
                let normalizedVolume = Double(item.volume) / maxVolume * (priceValues.max() ?? 1)
                BarMark(
                    x: .value("Date", item.date),
                    y: .value("Volume", normalizedVolume)
                )
                .foregroundStyle(.gray.opacity(0.8))
            }
            
            ForEach(history, id: \.date) { item in
                // 价格线
                LineMark(
                    x: .value("Date", item.date),
                    y: .value("Price", item.average)
                )
                .foregroundStyle(.blue)
                .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxis {
            // 价格轴（左侧）
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                if let price = value.as(Double.self) {
                    AxisValueLabel {
                        Text(formatPriceSimple(price))
                    }
                    AxisGridLine()
                }
            }
        }
        .chartYAxis {
            // 成交量轴（右侧）
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 5)) { value in
                if let price = value.as(Double.self) {
                    let volume = Int(price * maxVolume / (priceValues.max() ?? 1))
                    AxisValueLabel {
                        Text("\(volume)")
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .chartPlotStyle { plotArea in
            plotArea
                .background(.gray.opacity(0.1))
        }
        .chartXAxis {
            let dates = history.map { $0.date }
            AxisMarks(values: dates) { value in
                if let dateStr = value.as(String.self),
                   dates.firstIndex(of: dateStr).map({ $0 % (dates.count / 12 + 1) == 0 }) ?? false {
                    AxisValueLabel(anchor: .top) {
                        Text(formatMonth(dateStr))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    AxisGridLine()
                }
            }
        }
        .frame(height: 200)
        .padding(.top, 8)
    }
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
                Text("\(itemDetails.categoryName) / \(itemDetails.groupName) / ID:\(itemDetails.typeId)")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
        }
        .padding(.vertical, 8)
    }
}

// 缓存的图表视图
struct CachedMarketHistoryChartView: View {
    let history: [MarketHistory]
    let orders: [MarketOrder]
    
    var body: some View {
        MarketHistoryChartView(history: history, orders: orders)
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
        let query = """
            SELECT r.regionID, r.regionName
            FROM regions r
            WHERE r.regionID < 11000000
            ORDER BY r.regionName
        """
        
        if case .success(let rows) = databaseManager.executeQuery(query) {
            allRegions = rows.compactMap { row in
                guard let id = row["regionID"] as? Int,
                      let name = row["regionName"] as? String else {
                    return nil
                }
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
        NavigationView {
            List {
                if !pinnedRegions.isEmpty {
                    Section(header: Text(NSLocalizedString("Main_Market_Pinned_Regions", comment: ""))) {
                        ForEach(pinnedRegions) { region in
                            RegionRow(
                                region: region,
                                isSelected: region.id == selectedRegionID,
                                isEditMode: isEditMode,
                                onSelect: {
                                    selectedRegionID = region.id
                                    selectedRegionName = region.name
                                    let defaults: UserDefaultsManager = UserDefaultsManager.shared
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
                }
                
                Section(header: Text(isEditMode ? NSLocalizedString("Main_Market_Available_Regions", comment: "") : NSLocalizedString("Main_Market_All_Regions", comment: ""))) {
                    ForEach(unpinnedRegions) { region in
                        RegionRow(
                            region: region,
                            isSelected: region.id == selectedRegionID,
                            isEditMode: isEditMode,
                            onSelect: {
                                selectedRegionID = region.id
                                selectedRegionName = region.name
                                let defaults: UserDefaultsManager = UserDefaultsManager.shared
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
    @State private var selectedRegionID: Int = {
        let defaults: UserDefaultsManager = UserDefaultsManager.shared
        return defaults.selectedRegionID
    }()
    @State private var regions: [Region] = []
    @State private var groupedRegionsCache: [(key: String, regions: [Region])] = []
    @State private var selectedRegionName: String = "The Forge"
    @State private var searchText = ""
    @State private var isSearching = false
    
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
        
        let formattedFullPrice = numberFormatter.string(from: NSNumber(value: price)) ?? String(format: "%.2f", price)
        
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
                    if let orders = marketOrders {
                        MarketOrdersView(
                            itemID: itemID,
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
                    if isLoadingHistory {
                        ProgressView()
                    } else if let history = marketHistory, !history.isEmpty {
                        CachedMarketHistoryChartView(
                            history: history,
                            orders: marketOrders ?? []
                        )
                    } else {
                        Text("Null")
                            .foregroundColor(.secondary)
                    }
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
            RegionPickerView(selectedRegionID: $selectedRegionID, selectedRegionName: $selectedRegionName, databaseManager: databaseManager)
        }
        .onChange(of: selectedRegionID) { _, newValue in
            Task {
                await loadAllMarketData(forceRefresh: true)
            }
        }
        .onAppear {
            loadItemDetails()
            loadRegions()
            
            // 加载保存的星域ID和名称
            let defaults: UserDefaultsManager = UserDefaultsManager.shared
            selectedRegionID = defaults.selectedRegionID
            // 根据ID查找对应的星域名称
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
    
    private func loadItemDetails() {
        itemDetails = databaseManager.loadItemDetails(for: itemID)
    }

    
    private func loadMarketData(forceRefresh: Bool = false) async {
        guard !isLoadingPrice else { return }
        
        // 开始加载前清除旧数据
        marketOrders = nil
        lowestPrice = nil
        isLoadingPrice = true
        
        defer { isLoadingPrice = false }
        
        do {
            // 1. 如果不是强制刷新，先尝试从缓存获取
            if !forceRefresh {
                if let orders = StaticResourceManager.shared.getMarketOrders(itemId: itemID, regionId: selectedRegionID) {
                    marketOrders = orders
                    let sellOrders = orders.filter { !$0.isBuyOrder }
                    lowestPrice = sellOrders.map { $0.price }.min()
                    return
                }
            }
            
            // 2. 从网络加载数据
            NetworkManager.shared.setRegionID(selectedRegionID)
            let orders = try await NetworkManager.shared.fetchMarketOrders(
                typeID: itemID,
                forceRefresh: true
            )
            
            // 3. 确保在数据加载完成后，选中的星域ID没有改变
            guard selectedRegionID == NetworkManager.shared.regionID else {
                return
            }
            
            // 4. 保存到缓存
            try StaticResourceManager.shared.saveMarketOrders(orders, itemId: itemID, regionId: selectedRegionID)
            
            // 5. 更新UI
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
            // 1. 如果不是强制刷新，先尝试从缓存获取
            if !forceRefresh {
                if let history = StaticResourceManager.shared.getMarketHistory(itemId: itemID, regionId: selectedRegionID) {
                    marketHistory = history
                    return
                }
            }
            
            // 2. 从网络加载数据
            NetworkManager.shared.setRegionID(selectedRegionID)
            let history = try await NetworkManager.shared.fetchMarketHistory(
                typeID: itemID,
                forceRefresh: true
            )
            
            // 3. 确保在数据加载完成后，选中的星域ID没有改变
            guard selectedRegionID == NetworkManager.shared.regionID else {
                return
            }
            
            // 4. 保存到缓存
            try StaticResourceManager.shared.saveMarketHistory(history, itemId: itemID, regionId: selectedRegionID)
            
            // 5. 更新UI
            marketHistory = history
        } catch {
            Logger.error("加载市场历史数据失败: \(error)")
            marketHistory = []
        }
    }
    
    private func loadRegions() {
        let query = """
            SELECT r.regionID, r.regionName
            FROM regions r
            WHERE r.regionID < 11000000
            ORDER BY r.regionName
        """
        
        if case .success(let rows) = databaseManager.executeQuery(query) {
            regions = rows.compactMap { row in
                guard let id = row["regionID"] as? Int,
                      let name = row["regionName"] as? String else {
                    return nil
                }
                return Region(id: id, name: name)
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
        await (_, _) = (marketDataTask, historyDataTask)
    }
}
