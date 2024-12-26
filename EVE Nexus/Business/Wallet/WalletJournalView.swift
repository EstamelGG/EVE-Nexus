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

struct WalletJournalView: View {
    let characterId: Int
    @State private var journalGroups: [WalletJournalGroup] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    
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
    
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    
    var body: some View {
        List {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
            } else {
                ForEach(journalGroups) { group in
                    Section(header: Text(displayDateFormatter.string(from: group.date)).textCase(.none)) {
                        ForEach(group.entries, id: \.id) { entry in
                            WalletJournalEntryRow(entry: entry)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("Main_Wallet_Journal", comment: ""))
        .task {
            await loadJournalData()
        }
        .refreshable {
            await loadJournalData(forceRefresh: true)
        }
    }
    
    private func loadJournalData(forceRefresh: Bool = false) async {
        isLoading = true
        errorMessage = nil
        
        do {
            // 获取钱包日志数据
            guard let jsonString = try await CharacterWalletAPI.shared.getWalletJournal(characterId: characterId, forceRefresh: forceRefresh) else {
                throw NetworkError.invalidResponse
            }
            
            // 解析JSON数据
            guard let jsonData = jsonString.data(using: .utf8),
                  let entries = try? JSONDecoder().decode([WalletJournalEntry].self, from: jsonData) else {
                throw NetworkError.invalidResponse
            }
            
            // 按日期分组
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
            
            // 转换为数组并排序
            let groups = groupedEntries.map { (date, entries) -> WalletJournalGroup in
                WalletJournalGroup(date: date, entries: entries.sorted { $0.id > $1.id })
            }.sorted { $0.date > $1.date }
            
            // 更新UI
            await MainActor.run {
                self.journalGroups = groups
                self.isLoading = false
            }
            
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
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
                    .font(.system(.body, design: .monospaced))
            }
            
            Text(entry.description)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            
            Text("Balance:\(FormatUtil.format(entry.balance)) ISK")
                .font(.caption)
                .foregroundColor(.gray)
                
            if let date = dateFormatter.date(from: entry.date) {
                Text("\(displayDateFormatter.string(from: date)) \(timeFormatter.string(from: date)) (UTC+0)")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .padding(.vertical, 2)
    }
}
