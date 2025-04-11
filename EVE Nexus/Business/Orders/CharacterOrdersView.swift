import SwiftUI

// 订单物品信息模型
struct OrderItemInfo {
    let name: String
    let iconFileName: String
}

// 位置信息模型
typealias OrderLocationInfo = LocationInfoDetail

@MainActor
final class CharacterOrdersViewModel: ObservableObject {
    @Published private(set) var orders: [CharacterMarketOrder] = []
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var showError = false
    @Published private(set) var itemInfoCache: [Int64: OrderItemInfo] = [:]
    @Published private(set) var locationInfoCache: [Int64: OrderLocationInfo] = [:]
    @Published var showBuyOrders = false
    @Published private(set) var isDataReady = false

    // 添加一个标志，表示是否已经开始加载数据
    private var hasStartedLoading = false

    private let characterId: Int64
    private let databaseManager: DatabaseManager
    private var loadingTask: Task<Void, Never>?

    var filteredOrders: [CharacterMarketOrder] {
        orders
            .filter { $0.isBuyOrder ?? false == showBuyOrders }
            .sorted { $0.orderId > $1.orderId }
    }

    init(characterId: Int64, databaseManager: DatabaseManager) {
        self.characterId = characterId
        self.databaseManager = databaseManager
    }

    deinit {
        loadingTask?.cancel()
    }

    // 添加一个预加载方法，在初始化后立即调用
    func preloadOrders() {
        if !hasStartedLoading {
            hasStartedLoading = true
            Task {
                await loadOrders()
            }
        }
    }

    // 初始化订单显示类型
    private func initializeOrderType() {
        let sellOrdersCount = orders.filter { !($0.isBuyOrder ?? false) }.count
        let buyOrdersCount = orders.filter { $0.isBuyOrder ?? false }.count

        if sellOrdersCount > 0 {
            showBuyOrders = false
        } else if buyOrdersCount > 0 {
            showBuyOrders = true
        }
    }

    func loadOrders(forceRefresh: Bool = false) async {
        // 取消之前的加载任务
        loadingTask?.cancel()

        // 创建新的加载任务
        loadingTask = Task {
            isLoading = true
            errorMessage = nil
            showError = false
            isDataReady = false

            do {
                if let jsonString = try await CharacterMarketAPI.shared.getMarketOrders(
                    characterId: characterId,
                    forceRefresh: forceRefresh
                ) {
                    if Task.isCancelled { return }

                    // 解析JSON数据
                    let jsonData = jsonString.data(using: .utf8)!
                    let decoder = JSONDecoder()
                    orders = try decoder.decode([CharacterMarketOrder].self, from: jsonData)

                    if Task.isCancelled { return }

                    // 同步加载所有信息
                    await loadAllInformation()

                    if Task.isCancelled { return }

                    // 初始化订单显示类型
                    initializeOrderType()

                } else {
                    orders = []
                }

                await MainActor.run {
                    self.isDataReady = true
                    self.isLoading = false
                }

            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        self.errorMessage = error.localizedDescription
                        self.showError = true
                        self.orders = []
                        self.isDataReady = true
                        self.isLoading = false
                    }
                }
            }
        }

        // 等待任务完成
        await loadingTask?.value
    }

    private func loadAllInformation() async {
        // 1. 加载所有物品信息
        let typeIds = Set(orders.map { $0.typeId })
        if !typeIds.isEmpty {
            let query = """
                    SELECT type_id, name, icon_filename
                    FROM types
                    WHERE type_id IN (\(typeIds.sorted().map { String($0) }.joined(separator: ",")))
                """

            if case let .success(rows) = databaseManager.executeQuery(query) {
                for row in rows {
                    if let typeIdInt = (row["type_id"] as? NSNumber)?.int64Value,
                        let name = row["name"] as? String,
                        let iconFileName = row["icon_filename"] as? String
                    {
                        itemInfoCache[typeIdInt] = OrderItemInfo(
                            name: name,
                            iconFileName: iconFileName
                        )
                    }
                }
            }
        }

        // 2. 使用 LocationInfoLoader 加载位置信息
        let locationIds = Set(orders.map { $0.locationId })
        let locationLoader = LocationInfoLoader(
            databaseManager: databaseManager, characterId: characterId
        )
        locationInfoCache = await locationLoader.loadLocationInfo(locationIds: locationIds)

        Logger.debug("加载的物品信息数量: \(itemInfoCache.count)")
        Logger.debug("加载的位置信息数量: \(locationInfoCache.count)")
    }
}

struct CharacterOrdersView: View {
    let characterId: Int64
    @StateObject private var viewModel: CharacterOrdersViewModel

    init(characterId: Int64, databaseManager: DatabaseManager = DatabaseManager()) {
        self.characterId = characterId
        let vm = CharacterOrdersViewModel(
            characterId: characterId,
            databaseManager: databaseManager
        )
        _viewModel = StateObject(wrappedValue: vm)

        // 在初始化时预加载数据
        vm.preloadOrders()
    }

    var body: some View {
        VStack(spacing: 0) {
            // 买卖单切换按钮
            TabView(selection: $viewModel.showBuyOrders) {
                OrderListView(
                    orders: viewModel.filteredOrders.filter { !($0.isBuyOrder ?? false) },
                    itemInfoCache: viewModel.itemInfoCache,
                    locationInfoCache: viewModel.locationInfoCache,
                    isLoading: viewModel.isLoading,
                    isDataReady: viewModel.isDataReady
                )
                .tag(false)

                OrderListView(
                    orders: viewModel.filteredOrders.filter { $0.isBuyOrder ?? false },
                    itemInfoCache: viewModel.itemInfoCache,
                    locationInfoCache: viewModel.locationInfoCache,
                    isLoading: viewModel.isLoading,
                    isDataReady: viewModel.isDataReady
                )
                .tag(true)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    Picker("Order Type", selection: $viewModel.showBuyOrders) {
                        Text(
                            "\(NSLocalizedString("Orders_Sell", comment: "")) (\(viewModel.orders.filter { !($0.isBuyOrder ?? false) }.count))"
                        ).tag(false)
                        Text(
                            "\(NSLocalizedString("Orders_Buy", comment: "")) (\(viewModel.orders.filter { $0.isBuyOrder ?? false }.count))"
                        ).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                }
                .background(Color(.systemGroupedBackground))
            }
        }
        .refreshable {
            // 确保强制刷新功能正常工作
            await viewModel.loadOrders(forceRefresh: true)
        }
        .alert(NSLocalizedString("Error", comment: ""), isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
        .navigationTitle(NSLocalizedString("Main_Market_Orders", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
    }

    // 订单列表视图
    private struct OrderListView: View {
        let orders: [CharacterMarketOrder]
        let itemInfoCache: [Int64: OrderItemInfo]
        let locationInfoCache: [Int64: OrderLocationInfo]
        let isLoading: Bool
        let isDataReady: Bool

        var body: some View {
            List {
                if isLoading || !isDataReady {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding()
                            Spacer()
                        }
                    }
                    .listSectionSpacing(.compact)
                } else if orders.isEmpty {
                    Section {
                        HStack {
                            Spacer()
                            VStack(spacing: 4) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 30))
                                    .foregroundColor(.gray)
                                Text(NSLocalizedString("Orders_No_Data", comment: ""))
                                    .foregroundColor(.gray)
                            }
                            .padding()
                            Spacer()
                        }
                    }
                    .listSectionSpacing(.compact)
                } else {
                    Section {
                        ForEach(orders) { order in
                            OrderRow(
                                order: order,
                                itemInfo: itemInfoCache[order.typeId],
                                locationInfo: locationInfoCache[order.locationId]
                            )
                            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                        }
                    }
                    .listSectionSpacing(.compact)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.visible)
        }
    }

    // 将订单行提取为单独的视图组件
    private struct OrderRow: View {
        let order: CharacterMarketOrder
        let itemInfo: OrderItemInfo?
        let locationInfo: OrderLocationInfo?
        @StateObject private var databaseManager = DatabaseManager()

        private func calculateRemainingTime() -> String {
            guard let issuedDate = dateFormatter.date(from: order.issued) else {
                return ""
            }

            let expirationDate = issuedDate.addingTimeInterval(
                TimeInterval(order.duration * 24 * 3600))
            let remainingTime = expirationDate.timeIntervalSinceNow

            if remainingTime <= 0 {
                return NSLocalizedString("Orders_Expired", comment: "")
            }

            let days = Int(remainingTime) / (24 * 3600)
            let hours = (Int(remainingTime) % (24 * 3600)) / 3600
            let minutes = (Int(remainingTime) % 3600) / 60

            if days > 0 {
                if hours > 0 {
                    return String(
                        format: NSLocalizedString("Orders_Remaining_Days_Hours", comment: ""), days,
                        hours
                    )
                } else {
                    return String(
                        format: NSLocalizedString("Orders_Remaining_Days", comment: ""), days
                    )
                }
            } else if hours > 0 {
                if minutes > 0 {
                    return String(
                        format: NSLocalizedString("Orders_Remaining_Hours_Minutes", comment: ""),
                        hours, minutes
                    )
                } else {
                    return String(
                        format: NSLocalizedString("Orders_Remaining_Hours", comment: ""), hours
                    )
                }
            } else {
                return String(
                    format: NSLocalizedString("Orders_Remaining_Minutes", comment: ""), minutes
                )
            }
        }

        private let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
            formatter.timeZone = TimeZone(identifier: "UTC")!
            formatter.locale = Locale(identifier: "en_US_POSIX")
            return formatter
        }()

        private let displayDateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(identifier: "UTC")!
            formatter.locale = Locale(identifier: "en_US_POSIX")
            return formatter
        }()

        private let timeFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            formatter.timeZone = TimeZone(identifier: "UTC")!
            formatter.locale = Locale(identifier: "en_US_POSIX")
            return formatter
        }()

        var body: some View {
            NavigationLink(
                destination: MarketItemDetailView(
                    databaseManager: databaseManager, itemID: Int(order.typeId)
                )
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    // 订单标题行
                    HStack(spacing: 12) {
                        // 物品图标
                        if let itemInfo = itemInfo {
                            IconManager.shared.loadImage(for: itemInfo.iconFileName)
                                .resizable()
                                .frame(width: 36, height: 36)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        } else {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 36, height: 36)
                        }

                        VStack(alignment: .leading) {
                            HStack {
                                Text(itemInfo?.name ?? "Unknown Item")
                                    .font(.headline)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(order.volumeRemain)/\(order.volumeTotal)")
                                    .font(.caption)
                            }
                            Text(FormatUtil.format(order.price) + " ISK")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(order.isBuyOrder ?? false ? .red : .green)
                        }
                    }

                    // 订单详细信息
                    VStack(alignment: .leading, spacing: 4) {
                        // 位置信息
                        if let locationInfo = locationInfo {
                            LocationInfoView(
                                stationName: locationInfo.stationName,
                                solarSystemName: locationInfo.solarSystemName,
                                security: locationInfo.security
                            )
                            .lineLimit(1)
                        } else {
                            LocationInfoView(
                                stationName: nil,
                                solarSystemName: nil,
                                security: nil
                            )
                            .lineLimit(1)
                        }

                        // 时间信息
                        HStack {
                            if let date = dateFormatter.date(from: order.issued) {
                                Text(
                                    "\(displayDateFormatter.string(from: date)) \(timeFormatter.string(from: date)) (UTC+0)"
                                )
                                .font(.caption)
                                .foregroundColor(.gray)
                                .lineLimit(1)
                            }
                            Spacer()
                            Text(calculateRemainingTime())
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}
