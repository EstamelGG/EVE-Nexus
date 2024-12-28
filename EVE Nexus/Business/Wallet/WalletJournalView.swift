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
    @Published var isBackgroundLoading = false
    @Published var errorMessage: String?
    
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
    
    func loadJournalData(forceRefresh: Bool = false) async {
        // 只有在第一次加载（没有数据）时才显示全屏加载
        let shouldShowFullscreenLoading = journalGroups.isEmpty && !forceRefresh
        
        if shouldShowFullscreenLoading {
            isLoading = true
        } else {
            isBackgroundLoading = true
        }
        errorMessage = nil
        
        do {
            guard let jsonString = try await CharacterWalletAPI.shared.getWalletJournal(characterId: characterId, forceRefresh: forceRefresh) else {
                throw NetworkError.invalidResponse
            }
            
            guard let jsonData = jsonString.data(using: .utf8),
                  let entries = try? JSONDecoder().decode([WalletJournalEntry].self, from: jsonData) else {
                throw NetworkError.invalidResponse
            }
            
            var groupedEntries: [Date: [WalletJournalEntry]] = [:]
            for entry in entries {
                guard let date = dateFormatter.date(from: entry.date) else {
                    print("Failed to parse date: \(entry.date)")
                    continue
                }
                
                let components = calendar.dateComponents([.year, .month, .day], from: date)
                guard let dayDate = calendar.date(from: components) else {
                    print("Failed to create date from components for: \(entry.date)")
                    continue
                }
                
                groupedEntries[dayDate, default: []].append(entry)
            }
            
            let groups = groupedEntries.map { (date, entries) -> WalletJournalGroup in
                WalletJournalGroup(date: date, entries: entries.sorted { $0.id > $1.id })
            }.sorted { $0.date > $1.date }
            
            self.journalGroups = groups
            if shouldShowFullscreenLoading {
                isLoading = false
            } else {
                isBackgroundLoading = false
            }
            
        } catch {
            self.errorMessage = error.localizedDescription
            if shouldShowFullscreenLoading {
                isLoading = false
            } else {
                isBackgroundLoading = false
            }
        }
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
                ForEach(viewModel.journalGroups) { group in
                    Section(header: Text(displayDateFormatter.string(from: group.date))
                        .fontWeight(.bold)
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                        .textCase(.none)
                    ) {
                        ForEach(group.entries, id: \.id) { entry in
                            WalletJournalEntryRow(entry: entry)
                                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            // 立即触发刷新并返回，不等待加载完成
            Task {
                await viewModel.loadJournalData(forceRefresh: true)
            }
            // 立即完成下拉刷新动作
            return
        }
        .task {
            if viewModel.journalGroups.isEmpty {
                await viewModel.loadJournalData()
            }
        }
        .navigationTitle(NSLocalizedString("Main_Wallet_Journal", comment: ""))
        .toolbar {
            if viewModel.isBackgroundLoading {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
        }
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
                .lineLimit(1)
            
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
