import SwiftUI

struct MarketOrdersView: View {
    let itemID: Int
    let orders: [MarketOrder]
    @ObservedObject var databaseManager: DatabaseManager
    @State private var showBuyOrders = false
    
    // 获取安全等级对应的颜色
    private func getSecurityColor(_ security: Double) -> Color {
        switch security {
        case 0.5...1.0:
            return .blue
        case 0.1..<0.5:
            return .yellow
        default:
            return .red
        }
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
        List {
            ForEach(filteredOrders, id: \.orderId) { order in
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
                        
                        if let stationInfo = databaseManager.getStationInfo(stationID: order.locationId) {
                            HStack(spacing: 4) {
                                Text(String(format: "%.1f", stationInfo.security))
                                    .foregroundColor(getSecurityColor(stationInfo.security))
                                Text(stationInfo.stationName)
                                    .foregroundColor(.secondary)
                            }
                            .font(.caption)
                        }
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Order Type", selection: $showBuyOrders) {
                    Text("Sell Orders").tag(false)
                    Text("Buy Orders").tag(true)
                }
                .pickerStyle(.segmented)
            }
        }
    }
}