import SwiftUI

// 格式化location_flag显示
private func formatLocationFlag(_ flag: String) -> String {
    // 这里可以添加更多的映射
    switch flag {
    case "Hangar":
        return NSLocalizedString("Location_Flag_Hangar", comment: "")
    case "CorpSAG1":
        return NSLocalizedString("Location_Flag_CorpSAG1", comment: "")
    case "CorpSAG2":
        return NSLocalizedString("Location_Flag_CorpSAG2", comment: "")
    case "CorpSAG3":
        return NSLocalizedString("Location_Flag_CorpSAG3", comment: "")
    case "CorpSAG4":
        return NSLocalizedString("Location_Flag_CorpSAG4", comment: "")
    case "CorpSAG5":
        return NSLocalizedString("Location_Flag_CorpSAG5", comment: "")
    case "CorpSAG6":
        return NSLocalizedString("Location_Flag_CorpSAG6", comment: "")
    case "CorpSAG7":
        return NSLocalizedString("Location_Flag_CorpSAG7", comment: "")
    case "CorpDeliveries":
        return NSLocalizedString("Location_Flag_CorpDeliveries", comment: "")
    case "AutoFit":
        return NSLocalizedString("Location_Flag_AutoFit", comment: "")
    case "Cargo":
        return NSLocalizedString("Location_Flag_Cargo", comment: "")
    case "DroneBay":
        return NSLocalizedString("Location_Flag_DroneBay", comment: "")
    case "FleetHangar":
        return NSLocalizedString("Location_Flag_FleetHangar", comment: "")
    case "Deliveries":
        return NSLocalizedString("Location_Flag_Deliveries", comment: "")
    case "HiddenModifiers":
        return NSLocalizedString("Location_Flag_HiddenModifiers", comment: "")
    case "ShipHangar":
        return NSLocalizedString("Location_Flag_ShipHangar", comment: "")
    case "FighterBay":
        return NSLocalizedString("Location_Flag_FighterBay", comment: "")
    case "FighterTubes":
        return NSLocalizedString("Location_Flag_FighterTubes", comment: "")
    case "SubSystemBay":
        return NSLocalizedString("Location_Flag_SubSystemBay", comment: "")
    case "SubSystemSlots":
        return NSLocalizedString("Location_Flag_SubSystemSlots", comment: "")
    case "HiSlots":
        return NSLocalizedString("Location_Flag_HiSlots", comment: "")
    case "MedSlots":
        return NSLocalizedString("Location_Flag_MedSlots", comment: "")
    case "LoSlots":
        return NSLocalizedString("Location_Flag_LoSlots", comment: "")
    case "RigSlots":
        return NSLocalizedString("Location_Flag_RigSlots", comment: "")
    case "SpecializedAmmoHold":
        return NSLocalizedString("Location_Flag_SpecializedAmmoHold", comment: "")
    case "SpecializedCommandCenterHold":
        return NSLocalizedString("Location_Flag_SpecializedCommandCenterHold", comment: "")
    case "SpecializedFuelBay":
        return NSLocalizedString("Location_Flag_SpecializedFuelBay", comment: "")
    case "SpecializedGasHold":
        return NSLocalizedString("Location_Flag_SpecializedGasHold", comment: "")
    case "SpecializedIndustrialShipHold":
        return NSLocalizedString("Location_Flag_SpecializedIndustrialShipHold", comment: "")
    case "SpecializedLargeShipHold":
        return NSLocalizedString("Location_Flag_SpecializedLargeShipHold", comment: "")
    case "SpecializedMaterialBay":
        return NSLocalizedString("Location_Flag_SpecializedMaterialBay", comment: "")
    case "SpecializedMediumShipHold":
        return NSLocalizedString("Location_Flag_SpecializedMediumShipHold", comment: "")
    case "SpecializedMineralHold":
        return NSLocalizedString("Location_Flag_SpecializedMineralHold", comment: "")
    case "SpecializedOreHold":
        return NSLocalizedString("Location_Flag_SpecializedOreHold", comment: "")
    case "SpecializedPlanetaryCommoditiesHold":
        return NSLocalizedString("Location_Flag_SpecializedPlanetaryCommoditiesHold", comment: "")
    case "SpecializedSalvageHold":
        return NSLocalizedString("Location_Flag_SpecializedSalvageHold", comment: "")
    case "SpecializedShipHold":
        return NSLocalizedString("Location_Flag_SpecializedShipHold", comment: "")
    case "SpecializedSmallShipHold":
        return NSLocalizedString("Location_Flag_SpecializedSmallShipHold", comment: "")
    default:
        return flag
    }
}

// 主资产列表视图
struct LocationAssetsView: View {
    let location: AssetTreeNode
    @StateObject private var viewModel: LocationAssetsViewModel
    
    init(location: AssetTreeNode) {
        self.location = location
        _viewModel = StateObject(wrappedValue: LocationAssetsViewModel(location: location))
    }
    
    var body: some View {
        List {
            ForEach(viewModel.groupedAssets(), id: \.flag) { group in
                Section(header: Text(formatLocationFlag(group.flag))
                    .fontWeight(.bold)
                    .font(.system(size: 18))
                    .foregroundColor(.primary)
                    .textCase(.none)
                ) {
                    ForEach(group.items, id: \.item_id) { node in
                        if let items = node.items {
                            // 容器类物品，点击显示容器内容
                            NavigationLink {
                                SubLocationAssetsView(parentNode: node)
                            } label: {
                                AssetItemView(node: node, itemInfo: viewModel.itemInfo(for: node.type_id))
                            }
                        } else {
                            // 非容器物品，点击显示市场信息
                            NavigationLink {
                                MarketItemDetailView(databaseManager: viewModel.databaseManager, itemID: node.type_id)
                            } label: {
                                AssetItemView(node: node, itemInfo: viewModel.itemInfo(for: node.type_id))
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(location.name ?? location.system_name ?? NSLocalizedString("Unknown_System", comment: ""))
        .task {
            await viewModel.loadItemInfo()
        }
    }
}

// 单个资产项的视图
struct AssetItemView: View {
    let node: AssetTreeNode
    let itemInfo: ItemInfo?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // 资产图标
                IconManager.shared.loadImage(for: itemInfo?.iconFileName ?? DatabaseConfig.defaultItemIcon)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)
                VStack(alignment: .leading, spacing: 2) {
                    // 资产名称和自定义名称
                    HStack(spacing: 4) {
                        if let itemInfo = itemInfo {
                            Text(itemInfo.name)
                            if let customName = node.name {
                                Text("[\(customName)]")
                                    .foregroundColor(.secondary)
                            }
                            if node.quantity > 1 {
                                Text("×\(node.quantity)")
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text("Type ID: \(node.type_id)")
                        }
                    }
                    
                    // 如果有子资产，显示子资产数量
                    if let items = node.items, !items.isEmpty {
                        Text(String(format: NSLocalizedString("Assets_Item_Count", comment: ""), items.count))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(height: 36)
        }
    }
}

// 子位置资产视图
struct SubLocationAssetsView: View {
    let parentNode: AssetTreeNode
    @StateObject private var viewModel: LocationAssetsViewModel
    
    init(parentNode: AssetTreeNode) {
        self.parentNode = parentNode
        _viewModel = StateObject(wrappedValue: LocationAssetsViewModel(location: parentNode))
    }
    
    var body: some View {
        List {
            if let items = parentNode.items {
                // 容器本身的信息
                Section {
                    NavigationLink {
                        MarketItemDetailView(databaseManager: viewModel.databaseManager, itemID: parentNode.type_id)
                    } label: {
                        AssetItemView(node: parentNode, itemInfo: viewModel.itemInfo(for: parentNode.type_id))
                            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    }
                } header: {
                    Text(NSLocalizedString("Item_Basic_Info", comment: ""))
                        .fontWeight(.bold)
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                        .textCase(.none)
                }
                
                // 容器内的物品
                ForEach(viewModel.groupedAssets(), id: \.flag) { group in
                    Section(header: Text(formatLocationFlag(group.flag))
                        .fontWeight(.bold)
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                        .textCase(.none)
                    ) {
                        ForEach(group.items, id: \.item_id) { node in
                            if let subitems = node.items, !subitems.isEmpty {
                                NavigationLink {
                                    SubLocationAssetsView(parentNode: node)
                                } label: {
                                    AssetItemView(node: node, itemInfo: viewModel.itemInfo(for: node.type_id))
                                }
                            } else {
                                NavigationLink {
                                    MarketItemDetailView(databaseManager: viewModel.databaseManager, itemID: node.type_id)
                                } label: {
                                    AssetItemView(node: node, itemInfo: viewModel.itemInfo(for: node.type_id))
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(parentNode.name ?? viewModel.itemInfo(for: parentNode.type_id)?.name ?? String(parentNode.type_id))
        .task {
            await viewModel.loadItemInfo()
        }
    }
}

// LocationAssetsViewModel
class LocationAssetsViewModel: ObservableObject {
    private let location: AssetTreeNode
    private var itemInfoCache: [Int: ItemInfo] = [:]
    let databaseManager: DatabaseManager
    
    init(location: AssetTreeNode, databaseManager: DatabaseManager = DatabaseManager()) {
        self.location = location
        self.databaseManager = databaseManager
    }
    
    func itemInfo(for typeId: Int) -> ItemInfo? {
        itemInfoCache[typeId]
    }
    
    // 按location_flag分组的资产
    func groupedAssets() -> [(flag: String, items: [AssetTreeNode])] {
        // 如果是容器，使用其items属性
        let items = location.items ?? []
        var groups: [String: [AssetTreeNode]] = [:]
        
        // 第一步：按flag分组
        for item in items {
            let flag = processFlag(item.location_flag)
            if groups[flag] == nil {
                groups[flag] = []
            }
            groups[flag]?.append(item)
        }
        
        // 第二步：在每个分组内合并相同类型的物品
        var mergedGroups: [String: [AssetTreeNode]] = [:]
        for (flag, items) in groups {
            // 按type_id分组
            var typeGroups: [Int: [AssetTreeNode]] = [:]
            for item in items {
                if typeGroups[item.type_id] == nil {
                    typeGroups[item.type_id] = []
                }
                typeGroups[item.type_id]?.append(item)
            }
            
            // 合并每个type_id组的物品
            var mergedItems: [AssetTreeNode] = []
            for items in typeGroups.values {
                if items.count == 1 {
                    // 单个物品直接添加
                    mergedItems.append(items[0])
                } else {
                    // 多个物品需要合并
                    let firstItem = items[0]
                    // 只合并非容器物品
                    if firstItem.items == nil || firstItem.items?.isEmpty == true {
                        let totalQuantity = items.reduce(0) { $0 + $1.quantity }
                        let mergedItem = AssetTreeNode(
                            location_id: firstItem.location_id,
                            item_id: firstItem.item_id,
                            type_id: firstItem.type_id,
                            location_type: firstItem.location_type,
                            location_flag: firstItem.location_flag,
                            quantity: totalQuantity,
                            name: firstItem.name,
                            icon_name: firstItem.icon_name,
                            is_singleton: false,
                            is_blueprint_copy: firstItem.is_blueprint_copy,
                            system_name: firstItem.system_name,
                            region_name: firstItem.region_name,
                            security_status: firstItem.security_status,
                            items: nil
                        )
                        mergedItems.append(mergedItem)
                    } else {
                        // 容器类物品不合并
                        mergedItems.append(contentsOf: items)
                    }
                }
            }
            mergedGroups[flag] = mergedItems
        }
        
        // 第三步：按预定义顺序排序
        let result = flagOrder.compactMap { flag in
            if let items = mergedGroups[flag], !items.isEmpty {
                return (flag: flag, items: items)
            }
            return nil
        }
        
        // 如果没有预定义的分组，添加剩余的分组
        let remainingGroups = mergedGroups.filter { !flagOrder.contains($0.key) }
        let remainingResult = remainingGroups.map { (flag: $0.key, items: $0.value) }
            .sorted { $0.flag < $1.flag }
        
        return result + remainingResult
    }
    
    private func processFlag(_ flag: String) -> String {
        switch flag {
        case let f where f.hasPrefix("HiSlot"): return "HiSlots"
        case let f where f.hasPrefix("MedSlot"): return "MedSlots"
        case let f where f.hasPrefix("LoSlot"): return "LoSlots"
        case let f where f.hasPrefix("RigSlot"): return "RigSlots"
        case let f where f.hasPrefix("SubSystemSlot"): return "SubSystemSlots"
        default: return flag
        }
    }
    
    private let flagOrder = [
        "Hangar", "ShipHangar", "FleetHangar",
        "CorpSAG1", "CorpSAG2", "CorpSAG3", "CorpSAG4", "CorpSAG5", "CorpSAG6", "CorpSAG7",
        "CorpDeliveries", "Deliveries",
        "HiSlots", "MedSlots", "LoSlots", "RigSlots", "SubSystemSlots",
        "FighterBay", "FighterTubes", "DroneBay", "Cargo",
        "SpecializedAmmoHold", "SpecializedCommandCenterHold", "SpecializedFuelBay",
        "SpecializedGasHold", "SpecializedIndustrialShipHold", "SpecializedLargeShipHold",
        "SpecializedMaterialBay", "SpecializedMediumShipHold", "SpecializedMineralHold",
        "SpecializedOreHold", "SpecializedPlanetaryCommoditiesHold", "SpecializedSalvageHold",
        "SpecializedShipHold", "SpecializedSmallShipHold"
    ]
    
    @MainActor
    func loadItemInfo() async {
        var typeIds = Set<Int>()
        typeIds.insert(location.type_id)
        
        if let items = location.items {
            typeIds.formUnion(items.map { $0.type_id })
        }
        
        let query = """
            SELECT type_id, name, icon_filename
            FROM types
            WHERE type_id IN (\(typeIds.map { String($0) }.joined(separator: ",")))
        """
        
        if case .success(let rows) = databaseManager.executeQuery(query) {
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                   let name = row["name"] as? String {
                    let iconFileName = (row["icon_filename"] as? String) ?? DatabaseConfig.defaultItemIcon
                    itemInfoCache[typeId] = ItemInfo(name: name, iconFileName: iconFileName)
                }
            }
            objectWillChange.send()
        }
    }
}
