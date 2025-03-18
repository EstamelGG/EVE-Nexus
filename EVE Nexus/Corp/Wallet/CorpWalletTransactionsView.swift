import SwiftUI

// 军团交易记录条目模型
struct CorpWalletTransactionEntry: Codable, Identifiable {
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
struct CorpWalletTransactionGroup: Identifiable {
    let id = UUID()
    let date: Date
    var entries: [CorpWalletTransactionEntry]
}

@MainActor
final class CorpWalletTransactionsViewModel: ObservableObject {
    @Published private(set) var transactionGroups: [CorpWalletTransactionGroup] = []
    @Published var isLoading = true
    @Published var errorMessage: String?
    private var initialLoadDone = false

    private let characterId: Int
    private let division: Int
    let databaseManager: DatabaseManager
    var itemInfoCache: [Int: TransactionItemInfo] = [:]
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

    init(characterId: Int, division: Int, databaseManager: DatabaseManager) {
        self.characterId = characterId
        self.division = division
        self.databaseManager = databaseManager

        // 在初始化时立即开始加载数据
        loadingTask = Task {
            await loadTransactionData()
        }
    }

    deinit {
        loadingTask?.cancel()
    }

    // 批量加载所有物品信息
    private func loadAllItemInfo(for typeIds: [Int]) {
        // 如果没有需要加载的物品，直接返回
        if typeIds.isEmpty {
            return
        }

        // 构建查询参数
        let placeholders = Array(repeating: "?", count: typeIds.count).joined(separator: ",")
        let query =
            "SELECT type_id, name, icon_filename FROM types WHERE type_id IN (\(placeholders))"

        // 执行批量查询
        let result = databaseManager.executeQuery(
            query, parameters: typeIds.map { $0 as Any }
        )

        if case let .success(rows) = result {
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                    let name = row["name"] as? String,
                    let iconFileName = row["icon_filename"] as? String
                {
                    // 更新缓存
                    itemInfoCache[typeId] = TransactionItemInfo(
                        name: name, iconFileName: iconFileName)
                }
            }
        }

        // 为未找到的物品ID设置默认值
        for typeId in typeIds {
            if itemInfoCache[typeId] == nil {
                Logger.warning("未能加载物品信息: \(typeId)")
                itemInfoCache[typeId] = TransactionItemInfo(
                    name: "Unknown Item", iconFileName: DatabaseConfig.defaultItemIcon
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
                    let jsonString = try await CorpWalletAPI.shared.getCorpWalletTransactions(
                        characterId: characterId, division: division, forceRefresh: forceRefresh
                    )
                else {
                    throw NetworkError.invalidResponse
                }

                if Task.isCancelled { return }

                guard let jsonData = jsonString.data(using: .utf8),
                    let entries = try? JSONDecoder().decode(
                        [CorpWalletTransactionEntry].self, from: jsonData
                    )
                else {
                    throw NetworkError.invalidResponse
                }

                if Task.isCancelled { return }

                // 收集所有位置ID
                let locationIds = Set(entries.map { $0.location_id })

                // 收集所有物品ID并一次性加载所有物品信息
                let typeIds = Array(Set(entries.map { $0.type_id }))
                loadAllItemInfo(for: typeIds)

                // 使用 LocationInfoLoader 加载位置信息
                let locationLoader = LocationInfoLoader(
                    databaseManager: databaseManager, characterId: Int64(characterId)
                )
                locationInfoCache = await locationLoader.loadLocationInfo(locationIds: locationIds)

                if Task.isCancelled { return }

                var groupedEntries: [Date: [CorpWalletTransactionEntry]] = [:]
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

                let groups = groupedEntries.map { date, entries -> CorpWalletTransactionGroup in
                    CorpWalletTransactionGroup(
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
                Logger.error("加载军团交易记录失败: \(error.localizedDescription)")
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
}

// 特定日期的交易记录详情视图
struct CorpWalletTransactionDayDetailView: View {
    let group: CorpWalletTransactionGroup
    let viewModel: CorpWalletTransactionsViewModel
    @State private var displayedEntries: [CorpWalletTransactionEntry] = []
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
                CorpWalletTransactionEntryRow(entry: entry, viewModel: viewModel)
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

struct CorpWalletTransactionsView: View {
    @ObservedObject var viewModel: CorpWalletTransactionsViewModel

    private let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")!
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    var body: some View {
        List {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if viewModel.transactionGroups.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
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
                Section(
                    header: Text(NSLocalizedString("Transaction Dates", comment: ""))
                        .fontWeight(.bold)
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                        .textCase(.none)
                ) {
                    ForEach(viewModel.transactionGroups) { group in
                        NavigationLink(
                            destination: CorpWalletTransactionDayDetailView(
                                group: group, viewModel: viewModel)
                        ) {
                            HStack {
                                Text(displayDateFormatter.string(from: group.date))
                                    .font(.system(size: 16))

                                Spacer()

                                // 显示买入和卖出数量
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
        .navigationTitle(NSLocalizedString("Main_Market_Transactions", comment: ""))
    }
}

struct CorpWalletTransactionEntryRow: View {
    let entry: CorpWalletTransactionEntry
    let viewModel: CorpWalletTransactionsViewModel
    @State private var itemIcon: Image?

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

                    VStack(alignment: .leading, spacing: 2) {
                        Text(
                            viewModel.itemInfoCache[entry.type_id]?.name
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
                // 位置信息
                if let locationView = viewModel.getLocationView(for: entry.location_id) {
                    locationView
                        .lineLimit(1)
                }

                // 时间信息
                VStack(alignment: .trailing, spacing: 4) {
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
            // 直接从缓存中获取物品信息并加载图标
            if let itemInfo = viewModel.itemInfoCache[entry.type_id] {
                itemIcon = IconManager.shared.loadImage(for: itemInfo.iconFileName)
            }
        }
    }
}
