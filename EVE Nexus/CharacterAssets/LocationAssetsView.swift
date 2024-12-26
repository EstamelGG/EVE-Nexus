import SwiftUI

// 格式化location_flag显示
private func formatLocationFlag(_ flag: String) -> String {
    // 这里可以添加更多的映射
    switch flag {
    case "Hangar":
        return "机库"
    case "CorpSAG1":
        return "公司机库 1"
    case "CorpSAG2":
        return "公司机库 2"
    case "CorpSAG3":
        return "公司机库 3"
    case "CorpSAG4":
        return "公司机库 4"
    case "CorpSAG5":
        return "公司机库 5"
    case "CorpSAG6":
        return "公司机库 6"
    case "CorpSAG7":
        return "公司机库 7"
    case "CorpDeliveries":
        return "公司交付"
    case "AutoFit":
        return "自动装配"
    case "Cargo":
        return "货物"
    case "DroneBay":
        return "无人机舱"
    case "FleetHangar":
        return "舰队机库"
    case "Deliveries":
        return "交付"
    case "HiddenModifiers":
        return "隐藏修改器"
    case "ShipHangar":
        return "舰船机库"
    case "FighterBay":
        return "战斗机舱"
    case "FighterTubes":
        return "战斗机发射管"
    case "SubSystemBay":
        return "子系统舱"
    case "SubSystemSlots":
        return "子系统插槽"
    case "HiSlots":
        return "高槽"
    case "MedSlots":
        return "中槽"
    case "LoSlots":
        return "低槽"
    case "RigSlots":
        return "改装槽"
    case "SpecializedAmmoHold":
        return "特殊弹药仓"
    case "SpecializedCommandCenterHold":
        return "特殊指挥中心仓"
    case "SpecializedFuelBay":
        return "特殊燃料仓"
    case "SpecializedGasHold":
        return "特殊气体仓"
    case "SpecializedIndustrialShipHold":
        return "特殊工业舰船仓"
    case "SpecializedLargeShipHold":
        return "特殊大型舰船仓"
    case "SpecializedMaterialBay":
        return "特殊材料仓"
    case "SpecializedMediumShipHold":
        return "特殊中型舰船仓"
    case "SpecializedMineralHold":
        return "特殊矿物仓"
    case "SpecializedOreHold":
        return "特殊矿石仓"
    case "SpecializedPlanetaryCommoditiesHold":
        return "特殊行星商品仓"
    case "SpecializedSalvageHold":
        return "特殊打捞仓"
    case "SpecializedShipHold":
        return "特殊舰船仓"
    case "SpecializedSmallShipHold":
        return "特殊小型舰船仓"
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
