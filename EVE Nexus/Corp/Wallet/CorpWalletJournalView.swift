import SwiftUI

// 军团钱包流水条目模型
struct CorpWalletJournalEntry: Codable, Identifiable {
    let id: Int64
    let amount: Double
    let balance: Double
    let date: String
    let description: String
    let first_party_id: Int
    let reason: String
    let ref_type: String
    let second_party_id: Int
    let context_id: Int64?
    let context_id_type: String?
}

// 按日期分组的钱包流水
struct CorpWalletJournalGroup: Identifiable {
    let id = UUID()
    let date: Date
    var entries: [CorpWalletJournalEntry]
}

// 加载进度枚举
public enum WalletLoadingProgress {
    case loading(page: Int) // 正在加载特定页面
    case completed // 加载完成
}

@MainActor
final class CorpWalletJournalViewModel: ObservableObject {
    @AppStorage("selectedLanguage") private var selectedLanguage: String?
    @Published private(set) var journalGroups: [CorpWalletJournalGroup] = []
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published private(set) var totalIncome: Double = 0.0
    @Published private(set) var totalExpense: Double = 0.0
    @Published var loadingProgress: WalletLoadingProgress?
    @Published var timeRange: TimeRange = .last30Days
    @Published var showFilter = false
    @Published var selectedRefType: String? = nil
    @Published var selectedTransactionType: TransactionType? = nil
    private var initialLoadDone = false
    @Published private(set) var totalEntries: Int = 0
    @Published private(set) var isPartialData: Bool = false

    enum TransactionType {
        case income
        case expense
    }

    var filteredJournalGroups: [CorpWalletJournalGroup] {
        return journalGroups.map { group in
            let filteredEntries = group.entries.filter { entry in
                // 首先检查交易类型（收入/支出）
                if let transactionType = selectedTransactionType {
                    switch transactionType {
                    case .income:
                        if entry.amount <= 0 { return false }
                    case .expense:
                        if entry.amount >= 0 { return false }
                    }
                }

                // 然后检查 ref_type
                if let selectedType = selectedRefType {
                    if entry.ref_type != selectedType { return false }
                }

                return true
            }
            return CorpWalletJournalGroup(date: group.date, entries: filteredEntries)
        }.filter { !$0.entries.isEmpty }
    }

    // 获取所有可用的交易类型
    var availableRefTypes: [String] {
        let allRefTypes = Set(journalGroups.flatMap { $0.entries }.map { $0.ref_type })
        return Array(allRefTypes).sorted()
    }

    // 获取交易类型的本地化名称
    func getLocalizedRefType(_ refType: String) -> String {
        return LocalizationManager.shared.processEntryTypeName(
            for: refType.lowercased(),
            esiText: refType,
            language: selectedLanguage == "zh-Hans" ? "zh" : "en"
        )
    }

    enum TimeRange: String, CaseIterable {
        case last30Days
        case last7Days
        case last1Day

        var localizedString: String {
            switch self {
            case .last30Days:
                return String(format: NSLocalizedString("Time_Days_Long", comment: ""), 30)
            case .last7Days:
                return String(format: NSLocalizedString("Time_Days_Long", comment: ""), 7)
            case .last1Day:
                return String(format: NSLocalizedString("Time_Days_Long", comment: ""), 1)
            }
        }
    }

    private let characterId: Int
    private let division: Int
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
        calendar.timeZone = TimeZone.current // 使用本地时区
        return calendar
    }()

    init(characterId: Int, division: Int) {
        self.characterId = characterId
        self.division = division
        // 不在这里自动加载，由视图的 .task 或显式调用 loadJournalData() 来控制加载时机
    }

    deinit {
        loadingTask?.cancel()
    }

    // 计算总收支
    private func calculateTotals(from entries: [CorpWalletJournalEntry]) {
        var income: Double = 0
        var expense: Double = 0

        let calendar = Calendar.current
        let now = Date()
        let startDate: Date

        switch timeRange {
        case .last30Days:
            startDate = calendar.date(byAdding: .day, value: -30, to: now)!
        case .last7Days:
            startDate = calendar.date(byAdding: .day, value: -7, to: now)!
        case .last1Day:
            startDate = calendar.date(byAdding: .day, value: -1, to: now)!
        }

        for entry in entries {
            guard let entryDate = FormatUtil.parseUTCDate(entry.date),
                  entryDate >= startDate
            else {
                continue
            }

            if entry.amount > 0 {
                income += entry.amount
            } else {
                expense += abs(entry.amount)
            }
        }

        totalIncome = income
        totalExpense = expense
    }

    // 只更新总收支
    func updateTotals() {
        let allEntries = journalGroups.flatMap { $0.entries }
        calculateTotals(from: allEntries)
    }

    func loadJournalData(forceRefresh: Bool = false) async {
        // 如果已经加载过且不是强制刷新，则跳过
        if initialLoadDone, !forceRefresh {
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
                    let jsonString = try await CorpWalletAPI.shared.getCorpWalletJournal(
                        characterId: characterId,
                        division: division,
                        forceRefresh: forceRefresh,
                        progressCallback: { progress in
                            Task { @MainActor in
                                self.loadingProgress = progress
                            }
                        }
                    )
                else {
                    throw NetworkError.invalidResponse
                }

                if Task.isCancelled { return }

                guard let jsonData = jsonString.data(using: .utf8),
                      let entries = try? JSONDecoder().decode(
                          [CorpWalletJournalEntry].self, from: jsonData
                      )
                else {
                    throw NetworkError.invalidResponse
                }

                if Task.isCancelled { return }

                // 检查数据量
                totalEntries = entries.count

                // 检查是否只显示部分数据
                if totalEntries >= 9500 {
                    // 获取最久远的记录日期
                    if let oldestEntry = entries.min(by: { $0.date < $1.date }),
                       let oldestDate = dateFormatter.date(from: oldestEntry.date)
                    {
                        let calendar = Calendar.current
                        let now = Date()
                        let days =
                            calendar.dateComponents([.day], from: oldestDate, to: now).day ?? 0
                        isPartialData = days < 30
                    }
                }

                // 计算总收支
                calculateTotals(from: entries)

                // 按日期分组
                var groupedEntries: [Date: [CorpWalletJournalEntry]] = [:]
                for entry in entries {
                    guard let date = FormatUtil.parseUTCDate(entry.date) else {
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

                let groups = groupedEntries.map { date, entries -> CorpWalletJournalGroup in
                    CorpWalletJournalGroup(date: date, entries: entries.sorted { $0.id > $1.id })
                }.sorted { $0.date > $1.date }

                await MainActor.run {
                    self.journalGroups = groups
                    self.isLoading = false
                    self.loadingProgress = .completed
                    self.initialLoadDone = true
                }
                if !Task.isCancelled {
                    await MainActor.run {
                        self.loadingProgress = nil
                    }
                }

            } catch {
                // 忽略取消错误，这是预期的行为
                if error is CancellationError {
                    return
                }

                Logger.error("加载军团钱包流水失败: \(error.localizedDescription)")
                if !Task.isCancelled {
                    await MainActor.run {
                        self.errorMessage = error.localizedDescription
                        self.isLoading = false
                        self.loadingProgress = nil
                    }
                }
            }
        }

        // 等待任务完成
        await loadingTask?.value
    }
}

// 特定日期的军团钱包流水详情视图
struct CorpWalletJournalDayDetailView: View {
    let group: CorpWalletJournalGroup
    @State private var displayedEntries: [CorpWalletJournalEntry] = []
    @State private var showingCount = 100

    // 使用FormatUtil进行日期处理，无需自定义格式化器

    var body: some View {
        List {
            ForEach(displayedEntries, id: \.id) { entry in
                CorpWalletJournalEntryRow(entry: entry)
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
        .navigationTitle(FormatUtil.formatDateToLocalDate(group.date))
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

struct CorpWalletJournalView: View {
    @ObservedObject var viewModel: CorpWalletJournalViewModel

    // 使用FormatUtil进行日期处理，无需自定义格式化器

    var filterView: some View {
        NavigationView {
            List {
                Section(header: Text(NSLocalizedString("Wallet_Transaction_Type", comment: ""))) {
                    Button(action: {
                        viewModel.selectedTransactionType = nil
                    }) {
                        HStack {
                            Text(NSLocalizedString("Misc_All", comment: ""))
                                .foregroundColor(.primary)
                            Spacer()
                            if viewModel.selectedTransactionType == nil {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }

                    Button(action: {
                        viewModel.selectedTransactionType = .income
                    }) {
                        HStack {
                            Text(WalletJournalViewModel.TransactionType.income.localizedString)
                                .foregroundColor(.primary)
                            Spacer()
                            if viewModel.selectedTransactionType == .income {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }

                    Button(action: {
                        viewModel.selectedTransactionType = .expense
                    }) {
                        HStack {
                            Text(WalletJournalViewModel.TransactionType.expense.localizedString)
                                .foregroundColor(.primary)
                            Spacer()
                            if viewModel.selectedTransactionType == .expense {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }

                Section(header: Text(NSLocalizedString("Wallet_Transaction_Category", comment: ""))) {
                    Button(action: {
                        viewModel.selectedRefType = nil
                    }) {
                        HStack {
                            Text(NSLocalizedString("Misc_All", comment: ""))
                                .foregroundColor(.primary)
                            Spacer()
                            if viewModel.selectedRefType == nil {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }

                    ForEach(viewModel.availableRefTypes, id: \.self) { refType in
                        Button(action: {
                            viewModel.selectedRefType = refType
                        }) {
                            HStack {
                                Text(viewModel.getLocalizedRefType(refType))
                                    .foregroundColor(.primary)
                                Spacer()
                                if viewModel.selectedRefType == refType {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Misc_Filter", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Misc_Done", comment: "")) {
                        viewModel.showFilter = false
                    }
                }
            }
        }
    }

    var summarySection: some View {
        Section(
            header: HStack {
                Text(NSLocalizedString("Summary", comment: ""))
                    .fontWeight(.semibold)
                    .font(.system(size: 18))
                    .foregroundColor(.primary)
                    .textCase(.none)
                Spacer()
                Button(action: {
                    switch viewModel.timeRange {
                    case .last30Days:
                        viewModel.timeRange = .last7Days
                    case .last7Days:
                        viewModel.timeRange = .last1Day
                    case .last1Day:
                        viewModel.timeRange = .last30Days
                    }
                    viewModel.updateTotals()
                }) {
                    Text(viewModel.timeRange.localizedString)
                        .font(.system(size: 14))
                        .foregroundColor(.blue)
                }
            }
        ) {
            // 总收入
            HStack {
                Text(NSLocalizedString("Total Income", comment: ""))
                    .font(.system(size: 14))
                Spacer()
                Text(
                    "\(viewModel.totalIncome > 0 ? "+" : "")\(FormatUtil.format(viewModel.totalIncome, false)) ISK"
                )
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(viewModel.totalIncome > 0 ? .green : .secondary)
            }

            // 总支出
            HStack {
                Text(NSLocalizedString("Total Expense", comment: ""))
                    .font(.system(size: 14))
                Spacer()
                Text(
                    "\(viewModel.totalExpense > 0 ? "-" : "")\(FormatUtil.format(viewModel.totalExpense, false)) ISK"
                )
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(viewModel.totalExpense > 0 ? .red : .secondary)
            }

            // 净收益
            HStack {
                Text(NSLocalizedString("Net Income", comment: ""))
                    .font(.system(size: 14))
                Spacer()
                let netIncome = viewModel.totalIncome - viewModel.totalExpense
                Text("\(FormatUtil.format(netIncome, false)) ISK")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(netIncome > 0 ? .green : netIncome < 0 ? .red : .secondary)
            }
        }
    }

    var body: some View {
        List {
            // 加载进度部分
            if viewModel.isLoading || viewModel.loadingProgress != nil {
                Section {
                    HStack {
                        Spacer()
                        if let progress = viewModel.loadingProgress {
                            let text: String =
                                switch progress {
                                case let .loading(page):
                                    String(
                                        format: NSLocalizedString(
                                            "Wallet_Loading_Fetching", comment: ""
                                        ), page
                                    )
                                case .completed:
                                    NSLocalizedString("Wallet_Loading_Complete", comment: "")
                                }

                            Text(text)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(Color(.secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }

            if viewModel.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(.circular)
                    Spacer()
                }
            } else if viewModel.journalGroups.isEmpty {
                Section {
                    NoDataSection()
                }
            } else {
                summarySection

                if viewModel.filteredJournalGroups.isEmpty {
                    Section {
                        NoDataSection()
                    }
                } else {
                    Section(
                        header: Text(NSLocalizedString("Transaction Dates", comment: ""))
                            .fontWeight(.semibold)
                            .font(.system(size: 18))
                            .foregroundColor(.primary)
                            .textCase(.none)
                    ) {
                        ForEach(viewModel.filteredJournalGroups) { group in
                            NavigationLink(
                                destination: CorpWalletJournalDayDetailView(group: group)
                            ) {
                                HStack {
                                    // 左侧：日期和交易数垂直排列
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(FormatUtil.formatDateToLocalDate(group.date))
                                            .font(.system(size: 16))

                                        Text(
                                            "\(group.entries.count) \(NSLocalizedString("transactions", comment: ""))"
                                        )
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    // 右侧：净收益
                                    let dayNetIncome = group.entries.reduce(0.0) { $0 + $1.amount }
                                    Text(
                                        "\(dayNetIncome >= 0 ? "+" : "")\(FormatUtil.formatISK(dayNetIncome))"
                                    )
                                    .font(.caption)
                                    .foregroundColor(
                                        dayNetIncome > 0
                                            ? .green : dayNetIncome < 0 ? .red : .secondary)
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                        }
                    }

                    if viewModel.isPartialData {
                        Section {
                            HStack {
                                Spacer()
                                Text(NSLocalizedString("Wallet_Partial_Data_Notice", comment: ""))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                Spacer()
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await viewModel.loadJournalData(forceRefresh: true)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    if viewModel.selectedRefType != nil || viewModel.selectedTransactionType != nil {
                        Button(action: {
                            viewModel.selectedRefType = nil
                            viewModel.selectedTransactionType = nil
                        }) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundColor(.red)
                        }
                    }

                    Button(action: {
                        viewModel.showFilter = true
                    }) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $viewModel.showFilter) {
            filterView
        }
    }
}

// 钱包流水条目行视图
struct CorpWalletJournalEntryRow: View {
    let entry: CorpWalletJournalEntry
    @AppStorage("selectedLanguage") private var selectedLanguage: String?

    // 使用FormatUtil进行日期处理，无需自定义格式化器

    private func formatRefType(_ refType: String) -> String {
        let lowercaseRefType = refType.lowercased()
        let language = selectedLanguage == "zh-Hans" ? "zh" : "en"

        // 使用新的处理方法获取本地化名称
        return LocalizationManager.shared.processEntryTypeName(
            for: lowercaseRefType, esiText: refType, language: language
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // 交易类型和金额
            HStack {
                Text(formatRefType(entry.ref_type))
                    .font(.body)
                    .lineLimit(1)
                Spacer()
                Text("\(FormatUtil.format(entry.amount)) ISK")
                    .foregroundColor(entry.amount >= 0 ? .green : .red)
                    .font(.system(.caption, design: .monospaced))
            }

            // 交易细节
            Text(
                LocalizationManager.shared.processJournalMessage(
                    for: entry.ref_type.lowercased(),
                    esiText: entry.description,
                    language: selectedLanguage == "zh-Hans" ? "zh" : "en"
                )
            )
            .font(.caption)
            .foregroundColor(.secondary)

            // Reason 信息
            if !entry.reason.isEmpty {
                Text(String(format: NSLocalizedString("Reason", comment: ""), entry.reason))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // 余额
            Text(
                String(
                    format: NSLocalizedString("Balance", comment: ""),
                    FormatUtil.format(entry.balance)
                )
            )
            .font(.caption)
            .foregroundColor(.gray)

            // 时间
            Text(FormatUtil.formatUTCToLocalTime(entry.date))
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button {
                let processedDescription = LocalizationManager.shared.processJournalMessage(
                    for: entry.ref_type.lowercased(),
                    esiText: entry.description,
                    language: selectedLanguage == "zh-Hans" ? "zh" : "en"
                )
                let sign = entry.amount >= 0 ? "+" : ""
                let detailText = "[\(FormatUtil.formatUTCToLocalTime(entry.date))] \(processedDescription): \(sign)\(FormatUtil.format(entry.amount)) ISK, \(String(format: NSLocalizedString("Reason", comment: ""), entry.reason))"
                UIPasteboard.general.string = detailText
            } label: {
                Label(
                    NSLocalizedString("Wallet_Copy_Detail", comment: ""),
                    systemImage: "doc.on.doc"
                )
            }
        }
    }
}
