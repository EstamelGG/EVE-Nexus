import SwiftUI

// 添加一个结构体来包装日志条目
struct CorpWalletJournalEntry: Identifiable {
    let id: Int64
    let date: String
    let amount: Double
    let balance: Double
    let description: String
    
    init(from dictionary: [String: Any]) {
        self.id = dictionary["id"] as? Int64 ?? 0
        self.date = dictionary["date"] as? String ?? ""
        self.amount = dictionary["amount"] as? Double ?? 0.0
        self.balance = dictionary["balance"] as? Double ?? 0.0
        self.description = dictionary["description"] as? String ?? ""
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
    
    // 格式化金额
    private func formatAmount(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "0.00"
    }
    
    // 格式化日期
    private func formatDate(_ dateString: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        guard let date = dateFormatter.date(from: dateString) else { return dateString }
        
        dateFormatter.dateFormat = "MM-dd HH:mm"
        return dateFormatter.string(from: date)
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
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(entry.amount >= 0 ? .green : .red)
                        }
                        
                        // 描述
                        Text(entry.description)
                            .font(.system(size: 14))
                            .foregroundColor(.primary)
                            .lineLimit(2)
                        
                        // 余额
                        Text(String(format: NSLocalizedString("Balance: %@ ISK", comment: ""), formatAmount(entry.balance)))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
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