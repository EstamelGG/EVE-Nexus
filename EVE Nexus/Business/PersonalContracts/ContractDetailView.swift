import SwiftUI

// 导入必要的类型
typealias ContractItemInfo = CharacterContractsAPI.ContractItemInfo

@MainActor
final class ContractDetailViewModel: ObservableObject {
    @Published private(set) var items: [ContractItemInfo] = []
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published private(set) var issuerName: String = ""
    @Published private(set) var issuerCorpName: String = ""
    @Published private(set) var assigneeName: String = ""
    @Published private(set) var acceptorName: String = ""
    @Published private(set) var startLocationInfo: LocationInfo?
    @Published private(set) var endLocationInfo: LocationInfo?
    @Published var isLoadingNames = true

    private let characterId: Int
    private let contract: ContractInfo
    private let isCorpContract: Bool
    let databaseManager: DatabaseManager
    private lazy var locationLoader: LocationInfoLoader = .init(
        databaseManager: databaseManager, characterId: Int64(characterId))

    // 添加物品信息缓存
    private var itemDetailsCache: [Int: (name: String, description: String, iconFileName: String)] =
        [:]

    struct LocationInfo {
        let stationName: String
        let solarSystemName: String
        let security: Double

        init(stationName: String, solarSystemName: String, security: Double) {
            self.stationName = stationName
            self.solarSystemName = solarSystemName
            self.security = security
        }
    }

    // 添加排序后的物品列表计算属性
    var sortedIncludedItems: [ContractItemInfo] {
        return
            items
            .filter { $0.is_included }
            .sorted { item1, item2 in
                item1.record_id < item2.record_id
            }
    }

    var sortedRequiredItems: [ContractItemInfo] {
        return
            items
            .filter { !$0.is_included }
            .sorted { item1, item2 in
                item1.record_id < item2.record_id
            }
    }

    init(
        characterId: Int, contract: ContractInfo, databaseManager: DatabaseManager,
        isCorpContract: Bool
    ) {
        self.characterId = characterId
        self.contract = contract
        self.databaseManager = databaseManager
        self.isCorpContract = isCorpContract
    }

    // 批量加载物品详细信息
    private func loadItemDetails(for items: [ContractItemInfo]) {
        let typeIds = Set(items.map { $0.type_id })
        let query = """
                SELECT type_id, name, description, icon_filename
                FROM types
                WHERE type_id IN (\(typeIds.sorted().map { String($0) }.joined(separator: ",")))
            """

        let result = databaseManager.executeQuery(query)
        if case let .success(rows) = result {
            for row in rows {
                if let typeId = (row["type_id"] as? Int64).map(Int.init)
                    ?? (row["type_id"] as? Int),
                    let name = row["name"] as? String,
                    let description = row["description"] as? String,
                    let iconFileName = row["icon_filename"] as? String
                {
                    itemDetailsCache[typeId] = (
                        name: name,
                        description: description,
                        iconFileName: iconFileName.isEmpty
                            ? DatabaseConfig.defaultItemIcon : iconFileName
                    )
                }
            }
        }
        Logger.debug("已缓存 \(itemDetailsCache.count) 个物品信息")
    }

    func getItemDetails(for typeId: Int) -> (
        name: String, description: String, iconFileName: String
    )? {
        // 从缓存中获取
        if let cachedDetails = itemDetailsCache[typeId] {
            return cachedDetails
        }

        // 如果缓存中没有，返回默认值
        return (
            name: "Unknown Item",
            description: "",
            iconFileName: DatabaseConfig.defaultItemIcon
        )
    }

    func loadContractItems(forceRefresh: Bool = false) async {
        Logger.debug(
            "开始加载合同物品 - 角色ID: \(characterId), 合同ID: \(contract.contract_id), 强制刷新: \(forceRefresh), 是否军团合同: \(isCorpContract)"
        )
        isLoading = true
        errorMessage = nil

        await withTaskCancellationHandler(
            operation: {
                do {
                    if isCorpContract {
                        items = try await CorporationContractsAPI.shared.fetchContractItems(
                            characterId: characterId,
                            contractId: contract.contract_id
                        )
                    } else {
                        items = try await CharacterContractsAPI.shared.fetchContractItems(
                            characterId: characterId,
                            contractId: contract.contract_id,
                            forceRefresh: forceRefresh
                        )
                    }

                    // 批量加载物品详细信息
                    loadItemDetails(for: items)

                    isLoading = false
                } catch is CancellationError {
                    Logger.debug("合同物品加载任务被取消 - 合同ID: \(contract.contract_id)")
                } catch {
                    Logger.error("加载合同物品失败: \(error.localizedDescription)")
                    errorMessage = error.localizedDescription
                }
            },
            onCancel: {
                Task { @MainActor in
                    isLoading = false
                    Logger.debug("合同物品加载任务被取消，清理状态 - 合同ID: \(contract.contract_id)")
                }
            }
        )
    }

    func loadContractParties() async {
        isLoadingNames = true
        var ids = Set<Int>()

        // 添加人物和军团ID
        Logger.debug(
            "开始加载合同相关方信息 - 发起人ID: \(contract.issuer_id), 军团ID: \(contract.issuer_corporation_id)")

        // 添加发起人ID
        ids.insert(contract.issuer_id)
        ids.insert(contract.issuer_corporation_id)

        // 添加其他相关方ID
        if let assigneeId = contract.assignee_id {
            ids.insert(assigneeId)
        }
        if let acceptorId = contract.acceptor_id {
            ids.insert(acceptorId)
        }

        // 加载位置信息
        let locationIds = Set<Int64>([contract.start_location_id, contract.end_location_id])
        Logger.debug("开始加载位置信息 - 位置IDs: \(locationIds)")
        let locationInfos = await locationLoader.loadLocationInfo(locationIds: locationIds)

        // 更新位置信息
        if let startInfo = locationInfos[contract.start_location_id] {
            startLocationInfo = LocationInfo(
                stationName: startInfo.stationName,
                solarSystemName: startInfo.solarSystemName,
                security: startInfo.security
            )
            Logger.debug("已加载起始位置信息: \(startInfo.stationName)")
        }

        if let endInfo = locationInfos[contract.end_location_id] {
            endLocationInfo = LocationInfo(
                stationName: endInfo.stationName,
                solarSystemName: endInfo.solarSystemName,
                security: endInfo.security
            )
            Logger.debug("已加载目标位置信息: \(endInfo.stationName)")
        }

        do {
            Logger.debug("开始获取名称信息，IDs: \(ids)")
            let names = try await UniverseNameCache.shared.getNames(for: ids)

            // 更新名称
            if let name = names[contract.issuer_id] {
                Logger.debug("获取到发起人名称: \(name)")
                issuerName = name
            } else {
                Logger.error("未找到发起人名称 - ID: \(contract.issuer_id)")
            }

            if let corpName = names[contract.issuer_corporation_id] {
                Logger.debug("获取到军团名称: \(corpName)")
                issuerCorpName = corpName
            } else {
                Logger.error("未找到军团名称 - ID: \(contract.issuer_corporation_id)")
            }

            if let assigneeId = contract.assignee_id,
                let assigneeName = names[assigneeId]
            {
                Logger.debug("获取到指定人名称: \(assigneeName)")
                self.assigneeName = assigneeName
            }

            if let acceptorId = contract.acceptor_id, acceptorId > 0,
                let acceptorName = names[acceptorId]
            {
                Logger.debug("获取到接受人名称: \(acceptorName)")
                self.acceptorName = acceptorName
            }

            isLoadingNames = false
        } catch {
            Logger.error("加载合同相关方名称失败: \(error)")
            isLoadingNames = false
        }
    }
}

struct ContractDetailView: View {
    let contract: ContractInfo
    @StateObject private var viewModel: ContractDetailViewModel
    @State private var isRefreshing = false
    @State private var hasLoadedInitialData = false

    init(
        characterId: Int, contract: ContractInfo, databaseManager: DatabaseManager,
        isCorpContract: Bool
    ) {
        self.contract = contract
        _viewModel = StateObject(
            wrappedValue: ContractDetailViewModel(
                characterId: characterId,
                contract: contract,
                databaseManager: databaseManager,
                isCorpContract: isCorpContract
            ))
    }

    // 根据状态返回对应的颜色
    private func getStatusColor(_ status: String) -> Color {
        switch status {
        case "deleted", "cancelled":
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

    var body: some View {
        ZStack {
            if viewModel.isLoading || viewModel.isLoadingNames {
                ProgressView()
            } else {
                List {
                    // 合同基本信息
                    Section {
                        // 合同类型
                        VStack(alignment: .leading, spacing: 2) {
                            Text(NSLocalizedString("Contract_Type", comment: ""))
                            (Text(
                                "\(NSLocalizedString("Contract_Type_\(contract.type)", comment: "")) "
                            )
                            .foregroundColor(.secondary)
                                + Text(
                                    "[\(NSLocalizedString("Contract_Status_\(contract.status)", comment: ""))]"
                                )
                                .foregroundColor(getStatusColor(contract.status)))
                                .font(.caption)
                        }

                        // 地点信息
                        if let startInfo = viewModel.startLocationInfo {
                            if contract.start_location_id == contract.end_location_id {
                                // 如果起点和终点相同，显示单个地点
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(NSLocalizedString("Contract_Location", comment: ""))
                                    LocationInfoView(
                                        stationName: startInfo.stationName,
                                        solarSystemName: startInfo.solarSystemName,
                                        security: startInfo.security
                                    )
                                }
                            } else {
                                // 显示起点
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(NSLocalizedString("Contract_Start_Location", comment: ""))
                                    LocationInfoView(
                                        stationName: startInfo.stationName,
                                        solarSystemName: startInfo.solarSystemName,
                                        security: startInfo.security
                                    )
                                }
                                // 显示终点（如果存在）
                                if let endInfo = viewModel.endLocationInfo {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(
                                            NSLocalizedString("Contract_End_Location", comment: ""))
                                        LocationInfoView(
                                            stationName: endInfo.stationName,
                                            solarSystemName: endInfo.solarSystemName,
                                            security: endInfo.security
                                        )
                                    }
                                }
                            }
                        }

                        // 合同发起人
                        VStack(alignment: .leading, spacing: 2) {
                            Text(NSLocalizedString("Contract_Issuer", comment: ""))
                            HStack(spacing: 4) {
                                Text(
                                    viewModel.issuerName.isEmpty
                                        ? NSLocalizedString("Unknown", comment: "")
                                        : viewModel.issuerName)
                                if !viewModel.issuerCorpName.isEmpty {
                                    Text("[\(viewModel.issuerCorpName)]")
                                }
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }

                        // 合同对象（如果存在）
                        if let assigneeId = contract.assignee_id,
                            assigneeId > 0,
                            !viewModel.assigneeName.isEmpty
                        {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(NSLocalizedString("Contract_Assignee", comment: ""))
                                Text(viewModel.assigneeName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        // 如果接收人存在且与对象不同，显示接收人
                        if let acceptorId = contract.acceptor_id,
                            acceptorId > 0,
                            !viewModel.acceptorName.isEmpty
                                && viewModel.acceptorName != viewModel.assigneeName
                        {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(NSLocalizedString("Contract_Acceptor", comment: ""))
                                Text(viewModel.acceptorName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        // 合同价格（如果有）
                        if contract.price > 0 {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(NSLocalizedString("Contract_Price", comment: ""))
                                Text(
                                    "\(FormatUtil.format(contract.price)) ISK (\(FormatUtil.formatISK(contract.price)))"
                                )
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                            }
                        }

                        // 合同报酬（如果有）
                        if contract.reward > 0 {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(NSLocalizedString("Contract_Reward", comment: ""))
                                Text(
                                    "\(FormatUtil.format(contract.reward)) ISK (\(FormatUtil.formatISK(contract.reward)))"
                                )
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                            }
                        }

                        // 保证金（如果有）
                        if contract.collateral ?? 0 > 0 {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(NSLocalizedString("Contract_Collateral", comment: ""))
                                Text(
                                    "\(FormatUtil.format(contract.collateral ?? 0)) ISK (\(FormatUtil.formatISK(contract.collateral ?? 0)))"
                                )
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                            }
                        }

                        // 完成期限
                        if contract.days_to_complete > 0 {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(NSLocalizedString("Contract_Days_To_Complete", comment: ""))
                                Text("\(contract.days_to_complete)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } header: {
                        Text(NSLocalizedString("Contract_Basic_Info", comment: ""))
                            .fontWeight(.semibold)
                            .font(.system(size: 18))
                            .foregroundColor(.primary)
                            .textCase(.none)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

                    // 提供的物品列表
                    if !viewModel.sortedIncludedItems.isEmpty {
                        Section {
                            ForEach(viewModel.sortedIncludedItems) { item in
                                if let itemDetails = viewModel.getItemDetails(for: item.type_id) {
                                    ContractItemRow(
                                        item: item, itemDetails: itemDetails,
                                        databaseManager: viewModel.databaseManager
                                    )
                                }
                            }
                        } header: {
                            Text(NSLocalizedString("Contract_Items_Included", comment: ""))
                                .fontWeight(.semibold)
                                .font(.system(size: 18))
                                .foregroundColor(.primary)
                                .textCase(.none)
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }

                    // 需求的物品列表
                    if !viewModel.sortedRequiredItems.isEmpty {
                        Section {
                            ForEach(viewModel.sortedRequiredItems) { item in
                                if let itemDetails = viewModel.getItemDetails(for: item.type_id) {
                                    ContractItemRow(
                                        item: item, itemDetails: itemDetails,
                                        databaseManager: viewModel.databaseManager
                                    )
                                }
                            }
                        } header: {
                            Text(NSLocalizedString("Contract_Items_Required", comment: ""))
                                .fontWeight(.semibold)
                                .font(.system(size: 18))
                                .foregroundColor(.primary)
                                .textCase(.none)
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }
                }
                .refreshable {
                    Logger.debug("开始下拉刷新合同物品")
                    isRefreshing = true
                    // 使用Task来管理刷新操作
                    await Task {
                        await viewModel.loadContractItems(forceRefresh: true)
                    }.value
                    isRefreshing = false
                }
                .listStyle(.insetGrouped)
            }
        }
        .task {
            guard !hasLoadedInitialData else { return }
            Logger.debug("ContractDetailView.task 开始执行初始数据加载")
            // 使用withTaskGroup来更好地管理并发任务
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await viewModel.loadContractItems() }
                group.addTask { await viewModel.loadContractParties() }
            }
            hasLoadedInitialData = true
            Logger.debug("ContractDetailView.task 初始数据加载完成")
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !viewModel.items.isEmpty {
                    NavigationLink {
                        ContractAppraisalView(contract: contract, items: viewModel.items)
                    } label: {
                        Image(systemName: "list.clipboard")
                    }
                }
            }
        }
    }
}

struct ContractItemRow: View {
    let item: ContractItemInfo
    let itemDetails: (name: String, description: String, iconFileName: String)
    let databaseManager: DatabaseManager

    var body: some View {
        NavigationLink {
            MarketItemDetailView(databaseManager: databaseManager, itemID: item.type_id)
        } label: {
            HStack {
                // 物品图标
                IconManager.shared.loadImage(for: itemDetails.iconFileName)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(4)
                // 物品名称
                Text("\(itemDetails.name)")
                    .font(.body)
                Spacer()
                // 物品数量和包含状态
                HStack {
                    Text("\(item.quantity) \(NSLocalizedString("Misc_number_item_x", comment: ""))")
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
    }
}
