import SwiftUI

/// 无人机设置视图 - 用于显示和修改已安装无人机的详细设置
struct DroneSettingsView: View {
    // 无人机和数据依赖
    let drone: SimDrone
    let databaseManager: DatabaseManager
    let viewModel: FittingEditorViewModel
    
    // 回调函数
    var onDelete: () -> Void
    var onUpdateQuantity: (Int, Int) -> Void // (新数量, 新激活数)
    var onReplaceDrone: (Int) -> Void // 新无人机类型ID
    
    // 环境变量
    @Environment(\.dismiss) var dismiss
    
    // 状态变量
    @State private var droneDetails: DatabaseListItem? = nil
    @State private var isLoading = true
    @State private var variationsCount: Int = 0
    @State private var quantity: Int
    @State private var activeCount: Int
    @State private var currentDroneID: Int  // 当前无人机ID
    @State private var initialActiveCount: Int // 用于跟踪激活数量是否变化
    @State private var hasActiveCountChanged = false // 跟踪激活数量是否发生了变化
    
    // 初始化方法
    init(
        drone: SimDrone,
        databaseManager: DatabaseManager,
        viewModel: FittingEditorViewModel,
        onDelete: @escaping () -> Void = {},
        onUpdateQuantity: @escaping (Int, Int) -> Void = { _, _ in },
        onReplaceDrone: @escaping (Int) -> Void = { _ in }
    ) {
        self.drone = drone
        self.databaseManager = databaseManager
        self.viewModel = viewModel
        self.onDelete = onDelete
        self.onUpdateQuantity = onUpdateQuantity
        self.onReplaceDrone = onReplaceDrone
        
        // 初始化状态变量
        self._quantity = State(initialValue: drone.quantity)
        self._activeCount = State(initialValue: drone.activeCount)
        self._initialActiveCount = State(initialValue: drone.activeCount)
        self._currentDroneID = State(initialValue: drone.typeId)
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: Text(NSLocalizedString("Fitting_Setting_Drones", comment: ""))) {
                    if isLoading {
                        HStack {
                            ProgressView()
                            Text(NSLocalizedString("Misc_Loading", comment: ""))
                        }
                    } else if let details = droneDetails {
                        // 如果有变体，点击显示变体列表
                        if variationsCount > 1 {
                            NavigationLink(
                                destination: DroneVariationSelectionView(
                                    databaseManager: databaseManager,
                                    currentDroneID: currentDroneID,
                                    onSelectVariation: { variationID in
                                        // 保存当前状态
                                        let previousQuantity = quantity
                                        let previousActiveCount = min(activeCount, previousQuantity)
                                        
                                        // 替换无人机
                                        onReplaceDrone(variationID)
                                        
                                        // 更新当前无人机ID
                                        currentDroneID = variationID
                                        
                                        // 重新加载无人机信息
                                        loadDroneDetails()
                                        checkVariations()
                                        
                                        // 保持之前的数量和激活状态
                                        quantity = previousQuantity
                                        activeCount = previousActiveCount
                                        
                                        // 更新无人机数量和激活状态
                                        onUpdateQuantity(quantity, activeCount)
                                        
                                        // 如果激活数量与初始值不同，标记为已更改
                                        if activeCount != initialActiveCount {
                                            hasActiveCountChanged = true
                                        }
                                    }
                                )
                            ) {
                                DatabaseListItemView(
                                    item: details,
                                    showDetails: true
                                )
                            }
                        } else {
                            // 没有变体时只显示信息
                            DatabaseListItemView(
                                item: details,
                                showDetails: true
                            )
                        }
                    }
                    
                    // 数量设置
                    Stepper(value: $quantity, in: 1...500, step: 1) {
                        Text(String(format: NSLocalizedString("Fitting_Drones_Qty", comment: ""), quantity))
                    }
                    .onChange(of: quantity) { _, newValue in
                        // 如果数量小于激活数，更新激活数
                        if activeCount > newValue {
                            activeCount = newValue
                            // 如果激活数量与初始值不同，标记为已更改
                            if activeCount != initialActiveCount {
                                hasActiveCountChanged = true
                            }
                        }
                        
                        // 更新无人机数量
                        onUpdateQuantity(newValue, activeCount)
                    }
                    
                    // 激活数量设置
                    Stepper(value: $activeCount, in: 0...min(quantity, viewModel.maxActiveDrones)) {
                        Text(String(format: NSLocalizedString("Fitting_Act_Drones_Qty", comment: ""), activeCount))
                    }
                    .onChange(of: activeCount) { _, newValue in
                        // 更新激活数量
                        onUpdateQuantity(quantity, newValue)
                        
                        // 如果激活数量与初始值不同，标记为已更改
                        if newValue != initialActiveCount {
                            hasActiveCountChanged = true
                        } else {
                            hasActiveCountChanged = false
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Fitting_Setting_Drones", comment: ""))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        onDelete()  // 调用删除回调
                        dismiss()
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                            .frame(width: 30, height: 30)
                            .background(Color(.systemBackground))
                            .clipShape(Circle())
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(.primary)
                            .frame(width: 30, height: 30)
                            .background(Color(.systemBackground))
                            .clipShape(Circle())
                    }
                }
            }
            .onAppear {
                loadDroneDetails()
                checkVariations()
            }
            .onDisappear {
                // 无人机设置视图消失时，如果激活数量有变化，重新计算整个配置
                if hasActiveCountChanged {
                    Logger.info("无人机激活数量发生变化，重新计算属性")
                    viewModel.calculateAttributes()
                }
            }
        }
        .presentationDetents([.fraction(0.81)])  // 设置为屏幕高度的81%
        .presentationDragIndicator(.visible)  // 显示拖动指示器
    }
    
    // 加载无人机详细信息
    private func loadDroneDetails() {
        isLoading = true
        
        // 使用loadMarketItems方法获取无人机数据
        let items = databaseManager.loadMarketItems(
            whereClause: "t.type_id = ?",
            parameters: [currentDroneID]
        )
        
        if let item = items.first {
            droneDetails = item
        }
        
        isLoading = false
    }
    
    // 检查是否有变体
    private func checkVariations() {
        variationsCount = databaseManager.getVariationsCount(for: currentDroneID)
    }
}

/// 无人机变体选择视图 - 独立的Sheet视图
struct DroneVariationSelectionView: View {
    let databaseManager: DatabaseManager
    let currentDroneID: Int
    let onSelectVariation: (Int) -> Void
    
    @Environment(\.dismiss) var dismiss
    @State private var items: [DatabaseListItem] = []
    @State private var metaGroupNames: [Int: String] = [:]
    @State private var isLoading = true
    
    var body: some View {
        List {
            if isLoading {
                HStack {
                    ProgressView()
                    Text(NSLocalizedString("Misc_Loading", comment: ""))
                }
            } else {
                ForEach(groupedItems.keys.sorted(), id: \.self) { metaGroupID in
                    Section(header: Text(metaGroupNames[metaGroupID] ?? NSLocalizedString("Unknown", comment: ""))) {
                        ForEach(groupedItems[metaGroupID] ?? [], id: \.id) { item in
                            HStack {
                                DatabaseListItemView(item: item, showDetails: true)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onSelectVariation(item.id)
                                dismiss() // 只关闭变体选择器，返回到设置页
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Main_Database_Variations", comment: ""))
        .onAppear {
            loadData()
        }
    }
    
    private var groupedItems: [Int: [DatabaseListItem]] {
        Dictionary(grouping: items) { $0.metaGroupID ?? 0 }
    }
    
    private func loadData() {
        isLoading = true
        let result = databaseManager.loadVariations(for: currentDroneID)
        self.items = result.0
        self.metaGroupNames = result.1
        isLoading = false
    }
} 
