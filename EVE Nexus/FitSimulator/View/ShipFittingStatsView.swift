import SwiftUI

struct ShipFittingStatsView: View {
    @ObservedObject var viewModel: FittingEditorViewModel
    
    var body: some View {
        List {
            // 资源统计部分 - 使用单独的组件
            ShipResourcesStatsView(viewModel: viewModel)
            
            // 抗性统计部分
            ShipResistancesStatsView(viewModel: viewModel)
                        
            // 电容统计部分
            ShipCapacitorStatsView(viewModel: viewModel)
            
            // 火力统计部分
            ShipFirepowerStatsView(viewModel: viewModel)
            
            // 修理统计部分
            ShipRepairStatsView(viewModel: viewModel)
            
            // 杂项部分
            ShipMiscStatsView(viewModel: viewModel)
        }
        .listStyle(InsetGroupedListStyle())
    }
}
