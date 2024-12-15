import SwiftUI
import Charts

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
        Chart {
            ForEach(history, id: \.date) { item in
                // 成交量柱状图
                BarMark(
                    x: .value("Date", item.date),
                    y: .value("Volume", Double(item.volume))
                )
                .foregroundStyle(.gray.opacity(0.3))
                .position(by: .value("Type", "Volume"))
                
                // 价格线
                LineMark(
                    x: .value("Date", item.date),
                    y: .value("Price", item.average)
                )
                .foregroundStyle(.blue)
                .lineStyle(StrokeStyle(lineWidth: 1))
                .position(by: .value("Type", "Price"))
            }
        }
        .chartYAxis {
            // 价格轴（左侧）
            AxisMarks(preset: .extended, position: .leading, values: .automatic(desiredCount: 10)) { value in
                if let price = value.as(Double.self) {
                    AxisValueLabel {
                        Text(formatPriceSimple(price))
                    }
                    AxisGridLine()
                }
            }
            
            // 成交量轴（右侧）
            AxisMarks(preset: .extended, position: .trailing, values: .automatic(desiredCount: 10)) { value in
                let volumes = history.map { $0.volume }
                let maxVolume = Double(volumes.max() ?? 0)
                let minVolume = Double(volumes.min() ?? 0)
                let range = maxVolume - minVolume
                let step = range / 10
                
                let volumeValues = stride(from: minVolume, through: maxVolume, by: step).map { $0 }
                if volumeValues.contains(value.as(Double.self) ?? 0) {
                    AxisValueLabel {
                        Text("\(Int(value.as(Double.self) ?? 0))")
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .chartYScale(type: .linear)
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
        .padding(.top, 30)
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
                                Text("Loading...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .frame(height: 15)
                    }
                }
            }
            
            // 历史价格图表部分
            Section {
                VStack(alignment: .leading) {
                    Text("Price History")
                        .font(.headline)
                    if isLoadingHistory {
                        ProgressView()
                    } else if let history = marketHistory {
                        MarketHistoryChartView(history: history, orders: marketOrders ?? [])
                    } else {
                        Text("Loading...")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadItemDetails()
            loadMarketPath()
            Task {
                // 延迟0.5秒后加载价格
                try? await Task.sleep(nanoseconds: 500_000_000)
                await loadMarketData()
                await loadHistoryData()
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
        isLoadingPrice = true
        defer { isLoadingPrice = false }
        
        do {
            marketOrders = try await NetworkManager.shared.fetchMarketOrders(typeID: itemID, forceRefresh: forceRefresh)
            if let orders = marketOrders {
                let sellOrders = orders.filter { !$0.isBuyOrder }
                lowestPrice = sellOrders.map { $0.price }.min()
            }
        } catch {
            print("Failed to load market data: \(error)")
        }
    }
    
    private func loadHistoryData(forceRefresh: Bool = false) async {
        guard !isLoadingHistory else { return }
        isLoadingHistory = true
        defer { isLoadingHistory = false }
        
        do {
            marketHistory = try await NetworkManager.shared.fetchMarketHistory(typeID: itemID, forceRefresh: forceRefresh)
        } catch {
            print("Failed to load market history: \(error)")
        }
    }
}

#Preview {
    MarketItemDetailView(databaseManager: DatabaseManager(), itemID: 34)
} 
