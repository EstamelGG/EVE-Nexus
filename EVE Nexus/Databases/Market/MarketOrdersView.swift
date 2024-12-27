import SwiftUI

struct MarketOrdersView: View {
    let itemID: Int
    let itemName: String
    let orders: [MarketOrder]
    @ObservedObject var databaseManager: DatabaseManager
    @State private var showBuyOrders = false
    
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
            TabView(selection: $showBuyOrders) {
                OrderListView(
                    orders: orders.filter { !$0.isBuyOrder },
                    databaseManager: databaseManager
                )
                .tag(false)
                
                OrderListView(
                    orders: orders.filter { $0.isBuyOrder },
                    databaseManager: databaseManager
                )
                .tag(true)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    Picker("Order Type", selection: $showBuyOrders) {
                        Text("\(NSLocalizedString("Orders_Sell", comment: "")) (\(orders.filter { !$0.isBuyOrder }.count))").tag(false)
                        Text("\(NSLocalizedString("Orders_Buy", comment: "")) (\(orders.filter { $0.isBuyOrder }.count))").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                }
                .background(Color(.systemGroupedBackground))
            }
        }
        .navigationTitle(itemName).lineLimit(1)
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // 订单列表视图
    private struct OrderListView: View {
        let orders: [MarketOrder]
        let databaseManager: DatabaseManager
        
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
                            OrderRow(order: order, databaseManager: databaseManager)
                        }
                    }
                    .listSectionSpacing(.compact)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.visible)
        }
    }
    
    // 订单行视图
    private struct OrderRow: View {
        let order: MarketOrder
        let databaseManager: DatabaseManager
        
        var body: some View {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(formatPrice(order.price))
                            .font(.headline)
                        Spacer()
                        Text("Qty: \(order.volumeRemain)")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    
                    if let stationInfo = databaseManager.getStationInfo(stationID: Int64(order.locationId)) {
                        LocationInfoView(
                            stationName: stationInfo.stationName,
                            solarSystemName: stationInfo.solarSystemName,
                            security: stationInfo.security,
                            font: .caption,
                            textColor: .secondary
                        )
                    } else {
                        Text("Unknown Station")
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
