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

// 星域选择器视图
struct RegionPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let regions: [(key: String, regions: [Region])]
    let selectedRegionID: Int
    let onRegionSelect: (Region) -> Void
    
    // 常用星域列表
    private let frequentRegions = [
        Region(id: 10000002, name: "The Forge"),
        Region(id: 10000043, name: "Domain"),
        Region(id: 10000032, name: "Sinq Laison"),
        Region(id: 10000030, name: "Heimatar")
    ]
    
    var body: some View {
        NavigationView {
            List {
                // 常用星域分组
                Section(header: Text("#")) {
                    ForEach(frequentRegions) { region in
                        Button(action: {
                            onRegionSelect(region)
                            dismiss()
                        }) {
                            HStack {
                                Text(region.name)
                                Spacer()
                                if region.id == selectedRegionID {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .foregroundColor(.primary)
                    }
                }
                
                // 其他星域分组
                ForEach(regions, id: \.key) { group in
                    Section(header: Text(group.key)) {
                        ForEach(group.regions) { region in
                            Button(action: {
                                onRegionSelect(region)
                                dismiss()
                            }) {
                                HStack {
                                    Text(region.name)
                                    Spacer()
                                    if region.id == selectedRegionID {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                            .foregroundColor(.primary)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("选择星域")
            .navigationBarItems(trailing: Button("关闭") {
                dismiss()
            })
        }
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
    @State private var selectedRegionID: Int = 10000002 // 默认为 The Forge
    @State private var regions: [Region] = []
    @State private var groupedRegionsCache: [(key: String, regions: [Region])] = []
    @State private var selectedRegionName: String = "The Forge" // 添加状态变量存储当前星域名称
    
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
                            .disabled(isLoadingPrice)
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
                            } else if marketOrders?.isEmpty ?? true {
                                Text("Null")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("Loading...")
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
            RegionPickerView(
                regions: groupedRegionsCache,
                selectedRegionID: selectedRegionID
            ) { region in
                selectedRegionID = region.id
                selectedRegionName = region.name // 更新选中的星域名称
                // 保存选择的星域ID
                UserDefaults.standard.set(region.id, forKey: "selected_region_id")
                // 重新加载数据
                Task {
                    await loadMarketData(forceRefresh: true)
                    await loadHistoryData(forceRefresh: true)
                }
            }
        }
        .onAppear {
            loadItemDetails()
            loadMarketPath()
            loadRegions()
            
            // 加载保存的星域ID和名称
            if let savedRegionID = UserDefaults.standard.object(forKey: "selected_region_id") as? Int {
                selectedRegionID = savedRegionID
                // 根据ID查找对应的星域名称
                if let region = regions.first(where: { $0.id == savedRegionID }) {
                    selectedRegionName = region.name
                }
            }
            
            if isFromParent {
                Task {
                    await loadMarketData()
                    await loadHistoryData()
                }
                isFromParent = false
            }
        }
    }
    
    private func loadItemDetails() {
        itemDetails = databaseManager.loadItemDetails(for: itemID)
    }
    
    private func loadMarketPath() {
        // 从数据库加载市场路径
        if let path = databaseManager.getMarketPath(for: itemID) {
            marketPath = path
        }
    }
    
    private func loadMarketData(forceRefresh: Bool = false) async {
        guard !isLoadingPrice else { return }
        
        if !forceRefresh, let orders = marketOrders {
            let sellOrders = orders.filter { !$0.isBuyOrder }
            lowestPrice = sellOrders.map { $0.price }.min()
            return
        }
        
        isLoadingPrice = true
        defer { isLoadingPrice = false }
        
        do {
            NetworkManager.shared.setRegionID(selectedRegionID)
            marketOrders = try await NetworkManager.shared.fetchMarketOrders(
                typeID: itemID,
                forceRefresh: forceRefresh
            )
            if let orders = marketOrders {
                let sellOrders = orders.filter { !$0.isBuyOrder }
                lowestPrice = sellOrders.map { $0.price }.min()
            }
        } catch {
            Logger.error("加载市场订单失败: \(error)")
            marketOrders = []
        }
    }
    
    private func loadHistoryData(forceRefresh: Bool = false) async {
        guard !isLoadingHistory else { return }
        
        if !forceRefresh, let _ = marketHistory {
            return
        }
        
        isLoadingHistory = true
        defer { isLoadingHistory = false }
        
        do {
            NetworkManager.shared.setRegionID(selectedRegionID)
            marketHistory = try await NetworkManager.shared.fetchMarketHistory(
                typeID: itemID,
                forceRefresh: forceRefresh
            )
        } catch {
            Logger.error("加载市场历史数据失败: \(error)")
            marketHistory = []
        }
    }
    
    private func loadRegions() {
        let query = """
            SELECT regionID, regionName, UPPER(SUBSTR(regionName, 1, 1)) as initial
            FROM Regions
            ORDER BY initial, regionName
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
}

#Preview {
    MarketItemDetailView(databaseManager: DatabaseManager(), itemID: 34)
} 
