import SwiftUI

// 用于货舱物品设置的状态类，包装 Int 使其符合 Identifiable
class CargoItemState: ObservableObject, Identifiable {
    var id: Int { itemTypeId ?? 0 }
    @Published var itemTypeId: Int?
}

struct ShipFittingCargoView: View {
    @ObservedObject var viewModel: FittingEditorViewModel
    @State private var showingItemSelector = false
    @State private var showingItemSettings = false
    @StateObject private var selectedCargoItem = CargoItemState()
    
    var body: some View {
        VStack(spacing: 0) {
            // 货舱属性条
            CargoAttributesView(viewModel: viewModel)
            
            // 货舱物品列表
            List {
                ForEach(viewModel.simulationInput.cargo.items, id: \.typeId) { item in
                    HStack {
                        // 物品图标
                        if let iconFileName = item.iconFileName {
                            IconManager.shared.loadImage(for: iconFileName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 32, height: 32)
                                .cornerRadius(4)
                        } else {
                            Image(systemName: "questionmark.square")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 32, height: 32)
                                .foregroundColor(.gray)
                        }
                        
                        // 物品名称和数量
                        Text("\(item.quantity)x \(item.name)")
                        
                        Spacer()
                        
                        // 物品体积
                        Text("\(item.volume * Double(item.quantity), specifier: "%.1f") m³")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedCargoItem.itemTypeId = item.typeId
                        showingItemSettings = true
                    }
                    .contextMenu {
                        Button(action: {
                            viewModel.removeCargoItem(typeId: item.typeId)
                        }) {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet.sorted(by: >) {
                        if index < viewModel.simulationInput.cargo.items.count {
                            viewModel.removeCargoItem(at: index)
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                
                // 添加物品按钮
                Button(action: {
                    showingItemSelector = true
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                        Text(NSLocalizedString("Main_Market_Watch_List_Add_Item", comment: ""))
                    }
                }
            }
        }
        .sheet(isPresented: $showingItemSelector) {
            MarketItemSelectorWrapper(
                viewModel: viewModel,
                onItemSelected: { item in
                    addCargoItem(item)
                }
            )
        }
        .sheet(isPresented: $showingItemSettings) {
            if let itemTypeId = selectedCargoItem.itemTypeId,
               let itemIndex = viewModel.simulationInput.cargo.items.firstIndex(where: { $0.typeId == itemTypeId }) {
                let item = viewModel.simulationInput.cargo.items[itemIndex]
                CargoItemSettingsView(
                    cargoItem: item,
                    viewModel: viewModel,
                    onDelete: {
                        viewModel.removeCargoItem(typeId: itemTypeId)
                        showingItemSettings = false
                    },
                    onUpdateQuantity: { newQuantity in
                        viewModel.updateCargoItemQuantity(typeId: itemTypeId, quantity: newQuantity)
                    }
                )
            }
        }
    }
    
    // 添加货舱物品
    private func addCargoItem(_ item: DatabaseListItem) {
        viewModel.addCargoItem(
            typeId: item.id,
            name: item.name,
            iconFileName: item.iconFileName,
            quantity: 1
        )
    }
}

// 包装视图，用于访问环境值
struct MarketItemSelectorWrapper: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: FittingEditorViewModel
    let onItemSelected: (DatabaseListItem) -> Void
    
    var body: some View {
        MarketItemTreeSelectorView(
            databaseManager: viewModel.databaseManager,
            title: NSLocalizedString("Fitting_Setting_Items", comment: ""),
            marketGroupTree: MarketItemGroupTreeBuilder(
                databaseManager: viewModel.databaseManager,
                allowedTypeIDs: Set(),  // 允许所有物品
                parentGroupId: nil    // 从根目录开始
            ).buildGroupTree(),
            allowTypeIDs: Set(),      // 不限制物品类型
            existingItems: Set(),     // 不需要标记已有物品
            onItemSelected: { item in
                onItemSelected(item)
                dismiss()
            },
            onItemDeselected: { _ in },
            onDismiss: { _, _ in 
                dismiss()
            },
            lastVisitedGroupID: nil,
            initialSearchText: nil,
            searchItemsByKeyword: nil
        )
    }
}

/// 货舱物品设置视图 - 用于显示和修改货舱物品的详细设置
struct CargoItemSettingsView: View {
    // 物品和数据依赖
    let cargoItem: SimCargoItem
    let viewModel: FittingEditorViewModel
    
    // 回调函数
    var onDelete: () -> Void
    var onUpdateQuantity: (Int) -> Void
    
    // 环境变量
    @Environment(\.dismiss) var dismiss
    
    // 状态变量
    @State private var quantity: Int
    @State private var quantityText: String
    @State private var itemDetails: DatabaseListItem? = nil
    @State private var isLoading = true
    
    // 计算填满货舱的最大数量
    private var maxQuantity: Int {
        // 计算当前货舱已使用的体积（不包括当前物品）
        var usedVolume = 0.0
        for item in viewModel.simulationInput.cargo.items {
            if item.typeId != cargoItem.typeId {
                usedVolume += item.volume * Double(item.quantity)
            }
        }
        
        // 从计算后的属性中获取总货舱容量
        let totalCapacity: Double
        if let simulationOutput = viewModel.simulationOutput {
            totalCapacity = simulationOutput.ship.attributesByName["capacity"] ?? 0.0
        } else {
            // 如果没有计算结果，则使用基础属性
            totalCapacity = viewModel.simulationInput.ship.baseAttributesByName["capacity"] ?? 0.0
        }
        
        // 计算剩余可用空间
        let availableSpace = totalCapacity - usedVolume
        
        // 计算可以放置的最大数量
        let maxPossible = Int(availableSpace / cargoItem.volume)
        
        // 至少保留1个物品
        return max(1, maxPossible)
    }
    
    // 初始化方法
    init(
        cargoItem: SimCargoItem,
        viewModel: FittingEditorViewModel,
        onDelete: @escaping () -> Void = {},
        onUpdateQuantity: @escaping (Int) -> Void = { _ in }
    ) {
        self.cargoItem = cargoItem
        self.viewModel = viewModel
        self.onDelete = onDelete
        self.onUpdateQuantity = onUpdateQuantity
        
        // 初始化状态变量
        self._quantity = State(initialValue: cargoItem.quantity)
        self._quantityText = State(initialValue: String(cargoItem.quantity))
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: Text(NSLocalizedString("Fitting_Setting_Items", comment: ""))) {
                    if isLoading {
                        HStack {
                            ProgressView()
                            Text(NSLocalizedString("Misc_Loading", comment: ""))
                        }
                    } else if let details = itemDetails {
                        DatabaseListItemView(
                            item: details,
                            showDetails: true
                        )
                    } else {
                        // 如果无法加载详情，显示基本信息
                        HStack {
                            if let iconFileName = cargoItem.iconFileName {
                                IconManager.shared.loadImage(for: iconFileName)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(4)
                            } else {
                                Image(systemName: "questionmark.square")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 32, height: 32)
                                    .foregroundColor(.gray)
                            }
                            
                            Text(cargoItem.name)
                        }
                    }
                    
                    // 物品体积信息
                    HStack {
                        Text(NSLocalizedString("Fitting_unit_vol", comment: ""))
                        Spacer()
                        Text("\(cargoItem.volume, specifier: "%.2f") m³")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text(NSLocalizedString("Fitting_unit_vol_sum", comment: ""))
                        Spacer()
                        Text("\(cargoItem.volume * Double(quantity), specifier: "%.2f") m³")
                            .foregroundColor(.secondary)
                    }
                    
                    // 数量设置
                    HStack {
                        // 数量标签
                        Text(NSLocalizedString("Misc_Qty", comment: ""))
                        
                        Spacer()
                        
                        // 数量输入框
                        TextField(NSLocalizedString("Misc_Qty", comment: ""), text: $quantityText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                            )
                            .frame(width: 60)
                            .onChange(of: quantityText) { _, newValue in
                                if let newQuantity = Int(newValue), newQuantity > 0 {
                                    quantity = newQuantity
                                    onUpdateQuantity(newQuantity)
                                }
                            }
                        
                        // 数量调节器
                        Stepper(NSLocalizedString("Misc_Qty", comment: ""), value: $quantity, in: 1...10000, step: 1)
                            .labelsHidden()
                            .onChange(of: quantity) { _, newValue in
                                // 更新输入框文本
                                quantityText = String(newValue)
                                // 更新物品数量
                                onUpdateQuantity(newValue)
                            }
                        
                        // 设置最大数量按钮
                        Button(action: {
                            quantity = maxQuantity
                            quantityText = String(maxQuantity)
                            onUpdateQuantity(maxQuantity)
                        }) {
                            Text("Max")
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(6)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Fitting_Setting_Items", comment: ""))
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
                loadItemDetails()
            }
        }
        .presentationDetents([.fraction(0.81)])  // 设置为屏幕高度的81%
        .presentationDragIndicator(.visible)  // 显示拖动指示器
    }
    
    // 加载物品详细信息
    private func loadItemDetails() {
        isLoading = true
        
        // 使用loadMarketItems方法获取物品数据
        let items = viewModel.databaseManager.loadMarketItems(
            whereClause: "t.type_id = ?",
            parameters: [cargoItem.typeId]
        )
        
        if let item = items.first {
            itemDetails = item
        }
        
        isLoading = false
    }
}

// 货舱属性条视图
struct CargoAttributesView: View {
    @ObservedObject var viewModel: FittingEditorViewModel
    
    // 计算货舱容量
    private var cargoCapacity: (current: Double, total: Double) {
        // 从计算后的属性中获取总货舱容量
        let totalCapacity: Double
        if let simulationOutput = viewModel.simulationOutput {
            totalCapacity = simulationOutput.ship.attributesByName["capacity"] ?? 0.0
        } else {
            // 如果没有计算结果，则使用基础属性
            totalCapacity = viewModel.simulationInput.ship.baseAttributesByName["capacity"] ?? 0.0
        }
        
        // 计算当前使用的容量
        var currentCapacity = 0.0
        for item in viewModel.simulationInput.cargo.items {
            currentCapacity += item.volume * Double(item.quantity)
        }
        
        return (current: currentCapacity, total: totalCapacity)
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // 货舱状态行
            HStack(spacing: 8) {
                // 货舱容量
                AttributeProgressView(
                    icon: "cargo_fit",
                    current: cargoCapacity.current,
                    total: cargoCapacity.total,
                    unit: "m³"
                )
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .overlay(Divider(), alignment: .bottom)
    }
} 

