import SwiftUI

struct MarketOrdersView: View {
    let itemID: Int
    let itemName: String
    let orders: [MarketOrder]
    @ObservedObject var databaseManager: DatabaseManager
    @State private var showBuyOrders = false
    @State private var locationInfos: [Int64: LocationInfoDetail] = [:]
    @State private var isLoading = false
    let locationInfoLoader: LocationInfoLoader

    init(itemID: Int, itemName: String, orders: [MarketOrder], databaseManager: DatabaseManager) {
        self.itemID = itemID
        self.itemName = itemName
        self.orders = orders
        self.databaseManager = databaseManager

        // 从 UserDefaults 获取当前选择的角色ID
        let currentCharacterId = UserDefaults.standard.integer(forKey: "currentCharacterId")
        locationInfoLoader = LocationInfoLoader(
            databaseManager: databaseManager, characterId: Int64(currentCharacterId)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部选择器
            Picker("", selection: $showBuyOrders) {
                Text(
                    "\(NSLocalizedString("Orders_Sell", comment: "")) (\(orders.filter { !$0.isBuyOrder }.count))"
                ).tag(false)
                Text(
                    "\(NSLocalizedString("Orders_Buy", comment: "")) (\(orders.filter { $0.isBuyOrder }.count))"
                ).tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 4)

            // 内容视图
            TabView(selection: $showBuyOrders) {
                OrderListView(
                    orders: orders.filter { !$0.isBuyOrder },
                    locationInfos: locationInfos,
                    isLoadingLocations: isLoading
                )
                .tag(false)

                OrderListView(
                    orders: orders.filter { $0.isBuyOrder },
                    locationInfos: locationInfos,
                    isLoadingLocations: isLoading
                )
                .tag(true)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(edges: .bottom)

            if isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text(NSLocalizedString("Loading_Location_Info", comment: "正在加载地点信息..."))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .background(Color(UIColor.systemGroupedBackground))
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(itemName)
        .navigationBarTitleDisplayMode(.inline)
        .ignoresSafeArea(edges: .bottom)
        .task {
            // 立即显示订单列表，同时异步加载地点信息
            isLoading = true

            // 收集所有订单的位置ID
            let locationIds = Set(orders.map { $0.locationId })

            // 按类型分组位置ID
            let groupedIds = Dictionary(grouping: locationIds) { LocationType.from(id: $0) }

            // 先同步加载空间站信息（通常在本地数据库中，加载速度快）
            if let stationIds = groupedIds[.station] {
                let stationInfos = await locationInfoLoader.loadLocationInfo(
                    locationIds: Set(stationIds))
                locationInfos = stationInfos
            }

            // 异步加载其他类型的位置信息（星系、建筑物等）
            Task {
                var otherIds = locationIds
                if let stationIds = groupedIds[.station] {
                    // 从总ID集合中移除已加载的空间站ID
                    otherIds.subtract(stationIds)
                }

                if !otherIds.isEmpty {
                    let otherInfos = await locationInfoLoader.loadLocationInfo(
                        locationIds: otherIds)

                    // 在主线程更新UI
                    await MainActor.run {
                        // 合并空间站信息和其他位置信息
                        locationInfos.merge(otherInfos) { _, new in new }
                        isLoading = false
                    }
                } else {
                    // 如果没有其他ID需要加载，直接结束加载状态
                    await MainActor.run {
                        isLoading = false
                    }
                }
            }
        }
        .refreshable {
            // 添加下拉刷新功能
            isLoading = true

            // 收集所有订单的位置ID
            let locationIds = Set(orders.map { $0.locationId })

            // 重新加载所有位置信息
            let refreshedInfos = await locationInfoLoader.loadLocationInfo(
                locationIds: locationIds)

            // 更新UI
            locationInfos = refreshedInfos
            isLoading = false
        }
    }

    // 订单列表视图
    private struct OrderListView: View {
        let orders: [MarketOrder]
        let locationInfos: [Int64: LocationInfoDetail]
        let isLoadingLocations: Bool

        private var sortedOrders: [MarketOrder] {
            orders.sorted { order1, order2 -> Bool in
                if order1.isBuyOrder {
                    return order1.price > order2.price  // 买单按价格从高到低
                } else {
                    return order1.price < order2.price  // 卖单按价格从低到高
                }
            }
        }

        var body: some View {
            List {
                if orders.isEmpty {
                    Section {
                        NoDataSection()
                    }
                } else {
                    Section {
                        ForEach(sortedOrders, id: \.orderId) { order in
                            OrderRow(
                                order: order,
                                locationInfo: locationInfos[order.locationId],
                                isLoadingLocation: isLoadingLocations
                            )
                        }
                    }
                    .listSectionSpacing(.compact)
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    // 订单行视图
    private struct OrderRow: View {
        let order: MarketOrder
        let locationInfo: LocationInfoDetail?
        let isLoadingLocation: Bool

        var body: some View {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(formatPrice(order.price))
                            .font(.headline)
                        Spacer()
                        Text("Qty: \(order.volumeRemain)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let locationInfo = locationInfo {
                        LocationInfoView(
                            stationName: locationInfo.stationName,
                            solarSystemName: locationInfo.solarSystemName,
                            security: locationInfo.security,
                            font: .caption,
                            textColor: .secondary
                        )
                    } else if isLoadingLocation {
                        // 地点信息加载中的占位视图
                        HStack(spacing: 4) {
                            Text(NSLocalizedString("Loading_Location", comment: "加载中..."))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            ProgressView()
                                .scaleEffect(0.5)
                        }
                    } else {
                        Text(NSLocalizedString("Assets_Unknown_Location", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }

        private func formatPrice(_ price: Double) -> String {
            let billion = 1_000_000_000.0
            let million = 1_000_000.0

            let numberFormatter = NumberFormatter()
            numberFormatter.numberStyle = .decimal
            numberFormatter.maximumFractionDigits = 2
            numberFormatter.minimumFractionDigits = 2

            let formattedFullPrice =
                numberFormatter.string(from: NSNumber(value: price))
                ?? String(format: "%.2f", price)

            if price >= billion {
                let value = price / billion
                return String(format: "%.2fB (%@ ISK)", value, formattedFullPrice)
            } else if price >= million {
                let value = price / million
                return String(format: "%.2fM (%@ ISK)", value, formattedFullPrice)
            } else {
                return "\(formattedFullPrice) ISK"
            }
        }
    }
}
