import SwiftUI

struct CharacterWealthView: View {
    @StateObject private var viewModel: CharacterWealthViewModel
    @State private var isRefreshing = false
    @State private var loadedTypes: Set<WealthType> = []
    
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
                        if viewModel.isLoading {
                            Text(NSLocalizedString("Loading", comment: ""))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text(FormatUtil.formatISK(viewModel.totalWealth) + " ISK")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if viewModel.isLoading {
                        Spacer()
                        ProgressView()
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
                
                // 显示正在加载的项目
                if viewModel.isLoading {
                    ForEach(WealthType.allCases.filter { !loadedTypes.contains($0) }, id: \.self) { type in
                        HStack {
                            Image(type.icon)
                                .resizable()
                                .frame(width: 32, height: 32)
                                .cornerRadius(6)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(NSLocalizedString("Wealth_\(type.rawValue)", comment: ""))
                                Text(NSLocalizedString("Calculating", comment: ""))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            ProgressView()
                        }
                        .frame(height: 36)
                    }
                }
            }
            
            // 资产分布饼图
            if !viewModel.wealthItems.isEmpty {
                Section(header: Text(NSLocalizedString("Wealth_Distribution", comment: ""))) {
                    WealthPieChart(items: viewModel.wealthItems, size: 200)
                        .padding(.vertical)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle(NSLocalizedString("Main_Wealth", comment: ""))
        .refreshable {
            isRefreshing = true
            loadedTypes.removeAll()
            await loadData(forceRefresh: true)
            isRefreshing = false
        }
        .task {
            await loadData()
        }
    }
    
    private func loadData(forceRefresh: Bool = false) async {
        loadedTypes.removeAll()
        
        // 加载主要数据
        await viewModel.loadWealthData(forceRefresh: forceRefresh) { loadedType in
            loadedTypes.insert(loadedType)
        }
        
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
