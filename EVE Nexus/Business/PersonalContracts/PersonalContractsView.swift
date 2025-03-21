import SwiftUI

// 按日期分组的合同
struct ContractGroup: Identifiable {
    let id = UUID()
    let date: Date
    var contracts: [ContractInfo]
    let startLocation: String?
    let endLocation: String?

    init(
        date: Date, contracts: [ContractInfo], startLocation: String? = nil,
        endLocation: String? = nil
    ) {
        self.date = date
        self.contracts = contracts
        self.startLocation = startLocation
        self.endLocation = endLocation
    }
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
            Logger.debug("合同类型切换: \(showCorporationContracts ? "军团" : "个人")")
        }
    }

    @Published var isInitialized = false

    @Published var hasCorporationAccess = false
    @Published var courierMode = false {
        didSet {
            // 保存设置到 UserDefaults
            UserDefaults.standard.set(courierMode, forKey: "courierMode_\(characterId)")
            // 当切换模式时，重新分组但不立即更新 UI
            Task {
                // 使用缓存的合同数据重新处理分组
                let contracts =
                    showCorporationContracts ? cachedCorporationContracts : cachedPersonalContracts
                // 先处理数据
                let groups = await processContractGroups(contracts)
                // 一次性更新 UI
                await MainActor.run {
                    self.contractGroups = groups
                }
            }
        }
    }

    private var loadingTask: Task<Void, Never>?
    private var personalContractsInitialized = false
    private var corporationContractsInitialized = false
    private var cachedPersonalContracts: [ContractInfo] = []
    private var cachedCorporationContracts: [ContractInfo] = []
    let characterId: Int
    let databaseManager: DatabaseManager
    private lazy var locationLoader: LocationInfoLoader = .init(
        databaseManager: databaseManager, characterId: Int64(characterId))

    // 添加一个标志来跟踪是否正在进行强制刷新
    private var isForceRefreshing = false

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    // 添加地点名称缓存
    private var locationCache: [Int64: String] = [:]
    // 添加地点名称加载状态追踪
    private var locationLoadingTasks: Set<Int64> = []

    init(characterId: Int) {
        self.characterId = characterId
        databaseManager = DatabaseManager()
        // 初始化时检查军团访问权限
        Task {
            await checkCorporationAccess()
        }

        // 从 UserDefaults 读取快递模式设置
        if let courierModeSetting = UserDefaults.standard.value(
            forKey: "courierMode_\(characterId)") as? Bool
        {
            courierMode = courierModeSetting
        }
    }

    // 检查是否有军团合同访问权限
    private func checkCorporationAccess() async {
        do {
            if try
                (await CharacterDatabaseManager.shared.getCharacterCorporationId(
                    characterId: characterId)) != nil
            {
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

    private func updateContractGroups(with contracts: [ContractInfo]) async {
        let groups = await processContractGroups(contracts)
        await MainActor.run {
            self.contractGroups = groups
        }
    }

    private func loadContractsIfNeeded() async {
        // 取消之前的加载任务
        loadingTask?.cancel()

        // 如果已经加载过且不是强制刷新，直接使用缓存并重新分组
        if showCorporationContracts && corporationContractsInitialized {
            await updateContractGroups(with: cachedCorporationContracts)
            return
        } else if !showCorporationContracts && personalContractsInitialized {
            await updateContractGroups(with: cachedPersonalContracts)
            return
        }

        // 创建新的加载任务
        loadingTask = Task {
            await loadContractsData(forceRefresh: false)
        }

        // 等待任务完成
        await loadingTask?.value
    }

    func loadContractsData(forceRefresh: Bool = false) async {
        // 如果已经在加载中且不是强制刷新，则直接返回
        if isLoading && !forceRefresh {
            return
        }

        // 如果是强制刷新，设置标志
        if forceRefresh {
            isForceRefreshing = true
        }

        // 如果已经加载过且不是强制刷新，直接使用缓存
        if !forceRefresh {
            if showCorporationContracts && corporationContractsInitialized {
                await updateContractGroups(with: cachedCorporationContracts)
                return
            } else if !showCorporationContracts && personalContractsInitialized {
                await updateContractGroups(with: cachedPersonalContracts)
                return
            }
        }

        // 在开始加载前一次性更新 UI 状态
        await MainActor.run {
            isLoading = true
            errorMessage = nil
            currentLoadingPage = nil
            // 只有在非强制刷新（非下拉刷新）时才清空列表
            // 下拉刷新时保留旧数据，直到新数据加载完成
            if !forceRefresh {
                contractGroups = []
            }
        }

        do {
            let contracts: [ContractInfo]

            // 使用 Task.detached 在后台线程加载数据
            let loadedContracts = try await Task.detached(priority: .userInitiated) {
                if await self.showCorporationContracts {
                    // 获取军团合同
                    do {
                        return try await CorporationContractsAPI.shared.fetchContracts(
                            characterId: self.characterId,
                            forceRefresh: forceRefresh,
                            progressCallback: { page in
                                Task { @MainActor in
                                    self.currentLoadingPage = page
                                }
                            }
                        )
                    } catch is CancellationError {
                        throw CancellationError()
                    }
                } else {
                    // 获取个人合同
                    do {
                        return try await CharacterContractsAPI.shared.fetchContracts(
                            characterId: self.characterId,
                            forceRefresh: forceRefresh,
                            progressCallback: { page in
                                Task { @MainActor in
                                    self.currentLoadingPage = page
                                }
                            }
                        )
                    } catch is CancellationError {
                        throw CancellationError()
                    }
                }
            }.value

            // 检查任务是否被取消
            if Task.isCancelled {
                await MainActor.run {
                    isLoading = false
                    currentLoadingPage = nil
                    isForceRefreshing = false
                }
                return
            }

            contracts = loadedContracts

            // 更新缓存
            if showCorporationContracts {
                cachedCorporationContracts = contracts
                corporationContractsInitialized = true
            } else {
                cachedPersonalContracts = contracts
                personalContractsInitialized = true
            }

            // 先处理数据，再一次性更新 UI
            let processedGroups = await processContractGroups(contracts)

            // 一次性更新所有 UI 状态
            await MainActor.run {
                self.contractGroups = processedGroups
                isLoading = false
                currentLoadingPage = nil
                isForceRefreshing = false
                isInitialized = true
            }

        } catch {
            if !(error is CancellationError) {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    Logger.error("加载\(self.showCorporationContracts ? "军团" : "个人")合同数据失败: \(error)")
                    self.isLoading = false
                    self.currentLoadingPage = nil
                    self.isForceRefreshing = false
                }
            } else {
                await MainActor.run {
                    self.isLoading = false
                    self.currentLoadingPage = nil
                    self.isForceRefreshing = false
                }
            }
        }
    }

    deinit {
        loadingTask?.cancel()
    }

    // 修改获取地点名称的方法
    private func getLocationName(_ locationId: Int64) async -> String {
        if let cached = locationCache[locationId] {
            return cached
        }

        // 如果已经在加载中，等待加载完成
        if locationLoadingTasks.contains(locationId) {
            // 最多等待3秒
            for _ in 0..<30 {
                if let cached = locationCache[locationId] {
                    return cached
                }
                try? await Task.sleep(nanoseconds: 100_000_000)  // 等待100ms
            }
            // 如果等待超时，返回未知
            return "Unknown"
        }

        // 标记为正在加载
        locationLoadingTasks.insert(locationId)

        let locationInfos = await locationLoader.loadLocationInfo(locationIds: Set([locationId]))
        if let locationInfo = locationInfos[locationId] {
            let name = locationInfo.solarSystemName
            locationCache[locationId] = name
            locationLoadingTasks.remove(locationId)
            return name
        }
        locationLoadingTasks.remove(locationId)
        return "Unknown"
    }

    // 修改按路线分组合同的方法
    private func groupContractsByRoute(_ contracts: [ContractInfo]) async -> [ContractGroup] {
        // 按路线分组
        var groupedContracts: [String: [ContractInfo]] = [:]
        var routeNames: [String: (start: String, end: String)] = [:]

        // 第一步：收集所有合同并获取位置名称
        for contract in contracts {
            let startId = contract.start_location_id
            let endId = contract.end_location_id
            let routeKey = "\(startId)-\(endId)"

            if groupedContracts[routeKey] == nil {
                groupedContracts[routeKey] = []

                // 异步获取位置名称
                let startName = await getLocationName(startId)
                let endName = await getLocationName(endId)
                routeNames[routeKey] = (start: startName, end: endName)
            }
            groupedContracts[routeKey]?.append(contract)
        }

        // 第二步：创建分组
        var result: [ContractGroup] = []
        for (routeKey, contracts) in groupedContracts {
            let sortedContracts = contracts.sorted { $0.reward > $1.reward }
            if let first = sortedContracts.first,
                let routeName = routeNames[routeKey]
            {
                result.append(
                    ContractGroup(
                        date: first.date_issued,
                        contracts: sortedContracts,
                        startLocation: routeName.start,
                        endLocation: routeName.end
                    ))
            }
        }

        // 第三步：按照奖励排序
        return result.sorted { $0.contracts[0].reward > $1.contracts[0].reward }
    }

    // 新增方法：处理合同数据并返回分组，但不更新 UI
    private func processContractGroups(_ contracts: [ContractInfo]) async -> [ContractGroup] {
        if courierMode {
            // 快递模式
            return await groupContractsByRoute(contracts)
        } else {
            // 普通模式的分组逻辑
            var groupedContracts: [Date: [ContractInfo]] = [:]
            for contract in contracts {
                let date = calendar.startOfDay(for: contract.date_issued)
                if groupedContracts[date] == nil {
                    groupedContracts[date] = []
                }
                groupedContracts[date]?.append(contract)
            }

            // 创建分组并排序
            return groupedContracts.map { date, contracts in
                ContractGroup(
                    date: date,
                    contracts: contracts.sorted { $0.date_issued > $1.date_issued }
                )
            }.sorted { $0.date > $1.date }
        }
    }
}

struct PersonalContractsView: View {
    @StateObject private var viewModel: PersonalContractsViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var showSettings = false

    // 使用计算属性来获取和设置带有角色ID的AppStorage键
    private var showActiveOnlyKey: String { "showActiveOnly_\(viewModel.characterId)" }
    private var showCourierContractsKey: String { "showCourierContracts_\(viewModel.characterId)" }
    private var showItemExchangeContractsKey: String {
        "showItemExchangeContracts_\(viewModel.characterId)"
    }

    private var showAuctionContractsKey: String { "showAuctionContracts_\(viewModel.characterId)" }
    private var maxContractsKey: String { "maxContracts_\(viewModel.characterId)" }

    // 使用@AppStorage并使用动态key
    @AppStorage("") private var showActiveOnly: Bool = false
    @AppStorage("") private var showCourierContracts: Bool = true
    @AppStorage("") private var showItemExchangeContracts: Bool = true
    @AppStorage("") private var showAuctionContracts: Bool = true
    @AppStorage("") private var maxContracts: Int = 300
    @AppStorage("") private var courierMode: Bool = false

    private let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")!
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    init(characterId: Int) {
        // 先创建ViewModel实例
        let vm = PersonalContractsViewModel(characterId: characterId)
        _viewModel = StateObject(wrappedValue: vm)

        // 初始化@AppStorage的key
        _showActiveOnly = AppStorage(wrappedValue: false, "showActiveOnly_\(characterId)")
        _showCourierContracts = AppStorage(
            wrappedValue: true, "showCourierContracts_\(characterId)"
        )
        _showItemExchangeContracts = AppStorage(
            wrappedValue: true, "showItemExchangeContracts_\(characterId)"
        )
        _showAuctionContracts = AppStorage(
            wrappedValue: true, "showAuctionContracts_\(characterId)"
        )
        _maxContracts = AppStorage(wrappedValue: 300, "maxContracts_\(characterId)")
        _courierMode = AppStorage(wrappedValue: false, "courierMode_\(characterId)")

        // 在初始化后立即开始加载数据，但不在闭包中捕获self
        Task {
            Logger.debug("PersonalContractsView - 初始化时加载数据")
            // 等待数据加载完成
            await vm.loadContractsData()

            // 使用MainActor确保在主线程上更新UI状态
            // 数据加载完成后，一次性更新 UI 状态
            await MainActor.run {
                vm.isInitialized = true
            }
        }
    }

    // 修改过滤逻辑
    private var filteredContractGroups: [ContractGroup] {
        if courierMode {
            // 快递模式：只显示未完成的快递合同
            let filteredGroups = viewModel.contractGroups.compactMap { group -> ContractGroup? in
                let filteredContracts = group.contracts.filter { contract in
                    contract.type == "courier" && contract.status == "outstanding"
                }.sorted { $0.reward > $1.reward }  // 按照奖励金额从高到低排序

                return filteredContracts.isEmpty
                    ? nil
                    : ContractGroup(
                        date: group.date,
                        contracts: filteredContracts,
                        startLocation: group.startLocation,
                        endLocation: group.endLocation
                    )
            }
            // 按照组内第一个合同（最高奖励）的奖励金额排序
            return filteredGroups.sorted {
                $0.contracts[0].reward > $1.contracts[0].reward
            }
        } else {
            // 先按照设置过滤合同
            let filteredGroups = viewModel.contractGroups.compactMap { group -> ContractGroup? in
                // 过滤每个组内的合同
                let filteredContracts = group.contracts.filter { contract in
                    // 根据设置过滤合同
                    let showByType =
                        (contract.type == "courier" && showCourierContracts)
                        || (contract.type == "item_exchange" && showItemExchangeContracts)
                        || (contract.type == "auction" && showAuctionContracts)

                    let showByStatus = !showActiveOnly || contract.status == "outstanding"

                    return showByType && showByStatus
                }

                // 如果过滤后该组没有合同，返回nil（这样compactMap会自动移除这个组）
                return filteredContracts.isEmpty
                    ? nil
                    : ContractGroup(
                        date: group.date,
                        contracts: filteredContracts,
                        startLocation: group.startLocation,
                        endLocation: group.endLocation
                    )
            }.sorted { $0.date > $1.date }

            // 计算所有合同的总数
            var totalContracts = 0
            var limitedGroups: [ContractGroup] = []
            // 遍历排序后的组，直到达到maxContracts个合同的限制
            for group in filteredGroups {
                let remainingSlots = maxContracts - totalContracts
                if remainingSlots <= 0 {
                    break
                }

                if totalContracts + group.contracts.count <= maxContracts {
                    // 如果添加整个组不会超过限制，直接添加
                    limitedGroups.append(group)
                    totalContracts += group.contracts.count
                } else {
                    // 如果添加整个组会超过限制，只添加部分合同
                    let limitedContracts = Array(group.contracts.prefix(remainingSlots))
                    limitedGroups.append(
                        ContractGroup(
                            date: group.date,
                            contracts: limitedContracts,
                            startLocation: group.startLocation,
                            endLocation: group.endLocation
                        ))
                    break
                }
            }

            return limitedGroups
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                // 加载进度部分
                if viewModel.isLoading || viewModel.currentLoadingPage != nil {
                    Section {
                        HStack {
                            Spacer()
                            if let currentPage = viewModel.currentLoadingPage {
                                let text = String(
                                    format: NSLocalizedString(
                                        "Contract_Loading_Fetching", comment: "正在获取第 %d 页数据"
                                    ), currentPage
                                )

                                Text(text)
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 12)
                                    .background(Color(.secondarySystemGroupedBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            } else if viewModel.isLoading {
                                ProgressView()
                                    .progressViewStyle(.circular)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 12)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }
                }

                if filteredContractGroups.isEmpty && !viewModel.isLoading {
                    emptyView
                } else if !viewModel.isLoading || viewModel.isInitialized {
                    ForEach(filteredContractGroups) { group in
                        Section {
                            ForEach(group.contracts) { contract in
                                ContractRow(
                                    contract: contract,
                                    isCorpContract: viewModel.showCorporationContracts,
                                    databaseManager: viewModel.databaseManager
                                )
                            }
                        } header: {
                            if courierMode {
                                if let start = group.startLocation, let end = group.endLocation {
                                    Text(
                                        String(
                                            format: NSLocalizedString(
                                                "Contract_Route_Format", comment: ""
                                            ), start, end
                                        )
                                    )
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                    .textCase(nil)
                                }
                            } else {
                                Text(displayDateFormatter.string(from: group.date))
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                    .textCase(nil)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable {
                // 在刷新时重置加载状态
                await MainActor.run {
                    viewModel.currentLoadingPage = nil
                }
                await viewModel.loadContractsData(forceRefresh: true)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                if viewModel.hasCorporationAccess {
                    VStack(spacing: 4) {
                        Picker("Contract Type", selection: $viewModel.showCorporationContracts) {
                            Text(NSLocalizedString("Contracts_Personal", comment: ""))
                                .tag(false)
                            Text(NSLocalizedString("Contracts_Corporation", comment: ""))
                                .tag(true)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        .padding(.top, 4)
                        // 在加载过程中禁用 Picker
                        .disabled(viewModel.isLoading || viewModel.currentLoadingPage != nil)

                        // 计算总合同数和过滤后的合同数
                        let totalCount = viewModel.contractGroups.reduce(0) { count, group in
                            count + group.contracts.count
                        }

                        if courierMode {
                            // 计算活跃的快递合同数量
                            let activeCourierCount = viewModel.contractGroups.reduce(0) {
                                count, group in
                                count
                                    + group.contracts.filter { contract in
                                        contract.type == "courier"
                                            && contract.status == "outstanding"
                                    }.count
                            }

                            let countText =
                                activeCourierCount > maxContracts
                                ? String(
                                    format: NSLocalizedString(
                                        "Contract_Courier_Active_Count_Limited", comment: ""
                                    ),
                                    activeCourierCount, maxContracts
                                )
                                : String(
                                    format: NSLocalizedString(
                                        "Contract_Courier_Active_Count", comment: ""
                                    ),
                                    activeCourierCount
                                )

                            (Text(
                                "(" + NSLocalizedString("Contract_Courier_Mode", comment: "") + ")"
                            ).foregroundColor(.red) + Text(" ")
                                + Text(countText).foregroundColor(.secondary))
                                .font(.caption)
                                .padding(.bottom, 4)
                        } else {
                            let filteredCount = viewModel.contractGroups.reduce(0) { count, group in
                                count
                                    + group.contracts.filter { contract in
                                        let showByType =
                                            (contract.type == "courier" && showCourierContracts)
                                            || (contract.type == "item_exchange"
                                                && showItemExchangeContracts)
                                            || (contract.type == "auction" && showAuctionContracts)

                                        let showByStatus =
                                            !showActiveOnly || contract.status == "outstanding"

                                        return showByType && showByStatus
                                    }.count
                            }

                            if filteredCount > maxContracts {
                                Text(
                                    String(
                                        format: NSLocalizedString(
                                            "Contract_Filtered_Limited", comment: ""
                                        ), totalCount,
                                        filteredCount, maxContracts
                                    )
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.bottom, 4)
                            } else if filteredCount < totalCount {
                                Text(
                                    String(
                                        format: NSLocalizedString(
                                            "Contract_Filtered_Count", comment: ""
                                        ), totalCount,
                                        filteredCount
                                    )
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.bottom, 4)
                            } else {
                                Text(
                                    String(
                                        format: NSLocalizedString(
                                            "Contract_Total_Count", comment: ""
                                        ), totalCount
                                    )
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.bottom, 4)
                            }
                        }
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
        }
        .sheet(isPresented: $showSettings) {
            NavigationView {
                Form {
                    Section {
                        Toggle(
                            isOn: Binding(
                                get: { courierMode },
                                set: { newValue in
                                    courierMode = newValue
                                    viewModel.courierMode = newValue
                                }
                            )
                        ) {
                            VStack(alignment: .leading) {
                                Text(NSLocalizedString("Contract_Courier_Mode", comment: ""))
                                Text(
                                    NSLocalizedString(
                                        "Contract_Courier_Mode_Description", comment: ""
                                    )
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                        }
                    }

                    if !courierMode {
                        Section {
                            Toggle(isOn: $showActiveOnly) {
                                Text(NSLocalizedString("Contract_Show_Active_Only", comment: ""))
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

                    Section {
                        Picker(
                            NSLocalizedString("Contract_Max_Display", comment: ""),
                            selection: $maxContracts
                        ) {
                            Text(NSLocalizedString("Contract_Display_50", comment: "")).tag(50)
                            Text(NSLocalizedString("Contract_Display_100", comment: "")).tag(100)
                            Text(NSLocalizedString("Contract_Display_300", comment: "")).tag(300)
                            Text(NSLocalizedString("Contract_Display_500", comment: "")).tag(500)
                            Text(NSLocalizedString("Contract_Display_Unlimited", comment: "")).tag(
                                Int.max)
                        }
                        .pickerStyle(.navigationLink)
                    } header: {
                        Text(NSLocalizedString("Contract_Display_Limit", comment: ""))
                    } footer: {
                        Text(NSLocalizedString("Contract_Display_Limit_Warning", comment: ""))
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
        // 修改onChange监听器，添加延迟加载机制
        .onChange(of: viewModel.showCorporationContracts) { oldValue, newValue in
            Logger.debug("合同类型切换: \(oldValue) -> \(newValue)")
            // 只有在类型真正变化时才加载数据
            if oldValue != newValue {
                // 使用单一任务加载数据，添加短暂延迟
                Task {
                    // 添加短暂延迟，避免在同一帧内多次更新
                    try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1秒延迟
                    // 等待数据加载完成
                    await viewModel.loadContractsData(forceRefresh: false)
                }
            }
        }
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
        // 修改为传统的 NavigationLink
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
                        Text(
                            NSLocalizedString("Contract_Volume", comment: "")
                                + ": \(FormatUtil.format(contract.volume)) m³"
                        )
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
