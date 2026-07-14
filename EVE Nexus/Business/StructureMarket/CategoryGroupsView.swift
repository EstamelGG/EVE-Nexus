import SwiftUI

// MARK: - 目录分组视图

struct CategoryGroupsView: View {
    let category: CategoryOrderData
    let structureId: Int64
    let characterId: Int
    let orderType: MarketOrderType

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
                // Section 1: 分组饼图
                if !groupData.isEmpty {
                    Section(header: Text(NSLocalizedString("Structure_Market_Group_Distribution", comment: "分组分布"))) {
                        GroupPieChartView(data: groupData)
                            .padding(.vertical)
                            .frame(maxWidth: .infinity)
                    }
                }

                // Section 2: 所有分组列表
                if !groupData.isEmpty {
                    Section(header: Text(NSLocalizedString("Structure_Market_All_Groups", comment: "所有分组"))) {
                        ForEach(groupData) { group in
                            NavigationLink(destination: GroupItemsView(
                                group: group,
                                structureId: structureId,
                                characterId: characterId,
                                orderType: orderType
                            )) {
                                GroupListRowView(group: group)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // 只在首次加载时执行
            if !hasLoaded {
                hasLoaded = true
                await loadGroupData()
            }
        }
    }

    private func loadGroupData() async {
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

            // 计算该目录下所有分组的订单数
            let groups = await calculateCategoryGroups(orders: filteredOrders, categoryID: category.id)

            await MainActor.run {
                groupData = groups
                isLoading = false
            }
        } catch {
            Logger.error("加载分组数据失败: \(error)")
            await MainActor.run {
                groupData = []
                isLoading = false
            }
        }
    }

    /// 计算指定目录下所有分组的订单数
    private func calculateCategoryGroups(orders: [StructureMarketOrder], categoryID: Int) async -> [GroupOrderData] {
        guard !orders.isEmpty else {
            return []
        }

        // 获取所有唯一的 typeId（用于内存过滤）
        let orderTypeIds = Set(orders.map { $0.typeId })

        guard !orderTypeIds.isEmpty else {
            return []
        }

        // 直接查询该目录下所有物品（不限制 typeId，减少 SQL 参数）
        let query = """
            SELECT type_id, categoryID, groupID, group_name
            FROM types
            WHERE categoryID = ?
        """

        // 统计每个typeId的订单数
        var typeIdOrderCount: [Int: Int] = [:]
        for order in orders {
            typeIdOrderCount[order.typeId, default: 0] += 1
        }

        // 统计该目录下各组的订单数
        var groupOrderCount: [Int: (groupID: Int, groupName: String, orderCount: Int)] = [:]

        // 查询该目录下所有物品
        if case let .success(rows) = DatabaseManager.shared.executeQuery(
            query,
            parameters: [categoryID]
        ) {
            for row in rows {
                guard let typeId = row["type_id"] as? Int else {
                    continue
                }

                // 在内存中过滤：只处理订单中存在的 typeId
                guard orderTypeIds.contains(typeId),
                      let orderCount = typeIdOrderCount[typeId]
                else {
                    continue
                }

                // 处理组
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

        // 查询组图标（查询全部，在内存中过滤）
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

                    // 在内存中过滤：只处理需要的 groupID
                    guard uniqueGroupIDs.contains(groupID) else {
                        continue
                    }

                    groupIconMap[groupID] = iconFileName.isEmpty ? IconManager.defaultIcon : iconFileName
                }
            }
        }

        // 转换为数组并排序
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
