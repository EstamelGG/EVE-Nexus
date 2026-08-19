import SwiftUI

// MARK: - 市场订单可视化视图

struct MarketOrdersVisualizationView: View {
    let structureId: Int64
    let characterId: Int
    let orderType: MarketOrderType
    let title: String

    @State private var categoryData: [CategoryOrderData] = []
    @State private var groupData: [GroupOrderData] = []
    @State private var isLoading = false
    @State private var hasLoaded = false // 标记是否已加载过数据

    var body: some View {
        List {
            if isLoading {
                Section {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            } else {
                // Section 1: 目录饼图
                if !categoryData.isEmpty {
                    Section(header: Text(NSLocalizedString("Structure_Market_Category_Distribution", comment: "目录分布"))) {
                        CategoryPieChartView(data: categoryData)
                            .padding(.vertical)
                            .frame(maxWidth: .infinity)
                    }
                }

                // Section 2: 所有目录列表
                if !categoryData.isEmpty {
                    Section(header: Text(NSLocalizedString("Structure_Market_All_Categories", comment: "所有目录"))) {
                        ForEach(categoryData) { category in
                            NavigationLink(destination: CategoryGroupsView(
                                category: category,
                                structureId: structureId,
                                characterId: characterId,
                                orderType: orderType
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
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // 只在首次加载时执行
            if !hasLoaded {
                hasLoaded = true
                await loadVisualizationData()
            }
        }
    }

    private func loadVisualizationData() async {
        // 避免重复加载
        guard !isLoading else { return }

        await MainActor.run {
            isLoading = true
        }

        do {
            // 加载订单数据
            let orders = try await StructureMarketManager.shared.getStructureOrders(
                structureId: structureId,
                characterId: characterId,
                forceRefresh: false
            )

            // 过滤订单类型
            let filteredOrders = orders.filter { order in
                orderType == .buy ? order.isBuyOrder : !order.isBuyOrder
            }

            // 计算目录和组的订单数
            let (categories, groups) = await calculateOrderDistribution(orders: filteredOrders)

            await MainActor.run {
                categoryData = categories
                groupData = groups
                isLoading = false
            }
        } catch {
            Logger.error("加载可视化数据失败: \(error)")
            await MainActor.run {
                categoryData = []
                groupData = []
                isLoading = false
            }
        }
    }

    /// 计算订单分布（目录和组）
    private func calculateOrderDistribution(orders: [StructureMarketOrder]) async -> ([CategoryOrderData], [GroupOrderData]) {
        guard !orders.isEmpty else {
            return ([], [])
        }

        // 获取所有唯一的 typeId（用于内存过滤）
        let orderTypeIds = Set(orders.map { $0.typeId })

        guard !orderTypeIds.isEmpty else {
            return ([], [])
        }

        // 统计每个typeId的订单数
        var typeIdOrderCount: [Int: Int] = [:]
        for order in orders {
            typeIdOrderCount[order.typeId, default: 0] += 1
        }

        // 内存索引统计目录和组的订单数
        var categoryOrderCount: [Int: (categoryID: Int, categoryName: String, orderCount: Int)] = [:]
        var groupOrderCount: [Int: (groupID: Int, groupName: String, orderCount: Int)] = [:]

        // 收集所有唯一的categoryID，用于查询目录图标
        var uniqueCategoryIDs: Set<Int> = []

        for (typeId, info) in SDEMemoryStore.types {
            // 只处理订单中存在的 typeId
            guard orderTypeIds.contains(typeId),
                  let orderCount = typeIdOrderCount[typeId]
            else { continue }

            // 处理目录
            let categoryID = info.categoryID
            let categoryName = SDEMemoryStore.category(for: categoryID)?.name ?? ""
            uniqueCategoryIDs.insert(categoryID)
            if let existing = categoryOrderCount[categoryID] {
                categoryOrderCount[categoryID] = (
                    categoryID: categoryID,
                    categoryName: categoryName,
                    orderCount: existing.orderCount + orderCount
                )
            } else {
                categoryOrderCount[categoryID] = (
                    categoryID: categoryID,
                    categoryName: categoryName,
                    orderCount: orderCount
                )
            }

            // 处理组
            if let groupID = info.groupID {
                let groupName = SDEMemoryStore.group(for: groupID)?.name ?? ""
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

        // 查询目录图标（内存索引）
        var categoryIconMap: [Int: String] = [:]
        for categoryID in uniqueCategoryIDs {
            if let category = SDEMemoryStore.category(for: categoryID) {
                categoryIconMap[categoryID] = category.iconFilename
            }
        }

        // 查询组图标（内存索引）
        let uniqueGroupIDs = Set(groupOrderCount.keys)
        var groupIconMap: [Int: String] = [:]
        for groupID in uniqueGroupIDs {
            if let group = SDEMemoryStore.group(for: groupID) {
                groupIconMap[groupID] = group.iconFilename
            }
        }

        // 转换为数组并排序
        let categories = categoryOrderCount.values
            .sorted { $0.orderCount > $1.orderCount }
            .map { categoryInfo in
                let iconFileName = categoryIconMap[categoryInfo.categoryID] ?? IconManager.defaultIcon
                return CategoryOrderData(
                    id: categoryInfo.categoryID,
                    name: categoryInfo.categoryName,
                    orderCount: categoryInfo.orderCount,
                    iconFileName: iconFileName
                )
            }

        let groups = groupOrderCount.values
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

        return (categories, groups)
    }
}
