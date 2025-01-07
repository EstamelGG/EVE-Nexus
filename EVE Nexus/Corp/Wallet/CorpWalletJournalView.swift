import SwiftUI

// 添加一个结构体来包装日志条目
struct CorpWalletJournalEntry: Identifiable {
    let id: Int64
    let date: String
    let amount: Double
    let balance: Double
    let description: String
    let firstPartyId: Int
    let secondPartyId: Int
    let contextId: Int
    let contextIdType: String
    let refType: String
    let reason: String
    
    init(from dictionary: [String: Any]) {
        self.id = dictionary["id"] as? Int64 ?? 0
        self.date = dictionary["date"] as? String ?? ""
        self.amount = dictionary["amount"] as? Double ?? 0.0
        self.balance = dictionary["balance"] as? Double ?? 0.0
        self.description = dictionary["description"] as? String ?? ""
        self.firstPartyId = dictionary["first_party_id"] as? Int ?? 0
        self.secondPartyId = dictionary["second_party_id"] as? Int ?? 0
        self.contextId = dictionary["context_id"] as? Int ?? 0
        self.contextIdType = dictionary["context_id_type"] as? String ?? ""
        self.refType = dictionary["ref_type"] as? String ?? ""
        self.reason = dictionary["reason"] as? String ?? ""
    }
}

struct CorpWalletJournalView: View {
    let characterId: Int
    let division: Int
    let divisionName: String
    
    @State private var journalEntries: [CorpWalletJournalEntry] = []
    @State private var isLoading = true
    @State private var error: Error?
    @State private var showError = false
    @State private var totalIncome: Double = 0.0
    @State private var totalExpense: Double = 0.0
    
    // 格式化金额
    private func formatAmount(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: abs(amount))) ?? "0.00"
    }
    
    // 格式化日期
    private func formatDate(_ dateString: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        guard let date = dateFormatter.date(from: dateString) else { return dateString }
        
        dateFormatter.dateFormat = "MM-dd HH:mm"
        return dateFormatter.string(from: date)
    }
    
    // 计算总收支
    private func calculateTotals() {
        var income: Double = 0
        var expense: Double = 0
        
        for entry in journalEntries {
            if entry.amount > 0 {
                income += entry.amount
            } else {
                expense += abs(entry.amount)
            }
        }
        
        totalIncome = income
        totalExpense = expense
    }
    
    private func loadJournalData(forceRefresh: Bool = false) {
        isLoading = true
        error = nil
        
        Task {
            do {
                if let jsonString = try await CorpWalletAPI.shared.getCorpWalletJournal(
                    characterId: characterId,
                    division: division,
                    forceRefresh: forceRefresh
                ),
                   let data = jsonString.data(using: .utf8),
                   let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    await MainActor.run {
                        self.journalEntries = json.map { CorpWalletJournalEntry(from: $0) }
                        calculateTotals()
                        self.isLoading = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.error = error
                    self.showError = true
                    self.isLoading = false
                }
                Logger.error("获取军团钱包日志失败: \(error)")
            }
        }
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
                    .foregroundColor(.secondary)
                Spacer()
                Text("+ \(formatAmount(totalIncome)) ISK")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.green)
            }
            
            // 总支出
            HStack {
                Text(NSLocalizedString("Total Expense", comment: ""))
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                Spacer()
                Text("- \(formatAmount(totalExpense)) ISK")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.red)
            }
        }
    }
    
    var body: some View {
        List {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(.circular)
                    Spacer()
                }
            } else {
                summarySection
                
                Section(header: Text(NSLocalizedString("Transactions", comment: ""))
                    .fontWeight(.bold)
                    .font(.system(size: 18))
                    .foregroundColor(.primary)
                    .textCase(.none)
                ) {
                    ForEach(journalEntries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                // 日期
                                Text(formatDate(entry.date))
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                // 金额
                                Text("\(entry.amount >= 0 ? "+" : "")\(formatAmount(entry.amount)) ISK")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(entry.amount >= 0 ? .green : .red)
                            }
                            
                            // 描述
                            Text(entry.description)
                                .font(.system(size: 14))
                                .foregroundColor(.primary)
                                .lineLimit(2)
                            
                            // 交易类型和原因
                            if !entry.refType.isEmpty {
                                Text(entry.refType)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            
                            if !entry.reason.isEmpty {
                                Text(entry.reason)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            
                            // 余额
                            Text(String(format: NSLocalizedString("Balance: %@ ISK", comment: ""), formatAmount(entry.balance)))
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle(divisionName)
        .refreshable {
            loadJournalData(forceRefresh: true)
        }
        .alert(isPresented: $showError) {
            Alert(
                title: Text(NSLocalizedString("Common_Error", comment: "")),
                message: Text(error?.localizedDescription ?? NSLocalizedString("Common_Unknown_Error", comment: "")),
                dismissButton: .default(Text(NSLocalizedString("Common_OK", comment: "")))
            )
        }
        .onAppear {
            loadJournalData()
        }
    }
} 
