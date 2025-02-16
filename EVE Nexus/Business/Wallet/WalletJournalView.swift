import SwiftUI

// 钱包日志条目模型
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

// 按日期分组的钱包日志
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
    private var loadingTask: Task<Void, Never>?
    
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
    }
    
    deinit {
        loadingTask?.cancel()
    }
    
    // 计算总收支
    private func calculateTotals(from entries: [WalletJournalEntry]) {
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
        // 取消之前的加载任务
        loadingTask?.cancel()
        
        // 创建新的加载任务
        loadingTask = Task {
            isLoading = true
            errorMessage = nil
            
            do {
                guard let jsonString = try await CharacterWalletAPI.shared.getWalletJournal(characterId: characterId, forceRefresh: forceRefresh) else {
                    throw NetworkError.invalidResponse
                }
                
                if Task.isCancelled { return }
                
                guard let jsonData = jsonString.data(using: .utf8),
                      let entries = try? JSONDecoder().decode([WalletJournalEntry].self, from: jsonData) else {
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
                
                let groups = groupedEntries.map { (date, entries) -> WalletJournalGroup in
                    WalletJournalGroup(date: date, entries: entries.sorted { $0.id > $1.id })
                }.sorted { $0.date > $1.date }
                
                await MainActor.run {
                    self.journalGroups = groups
                    self.isLoading = false
                }
                
            } catch {
                Logger.error("加载钱包日志失败: \(error.localizedDescription)")
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
        Section(header: Text(NSLocalizedString("Summary", comment: ""))
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
                
                ForEach(viewModel.journalGroups) { group in
                    Section(header: Text(displayDateFormatter.string(from: group.date))
                        .fontWeight(.bold)
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                        .textCase(.none)
                    ) {
                        ForEach(group.entries, id: \.id) { entry in
                            WalletJournalEntryRow(entry: entry)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await viewModel.loadJournalData(forceRefresh: true)
        }
        .task {
            await viewModel.loadJournalData()
        }
        .navigationTitle(NSLocalizedString("Main_Wallet_Journal", comment: ""))
    }
}

// 钱包日志条目行视图
struct WalletJournalEntryRow: View {
    let entry: WalletJournalEntry
    
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
            HStack {
                Text(formatRefType(entry.ref_type))
                    .font(.body)
                    .lineLimit(1)
                Spacer()
                Text("\(FormatUtil.format(entry.amount)) ISK")
                    .foregroundColor(entry.amount >= 0 ? .green : .red)
                    .font(.system(.caption, design: .monospaced))
            }
            
            Text(entry.description)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("Balance: \(FormatUtil.format(entry.balance)) ISK")
                .font(.caption)
                .foregroundColor(.gray)
                
            if let date = dateFormatter.date(from: entry.date) {
                Text("\(displayDateFormatter.string(from: date)) \(timeFormatter.string(from: date)) (UTC+0)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(.vertical, 2)
    }
}
