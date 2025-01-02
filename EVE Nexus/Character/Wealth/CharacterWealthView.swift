import SwiftUI

struct CharacterWealthView: View {
    @StateObject private var viewModel: CharacterWealthViewModel
    @State private var isRefreshing = false
    @State private var loadedTypes: Set<WealthType> = []
    @State private var hasLoadedInitialData = false
    @State private var cachedWealthItems: [WealthItem] = []
    @State private var cachedTotalWealth: Double = 0
    
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
                        if viewModel.isLoading && !hasLoadedInitialData {
                            Text(NSLocalizedString("Loading", comment: ""))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text(FormatUtil.formatISK(cachedTotalWealth) + " ISK")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if viewModel.isLoading && !hasLoadedInitialData {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            
            // 资产明细
            Section {
                ForEach(cachedWealthItems) { item in
                    if item.type == .wallet {
                        // 钱包余额不可点击
                        WealthItemRow(item: item)
                    } else {
                        // 其他项目可以点击查看详情
                        NavigationLink {
                            WealthDetailView(
                                title: NSLocalizedString("Wealth_\(item.type.rawValue)", comment: ""),
                                valuedItems: getValuedItems(for: item.type),
                                viewModel: viewModel,
                                wealthType: item.type
                            )
                        } label: {
                            WealthItemRow(item: item)
                        }
                    }
                }
                
                // 只在首次加载时显示加载项，刷新时不显示
                if viewModel.isLoading && !hasLoadedInitialData && cachedWealthItems.isEmpty {
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
            if !cachedWealthItems.isEmpty {
                Section(header: Text(NSLocalizedString("Wealth_Distribution", comment: ""))) {
                    WealthPieChart(items: cachedWealthItems, size: 200)
                        .padding(.vertical)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle(NSLocalizedString("Main_Wealth", comment: ""))
        .refreshable {
            isRefreshing = true
            loadedTypes.removeAll()
            hasLoadedInitialData = false
            // 只重置现有的资产分类数据
            cachedWealthItems = cachedWealthItems.map { item in
                WealthItem(
                    type: item.type,
                    value: 0,
                    details: NSLocalizedString("Calculating", comment: "")
                )
            }
            cachedTotalWealth = 0
            await loadData(forceRefresh: true)
            isRefreshing = false
        }
        .task {
            if !hasLoadedInitialData {
                await loadData()
            }
        }
    }
    
    private func loadData(forceRefresh: Bool = false) async {
        loadedTypes.removeAll()
        
        // 加载主要数据
        await viewModel.loadWealthData(forceRefresh: forceRefresh) { loadedType in
            loadedTypes.insert(loadedType)
        }
        
        // 更新缓存的数据
        cachedWealthItems = viewModel.wealthItems
        cachedTotalWealth = viewModel.totalWealth
        
        // 预加载详情数据
        if !hasLoadedInitialData || forceRefresh {
            async let assets: () = viewModel.loadAssetDetails()
            async let implants: () = viewModel.loadImplantDetails()
            async let orders: () = viewModel.loadOrderDetails()
            _ = await [assets, implants, orders]
        }
        
        hasLoadedInitialData = true
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
