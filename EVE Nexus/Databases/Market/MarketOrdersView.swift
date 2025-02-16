import SwiftUI

struct MarketOrdersView: View {
    let itemID: Int
    let itemName: String
    let orders: [MarketOrder]
    @ObservedObject var databaseManager: DatabaseManager
    @State private var showBuyOrders = false
    @State private var locationInfos: [Int64: LocationInfoDetail] = [:]
    @State private var isLoading = true
    let locationInfoLoader: LocationInfoLoader
    
    init(itemID: Int, itemName: String, orders: [MarketOrder], databaseManager: DatabaseManager) {
        self.itemID = itemID
        self.itemName = itemName
        self.orders = orders
        self.databaseManager = databaseManager
        
        // 从 UserDefaults 获取当前选择的角色ID
        let currentCharacterId = UserDefaults.standard.integer(forKey: "currentCharacterId")
        self.locationInfoLoader = LocationInfoLoader(databaseManager: databaseManager, characterId: Int64(currentCharacterId))
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
    
    private var filteredOrders: [MarketOrder] {
        let filtered = orders.filter { $0.isBuyOrder == showBuyOrders }
        return filtered.sorted { (order1, order2) -> Bool in
            if showBuyOrders {
                return order1.price > order2.price // 买单按价格从高到低
            } else {
                return order1.price < order2.price // 卖单按价格从低到高
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                VStack {
                    ProgressView()
                    Text(NSLocalizedString("Main_Database_Loading", comment: ""))
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                }
                .padding()
            } else {
                // 顶部选择器
                Picker("Order Type", selection: $showBuyOrders) {
                    Text("\(NSLocalizedString("Orders_Sell", comment: "")) (\(orders.filter { !$0.isBuyOrder }.count))").tag(false)
                    Text("\(NSLocalizedString("Orders_Buy", comment: "")) (\(orders.filter { $0.isBuyOrder }.count))").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 4)
                
                // 内容视图
                TabView(selection: $showBuyOrders) {
                    OrderListView(
                        orders: orders.filter { !$0.isBuyOrder },
                        locationInfos: locationInfos
                    )
                    .tag(false)
                    
                    OrderListView(
                        orders: orders.filter { $0.isBuyOrder },
                        locationInfos: locationInfos
                    )
                    .tag(true)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .navigationTitle(itemName).lineLimit(1)
        .navigationBarTitleDisplayMode(.inline)
        .ignoresSafeArea(edges: .bottom)
        .task {
            isLoading = true
            // 收集所有订单的位置ID
            let locationIds = Set(orders.map { $0.locationId })
            // 加载位置信息
            let infos = await locationInfoLoader.loadLocationInfo(locationIds: locationIds)
            locationInfos = infos
            isLoading = false
        }
    }
    
    // 订单列表视图
    private struct OrderListView: View {
        let orders: [MarketOrder]
        let locationInfos: [Int64: LocationInfoDetail]
        
        private var sortedOrders: [MarketOrder] {
            orders.sorted { (order1, order2) -> Bool in
                if order1.isBuyOrder {
                    return order1.price > order2.price // 买单按价格从高到低
                } else {
                    return order1.price < order2.price // 卖单按价格从低到高
                }
            }
        }
        
        var body: some View {
            List {
                if orders.isEmpty {
                    Section {
                        HStack {
                            Spacer()
                            VStack(spacing: 4) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 30))
                                    .foregroundColor(.gray)
                                Text(NSLocalizedString("Orders_No_Data", comment: ""))
                                .foregroundColor(.gray)
                            }
                            .padding()
                            Spacer()
                        }
                    }
                    .listSectionSpacing(.compact)
                } else {
                    Section {
                        ForEach(sortedOrders, id: \.orderId) { order in
                            OrderRow(order: order, locationInfo: locationInfos[order.locationId])
                        }
                    }
                    .listSectionSpacing(.compact)
                }
            }
            .listStyle(.insetGrouped)
        }
    }
    
    // 订单行视图
    private struct OrderRow: View {
        let order: MarketOrder
        let locationInfo: LocationInfoDetail?
        
        var body: some View {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(formatPrice(order.price))
                            .font(.headline)
                        Spacer()
                        Text("Qty: \(order.volumeRemain)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let locationInfo = locationInfo {
                        LocationInfoView(
                            stationName: locationInfo.stationName,
                            solarSystemName: locationInfo.solarSystemName,
                            security: locationInfo.security,
                            font: .caption,
                            textColor: .secondary
                        )
                    } else {
                        Text(NSLocalizedString("Assets_Unknown_Location", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        
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
    }
}
