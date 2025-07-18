import SwiftUI

// 生产链条目
struct ProductionChainItem: Identifiable {
    let id: Int
    let typeId: Int
    let name: String
    let iconFileName: String
    let quantity: Int
    let level: Int
}

// 生产链段落
struct ProductionChainSection: Identifiable {
    let id: Int
    let title: String
    let level: Int
    let items: [ProductionChainItem]
}

@MainActor
final class PIProductionChainViewModel: ObservableObject {
    @Published var productionChain: [ProductionChainSection] = []
    @Published var selectedItems: Set<Int> = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let resourceCache = PIResourceCache.shared
    
    func loadProductionChain(for productId: Int) {
        isLoading = true
        errorMessage = nil
        productionChain = []
        selectedItems = []
        
        Task {
            do {
                let chain = try await calculateProductionChain(for: productId)
                
                await MainActor.run {
                    self.productionChain = chain
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    private func calculateProductionChain(for productId: Int) async throws -> [ProductionChainSection] {
        guard let productInfo = resourceCache.getResourceInfo(for: productId),
              let productLevel = resourceCache.getResourceLevel(for: productId) else {
            throw NSError(domain: "ProductionChain", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法获取产品信息"])
        }
        
        // 存储所有轮次的原始数据
        var allRoundsData: [[Int: (name: String, iconFileName: String, quantity: Int)]] = []
        
        // 一次性计算所有轮次
        var currentLevelItems: [Int: (name: String, iconFileName: String, quantity: Int)] = [productId: (productInfo.name, productInfo.iconFileName, 1)]
        var currentLevel = productLevel.rawValue
        
        while currentLevel > 0 && !currentLevelItems.isEmpty {
            let targetLevel = currentLevel - 1
            var nextLevelItems: [Int: (name: String, iconFileName: String, quantity: Int)] = [:]
            
            // 计算当前级别所有产品需要的下一级材料
            for (itemId, itemInfo) in currentLevelItems {
                if let schematic = resourceCache.getSchematic(for: itemId) {
                    let outputQuantity = Double(schematic.outputValue)
                    
                    for (index, inputTypeId) in schematic.inputTypeIds.enumerated() {
                        if index < schematic.inputValues.count {
                            let inputQuantity = Double(schematic.inputValues[index])
                            let requiredQuantity = Int(ceil(Double(itemInfo.quantity) * inputQuantity / outputQuantity))
                            
                            if let inputInfo = resourceCache.getResourceInfo(for: inputTypeId) {
                                let existingQuantity = nextLevelItems[inputTypeId]?.quantity ?? 0
                                nextLevelItems[inputTypeId] = (
                                    name: inputInfo.name,
                                    iconFileName: inputInfo.iconFileName,
                                    quantity: existingQuantity + requiredQuantity
                                )
                            }
                        }
                    }
                }
            }
            
            if !nextLevelItems.isEmpty {
                allRoundsData.append(nextLevelItems)
                currentLevelItems = nextLevelItems
                currentLevel = targetLevel
            } else {
                break
            }
        }
        
        // 根据计算结果创建sections，使用倒序的轮次编号
        let totalRounds = allRoundsData.count
        var sections: [ProductionChainSection] = []
        
        for (index, roundData) in allRoundsData.enumerated() {
            let sectionItems = roundData.enumerated().map { (itemIndex, element) in
                // 获取物品的真实PI等级
                let itemLevel = resourceCache.getResourceLevel(for: element.key)?.rawValue ?? 0
                
                return ProductionChainItem(
                    id: (index + 1) * 1000 + itemIndex,
                    typeId: element.key,
                    name: element.value.name,
                    iconFileName: element.value.iconFileName,
                    quantity: element.value.quantity,
                    level: itemLevel
                )
            }.sorted { $0.name < $1.name }
            
            // 使用倒序的轮次编号：从totalRounds开始递减
            let roundNumber = totalRounds - index
            let sectionTitle = String(format: NSLocalizedString("PI_Chain_Processing_Round", comment: "第%d轮加工"), roundNumber)
            
            let section = ProductionChainSection(
                id: index + 1,
                title: sectionTitle,
                level: index + 1, // 使用轮次作为section的level标识
                items: sectionItems
            )
            sections.append(section)
        }
        
        return sections
    }
    
    func toggleItemSelection(_ item: ProductionChainItem) {
        // 检查当前物品是否已被选中
        if selectedItems.contains(item.typeId) {
            // 如果已选中，则清除所有选择（取消选中）
            selectedItems.removeAll()
        } else {
            // 如果未选中，则清除之前的选择并查找相关物品
            selectedItems.removeAll()
            findRelatedItems(for: item.typeId)
        }
    }
    
    private func findRelatedItems(for itemId: Int) {
        // 添加当前物品
        selectedItems.insert(itemId)
        
        // 递归查找所有上游物品（需要此物品的产品）
        findUpstreamItems(for: itemId)
        
        // 递归查找所有下游物品（此物品需要的材料）
        findDownstreamItems(for: itemId)
    }
    
    private func findUpstreamItems(for itemId: Int) {
        // 查找所有使用此物品作为输入的配方
        for section in productionChain {
            for item in section.items {
                if let schematic = resourceCache.getSchematic(for: item.typeId),
                   schematic.inputTypeIds.contains(itemId) {
                    selectedItems.insert(item.typeId)
                }
            }
        }
    }
    
    private func findDownstreamItems(for itemId: Int) {
        // 查找此物品的配方中需要的所有输入材料
        if let schematic = resourceCache.getSchematic(for: itemId) {
            for inputTypeId in schematic.inputTypeIds {
                selectedItems.insert(inputTypeId)
                // 递归查找下游
                findDownstreamItems(for: inputTypeId)
            }
        }
    }
}

struct PIProductionChainView: View {
    let characterId: Int?
    @State private var selectedProduct: PlanetaryProduct?
    @State private var showProductSelector = false
    @StateObject private var viewModel = PIProductionChainViewModel()
    
    private static let allowedMarketGroups: Set<Int> = [1334, 1335, 1336, 1337]
    
    var body: some View {
        NavigationView {
            VStack {
                // 产品选择部分
                VStack(spacing: 16) {
                    Button(action: {
                        showProductSelector = true
                    }) {
                        HStack {
                            if let product = selectedProduct {
                                Image(uiImage: IconManager.shared.loadUIImage(for: product.icon))
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(6)
                                
                                VStack(alignment: .leading) {
                                    Text(product.name)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Text(NSLocalizedString("PI_Chain_Tap_To_Change", comment: "点击更换"))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            } else {
                                Text(NSLocalizedString("PI_Chain_Select_Product", comment: "选择行星产品"))
                                    .foregroundColor(.blue)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                    }
                }
                .padding()
                
                // 生产链展示部分
                if viewModel.isLoading {
                    Spacer()
                    VStack {
                        ProgressView()
                        Text(NSLocalizedString("PI_Chain_Loading", comment: "加载生产链中..."))
                            .foregroundColor(.gray)
                            .padding(.top, 8)
                    }
                    Spacer()
                } else if let errorMessage = viewModel.errorMessage {
                    Spacer()
                    VStack {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text(errorMessage)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                    }
                    Spacer()
                } else if !viewModel.productionChain.isEmpty {
                    List {
                        ForEach(viewModel.productionChain) { section in
                            Section(header: Text(section.title)) {
                                ForEach(section.items) { item in
                                    ProductionChainItemRow(
                                        item: item,
                                        isSelected: viewModel.selectedItems.contains(item.typeId),
                                        isFirstSection: section.id == 0,
                                        onTap: {
                                            if section.id != 0 { // 第一个section不允许点击
                                                viewModel.toggleItemSelection(item)
                                            }
                                        }
                                    )
                                }
                            }
                        }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }
                } else if selectedProduct != nil {
                    Spacer()
                    VStack {
                        Image(systemName: "list.bullet")
                            .font(.largeTitle)
                            .foregroundColor(.gray)
                        Text(NSLocalizedString("PI_Chain_No_Data", comment: "无法获取生产链数据"))
                            .foregroundColor(.gray)
                            .padding(.top, 8)
                    }
                    Spacer()
                } else {
                    Spacer()
                    VStack {
                        Image(systemName: "cube.box")
                            .font(.largeTitle)
                            .foregroundColor(.gray)
                        Text(NSLocalizedString("PI_Chain_Select_Product_Hint", comment: "请选择一个行星产品查看生产链"))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                    }
                    Spacer()
                }
            }
        }
        .sheet(isPresented: $showProductSelector) {
            NavigationView {
                MarketItemSelectorIntegratedView(
                    databaseManager: DatabaseManager.shared,
                    title: NSLocalizedString("PI_Chain_Select_Product", comment: "选择行星产品"),
                    allowedMarketGroups: PIProductionChainView.allowedMarketGroups,
                    allowTypeIDs: [],
                    existingItems: [],
                    onItemSelected: { item in
                        selectedProduct = PlanetaryProduct(
                            typeId: item.id,
                            name: item.name,
                            icon: item.iconFileName
                        )
                        viewModel.loadProductionChain(for: item.id)
                        showProductSelector = false
                    },
                    onItemDeselected: { _ in },
                    onDismiss: { showProductSelector = false },
                    showSelected: false
                )
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .navigationTitle(NSLocalizedString("PI_Chain_Title", comment: "生产链分析"))
        .onAppear {
            // 预加载资源缓存
            PIResourceCache.shared.preloadResourceInfo()
        }
    }
}

struct ProductionChainItemRow: View {
    let item: ProductionChainItem
    let isSelected: Bool
    let isFirstSection: Bool
    let onTap: () -> Void
    
    var body: some View {
        HStack {
            Image(uiImage: IconManager.shared.loadUIImage(for: item.iconFileName))
                .resizable()
                .frame(width: 32, height: 32)
                .cornerRadius(6)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                
                Text(String(format: NSLocalizedString("PI_Chain_Level_And_Quantity_Format", comment: "等级：P%d，数量：%d"), item.level, item.quantity))
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            
            Spacer()
            
            if !isFirstSection {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .gray)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .padding(.trailing, 8) // 给右侧额外添加间距，让蓝色背景边界与选择框右侧有距离
        .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        .cornerRadius(6)
        .contentShape(Rectangle()) // 确保整个区域都可以点击
        .onTapGesture {
            if !isFirstSection {
                onTap()
            }
        }
    }
}
