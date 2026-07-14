import SwiftUI

// MARK: - 含全语种名称的溢价物品信息（用于搜索）

struct PremiumItemInfoWithNames: Identifiable {
    let id: Int
    let premiumItem: PremiumItemInfo
    let names: LocalizedText

    init(premiumItem: PremiumItemInfo, names: LocalizedText) {
        id = premiumItem.id
        self.premiumItem = premiumItem
        self.names = names
    }

    func matches(_ query: String) -> Bool {
        names.matchesSearch(query) || premiumItem.name.localizedCaseInsensitiveContains(query)
    }
}

// MARK: - 溢价物品视图

struct PremiumItemsView: View {
    let structureId: Int64
    let characterId: Int
    let allPremiumItems: [PremiumItemInfo] // 所有溢价物品（从父视图传入）
    let sellOrders: [StructureMarketOrder] // 卖单数据（从父视图传入）

    @State private var categoryData: [CategoryOrderData] = []
    @State private var hasLoaded = false
    @State private var searchText = ""
    @State private var allPremiumItemsWithNames: [PremiumItemInfoWithNames] = [] // 包含中英文名称的溢价物品
    @State private var showBuyPrice = false // 是否显示买价溢价（false = 卖价，true = 买价）

    /// 过滤后的搜索结果
    private var filteredItems: [PremiumItemInfoWithNames] {
        guard searchText.count >= 2 else {
            return []
        }

        return allPremiumItemsWithNames.filter { $0.matches(searchText) }
            .sorted { item1, item2 in
                // 按名称顺序排序
                item1.premiumItem.name.localizedCompare(item2.premiumItem.name) == .orderedAscending
            }
    }

    var body: some View {
        List {
            // 搜索模式：显示搜索结果
            if searchText.count >= 2 {
                if filteredItems.isEmpty {
                    Section {
                        NoDataSection()
                    }
                } else {
                    Section(header: HStack {
                        Text(showBuyPrice
                            ? NSLocalizedString("Structure_Market_Search_Results_Buy", comment: "搜索结果 (买单溢价)")
                            : NSLocalizedString("Structure_Market_Search_Results_Sell", comment: "搜索结果 (卖单溢价)"))
                        Spacer()
                        Button {
                            showBuyPrice.toggle()
                        } label: {
                            Text(showBuyPrice
                                ? NSLocalizedString("Main_Market_Order_Buy", comment: "买单")
                                : NSLocalizedString("Main_Market_Order_Sell", comment: "卖单"))
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }) {
                        ForEach(filteredItems) { itemWithNames in
                            let item = itemWithNames.premiumItem
                            NavigationLink(destination: StructureItemOrdersView(
                                structureId: structureId,
                                characterId: characterId,
                                itemID: item.typeId,
                                itemName: item.name,
                                orderType: showBuyPrice ? .buy : .sell,
                                databaseManager: DatabaseManager.shared
                            )) {
                                HStack(spacing: 12) {
                                    // 物品图标
                                    IconManager.shared.loadImage(for: item.iconFileName)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 32, height: 32)
                                        .cornerRadius(6)

                                    // 物品名称
                                    Text(item.name)
                                        .font(.body)
                                        .foregroundColor(.primary)

                                    Spacer()

                                    // 溢价百分比（根据切换状态显示买价或卖价）
                                    VStack(alignment: .trailing, spacing: 2) {
                                        if showBuyPrice {
                                            // 显示买价溢价
                                            if let buyPremium = item.buyPremiumPercentage {
                                                Text("\(String(format: "%.1f", buyPremium))%")
                                                    .font(.system(.body, design: .monospaced))
                                                    .foregroundColor(buyPremium > 0 ? .green : .red)
                                                    .fontWeight(.semibold)
                                                if let buyPrice = item.structureBuyPrice {
                                                    Text("\(FormatUtil.formatISK(buyPrice))")
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                            } else {
                                                Text(NSLocalizedString("Misc_No_Data", comment: "无数据"))
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        } else {
                                            // 显示卖价溢价
                                            Text("\(String(format: "%.1f", item.sellPremiumPercentage))%")
                                                .font(.system(.body, design: .monospaced))
                                                .foregroundColor(item.sellPremiumPercentage > 0 ? .red : .green)
                                                .fontWeight(.semibold)
                                            Text("\(FormatUtil.formatISK(item.structureSellPrice))")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }
                }
            } else {
                // 正常模式：显示目录列表
                if categoryData.isEmpty && !hasLoaded {
                    Section {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                } else if categoryData.isEmpty {
                    Section {
                        NoDataSection()
                    }
                } else {
                    // 所有目录列表（在一个 section 中）
                    Section(header: Text(NSLocalizedString("Structure_Market_All_Categories", comment: "所有目录"))) {
                        ForEach(categoryData) { category in
                            NavigationLink(destination: PremiumCategoryGroupsView(
                                category: category,
                                structureId: structureId,
                                characterId: characterId,
                                allPremiumItems: allPremiumItems,
                                sellOrders: sellOrders
                            )) {
                                CategoryListRowView(category: category)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(
            text: $searchText,
            prompt: NSLocalizedString("Structure_Market_Search_Placeholder", comment: "搜索物品名称（至少2个字符）")
        )
        .navigationTitle(NSLocalizedString("Structure_Market_Top_Premium", comment: "最高溢价"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if !hasLoaded {
                hasLoaded = true
                await loadPremiumData()
            }
        }
    }

    private func loadPremiumData() async {
        // 使用传入的溢价物品数据，直接计算目录分布（同时加载中英文名称）
        let (categories, itemsWithNames) = await calculatePremiumCategories(orders: sellOrders, premiumItems: allPremiumItems)

        await MainActor.run {
            categoryData = categories
            allPremiumItemsWithNames = itemsWithNames
        }

        Logger.info("成功加载 \(allPremiumItems.count) 个溢价物品，分布在 \(categories.count) 个目录中")
    }

    /// 计算溢价物品的目录分布（同时加载中英文名称用于搜索）
    private func calculatePremiumCategories(orders: [StructureMarketOrder], premiumItems: [PremiumItemInfo]) async -> ([CategoryOrderData], [PremiumItemInfoWithNames]) {
        guard !premiumItems.isEmpty else {
            return ([], [])
        }

        // 获取所有溢价物品的 typeId
        let premiumTypeIds = Set(premiumItems.map { $0.typeId })

        // 统计每个 typeId 的订单数
        var typeIdOrderCount: [Int: Int] = [:]
        for order in orders {
            if premiumTypeIds.contains(order.typeId) {
                typeIdOrderCount[order.typeId, default: 0] += 1
            }
        }

        // 查询溢价物品的目录信息；名称从内存全语种索引取
        let typeIdsArray = Array(premiumTypeIds)
        let placeholders = String(repeating: "?,", count: typeIdsArray.count).dropLast()
        let query = """
            SELECT type_id, categoryID, category_name
            FROM types
            WHERE type_id IN (\(placeholders))
        """

        var categoryOrderCount: [Int: (name: String, orderCount: Int)] = [:]
        var nameMap: [Int: LocalizedText] = [:]

        if case let .success(rows) = DatabaseManager.shared.executeQuery(query, parameters: typeIdsArray) {
            for row in rows {
                guard let typeId = row["type_id"] as? Int,
                      let categoryId = row["categoryID"] as? Int,
                      let categoryName = row["category_name"] as? String,
                      let orderCount = typeIdOrderCount[typeId]
                else {
                    continue
                }

                if let type = SDEMemoryStore.type(for: typeId) {
                    nameMap[typeId] = type.names
                }

                // 统计目录订单数
                if let existing = categoryOrderCount[categoryId] {
                    categoryOrderCount[categoryId] = (
                        name: categoryName,
                        orderCount: existing.orderCount + orderCount
                    )
                } else {
                    categoryOrderCount[categoryId] = (
                        name: categoryName,
                        orderCount: orderCount
                    )
                }
            }
        }

        // 查询目录图标
        let uniqueCategoryIDs = Set(categoryOrderCount.keys)
        var categoryIconMap: [Int: String] = [:]
        if !uniqueCategoryIDs.isEmpty {
            let categoryIconQuery = """
                SELECT category_id, icon_filename
                FROM categories
            """

            if case let .success(iconRows) = DatabaseManager.shared.executeQuery(
                categoryIconQuery,
                parameters: []
            ) {
                for iconRow in iconRows {
                    guard let categoryID = iconRow["category_id"] as? Int,
                          let iconFileName = iconRow["icon_filename"] as? String
                    else {
                        continue
                    }

                    guard uniqueCategoryIDs.contains(categoryID) else {
                        continue
                    }

                    categoryIconMap[categoryID] = iconFileName.isEmpty ? IconManager.defaultIcon : iconFileName
                }
            }
        }

        // 转换为数组并按订单数排序
        let categories = categoryOrderCount
            .sorted { $0.value.orderCount > $1.value.orderCount }
            .map { categoryId, categoryInfo in
                let iconFileName = categoryIconMap[categoryId] ?? IconManager.defaultIcon
                return CategoryOrderData(
                    id: categoryId,
                    name: categoryInfo.name,
                    orderCount: categoryInfo.orderCount,
                    iconFileName: iconFileName
                )
            }

        // 构建含全语种名称的溢价物品列表（用于搜索）
        let itemsWithNames = premiumItems.compactMap { item -> PremiumItemInfoWithNames? in
            guard let names = nameMap[item.typeId] else {
                return nil
            }
            return PremiumItemInfoWithNames(
                premiumItem: item,
                names: names
            )
        }

        return (categories, itemsWithNames)
    }
}

// MARK: - 溢价目录分组视图

struct PremiumCategoryGroupsView: View {
    let category: CategoryOrderData
    let structureId: Int64
    let characterId: Int
    let allPremiumItems: [PremiumItemInfo] // 所有溢价物品（从父视图传入）
    let sellOrders: [StructureMarketOrder] // 卖单数据（从父视图传入）

    @State private var groupData: [GroupOrderData] = []
    @State private var hasLoaded = false

    var body: some View {
        List {
            if groupData.isEmpty && !hasLoaded {
                Section {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            } else if groupData.isEmpty {
                Section {
                    NoDataSection()
                }
            } else {
                Section(header: Text(NSLocalizedString("Structure_Market_All_Groups", comment: "所有分组"))) {
                    ForEach(groupData) { group in
                        NavigationLink(destination: PremiumGroupItemsView(
                            group: group,
                            structureId: structureId,
                            characterId: characterId,
                            allPremiumItems: allPremiumItems,
                            sellOrders: sellOrders
                        )) {
                            GroupListRowView(group: group)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if !hasLoaded {
                hasLoaded = true
                await loadGroupData()
            }
        }
    }

    private func loadGroupData() async {
        // 使用传入的溢价物品和订单数据，直接计算分组
        let groups = await calculatePremiumCategoryGroups(orders: sellOrders, categoryId: category.id)

        await MainActor.run {
            groupData = groups
        }
    }

    /// 计算指定目录下所有分组的订单数（只包含溢价物品）
    private func calculatePremiumCategoryGroups(orders: [StructureMarketOrder], categoryId _: Int) async -> [GroupOrderData] {
        guard !orders.isEmpty else {
            return []
        }

        // 使用传入的溢价物品数据
        let premiumTypeIds = Set(allPremiumItems.map { $0.typeId })

        // 过滤出溢价物品的订单
        let premiumOrders = orders.filter { premiumTypeIds.contains($0.typeId) }

        guard !premiumOrders.isEmpty else {
            return []
        }

        // 获取所有唯一的 typeId
        let orderTypeIds = Set(premiumOrders.map { $0.typeId })

        guard !orderTypeIds.isEmpty else {
            return []
        }

        // 查询该目录下所有物品（使用 category.id）
        let query = """
            SELECT type_id, categoryID, groupID, group_name
            FROM types
            WHERE categoryID = ?
        """

        // 统计每个typeId的订单数
        var typeIdOrderCount: [Int: Int] = [:]
        for order in premiumOrders {
            typeIdOrderCount[order.typeId, default: 0] += 1
        }

        // 统计该目录下各组的订单数
        var groupOrderCount: [Int: (groupID: Int, groupName: String, orderCount: Int)] = [:]

        if case let .success(rows) = DatabaseManager.shared.executeQuery(
            query,
            parameters: [category.id]
        ) {
            for row in rows {
                guard let typeId = row["type_id"] as? Int else {
                    continue
                }

                guard orderTypeIds.contains(typeId),
                      let orderCount = typeIdOrderCount[typeId]
                else {
                    continue
                }

                if let groupID = row["groupID"] as? Int,
                   let groupName = row["group_name"] as? String
                {
                    if let existing = groupOrderCount[groupID] {
                        groupOrderCount[groupID] = (
                            groupID: groupID,
                            groupName: groupName,
                            orderCount: existing.orderCount + orderCount
                        )
                    } else {
                        groupOrderCount[groupID] = (
                            groupID: groupID,
                            groupName: groupName,
                            orderCount: orderCount
                        )
                    }
                }
            }
        }

        // 查询组图标
        let uniqueGroupIDs = Set(groupOrderCount.keys)
        var groupIconMap: [Int: String] = [:]
        if !uniqueGroupIDs.isEmpty {
            let groupIconQuery = """
                SELECT group_id, icon_filename
                FROM groups
            """

            if case let .success(iconRows) = DatabaseManager.shared.executeQuery(
                groupIconQuery,
                parameters: []
            ) {
                for iconRow in iconRows {
                    guard let groupID = iconRow["group_id"] as? Int,
                          let iconFileName = iconRow["icon_filename"] as? String
                    else {
                        continue
                    }

                    guard uniqueGroupIDs.contains(groupID) else {
                        continue
                    }

                    groupIconMap[groupID] = iconFileName.isEmpty ? IconManager.defaultIcon : iconFileName
                }
            }
        }

        // 转换为数组并按订单数排序
        return groupOrderCount.values
            .sorted { $0.orderCount > $1.orderCount }
            .map { groupInfo in
                let iconFileName = groupIconMap[groupInfo.groupID] ?? IconManager.defaultIcon
                return GroupOrderData(
                    id: groupInfo.groupID,
                    name: groupInfo.groupName,
                    orderCount: groupInfo.orderCount,
                    iconFileName: iconFileName
                )
            }
    }
}

// MARK: - 溢价分组物品视图

struct PremiumGroupItemsView: View {
    let group: GroupOrderData
    let structureId: Int64
    let characterId: Int
    let allPremiumItems: [PremiumItemInfo] // 所有溢价物品（从父视图传入）
    let sellOrders: [StructureMarketOrder] // 卖单数据（从父视图传入）

    @State private var itemData: [PremiumItemInfo] = []
    @State private var hasLoaded = false
    @State private var showBuyPrice = false // 是否显示买价溢价（false = 卖价，true = 买价）

    /// 根据当前显示模式排序的物品列表
    private var sortedItemData: [PremiumItemInfo] {
        if showBuyPrice {
            // 按买价溢价排序（有买价数据的优先，然后按溢价从大到小）
            return itemData.sorted { item1, item2 in
                let premium1 = item1.buyPremiumPercentage ?? -Double.infinity
                let premium2 = item2.buyPremiumPercentage ?? -Double.infinity
                return premium1 > premium2
            }
        } else {
            // 按卖价溢价排序（从大到小）
            return itemData.sorted { $0.sellPremiumPercentage > $1.sellPremiumPercentage }
        }
    }

    var body: some View {
        List {
            if itemData.isEmpty && !hasLoaded {
                Section {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            } else if itemData.isEmpty {
                Section {
                    NoDataSection()
                }
            } else {
                Section(header: HStack {
                    Text(showBuyPrice
                        ? NSLocalizedString("Structure_Market_Top_Premium_Items_Buy", comment: "所有物品 (买单溢价比例)")
                        : NSLocalizedString("Structure_Market_Top_Premium_Items_Sell", comment: "所有物品 (卖单溢价比例)"))
                    Spacer()
                    Button {
                        showBuyPrice.toggle()
                    } label: {
                        Text(showBuyPrice
                            ? NSLocalizedString("Main_Market_Order_Buy", comment: "买单")
                            : NSLocalizedString("Main_Market_Order_Sell", comment: "卖单"))
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }) {
                    ForEach(sortedItemData) { item in
                        NavigationLink(destination: StructureItemOrdersView(
                            structureId: structureId,
                            characterId: characterId,
                            itemID: item.typeId,
                            itemName: item.name,
                            orderType: showBuyPrice ? .buy : .sell,
                            databaseManager: DatabaseManager.shared
                        )) {
                            HStack(spacing: 12) {
                                // 物品图标
                                IconManager.shared.loadImage(for: item.iconFileName)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(6)

                                // 物品名称
                                Text(item.name)
                                    .font(.body)
                                    .foregroundColor(.primary)

                                Spacer()

                                // 溢价百分比（根据切换状态显示买价或卖价）
                                VStack(alignment: .trailing, spacing: 2) {
                                    if showBuyPrice {
                                        // 显示买价溢价
                                        if let buyPremium = item.buyPremiumPercentage {
                                            Text("\(String(format: "%.1f", buyPremium))%")
                                                .font(.system(.body, design: .monospaced))
                                                .foregroundColor(buyPremium > 0 ? .green : .red)
                                                .fontWeight(.semibold)
                                            if let buyPrice = item.structureBuyPrice {
                                                Text("\(FormatUtil.formatISK(buyPrice))")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        } else {
                                            Text(NSLocalizedString("Misc_No_Data", comment: "无数据"))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    } else {
                                        // 显示卖价溢价
                                        Text("\(String(format: "%.1f", item.sellPremiumPercentage))%")
                                            .font(.system(.body, design: .monospaced))
                                            .foregroundColor(item.sellPremiumPercentage > 0 ? .red : .green)
                                            .fontWeight(.semibold)
                                        Text("\(FormatUtil.formatISK(item.structureSellPrice))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if !hasLoaded {
                hasLoaded = true
                await loadItemData()
            }
        }
    }

    private func loadItemData() async {
        // 使用传入的溢价物品和订单数据，直接计算该组的物品
        let items = await calculatePremiumGroupItems(orders: sellOrders, groupID: group.id)

        await MainActor.run {
            itemData = items
        }
    }

    /// 计算指定组内物品的溢价
    private func calculatePremiumGroupItems(orders: [StructureMarketOrder], groupID: Int) async -> [PremiumItemInfo] {
        guard !orders.isEmpty else {
            return []
        }

        // 使用传入的溢价物品数据
        let premiumTypeIds = Set(allPremiumItems.map { $0.typeId })

        // 过滤出该组的订单
        let orderTypeIds = Set(orders.map { $0.typeId })

        // 查询该组内所有物品
        let query = """
            SELECT type_id, name, icon_filename
            FROM types
            WHERE groupID = ?
        """

        // 统计每个typeId的订单数
        var typeIdOrderCount: [Int: Int] = [:]
        for order in orders {
            if premiumTypeIds.contains(order.typeId) {
                typeIdOrderCount[order.typeId, default: 0] += 1
            }
        }

        // 查询该组内所有物品
        var itemInfoMap: [Int: (name: String, iconFileName: String, orderCount: Int)] = [:]

        if case let .success(rows) = DatabaseManager.shared.executeQuery(
            query,
            parameters: [groupID]
        ) {
            for row in rows {
                guard let typeId = row["type_id"] as? Int,
                      let name = row["name"] as? String,
                      orderTypeIds.contains(typeId),
                      let orderCount = typeIdOrderCount[typeId]
                else {
                    continue
                }
                let iconFileName = row["icon_filename"] as? String ?? ""

                itemInfoMap[typeId] = (
                    name: name,
                    iconFileName: iconFileName.isEmpty ? IconManager.defaultItemIcon : iconFileName,
                    orderCount: orderCount
                )
            }
        }

        // 合并溢价信息和物品信息，按溢价从大到小排序
        let items = allPremiumItems
            .filter { itemInfoMap[$0.typeId] != nil }
            .map { premiumItem -> PremiumItemInfo in
                let info = itemInfoMap[premiumItem.typeId]!
                var result = premiumItem
                result.name = info.name
                result.iconFileName = info.iconFileName
                return result
            }
            .sorted { $0.sellPremiumPercentage > $1.sellPremiumPercentage }

        return Array(items)
    }
}
