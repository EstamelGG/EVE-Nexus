import SwiftUI

struct MarketOrdersView: View {
    let itemID: Int
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
        List {
            ForEach(filteredOrders, id: \.orderId) { order in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(formatPrice(order.price))
                            .font(.headline)
                        
                        if let stationInfo = databaseManager.getStationInfo(stationID: order.locationId) {
                            Text(String(format: "%.1f", stationInfo.security) + " " + stationInfo.stationName)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Text("\(order.volumeRemain)")
                        .font(.headline)
                        .foregroundColor(.secondary)
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

#Preview {
    NavigationView {
        MarketOrdersView(
            itemID: 34,
            orders: [],
            databaseManager: DatabaseManager()
        )
    }
} 