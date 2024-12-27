import SwiftUI

// 按日期分组的合同
struct ContractGroup: Identifiable {
    let id = UUID()
    let date: Date
    var contracts: [ContractInfo]
}

@MainActor
final class PersonalContractsViewModel: ObservableObject {
    @Published private(set) var contractGroups: [ContractGroup] = []
    @Published var isLoading = true
    @Published var errorMessage: String?
    
    private let characterId: Int
    
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    
    init(characterId: Int) {
        self.characterId = characterId
    }
    
    func loadContractsData(forceRefresh: Bool = false) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let contracts = try await CharacterContractsAPI.shared.fetchContracts(
                characterId: characterId,
                forceRefresh: forceRefresh
            )
            
            var groupedContracts: [Date: [ContractInfo]] = [:]
            for contract in contracts {
                let components = calendar.dateComponents([.year, .month, .day], from: contract.date_issued)
                guard let dayDate = calendar.date(from: components) else {
                    print("Failed to create date from components for contract: \(contract.contract_id)")
                    continue
                }
                
                groupedContracts[dayDate, default: []].append(contract)
            }
            
            let groups = groupedContracts.map { (date, contracts) -> ContractGroup in
                ContractGroup(date: date, contracts: contracts.sorted { $0.date_issued > $1.date_issued })
            }.sorted { $0.date > $1.date }
            
            self.contractGroups = groups
            self.isLoading = false
            
        } catch {
            self.errorMessage = error.localizedDescription
            self.isLoading = false
        }
    }
}

struct PersonalContractsView: View {
    @StateObject private var viewModel: PersonalContractsViewModel
    
    private let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")!
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    
    init(characterId: Int) {
        _viewModel = StateObject(wrappedValue: PersonalContractsViewModel(characterId: characterId))
    }
    
    var body: some View {
        List {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if viewModel.contractGroups.isEmpty {
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
                ForEach(viewModel.contractGroups) { group in
                    Section(header: Text(displayDateFormatter.string(from: group.date))
                        .fontWeight(.bold)
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                        .textCase(.none)
                    ) {
                        ForEach(group.contracts) { contract in
                            ContractRow(contract: contract)
                                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await viewModel.loadContractsData(forceRefresh: true)
        }
        .task {
            if viewModel.contractGroups.isEmpty {
                await viewModel.loadContractsData()
            }
        }
        .navigationTitle(NSLocalizedString("Main_Contracts", comment: ""))
    }
}

struct ContractRow: View {
    let contract: ContractInfo
    
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")!
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    
    private func formatContractType(_ type: String) -> String {
        return NSLocalizedString("Contract_Type_\(type)", comment: "")
    }
    
    private func formatContractStatus(_ status: String) -> String {
        return NSLocalizedString("Contract_Status_\(status)", comment: "")
    }
    
    @ViewBuilder
    private func priceView() -> some View {
        switch contract.type {
        case "item_exchange":
            if contract.price > 0 {
                Text("\(FormatUtil.format(contract.price)) ISK")
                    .foregroundColor(.red)
                    .font(.system(.caption, design: .monospaced))
            }
        case "courier":
            VStack(alignment: .trailing, spacing: 2) {
                if contract.reward > 0 {
                    Text("+\(FormatUtil.format(contract.reward)) ISK")
                        .foregroundColor(.green)
                        .font(.system(.caption, design: .monospaced))
                }
                if contract.collateral > 0 {
                    Text(NSLocalizedString("Contract_Collateral", comment: "") + ": \(FormatUtil.format(contract.collateral)) ISK")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        case "auction":
            if contract.price > 0 {
                Text("\(FormatUtil.format(contract.price)) ISK")
                    .foregroundColor(.orange)
                    .font(.system(.caption, design: .monospaced))
            }
        default:
            EmptyView()
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(formatContractType(contract.type))
                    .font(.body)
                    .lineLimit(1)
                Spacer()
                priceView()
            }
            
            if !contract.title.isEmpty {
                Text(contract.title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            if contract.volume > 0 {
                Text(NSLocalizedString("Contract_Volume", comment: "") + ": \(FormatUtil.format(contract.volume)) m³")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text(formatContractStatus(contract.status))
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Spacer()
                
                Text("\(timeFormatter.string(from: contract.date_issued)) (UTC+0)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(.vertical, 2)
    }
} 