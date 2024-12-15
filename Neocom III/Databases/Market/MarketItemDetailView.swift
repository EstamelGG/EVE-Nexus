import SwiftUI

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
                    
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Price")
                            Button(action: {
                                Task {
                                    await loadMarketData(forceRefresh: true)
                                }
                            }) {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundColor(.blue)
                            }
                            .disabled(isLoadingPrice)
                        }
                        if isLoadingPrice {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else if let price = lowestPrice {
                            Text("\(price, specifier: "%.2f") ISK")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Loading...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
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
}

#Preview {
    MarketItemDetailView(databaseManager: DatabaseManager(), itemID: 34)
} 
