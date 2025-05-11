import SwiftUI

// 交易记录条目模型
struct WalletTransactionEntry: Codable, Identifiable {
    let client_id: Int
    let date: String
    let is_buy: Bool
    let is_personal: Bool
    let journal_ref_id: Int64
    let location_id: Int64
    let quantity: Int
    let transaction_id: Int64
    let type_id: Int
    let unit_price: Double

    var id: Int64 { transaction_id }
}

// 按日期分组的交易记录
struct WalletTransactionGroup: Identifiable {
    let id = UUID()
    let date: Date
    var entries: [WalletTransactionEntry]
}

// 交易记录物品信息模型
struct TransactionItemInfo {
    let name: String
    let enName: String
    let zhName: String
    let iconFileName: String
}

@MainActor
final class WalletTransactionsViewModel: ObservableObject {
    @Published private(set) var transactionGroups: [WalletTransactionGroup] = []
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var searchText = ""  // 添加搜索文本状态
    private var initialLoadDone = false

    private let characterId: Int
    let databaseManager: DatabaseManager
    private var itemInfoCache: [Int: TransactionItemInfo] = [:]
    private var locationInfoCache: [Int64: LocationInfoDetail] = [:]
    private var loadingTask: Task<Void, Never>?

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")!
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    init(characterId: Int, databaseManager: DatabaseManager) {
        self.characterId = characterId
        self.databaseManager = databaseManager

        // 在初始化时立即开始加载数据
        loadingTask = Task {
            await loadTransactionData()
        }
    }

    deinit {
        loadingTask?.cancel()
    }

    func getItemInfo(for typeId: Int) -> TransactionItemInfo {
        // 先检查缓存
        if let cachedInfo = itemInfoCache[typeId] {
            return cachedInfo
        }

        // 如果缓存中没有，返回默认值（这种情况应该很少发生，因为我们已经预加载了所有物品信息）
        Logger.warning("物品信息未在缓存中找到: \(typeId)")
        return TransactionItemInfo(
            name: "Unknown Item",
            enName: "Unknown Item",
            zhName: "未知物品",
            iconFileName: DatabaseConfig.defaultItemIcon
        )
    }

    // 一次性加载所有物品信息
    private func loadAllItemInfo(from entries: [WalletTransactionEntry]) {
        let typeIds = Set(entries.map { $0.type_id })
        if typeIds.isEmpty { return }

        let placeholders = Array(repeating: "?", count: typeIds.count).joined(separator: ",")
        let query =
            "SELECT type_id, name, en_name, zh_name, icon_filename FROM types WHERE type_id IN (\(placeholders))"

        let result = databaseManager.executeQuery(query, parameters: typeIds.map { $0 as Any })

        if case let .success(rows) = result {
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                    let name = row["name"] as? String,
                    let enName = row["en_name"] as? String,
                    let zhName = row["zh_name"] as? String,
                    let iconFileName = row["icon_filename"] as? String
                {
                    itemInfoCache[typeId] = TransactionItemInfo(
                        name: name,
                        enName: enName,
                        zhName: zhName,
                        iconFileName: iconFileName
                    )
                }
            }
        }

        // 为未找到的物品设置默认值
        for typeId in typeIds {
            if itemInfoCache[typeId] == nil {
                itemInfoCache[typeId] = TransactionItemInfo(
                    name: "Unknown Item",
                    enName: "Unknown Item",
                    zhName: "未知物品",
                    iconFileName: DatabaseConfig.defaultItemIcon
                )
            }
        }
    }

    func getLocationView(for locationId: Int64) -> LocationInfoView? {
        // 如果缓存中已有，直接返回
        if let info = locationInfoCache[locationId] {
            return LocationInfoView(
                stationName: info.stationName,
                solarSystemName: info.solarSystemName,
                security: info.security,
                font: .caption,
                textColor: .secondary
            )
        }
        return nil
    }

    func loadTransactionData(forceRefresh: Bool = false) async {
        // 如果已经加载过且不是强制刷新，则跳过
        if initialLoadDone && !forceRefresh {
            return
        }

        // 取消之前的加载任务
        loadingTask?.cancel()

        // 创建新的加载任务
        loadingTask = Task {
            isLoading = true
            errorMessage = nil

            do {
                guard
                    let jsonString = try await CharacterWalletAPI.shared.getWalletTransactions(
                        characterId: characterId, forceRefresh: forceRefresh
                    )
                else {
                    throw NetworkError.invalidResponse
                }

                if Task.isCancelled { return }

                guard let jsonData = jsonString.data(using: .utf8),
                    let entries = try? JSONDecoder().decode(
                        [WalletTransactionEntry].self, from: jsonData
                    )
                else {
                    throw NetworkError.invalidResponse
                }

                if Task.isCancelled { return }

                // 收集所有位置ID
                let locationIds = Set(entries.map { $0.location_id })

                // 使用 LocationInfoLoader 加载位置信息
                let locationLoader = LocationInfoLoader(
                    databaseManager: databaseManager, characterId: Int64(characterId)
                )
                locationInfoCache = await locationLoader.loadLocationInfo(locationIds: locationIds)

                if Task.isCancelled { return }

                // 一次性加载所有物品信息
                loadAllItemInfo(from: entries)

                if Task.isCancelled { return }

                var groupedEntries: [Date: [WalletTransactionEntry]] = [:]
                for entry in entries {
                    guard let date = dateFormatter.date(from: entry.date) else {
                        Logger.error("Failed to parse date: \(entry.date)")
                        continue
                    }

                    let components = calendar.dateComponents([.year, .month, .day], from: date)
                    guard let dayDate = calendar.date(from: components) else {
                        Logger.error("Failed to create date from components for: \(entry.date)")
                        continue
                    }

                    groupedEntries[dayDate, default: []].append(entry)
                }

                if Task.isCancelled { return }

                let groups = groupedEntries.map { date, entries -> WalletTransactionGroup in
                    WalletTransactionGroup(
                        date: date,
                        entries: entries.sorted { $0.transaction_id > $1.transaction_id }
                    )
                }.sorted { $0.date > $1.date }

                await MainActor.run {
                    self.transactionGroups = groups
                    self.isLoading = false
                    self.initialLoadDone = true
                }

            } catch {
                Logger.error("加载交易记录失败: \(error.localizedDescription)")
                if !Task.isCancelled {
                    await MainActor.run {
                        self.errorMessage = error.localizedDescription
                        self.isLoading = false
                    }
                }
            }
        }

        // 等待任务完成
        await loadingTask?.value
    }

    // 添加过滤后的交易记录计算属性
    var filteredTransactionGroups: [WalletTransactionGroup] {
        if searchText.isEmpty {
            return transactionGroups
        }

        return transactionGroups.map { group in
            let filteredEntries = group.entries.filter { entry in
                let itemInfo = getItemInfo(for: entry.type_id)
                return itemInfo.enName.localizedCaseInsensitiveContains(searchText)
                    || itemInfo.zhName.localizedCaseInsensitiveContains(searchText)
            }
            return WalletTransactionGroup(date: group.date, entries: filteredEntries)
        }.filter { !$0.entries.isEmpty }
    }
}

// 特定日期的交易记录详情视图
struct WalletTransactionDayDetailView: View {
    let group: WalletTransactionGroup
    let viewModel: WalletTransactionsViewModel
    @State private var displayedEntries: [WalletTransactionEntry] = []
    @State private var showingCount = 100

    private let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")!
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    var body: some View {
        List {
            ForEach(displayedEntries) { entry in
                WalletTransactionEntryRow(entry: entry, viewModel: viewModel)
            }

            if showingCount < group.entries.count {
                Button(action: {
                    loadMoreEntries()
                }) {
                    HStack {
                        Spacer()
                        Text(NSLocalizedString("Load More", comment: ""))
                            .foregroundColor(.blue)
                        Spacer()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(displayDateFormatter.string(from: group.date))
        .onAppear {
            // 初始加载前100条
            loadMoreEntries()
        }
    }

    private func loadMoreEntries() {
        let nextBatch = min(showingCount + 100, group.entries.count)
        displayedEntries = Array(group.entries.prefix(nextBatch))
        showingCount = nextBatch
    }
}

struct WalletTransactionsView: View {
    @StateObject private var viewModel: WalletTransactionsViewModel

    private let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")!
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    init(characterId: Int, databaseManager: DatabaseManager) {
        _viewModel = StateObject(
            wrappedValue: WalletTransactionsViewModel(
                characterId: characterId, databaseManager: databaseManager
            ))
    }

    var body: some View {
        VStack(spacing: 0) {
            TransactionListView(
                viewModel: viewModel,
                displayDateFormatter: displayDateFormatter
            )
        }
        .navigationTitle(NSLocalizedString("Main_Market_Transactions", comment: ""))
        .searchable(
            text: $viewModel.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text(NSLocalizedString("Main_Database_Search", comment: ""))
        )
        .navigationBarTitleDisplayMode(.inline)
    }
}

// 交易记录列表视图
private struct TransactionListView: View {
    @ObservedObject var viewModel: WalletTransactionsViewModel
    let displayDateFormatter: DateFormatter

    var body: some View {
        List {
            if viewModel.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(.circular)
                    Spacer()
                }
            } else if viewModel.transactionGroups.isEmpty {
                Section {
                    NoDataSection()
                }
            } else {
                Section {
                    ForEach(viewModel.filteredTransactionGroups) { group in
                        NavigationLink(
                            destination: WalletTransactionDayDetailView(
                                group: group, viewModel: viewModel)
                        ) {
                            HStack {
                                Text(displayDateFormatter.string(from: group.date))
                                    .font(.system(size: 16))

                                Spacer()

                                let buyCount = group.entries.filter { $0.is_buy }.count
                                let sellCount = group.entries.filter { !$0.is_buy }.count
                                Text(
                                    "\(NSLocalizedString("Main_Market_Transactions_Buy", comment: "")): \(buyCount), \(NSLocalizedString("Main_Market_Transactions_Sell", comment: "")): \(sellCount)"
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await viewModel.loadTransactionData(forceRefresh: true)
        }
    }
}

struct WalletTransactionEntryRow: View {
    let entry: WalletTransactionEntry
    let viewModel: WalletTransactionsViewModel
    @State private var itemInfo: TransactionItemInfo?
    @State private var itemIcon: Image?

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
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
        NavigationLink {
            MarketItemDetailView(databaseManager: viewModel.databaseManager, itemID: entry.type_id)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                // 物品信息行
                HStack(spacing: 12) {
                    // 物品图标
                    if let icon = itemIcon {
                        icon
                            .resizable()
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 36, height: 36)
                    }

                    VStack(alignment: .leading) {
                        Text(
                            itemInfo?.name
                                ?? NSLocalizedString(
                                    "Main_Market_Transactions_Loading", comment: ""
                                )
                        )
                        .font(.body)
                        Text("\(FormatUtil.format(entry.unit_price * Double(entry.quantity))) ISK")
                            .foregroundColor(entry.is_buy ? .red : .green)
                            .font(.system(.caption, design: .monospaced))
                    }
                }

                // 交易地点
                if let locationView = viewModel.getLocationView(for: entry.location_id) {
                    locationView
                        .lineLimit(1)
                }

                // 交易详细信息
                VStack(alignment: .leading, spacing: 4) {
                    // 交易时间
                    HStack {
                        // 交易类型和数量
                        Text(
                            "\(entry.is_buy ? NSLocalizedString("Main_Market_Transactions_Buy", comment: "") : NSLocalizedString("Main_Market_Transactions_Sell", comment: "")) - \(entry.quantity) × \(FormatUtil.format(entry.unit_price)) ISK"
                        )
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                        Spacer()
                        if let date = dateFormatter.date(from: entry.date) {
                            Text(
                                "\(timeFormatter.string(from: date))"
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .task {
            // 加载物品信息
            itemInfo = viewModel.getItemInfo(for: entry.type_id)
            // 加载图标
            if let itemInfo = itemInfo {
                itemIcon = IconManager.shared.loadImage(for: itemInfo.iconFileName)
            }
        }
    }
}
