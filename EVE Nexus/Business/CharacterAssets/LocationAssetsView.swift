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
    @AppStorage("useEnglishSystemNames") private var useEnglishSystemNames = false
    
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
                        if node.items != nil {
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
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            }
        }
        .task {
            await viewModel.loadItemInfo()
        }
    }
}

// 单个资产项的视图
struct AssetItemView: View {
    let node: AssetTreeNode
    let itemInfo: ItemInfo?
    let showItemCount: Bool
    let showCustomName: Bool
    @AppStorage("useEnglishSystemNames") private var useEnglishSystemNames = false
    
    init(node: AssetTreeNode, itemInfo: ItemInfo?, showItemCount: Bool = true, showCustomName: Bool = true) {
        self.node = node
        self.itemInfo = itemInfo
        self.showItemCount = showItemCount
        self.showCustomName = showCustomName
    }
    
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
                            if showCustomName, let customName = node.name {
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
                    
                    // 如果有子资产且需要显示数量，显示子资产数量
                    if showItemCount, let items = node.items, !items.isEmpty {
                        Text(String(format: NSLocalizedString("Assets_Item_Count", comment: ""), items.count))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

// 子位置资产视图
struct SubLocationAssetsView: View {
    let parentNode: AssetTreeNode
    @StateObject private var viewModel: LocationAssetsViewModel
    @AppStorage("useEnglishSystemNames") private var useEnglishSystemNames = false
    
    init(parentNode: AssetTreeNode) {
        self.parentNode = parentNode
        _viewModel = StateObject(wrappedValue: LocationAssetsViewModel(location: parentNode))
    }
    
    var body: some View {
        List {
            if parentNode.items != nil {
                // 容器本身的信息
                Section {
                    NavigationLink {
                        MarketItemDetailView(databaseManager: viewModel.databaseManager, itemID: parentNode.type_id)
                    } label: {
                        AssetItemView(node: parentNode, 
                                    itemInfo: viewModel.itemInfo(for: parentNode.type_id), 
                                    showItemCount: false,
                                    showCustomName: false)
                            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }
                } header: {
                    Text(NSLocalizedString("Container_Basic_Info", comment: ""))
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
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
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
        
        // 第二步：在每个分组内处理物品
        var mergedGroups: [String: [AssetTreeNode]] = [:]
        for (flag, items) in groups {
            // 将物品分为容器和非容器两类
            let containers = items.filter { $0.items != nil && !$0.items!.isEmpty }
            let normalItems = items.filter { $0.items == nil || $0.items!.isEmpty }
            
            // 处理非容器物品：按type_id分组并合并
            var typeGroups: [Int: [AssetTreeNode]] = [:]
            for item in normalItems {
                if typeGroups[item.type_id] == nil {
                    typeGroups[item.type_id] = []
                }
                typeGroups[item.type_id]?.append(item)
            }
            
            // 合并相同类型的非容器物品
            var mergedNormalItems: [AssetTreeNode] = []
            for items in typeGroups.values {
                if items.count == 1 {
                    mergedNormalItems.append(items[0])
                } else {
                    // 对相同type_id的物品按item_id排序
                    let sortedItems = items.sorted { $0.item_id < $1.item_id }
                    let firstItem = sortedItems[0]
                    let totalQuantity = sortedItems.reduce(0) { $0 + $1.quantity }
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
                        system_id: firstItem.system_id,
                        region_id: firstItem.region_id,
                        security_status: firstItem.security_status,
                        items: nil
                    )
                    mergedNormalItems.append(mergedItem)
                }
            }
            
            // 将容器和合并后的普通物品组合，并按物品名称和item_id排序
            var allItems = containers + mergedNormalItems
            allItems.sort { item1, item2 in
                let name1 = itemInfo(for: item1.type_id)?.name ?? ""
                let name2 = itemInfo(for: item2.type_id)?.name ?? ""
                if name1 != name2 {
                    return name1.localizedCompare(name2) == .orderedAscending
                }
                return item1.item_id < item2.item_id
            }
            mergedGroups[flag] = allItems
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

// 递归构建树节点的辅助函数
private func buildTreeNode(
    from asset: CharacterAsset,
    locationMap: [Int64: [CharacterAsset]],
    names: [Int64: String],
    databaseManager: DatabaseManager,
    iconMap: [Int: String]
) -> AssetTreeNode {
    // 从图标映射中获取图标名称
    let iconName = iconMap[asset.type_id] ?? DatabaseConfig.defaultItemIcon
    
    // 获取子项
    let children = locationMap[asset.item_id, default: []].map { childAsset in
        buildTreeNode(
            from: childAsset,
            locationMap: locationMap,
            names: names,
            databaseManager: databaseManager,
            iconMap: iconMap
        )
    }
    
    return AssetTreeNode(
        location_id: asset.location_id,
        item_id: asset.item_id,
        type_id: asset.type_id,
        location_type: asset.location_type,
        location_flag: asset.location_flag,
        quantity: asset.quantity,
        name: names[asset.item_id],
        icon_name: iconName,
        is_singleton: asset.is_singleton,
        is_blueprint_copy: asset.is_blueprint_copy,
        system_id: nil,  // 子节点不需要系统和区域信息
        region_id: nil,
        security_status: nil,
        items: children.isEmpty ? nil : children
    )
}
