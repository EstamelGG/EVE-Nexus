import SwiftUI

struct CharacterWealthView: View {
    let characterId: Int
    @StateObject private var viewModel: CharacterWealthViewModel
    
    init(characterId: Int) {
        self.characterId = characterId
        self._viewModel = StateObject(wrappedValue: CharacterWealthViewModel(characterId: characterId))
    }
    
    private func getDestination(for type: WealthType) -> some View {
        switch type {
        case .assets:
            return AnyView(WealthDetailView(
                title: NSLocalizedString("Wealth_Assets", comment: ""),
                valuedItems: viewModel.valuedAssets,
                viewModel: viewModel
            ).task {
                await viewModel.loadAssetDetails()
            })
        case .implants:
            return AnyView(WealthDetailView(
                title: NSLocalizedString("Wealth_Implants", comment: ""),
                valuedItems: viewModel.valuedImplants,
                viewModel: viewModel
            ).task {
                await viewModel.loadImplantDetails()
            })
        case .orders:
            return AnyView(WealthDetailView(
                title: NSLocalizedString("Wealth_Orders", comment: ""),
                valuedItems: viewModel.valuedOrders,
                viewModel: viewModel
            ).task {
                await viewModel.loadOrderDetails()
            })
        case .wallet:
            return AnyView(EmptyView())
        }
    }
    
    private func isNavigable(_ type: WealthType) -> Bool {
        return type != .wallet
    }
    
    var body: some View {
        List {
            if viewModel.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else {
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
                    .frame(height: 36)
                }
                
                // 资产明细
                Section {
                    ForEach(viewModel.wealthItems) { item in
                        if isNavigable(item.type) {
                            NavigationLink(destination: getDestination(for: item.type)) {
                                WealthItemRow(item: item)
                            }
                        } else {
                            WealthItemRow(item: item)
                        }
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Main_Wealth", comment: ""))
        .task {
            await viewModel.loadWealthData()
        }
        .refreshable {
            await viewModel.loadWealthData(forceRefresh: true)
        }
    }
}

// 提取出单独的行视图组件
struct WealthItemRow: View {
    let item: WealthItem
    
    var body: some View {
        HStack {
            Image(item.type.icon)
                .resizable()
                .frame(width: 36, height: 36)
                .cornerRadius(6)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("Wealth_" + item.type.rawValue, comment: ""))
                Text(item.details)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(FormatUtil.formatISK(item.value) + " ISK")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(height: 36)
    }
} 