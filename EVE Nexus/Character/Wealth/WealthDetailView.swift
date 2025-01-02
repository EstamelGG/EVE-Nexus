import SwiftUI

struct WealthDetailView: View {
    let title: String
    let valuedItems: [ValuedItem]
    let databaseManager: DatabaseManager
    @StateObject private var viewModel: CharacterWealthViewModel
    @State private var itemInfos: [[String: Any]] = []
    @State private var isLoading = true
    @State private var itemsWithoutPrice: [NoMarketPriceItem] = []
    
    struct NoMarketPriceItem: Identifiable {
        let id: Int
        let typeId: Int
        let quantity: Int
        var name: String = ""
        var iconFileName: String = ""
    }
    
    init(title: String, valuedItems: [ValuedItem], viewModel: CharacterWealthViewModel) {
        self.title = title
        self.valuedItems = valuedItems
        self.databaseManager = DatabaseManager()
        self._viewModel = StateObject(wrappedValue: viewModel)
    }
    
    private func getItemInfo(typeId: Int) -> (name: String, iconFileName: String)? {
        if let row = itemInfos.first(where: { ($0["type_id"] as? Int) == typeId }) {
            return (
                name: row["name"] as? String ?? "Unknown Item",
                iconFileName: row["icon_filename"] as? String ?? ""
            )
        }
        return nil
    }
    
    var body: some View {
        List {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Text(NSLocalizedString("Wealth_Detail_Loading", comment: ""))
                    Spacer()
                }
            } else {
                // 有市场价格的物品
                if !valuedItems.isEmpty {
                    Section(header: Text(NSLocalizedString("Wealth_Detail_HasPrice", comment: ""))) {
                        ForEach(valuedItems, id: \.typeId) { item in
                            if let itemInfo = getItemInfo(typeId: item.typeId) {
                                NavigationLink {
                                    MarketItemDetailView(databaseManager: databaseManager, itemID: item.typeId)
                                } label: {
                                    HStack {
                                        // 物品图标
                                        IconManager.shared.loadImage(for: itemInfo.iconFileName)
                                            .resizable()
                                            .frame(width: 32, height: 32)
                                            .cornerRadius(6)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(itemInfo.name)
                                            Text("\(item.quantity) × \(FormatUtil.formatISK(item.value)) ISK")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        // 总价值
                                        Text(FormatUtil.formatISK(item.totalValue) + " ISK")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .frame(height: 36)
                                }
                            }
                        }
                    }
                }
                
                // 无市场价格的物品
                if !itemsWithoutPrice.isEmpty {
                    Section(header: Text(NSLocalizedString("Wealth_Detail_NoPrice", comment: ""))) {
                        ForEach(itemsWithoutPrice) { item in
                            NavigationLink {
                                MarketItemDetailView(databaseManager: databaseManager, itemID: item.typeId)
                            } label: {
                                HStack {
                                    // 物品图标
                                    IconManager.shared.loadImage(for: item.iconFileName)
                                        .resizable()
                                        .frame(width: 32, height: 32)
                                        .cornerRadius(6)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name)
                                        Text("\(item.quantity)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .frame(height: 36)
                            }
                        }
                    }
                }
                
                // 如果两个列表都为空
                if valuedItems.isEmpty && itemsWithoutPrice.isEmpty {
                    HStack {
                        Spacer()
                        Text(NSLocalizedString("Wealth_Detail_NoData", comment: ""))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle(String(format: NSLocalizedString("Wealth_Detail_Title", comment: ""), title))
        .task {
            // 加载所有物品的信息
            let typeIds = valuedItems.map { $0.typeId }
            itemInfos = viewModel.getItemsInfo(typeIds: typeIds)
            
            // 获取无市场价格的物品
            itemsWithoutPrice = await viewModel.getItemsWithoutPrice()
            
            isLoading = false
        }
    }
}
