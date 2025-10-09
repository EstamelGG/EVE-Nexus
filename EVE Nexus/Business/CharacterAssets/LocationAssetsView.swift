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
    case "StructureDeedBay":
        return NSLocalizedString("Location_Flag_StructureDeedBay", comment: "")
    case "Unlocked":
        return NSLocalizedString("Location_Flag_Unlocked", comment: "")
    case "Wardrobe":
        return NSLocalizedString("Location_Flag_Wardrobe", comment: "")
    default:
        return flag
    }
}

// 扩展，提供共用的获取位置名称方法
extension AssetTreeNode {
    func getLocationName(
        stationNameCache: [Int64: String]? = nil, solarSystemNameCache: [Int: String]? = nil
    ) -> String {
        // 如果有自定义名称，优先使用
        if let name = name {
            return HTMLUtils.decodeHTMLEntities(name)
        }

        // 如果是空间站类型，从缓存中获取
        if location_type == "station", let cache = stationNameCache {
            if let name = cache[location_id] {
                return HTMLUtils.decodeHTMLEntities(name)
            }
        }

        // 如果有星系ID，尝试显示星系名称
        if let systemId = system_id, let cache = solarSystemNameCache,
           let name = cache[systemId]
        {
            return HTMLUtils.decodeHTMLEntities(name)
        }

        // 最后的回退选项
        return String(location_id)
    }
}

// 共用的图标视图
private struct AssetIconView: View {
    let iconName: String
    let size: CGFloat

    init(iconName: String, size: CGFloat = 32) {
        self.iconName = iconName
        self.size = size
    }

    var body: some View {
        IconManager.shared.loadImage(for: iconName)
            .resizable()
            .frame(width: size, height: size)
            .cornerRadius(6)
    }
}

// 主资产列表视图
struct LocationAssetsView: View {
    let location: AssetTreeNode
    @StateObject private var viewModel: LocationAssetsViewModel
    let stationNameCache: [Int64: String]?
    let solarSystemNameCache: [Int: String]?

    init(
        location: AssetTreeNode, preloadedItemInfo: [Int: ItemInfo]? = nil,
        stationNameCache: [Int64: String]? = nil, solarSystemNameCache: [Int: String]? = nil
    ) {
        self.location = location
        self.stationNameCache = stationNameCache
        self.solarSystemNameCache = solarSystemNameCache
        _viewModel = StateObject(
            wrappedValue: LocationAssetsViewModel(
                location: location, preloadedItemInfo: preloadedItemInfo
            ))
    }

    // 获取位置名称
    private func getLocationName() -> String {
        return location.getLocationName(
            stationNameCache: stationNameCache, solarSystemNameCache: solarSystemNameCache
        )
    }

    var body: some View {
        List {
            ForEach(viewModel.groupedAssets(), id: \.flag) { group in
                assetGroupSection(for: group)
            }
        }
        .navigationTitle(getLocationName())
        .task {
            await viewModel.loadItemInfo()
        }
    }

    // 将Section提取为单独的函数
    private func assetGroupSection(for group: (flag: String, items: [AssetTreeNode])) -> some View {
        Section(
            header: Text(formatLocationFlag(group.flag))
                .fontWeight(.semibold)
                .font(.system(size: 18))
                .foregroundColor(.primary)
                .textCase(.none)
        ) {
            ForEach(group.items, id: \.item_id) { node in
                assetRow(for: node)
            }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
    }

    // 将资产行提取为单独的函数
    @ViewBuilder
    private func assetRow(for node: AssetTreeNode) -> some View {
        if node.items != nil {
            // 容器类物品
            containerLink(for: node)
        } else {
            // 非容器物品
            itemLink(for: node)
        }
    }

    // 容器链接
    private func containerLink(for node: AssetTreeNode) -> some View {
        NavigationLink {
            SubLocationAssetsView(
                parentNode: node, preloadedItemInfo: viewModel.preloadedItemInfo,
                stationNameCache: stationNameCache, solarSystemNameCache: solarSystemNameCache
            )
        } label: {
            AssetItemView(node: node, itemInfo: viewModel.itemInfo(for: node.type_id))
        }
    }

    // 物品链接
    private func itemLink(for node: AssetTreeNode) -> some View {
        NavigationLink {
            MarketItemDetailView(databaseManager: viewModel.databaseManager, itemID: node.type_id)
        } label: {
            AssetItemView(node: node, itemInfo: viewModel.itemInfo(for: node.type_id))
        }
    }
}

// 单个资产项的视图
struct AssetItemView: View {
    let node: AssetTreeNode
    let itemInfo: ItemInfo?
    let showItemCount: Bool
    let showCustomName: Bool

    init(
        node: AssetTreeNode, itemInfo: ItemInfo?, showItemCount: Bool = true,
        showCustomName: Bool = true
    ) {
        self.node = node
        self.itemInfo = itemInfo
        self.showItemCount = showItemCount
        self.showCustomName = showCustomName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // 资产图标 - 优先使用节点上的icon_name
                AssetIconView(
                    iconName: node.icon_name ?? itemInfo?.iconFileName
                        ?? DatabaseConfig.defaultItemIcon)
                VStack(alignment: .leading, spacing: 2) {
                    // 资产名称和自定义名称
                    HStack(spacing: 4) {
                        if let itemInfo = itemInfo {
                            Text(itemInfo.name).lineLimit(1)
                                .contextMenu {
                                    Button {
                                        UIPasteboard.general.string = itemInfo.name
                                    } label: {
                                        Label(
                                            NSLocalizedString("Misc_Copy_Item_Name", comment: ""),
                                            systemImage: "doc.on.doc"
                                        )
                                    }
                                }
                            if showCustomName, let customName = node.name, node.items != nil,
                               !customName.isEmpty, customName != "None"
                            {
                                Text("[\(HTMLUtils.decodeHTMLEntities(customName))]")
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            if node.quantity > 1 {
                                Text("×\(node.quantity)")
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text("Type ID: \(node.type_id)")
                        }
                    }
                    if let isBlueprintCopy = node.is_blueprint_copy, isBlueprintCopy {
                        Text(NSLocalizedString("Assets_is_BPC", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if showItemCount, let items = node.items, !items.isEmpty {
                        Text(
                            String(
                                format: NSLocalizedString("Assets_Item_Count", comment: ""),
                                items.count
                            )
                        )
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
    let stationNameCache: [Int64: String]?
    let solarSystemNameCache: [Int: String]?

    init(
        parentNode: AssetTreeNode, preloadedItemInfo: [Int: ItemInfo]? = nil,
        stationNameCache: [Int64: String]? = nil, solarSystemNameCache: [Int: String]? = nil
    ) {
        self.parentNode = parentNode
        self.stationNameCache = stationNameCache
        self.solarSystemNameCache = solarSystemNameCache
        _viewModel = StateObject(
            wrappedValue: LocationAssetsViewModel(
                location: parentNode, preloadedItemInfo: preloadedItemInfo
            ))
    }

    var body: some View {
        List {
            if parentNode.items != nil {
                // 容器本身的信息
                containerInfoSection

                // 容器内的物品
                ForEach(viewModel.groupedAssets(), id: \.flag) { group in
                    containerContentSection(for: group)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(getLocationName())
        .task {
            await viewModel.loadItemInfo()
        }
    }

    // 获取位置名称
    private func getLocationName() -> String {
        return parentNode.getLocationName(
            stationNameCache: stationNameCache, solarSystemNameCache: solarSystemNameCache
        )
    }

    // 容器信息部分
    private var containerInfoSection: some View {
        Section {
            NavigationLink {
                MarketItemDetailView(
                    databaseManager: viewModel.databaseManager, itemID: parentNode.type_id
                )
            } label: {
                AssetItemView(
                    node: parentNode,
                    itemInfo: viewModel.itemInfo(for: parentNode.type_id),
                    showItemCount: false,
                    showCustomName: false
                )
            }
        } header: {
            Text(NSLocalizedString("Container_Basic_Info", comment: ""))
                .fontWeight(.semibold)
                .font(.system(size: 18))
                .foregroundColor(.primary)
                .textCase(.none)
        }
    }

    // 容器内容部分
    private func containerContentSection(for group: (flag: String, items: [AssetTreeNode]))
        -> some View
    {
        Section(
            header: Text(formatLocationFlag(group.flag))
                .fontWeight(.semibold)
                .font(.system(size: 18))
                .foregroundColor(.primary)
                .textCase(.none)
        ) {
            ForEach(group.items, id: \.item_id) { node in
                containerItemRow(for: node)
            }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
    }

    // 容器内物品行
    @ViewBuilder
    private func containerItemRow(for node: AssetTreeNode) -> some View {
        if let subitems = node.items, !subitems.isEmpty {
            // 子容器
            NavigationLink {
                SubLocationAssetsView(
                    parentNode: node,
                    preloadedItemInfo: viewModel.preloadedItemInfo,
                    stationNameCache: stationNameCache,
                    solarSystemNameCache: solarSystemNameCache
                )
            } label: {
                AssetItemView(node: node, itemInfo: viewModel.itemInfo(for: node.type_id))
            }
        } else {
            // 普通物品
            NavigationLink {
                MarketItemDetailView(
                    databaseManager: viewModel.databaseManager, itemID: node.type_id
                )
            } label: {
                AssetItemView(node: node, itemInfo: viewModel.itemInfo(for: node.type_id))
            }
        }
    }
}

// LocationAssetsViewModel
class LocationAssetsViewModel: ObservableObject {
    private let location: AssetTreeNode
    private var itemInfoCache: [Int: ItemInfo] = [:]
    let databaseManager: DatabaseManager

    // 添加一个标志来跟踪是否正在加载
    private var isLoadingItems = false

    // 修改为internal，使其可以被视图访问
    let preloadedItemInfo: [Int: ItemInfo]?

    // 添加优先显示的货物集装箱的marketGroupID列表
    private let priorityMarketGroups = [1651, 1652, 1653, 1657, 1658]

    init(
        location: AssetTreeNode, databaseManager: DatabaseManager = DatabaseManager(),
        preloadedItemInfo: [Int: ItemInfo]? = nil
    ) {
        self.location = location
        self.databaseManager = databaseManager
        self.preloadedItemInfo = preloadedItemInfo
    }

    func itemInfo(for typeId: Int) -> ItemInfo? {
        // 从缓存中查找该类型的物品信息
        return itemInfoCache[typeId]
    }

    // 从数据库获取优先级容器的type_id集合
    private func getPriorityContainerTypeIds() -> Set<Int> {
        // 构建查询，一次性获取所有优先市场组ID的物品类型
        let marketGroupList = priorityMarketGroups.map { String($0) }.joined(separator: ",")
        let query = "SELECT type_id FROM types WHERE marketGroupID IN (\(marketGroupList))"

        var typeIds = Set<Int>()

        if case let .success(rows) = databaseManager.executeQuery(query) {
            for row in rows {
                if let typeId = row["type_id"] as? Int {
                    typeIds.insert(typeId)
                }
            }
        }

        return typeIds
    }

    // 按location_flag分组的资产
    func groupedAssets() -> [(flag: String, items: [AssetTreeNode])] {
        // 如果是容器，使用其items属性
        let items = location.items ?? []
        if items.isEmpty {
            return []
        }

        // 获取优先显示的容器类型ID集合
        let priorityTypeIds = getPriorityContainerTypeIds()

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

            // 直接使用预先获取的type_id集合来确定优先容器
            let priorityContainers = containers.filter { priorityTypeIds.contains($0.type_id) }
            let normalContainers = containers.filter { !priorityTypeIds.contains($0.type_id) }

            // 分别对优先容器和普通容器进行排序
            let sortedPriorityContainers = priorityContainers.sorted { item1, item2 in
                let name1 = itemInfo(for: item1.type_id)?.name ?? ""
                let name2 = itemInfo(for: item2.type_id)?.name ?? ""
                if name1 != name2 {
                    return name1.localizedCompare(name2) == .orderedAscending
                }
                return item1.item_id < item2.item_id
            }

            let sortedNormalContainers = normalContainers.sorted { item1, item2 in
                let name1 = itemInfo(for: item1.type_id)?.name ?? ""
                let name2 = itemInfo(for: item2.type_id)?.name ?? ""
                if name1 != name2 {
                    return name1.localizedCompare(name2) == .orderedAscending
                }
                return item1.item_id < item2.item_id
            }

            // 再对普通物品按名称排序
            let sortedNormalItems = mergedNormalItems.sorted { item1, item2 in
                let name1 = itemInfo(for: item1.type_id)?.name ?? ""
                let name2 = itemInfo(for: item2.type_id)?.name ?? ""
                if name1 != name2 {
                    return name1.localizedCompare(name2) == .orderedAscending
                }
                return item1.item_id < item2.item_id
            }

            // 优先容器 + 普通容器 + 普通物品
            let allItems = sortedPriorityContainers + sortedNormalContainers + sortedNormalItems
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
        case let f where f.hasPrefix("FighterTube"): return "FighterTubes"
        default: return flag
        }
    }

    private let flagOrder = [
        "HiSlots", "MedSlots", "LoSlots", "RigSlots", "SubSystemSlots",
        "FighterBay", "FighterTubes", "DroneBay", "Cargo", "Hangar", "ShipHangar", "FleetHangar",
        "CorpSAG1", "CorpSAG2", "CorpSAG3", "CorpSAG4", "CorpSAG5", "CorpSAG6", "CorpSAG7",
        "CorpDeliveries", "Deliveries", "SpecializedAmmoHold", "SpecializedCommandCenterHold",
        "SpecializedFuelBay",
        "SpecializedGasHold", "SpecializedIndustrialShipHold", "SpecializedLargeShipHold",
        "SpecializedMaterialBay", "SpecializedMediumShipHold", "SpecializedMineralHold",
        "SpecializedOreHold", "SpecializedPlanetaryCommoditiesHold", "SpecializedSalvageHold",
        "SpecializedShipHold", "SpecializedSmallShipHold",
    ]

    @MainActor
    func loadItemInfo() async {
        // 如果已经在加载中，直接返回
        guard !isLoadingItems else {
            return
        }

        // 设置加载标志
        isLoadingItems = true

        // 如果有预加载的物品信息，直接使用
        if let preloadedInfo = preloadedItemInfo {
            itemInfoCache = preloadedInfo
            objectWillChange.send()
            isLoadingItems = false
            return
        }

        // 收集需要查询的type_id和已有的图标
        var typeIds = Set<Int>()
        var typeIdToNodes: [Int: [AssetTreeNode]] = [:]

        // 添加当前位置节点
        collectNode(location, typeIds: &typeIds, typeIdToNodes: &typeIdToNodes)

        // 处理子项
        if let items = location.items {
            for item in items {
                collectNode(item, typeIds: &typeIds, typeIdToNodes: &typeIdToNodes)
            }
        }

        // 查询所有物品的名称
        if !typeIds.isEmpty {
            let query = """
                SELECT t.type_id, t.name, t.zh_name, t.en_name
                FROM types t
                WHERE t.type_id IN (\(typeIds.sorted().map { String($0) }.joined(separator: ",")))
            """

            if case let .success(rows) = databaseManager.executeQuery(query) {
                var typeIdToName: [Int: String] = [:]

                // 先收集所有的名称
                for row in rows {
                    if let typeId = row["type_id"] as? Int,
                       let name = row["name"] as? String,
                       let zh_name = row["zh_name"] as? String,
                       let en_name = row["en_name"] as? String
                    {
                        typeIdToName[typeId] = name

                        // 为每个节点创建ItemInfo
                        if let nodes = typeIdToNodes[typeId] {
                            // 一般情况下，对于相同的type_id，我们只需要存储一个ItemInfo
                            // 我们默认使用第一个非蓝图复制品节点的图标（如果有的话）
                            let nonBPCNode =
                                nodes.first { node in
                                    !(node.is_blueprint_copy ?? false)
                                } ?? nodes.first

                            if let node = nonBPCNode {
                                let iconName = node.icon_name ?? DatabaseConfig.defaultItemIcon
                                itemInfoCache[typeId] = ItemInfo(
                                    name: name,
                                    zh_name: zh_name,
                                    en_name: en_name,
                                    iconFileName: iconName
                                )
                            }
                        }
                    }
                }

                objectWillChange.send()
            }
        }

        // 重置加载标志
        isLoadingItems = false
    }

    // 收集节点信息的辅助方法
    private func collectNode(
        _ node: AssetTreeNode, typeIds: inout Set<Int>, typeIdToNodes: inout [Int: [AssetTreeNode]]
    ) {
        let typeId = node.type_id
        typeIds.insert(typeId)

        if typeIdToNodes[typeId] == nil {
            typeIdToNodes[typeId] = []
        }
        typeIdToNodes[typeId]?.append(node)
    }
}
