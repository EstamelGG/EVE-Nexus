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
    
    let characterId: Int
    
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ContractsUpdated"))) { notification in
            if let characterId = notification.userInfo?["characterId"] as? Int,
               characterId == viewModel.characterId {
                // 重新加载数据
                Task {
                    await viewModel.loadContractsData()
                }
            }
        }
    }
}

struct ContractRow: View {
    let contract: ContractInfo
    @AppStorage("currentCharacterId") private var currentCharacterId: Int = 0
    @StateObject private var databaseManager = DatabaseManager()
    
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
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
    
    // 根据状态返回对应的颜色
    private func getStatusColor(_ status: String) -> Color {
        switch status {
        case "deleted":
            return .secondary
        case "rejected", "failed", "reversed":
            return .red
        case "outstanding", "in_progress":
            return .blue  // 进行中和待处理状态显示为蓝色
        case "finished", "finished_issuer", "finished_contractor":
            return .green  // 完成状态显示为绿色
        default:
            return .primary  // 其他状态使用主色调
        }
    }
    
    // 判断当前角色是否是合同发布者
    private var isIssuer: Bool {
        return contract.issuer_id == currentCharacterId
    }
    
    // 判断当前角色是否是合同接收者
    private var isAcceptor: Bool {
        return contract.acceptor_id == currentCharacterId
    }
    
    @ViewBuilder
    private func priceView() -> some View {
        switch contract.type {
        case "item_exchange":
            // 物品交换合同
            if isIssuer {
                // 发布者显示收入
                Text("+\(FormatUtil.format(contract.price)) ISK")
                    .foregroundColor(.green)
                    .font(.system(.caption, design: .monospaced))
            } else {
                // 接收者显示支出
                Text("-\(FormatUtil.format(contract.price)) ISK")
                    .foregroundColor(.red)
                    .font(.system(.caption, design: .monospaced))
            }
            
        case "courier":
            // 运输合同
            VStack(alignment: .trailing, spacing: 2) {
                if isIssuer {
                    // 发布者显示支出（报酬）和收回（保证金）
                    Text("-\(FormatUtil.format(contract.reward)) ISK")
                        .foregroundColor(.red)
                        .font(.system(.caption, design: .monospaced))
                } else {
                    // 接收者显示收入（报酬）和冻结（保证金）
                    Text("+\(FormatUtil.format(contract.reward)) ISK")
                        .foregroundColor(.green)
                        .font(.system(.caption, design: .monospaced))
                }
            }
            
        case "auction":
            // 拍卖合同
            if isIssuer {
                // 发布者显示预期收入
                Text("+\(FormatUtil.format(contract.price)) ISK")
                    .foregroundColor(.green)
                    .font(.system(.caption, design: .monospaced))
            } else if isAcceptor {
                // 当前最高出价者显示可能支出
                Text("-\(FormatUtil.format(contract.price)) ISK")
                    .foregroundColor(.red)
                    .font(.system(.caption, design: .monospaced))
            } else {
                // 其他人显示当前价格
                Text("\(FormatUtil.format(contract.price)) ISK")
                    .foregroundColor(.orange)
                    .font(.system(.caption, design: .monospaced))
            }
            
        default:
            EmptyView()
        }
    }
    
    var body: some View {
        NavigationLink {
            ContractDetailView(
                characterId: currentCharacterId,
                contract: contract,
                databaseManager: databaseManager
            )
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(formatContractStatus(contract.status))
                        .font(.caption)
                        .foregroundColor(getStatusColor(contract.status))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))
                        )
                    Text(formatContractType(contract.type))
                        .font(.body)
                        .lineLimit(1)
                    Spacer()
                    priceView()
                }
                
                if !contract.title.isEmpty {
                    Text(NSLocalizedString("Contract_Title", comment: "") + ": \(contract.title)")
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
                    Text("\(timeFormatter.string(from: contract.date_issued)) (UTC+0)")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .padding(.vertical, 2)
        }
    }
} 
