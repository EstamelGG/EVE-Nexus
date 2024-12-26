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
                Section(header: Text(formatLocationFlag(group.flag))) {
                    ForEach(group.items, id: \.item_id) { node in
                        if let items = node.items, !items.isEmpty {
                            // 如果有子资产，使用导航链接
                            NavigationLink {
                                SubLocationAssetsView(parentNode: node)
                            } label: {
                                AssetItemView(node: node, itemInfo: viewModel.itemInfo(for: node.type_id))
                            }
                        } else {
                            // 如果没有子资产，只显示资产信息
                            AssetItemView(node: node, itemInfo: viewModel.itemInfo(for: node.type_id))
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
            if parentNode.items != nil {
                ForEach(viewModel.groupedAssets(), id: \.flag) { group in
                    Section(header: Text(formatLocationFlag(group.flag))) {
                        ForEach(group.items, id: \.item_id) { node in
                            if let subitems = node.items, !subitems.isEmpty {
                                NavigationLink {
                                    SubLocationAssetsView(parentNode: node)
                                } label: {
                                    AssetItemView(node: node, itemInfo: viewModel.itemInfo(for: node.type_id))
                                }
                            } else {
                                AssetItemView(node: node, itemInfo: viewModel.itemInfo(for: node.type_id))
                            }
                        }
                    }
                }
            }
        }
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
    private let databaseManager: DatabaseManager
    
    init(location: AssetTreeNode, databaseManager: DatabaseManager = DatabaseManager()) {
        self.location = location
        self.databaseManager = databaseManager
    }
    
    func itemInfo(for typeId: Int) -> ItemInfo? {
        itemInfoCache[typeId]
    }
    
    // 按location_flag分组的资产
    func groupedAssets() -> [(flag: String, items: [AssetTreeNode])] {
        let items = location.items ?? []
        
        // 预处理location_flag，将相同类型的槽位合并
        let processedItems = items.map { item -> (flag: String, node: AssetTreeNode) in
            let flag = item.location_flag
            let processedFlag: String
            
            switch flag {
            case let f where f.hasPrefix("HiSlot"):
                processedFlag = "HiSlots"
            case let f where f.hasPrefix("MedSlot"):
                processedFlag = "MedSlots"
            case let f where f.hasPrefix("LoSlot"):
                processedFlag = "LoSlots"
            case let f where f.hasPrefix("RigSlot"):
                processedFlag = "RigSlots"
            case let f where f.hasPrefix("SubSystemSlot"):
                processedFlag = "SubSystemSlots"
            case let f where f.hasPrefix("FighterTube"):
                processedFlag = "FighterTubes"
            default:
                processedFlag = flag
            }
            
            return (flag: processedFlag, node: item)
        }
        
        // 按处理后的flag分组
        let grouped = Dictionary(grouping: processedItems) { $0.flag }
        
        // 对分组进行排序，并合并相同物品
        return grouped.map { flag, items in
            // 对每个分组内的物品进行合并
            let mergedItems = Dictionary(grouping: items) { item in
                // 如果有子物品（是容器），使用唯一标识符防止合并
                if let items = item.node.items, !items.isEmpty {
                    return "\(item.node.type_id)_\(item.node.name ?? "")_\(item.node.item_id)"
                }
                // 非容器物品使用type_id和name作为合并的key
                return "\(item.node.type_id)_\(item.node.name ?? "")"
            }.map { _, sameItems -> AssetTreeNode in
                let firstItem = sameItems[0].node
                
                // 只有在非容器且数量大于1时才合并
                if (firstItem.items == nil || firstItem.items?.isEmpty == true) && (sameItems.count > 1 || firstItem.quantity > 1) {
                    let totalQuantity = sameItems.reduce(0) { $0 + $1.node.quantity }
                    return AssetTreeNode(
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
                } else {
                    return firstItem
                }
            }
            .sorted { node1, node2 in
                // 获取物品名称
                let name1 = itemInfo(for: node1.type_id)?.name ?? ""
                let name2 = itemInfo(for: node2.type_id)?.name ?? ""
                
                // 先按名称排序
                if name1 != name2 {
                    return name1 < name2
                }
                
                // 如果名称相同，按item_id排序
                return node1.item_id < node2.item_id
            }
            
            return (flag: flag, items: mergedItems)
        }
        .sorted { pair1, pair2 in
            // 自定义排序逻辑
            let order: [String] = [
                // 装配槽位
                "HiSlots",
                "MedSlots",
                "LoSlots",
                "RigSlots",
                "SubSystemSlots",
                
                // 无人机和战斗机
                "DroneBay",
                "FighterBay",
                "FighterTubes",
                
                // 特殊舱室
                "SpecializedAmmoHold",
                "SpecializedFuelBay",
                "SpecializedOreHold",
                "SpecializedGasHold",
                "SpecializedMineralHold",
                "SpecializedSalvageHold",
                "SpecializedShipHold",
                "SpecializedSmallShipHold",
                "SpecializedMediumShipHold",
                "SpecializedLargeShipHold",
                "SpecializedIndustrialShipHold",
                "SpecializedMaterialBay",
                "SpecializedPlanetaryCommoditiesHold",
                "SpecializedCommandCenterHold",
                
                // 基础舱室
                "Cargo",
                "Hangar",
                "ShipHangar",
                "FleetHangar",
                "SubSystemBay",
                
                // 公司机库
                "CorpSAG1", 
                "CorpSAG2", 
                "CorpSAG3", 
                "CorpSAG4", 
                "CorpSAG5", 
                "CorpSAG6", 
                "CorpSAG7",
                
                // 交付箱
                "Deliveries",
                "CorpDeliveries",
                
                // 其他
                "AutoFit",
                "HiddenModifiers"
            ]
            
            let index1 = order.firstIndex(of: pair1.flag) ?? Int.max
            let index2 = order.firstIndex(of: pair2.flag) ?? Int.max
            return index1 < index2
        }
    }
    
    // 从数据库加载物品信息
    @MainActor
    func loadItemInfo() async {
        guard let items = location.items else { return }
        
        let typeIds = Set(items.map { $0.type_id })
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
