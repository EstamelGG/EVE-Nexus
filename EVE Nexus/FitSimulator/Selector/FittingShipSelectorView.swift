import SwiftUI

// 飞船选择器
struct FittingShipSelectorView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var showSelected = false
    @Environment(\.dismiss) private var dismiss

    // 舰船子分组ID (从Ships 4下获取)
    @State private var allowedTopMarketGroupIDs: Set<Int> = []

    let onSelect: (DatabaseListItem) -> Void

    init(databaseManager: DatabaseManager, onSelect: @escaping (DatabaseListItem) -> Void) {
        self.databaseManager = databaseManager
        self.onSelect = onSelect

        // 在初始化时加载舰船分组ID
        let marketGroups = MarketManager.shared.loadMarketGroups(databaseManager: databaseManager)
        self._allowedTopMarketGroupIDs = State(
            initialValue: Set(MarketManager.shared.getChildGroupIDs(marketGroups, parentGroupID: 4))
        )
    }

    var body: some View {
        NavigationStack {
            MarketItemSelectorIntegratedView(
                databaseManager: databaseManager,
                title: NSLocalizedString("Fitting_Select_Ship", comment: "选择舰船"),
                allowedMarketGroups: allowedTopMarketGroupIDs,
                allowTypeIDs: [],
                existingItems: Set<Int>(),
                onItemSelected: { ship in
                    dismiss()
                    onSelect(ship)
                },
                onItemDeselected: { _ in },
                onDismiss: { dismiss() },
                showSelected: showSelected
            )
            .interactiveDismissDisabled()
        }
    }
} 
