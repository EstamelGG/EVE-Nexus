import SwiftUI

// 按日期分组的合同
struct ContractGroup: Identifiable {
    let id = UUID()
    let date: Date
    var contracts: [ContractInfo]
}

@MainActor
final class PersonalContractsViewModel: ObservableObject {
    @Published var contracts: [ContractInfo] = []
    @Published var contractGroups: [ContractGroup] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showCorporationContracts = false
    
    private var loadingTask: Task<Void, Never>?
    private var initialLoadDone = false
    private var characterId: Int
    
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    
    init(characterId: Int) {
        self.characterId = characterId
    }
    
    func loadContractsData(forceRefresh: Bool = false) async {
        // 取消之前的加载任务
        loadingTask?.cancel()
        
        // 创建新的加载任务
        loadingTask = Task {
            isLoading = true
            errorMessage = nil
            
            do {
                let contracts: [ContractInfo]
                if showCorporationContracts {
                    contracts = try await CorporationContractsAPI.shared.fetchContracts(
                        characterId: characterId,
                        forceRefresh: forceRefresh
                    )
                } else {
                    contracts = try await CharacterContractsAPI.shared.fetchContracts(
                        characterId: characterId,
                        forceRefresh: forceRefresh
                    )
                }
                
                if Task.isCancelled { return }
                
                // 按日期分组
                var groupedContracts: [Date: [ContractInfo]] = [:]
                for contract in contracts {
                    let date = calendar.startOfDay(for: contract.date_issued)
                    if groupedContracts[date] == nil {
                        groupedContracts[date] = []
                    }
                    groupedContracts[date]?.append(contract)
                }
                
                // 创建分组并排序
                let groups = groupedContracts.map { date, contracts in
                    ContractGroup(
                        date: date,
                        contracts: contracts.sorted { $0.date_issued > $1.date_issued }
                    )
                }.sorted { $0.date > $1.date }
                
                if Task.isCancelled { return }
                
                await MainActor.run {
                    self.contractGroups = groups
                    self.isLoading = false
                    self.initialLoadDone = true
                }
                
            } catch {
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
    
    deinit {
        loadingTask?.cancel()
    }
}

struct PersonalContractsView: View {
    @StateObject private var viewModel: PersonalContractsViewModel
    @Environment(\.colorScheme) private var colorScheme
    
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
        VStack(spacing: 0) {
            List {
                if viewModel.isLoading {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                    .listSectionSpacing(.compact)
                } else if viewModel.contractGroups.isEmpty {
                    Section {
                        HStack {
                            Spacer()
                            VStack(spacing: 4) {
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
                    .listSectionSpacing(.compact)
                } else {
                    ForEach(viewModel.contractGroups) { group in
                        Section {
                            ForEach(group.contracts) { contract in
                                ContractRow(contract: contract)
                            }
                        } header: {
                            Text(displayDateFormatter.string(from: group.date))
                                .font(.headline)
                                .foregroundColor(.primary)
                                .textCase(nil)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable {
                await viewModel.loadContractsData(forceRefresh: true)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                Picker("Contract Type", selection: $viewModel.showCorporationContracts) {
                    Text(NSLocalizedString("Contracts_Personal", comment: ""))
                        .tag(false)
                    Text(NSLocalizedString("Contracts_Corporation", comment: ""))
                        .tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 4)
            }
            .background(Color(.systemGroupedBackground))
        }
        .navigationTitle(NSLocalizedString("Main_Contracts", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadContractsData()
        }
        .onChange(of: viewModel.showCorporationContracts) { _, _ in
            Task {
                await viewModel.loadContractsData()
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
                HStack {
                    if contract.volume > 0 {
                        Text(NSLocalizedString("Contract_Volume", comment: "") + ": \(FormatUtil.format(contract.volume)) m³")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text("\(timeFormatter.string(from: contract.date_issued)) (UTC+0)")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
            }
            .padding(.vertical, 2)
        }
    }
} 
