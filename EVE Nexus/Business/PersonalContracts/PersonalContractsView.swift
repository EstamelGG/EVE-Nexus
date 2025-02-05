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
    @Published var currentLoadingPage: Int?
    @Published var showCorporationContracts = false {
        didSet {
            // 切换时，如果对应类型的合同还未加载过，则加载
            Task {
                await loadContractsIfNeeded()
            }
        }
    }
    @Published var hasCorporationAccess = false
    
    private var loadingTask: Task<Void, Never>?
    private var personalContractsInitialized = false
    private var corporationContractsInitialized = false
    private var cachedPersonalContracts: [ContractInfo] = []
    private var cachedCorporationContracts: [ContractInfo] = []
    let characterId: Int
    let databaseManager: DatabaseManager
    
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    
    init(characterId: Int) {
        self.characterId = characterId
        self.databaseManager = DatabaseManager()
        // 初始化时检查军团访问权限
        Task {
            await checkCorporationAccess()
        }
    }
    
    // 检查是否有军团合同访问权限
    private func checkCorporationAccess() async {
        do {
            if (try await CharacterDatabaseManager.shared.getCharacterCorporationId(characterId: characterId)) != nil {
                // 如果能获取到军团ID，说明有访问权限
                hasCorporationAccess = true
            } else {
                hasCorporationAccess = false
                showCorporationContracts = false
            }
        } catch {
            Logger.error("检查军团访问权限失败: \(error)")
            hasCorporationAccess = false
            showCorporationContracts = false
        }
    }
    
    private func loadContractsIfNeeded() async {
        // 取消之前的加载任务
        loadingTask?.cancel()
        
        // 如果已经加载过且不是强制刷新，直接使用缓存
        if showCorporationContracts && corporationContractsInitialized {
            updateContractGroups(with: cachedCorporationContracts)
            return
        } else if !showCorporationContracts && personalContractsInitialized {
            updateContractGroups(with: cachedPersonalContracts)
            return
        }
        
        // 创建新的加载任务
        loadingTask = Task {
            await loadContractsData(forceRefresh: false)
        }
        
        // 等待任务完成
        await loadingTask?.value
    }
    
    private func updateContractGroups(with contracts: [ContractInfo]) {
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
        
        self.contractGroups = groups
    }
    
    func loadContractsData(forceRefresh: Bool = false) async {
        if isLoading { return }
        
        // 如果不是强制刷新，且数据已加载，则直接使用缓存
        if !forceRefresh {
            if showCorporationContracts && corporationContractsInitialized {
                updateContractGroups(with: cachedCorporationContracts)
                return
            } else if !showCorporationContracts && personalContractsInitialized {
                updateContractGroups(with: cachedPersonalContracts)
                return
            }
        }
        
        isLoading = true
        errorMessage = nil
        currentLoadingPage = nil
        
        do {
            let contracts: [ContractInfo]
            if showCorporationContracts {
                // 获取军团合同
                do {
                    contracts = try await CorporationContractsAPI.shared.fetchContracts(
                        characterId: characterId,
                        forceRefresh: forceRefresh,
                        progressCallback: { page in
                            Task { @MainActor in
                                self.currentLoadingPage = page
                            }
                        }
                    )
                    cachedCorporationContracts = contracts
                    corporationContractsInitialized = true
                } catch is CancellationError {
                    // 如果是取消操作，不显示错误
                    isLoading = false
                    currentLoadingPage = nil
                    return
                }
            } else {
                // 获取个人合同
                do {
                    contracts = try await CharacterContractsAPI.shared.fetchContracts(
                        characterId: characterId,
                        forceRefresh: forceRefresh,
                        progressCallback: { page in
                            Task { @MainActor in
                                self.currentLoadingPage = page
                            }
                        }
                    )
                    cachedPersonalContracts = contracts
                    personalContractsInitialized = true
                } catch is CancellationError {
                    // 如果是取消操作，不显示错误
                    isLoading = false
                    currentLoadingPage = nil
                    return
                }
            }
            
            updateContractGroups(with: contracts)
            isLoading = false
            currentLoadingPage = nil
            
        } catch {
            if !(error is CancellationError) {
                self.errorMessage = error.localizedDescription
                Logger.error("加载\(showCorporationContracts ? "军团" : "个人")合同数据失败: \(error)")
            }
            self.isLoading = false
            self.currentLoadingPage = nil
        }
    }
    
    deinit {
        loadingTask?.cancel()
    }
}

struct PersonalContractsView: View {
    @StateObject private var viewModel: PersonalContractsViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var showSettings = false
    
    // 使用计算属性来获取和设置带有角色ID的AppStorage键
    private var showFinishedContractsKey: String { "showFinishedContracts_\(viewModel.characterId)" }
    private var showCourierContractsKey: String { "showCourierContracts_\(viewModel.characterId)" }
    private var showItemExchangeContractsKey: String { "showItemExchangeContracts_\(viewModel.characterId)" }
    private var showAuctionContractsKey: String { "showAuctionContracts_\(viewModel.characterId)" }
    
    // 使用@AppStorage并使用动态key
    @AppStorage("") private var showFinishedContracts: Bool = true
    @AppStorage("") private var showCourierContracts: Bool = true
    @AppStorage("") private var showItemExchangeContracts: Bool = true
    @AppStorage("") private var showAuctionContracts: Bool = true
    
    private let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")!
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    
    init(characterId: Int) {
        _viewModel = StateObject(wrappedValue: PersonalContractsViewModel(characterId: characterId))
        
        // 初始化@AppStorage的key
        _showFinishedContracts = AppStorage(wrappedValue: true, "showFinishedContracts_\(characterId)")
        _showCourierContracts = AppStorage(wrappedValue: true, "showCourierContracts_\(characterId)")
        _showItemExchangeContracts = AppStorage(wrappedValue: true, "showItemExchangeContracts_\(characterId)")
        _showAuctionContracts = AppStorage(wrappedValue: true, "showAuctionContracts_\(characterId)")
    }
    
    var body: some View {
        VStack(spacing: 0) {
            List {
                if viewModel.isLoading {
                    loadingView
                } else if viewModel.contractGroups.isEmpty {
                    emptyView
                } else {
                    ForEach(viewModel.contractGroups) { group in
                        Section {
                            ForEach(group.contracts.filter { contract in
                                // 根据设置过滤合同
                                let showByType = (contract.type == "courier" && showCourierContracts) ||
                                               (contract.type == "item_exchange" && showItemExchangeContracts) ||
                                               (contract.type == "auction" && showAuctionContracts)
                                
                                let showByStatus = showFinishedContracts || 
                                                 !["finished", "finished_issuer", "finished_contractor"].contains(contract.status)
                                
                                return showByType && showByStatus
                            }) { contract in
                                ContractRow(
                                    contract: contract,
                                    isCorpContract: viewModel.showCorporationContracts,
                                    databaseManager: viewModel.databaseManager
                                )
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
                if viewModel.hasCorporationAccess {
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
            }
            .background(Color(.systemGroupedBackground))
        }
        .navigationTitle(NSLocalizedString("Main_Contracts", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showSettings = true
                }) {
                    Image(systemName: "gear")
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationView {
                Form {
                    Section {
                        Toggle(isOn: $showFinishedContracts) {
                            Text(NSLocalizedString("Contract_Show_Finished", comment: ""))
                        }
                        Toggle(isOn: $showCourierContracts) {
                            Text(NSLocalizedString("Contract_Show_Courier", comment: ""))
                        }
                        Toggle(isOn: $showItemExchangeContracts) {
                            Text(NSLocalizedString("Contract_Show_ItemExchange", comment: ""))
                        }
                        Toggle(isOn: $showAuctionContracts) {
                            Text(NSLocalizedString("Contract_Show_Auction", comment: ""))
                        }
                    }
                }
                .navigationTitle(NSLocalizedString("Contract_Settings", comment: ""))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(NSLocalizedString("Contract_Done", comment: "")) {
                            showSettings = false
                        }
                    }
                }
            }
        }
        .task(id: viewModel.showCorporationContracts) {
            try? await Task.sleep(nanoseconds: 100_000_000) // 等待100ms
            await viewModel.loadContractsData()
        }
    }
    
    private var loadingView: some View {
        Section {
            HStack {
                Spacer()
                if let page = viewModel.currentLoadingPage {
                    Text(NSLocalizedString("Loading_Page", comment: "") + " \(page)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
        }
        .listSectionSpacing(.compact)
    }
    
    private var emptyView: some View {
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
    }
}

struct ContractRow: View {
    let contract: ContractInfo
    let isCorpContract: Bool
    let databaseManager: DatabaseManager
    @AppStorage("currentCharacterId") private var currentCharacterId: Int = 0
    
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
        if isCorpContract {
            // 军团合同：检查是否是军团发布的合同
            return contract.for_corporation
        } else {
            // 个人合同：检查是否是当前角色发布的
            return contract.issuer_id == currentCharacterId
        }
    }
    
    // 判断当前角色是否是合同接收者
    private var isAcceptor: Bool {
        if isCorpContract {
            // 军团合同：检查是否是指定给军团的
            return contract.assignee_id == contract.issuer_corporation_id
        } else {
            // 个人合同：检查是否是指定给当前角色的
            return contract.acceptor_id == currentCharacterId
        }
    }
    
    @ViewBuilder
    private func priceView() -> some View {
        switch contract.type {
        case "item_exchange":
            // 物品交换合同
            if isCorpContract {
                // 军团合同：发起人是自己则显示收入（绿色），否则显示支出（红色）
                if contract.issuer_id == currentCharacterId {
                    Text("+\(FormatUtil.format(contract.price)) ISK")
                        .foregroundColor(.green)
                        .font(.system(.caption, design: .monospaced))
                } else {
                    Text("-\(FormatUtil.format(contract.price)) ISK")
                        .foregroundColor(.red)
                        .font(.system(.caption, design: .monospaced))
                }
            } else {
                // 个人合同：保持原有逻辑
                if isIssuer {
                    Text("+\(FormatUtil.format(contract.price)) ISK")
                        .foregroundColor(.green)
                        .font(.system(.caption, design: .monospaced))
                } else {
                    Text("-\(FormatUtil.format(contract.price)) ISK")
                        .foregroundColor(.red)
                        .font(.system(.caption, design: .monospaced))
                }
            }
            
        case "courier":
            // 运输合同
            if isCorpContract {
                // 军团合同：发起人是自己则显示支出（红色），否则显示收入（绿色）
                if contract.issuer_id == currentCharacterId {
                    Text("-\(FormatUtil.format(contract.reward)) ISK")
                        .foregroundColor(.red)
                        .font(.system(.caption, design: .monospaced))
                } else {
                    Text("+\(FormatUtil.format(contract.reward)) ISK")
                        .foregroundColor(.green)
                        .font(.system(.caption, design: .monospaced))
                }
            } else {
                // 个人合同：保持原有逻辑
                if isIssuer {
                    Text("-\(FormatUtil.format(contract.reward)) ISK")
                        .foregroundColor(.red)
                        .font(.system(.caption, design: .monospaced))
                } else {
                    Text("+\(FormatUtil.format(contract.reward)) ISK")
                        .foregroundColor(.green)
                        .font(.system(.caption, design: .monospaced))
                }
            }
            
        case "auction":
            // 拍卖合同：保持原有逻辑
            if isIssuer {
                Text("+\(FormatUtil.format(contract.price)) ISK")
                    .foregroundColor(.green)
                    .font(.system(.caption, design: .monospaced))
            } else if isAcceptor {
                Text("-\(FormatUtil.format(contract.price)) ISK")
                    .foregroundColor(.red)
                    .font(.system(.caption, design: .monospaced))
            } else {
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
                databaseManager: databaseManager,
                isCorpContract: isCorpContract
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
