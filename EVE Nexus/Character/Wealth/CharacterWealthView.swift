import SwiftUI

struct CharacterWealthView: View {
    @StateObject private var viewModel: CharacterWealthViewModel
    @State private var isRefreshing = false
    
    init(characterId: Int) {
        self._viewModel = StateObject(wrappedValue: CharacterWealthViewModel(characterId: characterId))
    }
    
    var body: some View {
        List {
            // 总资产
            Section {
                HStack {
                    Image("Folder")
                        .resizable()
                        .frame(width: 36, height: 36)
                        .cornerRadius(6)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("Wealth_Total", comment: ""))
                        Text(FormatUtil.formatISK(viewModel.totalWealth) + " ISK")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // 资产明细
            Section {
                ForEach(viewModel.wealthItems) { item in
                    if item.type == .wallet {
                        // 钱包余额不可点击
                        WealthItemRow(item: item)
                    } else {
                        // 其他项目可以点击查看详情
                        NavigationLink {
                            WealthDetailView(
                                title: NSLocalizedString("Wealth_\(item.type.rawValue)", comment: ""),
                                valuedItems: getValuedItems(for: item.type),
                                viewModel: viewModel
                            )
                        } label: {
                            WealthItemRow(item: item)
                        }
                    }
                }
            }
        }
        .navigationTitle("财富")
        .refreshable {
            isRefreshing = true
            await loadData(forceRefresh: true)
            isRefreshing = false
        }
        .task {
            await loadData()
        }
    }
    
    private func loadData(forceRefresh: Bool = false) async {
        // 加载主要数据
        await viewModel.loadWealthData(forceRefresh: forceRefresh)
        
        // 预加载详情数据
        async let assets: () = viewModel.loadAssetDetails()
        async let implants: () = viewModel.loadImplantDetails()
        async let orders: () = viewModel.loadOrderDetails()
        _ = await [assets, implants, orders]
    }
    
    private func getValuedItems(for type: WealthType) -> [ValuedItem] {
        switch type {
        case .assets:
            return viewModel.valuedAssets
        case .implants:
            return viewModel.valuedImplants
        case .orders:
            return viewModel.valuedOrders
        case .wallet:
            return []
        }
    }
}

struct WealthItemRow: View {
    let item: WealthItem
    
    var body: some View {
        HStack {
            // 图标
            Image(item.type.icon)
                .resizable()
                .frame(width: 32, height: 32)
                .cornerRadius(6)
            
            // 名称和详情
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("Wealth_\(item.type.rawValue)", comment: ""))
                Text(item.details)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // 价值
            Text(item.formattedValue + " ISK")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(height: 36)
    }
} 
