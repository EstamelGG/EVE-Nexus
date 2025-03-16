import SwiftUI

// 军团钱包日志条目模型
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

// 按日期分组的钱包日志
struct CorpWalletJournalGroup: Identifiable {
    let id = UUID()
    let date: Date
    var entries: [CorpWalletJournalEntry]
}

// 加载进度枚举
public enum WalletLoadingProgress {
    case loading(page: Int)  // 正在加载特定页面
    case completed  // 加载完成
}

@MainActor
final class CorpWalletJournalViewModel: ObservableObject {
    @Published private(set) var journalGroups: [CorpWalletJournalGroup] = []
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published private(set) var totalIncome: Double = 0.0
    @Published private(set) var totalExpense: Double = 0.0
    @Published var loadingProgress: WalletLoadingProgress?
    private var initialLoadDone = false

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
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    init(characterId: Int, division: Int) {
        self.characterId = characterId
        self.division = division
        
        // 在初始化时立即开始加载数据
        loadingTask = Task {
            await loadJournalData()
        }
    }

    deinit {
        loadingTask?.cancel()
    }

    // 计算总收支
    private func calculateTotals(from entries: [CorpWalletJournalEntry]) {
        var income: Double = 0
        var expense: Double = 0

        for entry in entries {
            if entry.amount > 0 {
                income += entry.amount
            } else {
                expense += abs(entry.amount)
            }
        }

        totalIncome = income
        totalExpense = expense
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

                // 计算总收支
                calculateTotals(from: entries)

                // 按日期分组
                var groupedEntries: [Date: [CorpWalletJournalEntry]] = [:]
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
                Logger.error("加载军团钱包日志失败: \(error.localizedDescription)")
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

// 特定日期的军团钱包日志详情视图
struct CorpWalletJournalDayDetailView: View {
    let group: CorpWalletJournalGroup
    @State private var displayedEntries: [CorpWalletJournalEntry] = []
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

struct CorpWalletJournalView: View {
    @ObservedObject var viewModel: CorpWalletJournalViewModel

    private let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")!
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    var summarySection: some View {
        Section(
            header: Text(NSLocalizedString("Summary", comment: ""))
                .fontWeight(.bold)
                .font(.system(size: 18))
                .foregroundColor(.primary)
                .textCase(.none)
        ) {
            // 总收入
            HStack {
                Text(NSLocalizedString("Total Income", comment: ""))
                    .font(.system(size: 14))
                Spacer()
                Text("+ \(FormatUtil.format(viewModel.totalIncome)) ISK")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.green)
            }

            // 总支出
            HStack {
                Text(NSLocalizedString("Total Expense", comment: ""))
                    .font(.system(size: 14))
                Spacer()
                Text("- \(FormatUtil.format(viewModel.totalExpense)) ISK")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.red)
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
                        NavigationLink(destination: CorpWalletJournalDayDetailView(group: group)) {
                            HStack {
                                Text(displayDateFormatter.string(from: group.date))
                                    .font(.system(size: 16))
                                
                                Spacer()
                                
                                // 显示当日交易数量
                                Text("\(group.entries.count) \(NSLocalizedString("transactions", comment: ""))")
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
    }
}

// 钱包日志条目行视图
struct CorpWalletJournalEntryRow: View {
    let entry: CorpWalletJournalEntry

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
        return refType.split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
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
            Text(entry.description)
                .font(.caption)
                .foregroundColor(.secondary)

            // 余额
            Text(
                String(
                    format: NSLocalizedString("Balance: %@ ISK", comment: ""),
                    FormatUtil.format(entry.balance)
                )
            )
            .font(.caption)
            .foregroundColor(.gray)

            // 时间
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
