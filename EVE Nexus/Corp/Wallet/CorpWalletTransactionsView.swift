import SwiftUI

// 添加WalletTab枚举
enum WalletTab {
    case journal
    case transactions
}

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

// 合并后的军团交易记录条目
struct CorpMergedTransactionEntry: Identifiable {
    let id = UUID()
    let type_id: Int
    let is_buy: Bool
    let location_id: Int64
    let date: String
    let totalQuantity: Int
    let averagePrice: Double
    let totalAmount: Double
    let originalEntries: [CorpWalletTransactionEntry]
    
    init(entries: [CorpWalletTransactionEntry]) {
        guard let firstEntry = entries.first else {
            fatalError("Cannot create merged entry from empty array")
        }
        
        // 按transaction_id排序，最新的在前
        let sortedEntries = entries.sorted { $0.transaction_id > $1.transaction_id }
        
        self.type_id = firstEntry.type_id
        self.is_buy = firstEntry.is_buy
        self.location_id = firstEntry.location_id
        self.date = sortedEntries.first!.date // 使用最新的日期
        self.totalQuantity = entries.reduce(0) { $0 + $1.quantity }
        self.totalAmount = entries.reduce(0.0) { $0 + ($1.unit_price * Double($1.quantity)) }
        self.averagePrice = self.totalAmount / Double(self.totalQuantity)
        self.originalEntries = sortedEntries
    }
}

// 按日期分组的交易记录
struct CorpWalletTransactionGroup: Identifiable {
    let id = UUID()
    let date: Date
    var entries: [CorpWalletTransactionEntry]
    var mergedEntries: [CorpMergedTransactionEntry] = []
}

@MainActor
final class CorpWalletTransactionsViewModel: ObservableObject {
    @Published private(set) var transactionGroups: [CorpWalletTransactionGroup] = []
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var searchText = ""  // 添加搜索文本状态
    @Published var showSettings = false  // 添加设置显示状态
    @Published var mergeSimilarTransactions: Bool {
        didSet {
            UserDefaultsManager.shared.mergeSimilarTransactions = mergeSimilarTransactions
        }
    }
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
        self.mergeSimilarTransactions = UserDefaultsManager.shared.mergeSimilarTransactions

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

    // 合并相似交易记录
    private func mergeSimilarTransactions(_ entries: [CorpWalletTransactionEntry]) -> [CorpMergedTransactionEntry] {
        var mergedDict: [String: [CorpWalletTransactionEntry]] = [:]
        
        for entry in entries {
            // 创建唯一键：时间（精确到分钟）+ 物品ID + 买卖类型 + 地点ID
            let dateComponents = dateFormatter.date(from: entry.date) ?? Date()
            let calendar = Calendar.current
            let minuteComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: dateComponents)
            let minuteDate = calendar.date(from: minuteComponents) ?? dateComponents
            
            let minuteString = dateFormatter.string(from: minuteDate)
            let key = "\(minuteString)_\(entry.type_id)_\(entry.is_buy)_\(entry.location_id)"
            
            mergedDict[key, default: []].append(entry)
        }
        
        return mergedDict.values.map { CorpMergedTransactionEntry(entries: $0) }
            .sorted { 
                // 按原始交易记录中最大的transaction_id排序（最新的在前）
                let maxId1 = $0.originalEntries.map { $0.transaction_id }.max() ?? 0
                let maxId2 = $1.originalEntries.map { $0.transaction_id }.max() ?? 0
                return maxId1 > maxId2
            }
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
                    let sortedEntries = entries.sorted { $0.transaction_id > $1.transaction_id }
                    let mergedEntries = mergeSimilarTransactions(sortedEntries)
                    return CorpWalletTransactionGroup(
                        date: date,
                        entries: sortedEntries,
                        mergedEntries: mergedEntries
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

    // 修改过滤后的交易记录计算属性,返回按日期分组的过滤结果
    var filteredTransactionGroups: [CorpWalletTransactionGroup] {
        if searchText.isEmpty {
            return transactionGroups
        }

        return transactionGroups.map { group in
            if mergeSimilarTransactions {
                let filteredMergedEntries = group.mergedEntries.filter { entry in
                    if let itemInfo = itemInfoCache[entry.type_id] {
                        return itemInfo.enName.localizedCaseInsensitiveContains(searchText)
                            || itemInfo.zhName.localizedCaseInsensitiveContains(searchText)
                    }
                    return false
                }
                return CorpWalletTransactionGroup(
                    date: group.date,
                    entries: group.entries,
                    mergedEntries: filteredMergedEntries
                )
            } else {
                let filteredEntries = group.entries.filter { entry in
                    if let itemInfo = itemInfoCache[entry.type_id] {
                        return itemInfo.enName.localizedCaseInsensitiveContains(searchText)
                            || itemInfo.zhName.localizedCaseInsensitiveContains(searchText)
                    }
                    return false
                }
                return CorpWalletTransactionGroup(
                    date: group.date,
                    entries: filteredEntries,
                    mergedEntries: group.mergedEntries
                )
            }
        }.filter { mergeSimilarTransactions ? !$0.mergedEntries.isEmpty : !$0.entries.isEmpty }
    }
}

// 军团交易记录设置视图
struct CorpWalletTransactionSettingsView: View {
    @ObservedObject var viewModel: CorpWalletTransactionsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Toggle(isOn: $viewModel.mergeSimilarTransactions) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(NSLocalizedString("Wallet_Transaction_Merge_Similar", comment: ""))
                                .font(.body)
                            Text(NSLocalizedString("Wallet_Transaction_Merge_Similar_Description", comment: ""))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Wallet_Transaction_Settings", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Wallet_Transaction_Settings_Done", comment: "")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

// 特定日期的交易记录详情视图
struct CorpWalletTransactionDayDetailView: View {
    let group: CorpWalletTransactionGroup
    let viewModel: CorpWalletTransactionsViewModel

    private let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")!
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    var body: some View {
        List {
            if viewModel.mergeSimilarTransactions {
                ForEach(group.mergedEntries) { entry in
                    CorpMergedTransactionEntryRow(entry: entry, viewModel: viewModel)
                }
            } else {
                ForEach(group.entries) { entry in
                    CorpWalletTransactionEntryRow(entry: entry, viewModel: viewModel)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(displayDateFormatter.string(from: group.date))
    }
}

struct CorpWalletTransactionsView: View {
    @ObservedObject var viewModel: CorpWalletTransactionsViewModel
    @Binding var selectedTab: WalletTab

    private let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")!
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            // 搜索框
            if selectedTab == .transactions {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray.opacity(0.6))
                    TextField(
                        NSLocalizedString("Main_Database_Search", comment: ""),
                        text: $viewModel.searchText
                    )
                    .textFieldStyle(.plain)
                    .foregroundColor(.primary)
                    if !viewModel.searchText.isEmpty {
                        Button(action: {
                            viewModel.searchText = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray.opacity(0.6))
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(.systemGray5))
                .cornerRadius(10)
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

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
                        if viewModel.filteredTransactionGroups.isEmpty {
                            NoDataSection()
                        } else {
                            ForEach(viewModel.filteredTransactionGroups) { group in
                                NavigationLink(
                                    destination: CorpWalletTransactionDayDetailView(
                                        group: group,
                                        viewModel: viewModel
                                    )
                                ) {
                                    HStack {
                                        Text(displayDateFormatter.string(from: group.date))
                                            .font(.system(size: 16))

                                        Spacer()

                                        let (buyCount, sellCount) = if viewModel.mergeSimilarTransactions {
                                            (group.mergedEntries.filter { $0.is_buy }.count, group.mergedEntries.filter { !$0.is_buy }.count)
                                        } else {
                                            (group.entries.filter { $0.is_buy }.count, group.entries.filter { !$0.is_buy }.count)
                                        }
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
            }
            .listStyle(.insetGrouped)
            .refreshable {
                await viewModel.loadTransactionData(forceRefresh: true)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        viewModel.showSettings = true
                    }) {
                        Image(systemName: "gear")
                    }
                }
            }
        }
        .opacity(selectedTab == .transactions ? 1 : 0)  // 控制整个视图的显示/隐藏
        .sheet(isPresented: $viewModel.showSettings) {
            CorpWalletTransactionSettingsView(viewModel: viewModel)
        }
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

// 合并军团交易记录行视图
struct CorpMergedTransactionEntryRow: View {
    let entry: CorpMergedTransactionEntry
    let viewModel: CorpWalletTransactionsViewModel
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

                    VStack(alignment: .leading, spacing: 2) {
                        Text(
                            viewModel.itemInfoCache[entry.type_id]?.name
                                ?? NSLocalizedString(
                                    "Main_Market_Transactions_Loading", comment: ""
                                )
                        )
                        .font(.body)
                        Text("\(FormatUtil.format(entry.totalAmount)) ISK")
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
                            "\(entry.is_buy ? NSLocalizedString("Main_Market_Transactions_Buy", comment: "") : NSLocalizedString("Main_Market_Transactions_Sell", comment: "")) - \(entry.totalQuantity) × \(FormatUtil.format(entry.averagePrice)) ISK"
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
            // 加载图标
            if let itemInfo = viewModel.itemInfoCache[entry.type_id] {
                itemIcon = IconManager.shared.loadImage(for: itemInfo.iconFileName)
            }
        }
    }
}
