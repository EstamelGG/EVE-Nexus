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
    case "FighterTube0", "FighterTube1", "FighterTube2", "FighterTube3", "FighterTube4":
        return "战斗机发射管 \(flag.dropFirst("FighterTube".count))"
    case "SubSystemBay":
        return "子系统舱"
    case "SubSystemSlot0", "SubSystemSlot1", "SubSystemSlot2", "SubSystemSlot3", "SubSystemSlot4":
        return "子系统插槽 \(flag.dropFirst("SubSystemSlot".count))"
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
    case "HiSlot0", "HiSlot1", "HiSlot2", "HiSlot3", "HiSlot4", "HiSlot5", "HiSlot6", "HiSlot7":
        return "高槽 \(flag.dropFirst("HiSlot".count))"
    case "MedSlot0", "MedSlot1", "MedSlot2", "MedSlot3", "MedSlot4", "MedSlot5", "MedSlot6", "MedSlot7":
        return "中槽 \(flag.dropFirst("MedSlot".count))"
    case "LoSlot0", "LoSlot1", "LoSlot2", "LoSlot3", "LoSlot4", "LoSlot5", "LoSlot6", "LoSlot7":
        return "低槽 \(flag.dropFirst("LoSlot".count))"
    case "RigSlot0", "RigSlot1", "RigSlot2", "RigSlot3", "RigSlot4", "RigSlot5", "RigSlot6", "RigSlot7":
        return "改装槽 \(flag.dropFirst("RigSlot".count))"
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
                        } else {
                            Text("Type ID: \(node.type_id)")
                        }
                    }
                    
                    // 数量信息
                    if node.quantity > 1 {
                        Text("数量：\(node.quantity)")
                            .font(.caption)
                            .foregroundColor(.secondary)
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
        let grouped = Dictionary(grouping: items) { item in
            item.location_flag
        }
        
        // 对分组进行排序
        return grouped.map { (flag: $0.key, items: $0.value) }
            .sorted { $0.flag < $1.flag }
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
