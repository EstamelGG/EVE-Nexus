import SwiftUI

// 钱包流水条目模型
struct WalletJournalEntry: Codable, Identifiable {
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
struct WalletJournalGroup: Identifiable {
    let id = UUID()
    let date: Date
    var entries: [WalletJournalEntry]
}

@MainActor
final class WalletJournalViewModel: ObservableObject {
    @Published private(set) var journalGroups: [WalletJournalGroup] = []
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published private(set) var totalIncome: Double = 0.0
    @Published private(set) var totalExpense: Double = 0.0
    @Published var timeRange: TimeRange = .last30Days
    private var loadingTask: Task<Void, Never>?
    private var initialLoadDone = false

    enum TimeRange: String, CaseIterable {
        case last30Days = "last30Days"
        case last7Days = "last7Days"
        case last1Day = "last1Day"

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

    init(characterId: Int) {
        self.characterId = characterId

        // 在初始化时立即开始加载数据
        loadingTask = Task {
            await loadJournalData()
        }
    }

    deinit {
        loadingTask?.cancel()
    }

    // 计算总收支
    private func calculateTotals(from entries: [WalletJournalEntry]) {
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
            guard let entryDate = dateFormatter.date(from: entry.date),
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
                    let jsonString = try await CharacterWalletAPI.shared.getWalletJournal(
                        characterId: characterId, forceRefresh: forceRefresh
                    )
                else {
                    throw NetworkError.invalidResponse
                }

                if Task.isCancelled { return }

                guard let jsonData = jsonString.data(using: .utf8),
                    let entries = try? JSONDecoder().decode(
                        [WalletJournalEntry].self, from: jsonData
                    )
                else {
                    throw NetworkError.invalidResponse
                }

                if Task.isCancelled { return }

                // 计算总收支
                calculateTotals(from: entries)

                var groupedEntries: [Date: [WalletJournalEntry]] = [:]
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

                let groups = groupedEntries.map { date, entries -> WalletJournalGroup in
                    WalletJournalGroup(date: date, entries: entries.sorted { $0.id > $1.id })
                }.sorted { $0.date > $1.date }

                await MainActor.run {
                    self.journalGroups = groups
                    self.isLoading = false
                    self.initialLoadDone = true
                }

            } catch {
                Logger.error("加载钱包流水失败: \(error.localizedDescription)")
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

// 特定日期的钱包流水详情视图
struct WalletJournalDayDetailView: View {
    let group: WalletJournalGroup
    @State private var displayedEntries: [WalletJournalEntry] = []
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
            ForEach(displayedEntries, id: \.id) { entry in
                WalletJournalEntryRow(entry: entry)
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

struct WalletJournalView: View {
    @StateObject private var viewModel: WalletJournalViewModel

    private let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")!
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    init(characterId: Int) {
        _viewModel = StateObject(wrappedValue: WalletJournalViewModel(characterId: characterId))
    }

    var summarySection: some View {
        Section(
            header: HStack {
                Text(NSLocalizedString("Summary", comment: ""))
                    .fontWeight(.bold)
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
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if viewModel.journalGroups.isEmpty {
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
            } else {
                summarySection

                Section(
                    header: Text(NSLocalizedString("Transaction Dates", comment: ""))
                        .fontWeight(.bold)
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                        .textCase(.none)
                ) {
                    ForEach(viewModel.journalGroups) { group in
                        NavigationLink(destination: WalletJournalDayDetailView(group: group)) {
                            HStack {
                                Text(displayDateFormatter.string(from: group.date))
                                    .font(.system(size: 16))

                                Spacer()

                                // 显示当日交易数量
                                Text(
                                    "\(group.entries.count) \(NSLocalizedString("transactions", comment: ""))"
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
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
        .navigationTitle(NSLocalizedString("Main_Wallet_Journal", comment: ""))
    }
}

// 钱包流水条目行视图
struct WalletJournalEntryRow: View {
    let entry: WalletJournalEntry
    @AppStorage("selectedLanguage") private var selectedLanguage: String?

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

    private func formatRefType(_ refType: String) -> String {
        let lowercaseRefType = refType.lowercased()
        let language = selectedLanguage == "zh-Hans" ? "zh" : "en"

        // 使用新的处理方法获取本地化名称
        return LocalizationManager.shared.processEntryTypeName(
            for: lowercaseRefType, esiText: refType, language: language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(formatRefType(entry.ref_type))
                    .font(.body)
                    .lineLimit(1)
                Spacer()
                Text("\(FormatUtil.format(entry.amount)) ISK")
                    .foregroundColor(entry.amount >= 0 ? .green : .red)
                    .font(.system(.caption, design: .monospaced))
            }

            // 使用模板处理后的描述文本
            Text(
                LocalizationManager.shared.processJournalMessage(
                    for: entry.ref_type.lowercased(),
                    esiText: entry.description,
                    language: selectedLanguage == "zh-Hans" ? "zh" : "en"
                )
            )
            .font(.caption)
            .foregroundColor(.secondary)

            Text(
                String(
                    format: NSLocalizedString("Balance", comment: ""),
                    FormatUtil.format(entry.balance)
                )
            )
            .font(.caption)
            .foregroundColor(.gray)

            if let date = dateFormatter.date(from: entry.date) {
                Text(
                    "\(displayDateFormatter.string(from: date)) \(timeFormatter.string(from: date)) (UTC+0)"
                )
                .font(.caption)
                .foregroundColor(.gray)
            }
        }
        .padding(.vertical, 2)
    }
}
