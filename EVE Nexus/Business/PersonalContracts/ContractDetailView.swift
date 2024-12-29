import SwiftUI

// 导入必要的类型
typealias ContractItemInfo = CharacterContractsAPI.ContractItemInfo

struct UniverseNameResponse: Codable {
    let category: String
    let id: Int
    let name: String
}

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
    let databaseManager: DatabaseManager
    private lazy var locationLoader: LocationInfoLoader = {
        LocationInfoLoader(databaseManager: databaseManager, characterId: Int64(characterId))
    }()
    
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
        return items
            .filter { $0.is_included }
            .sorted { item1, item2 in
                item1.record_id < item2.record_id
            }
    }
    
    var sortedRequiredItems: [ContractItemInfo] {
        return items
            .filter { !$0.is_included }
            .sorted { item1, item2 in
                item1.record_id < item2.record_id
            }
    }
    
    init(characterId: Int, contract: ContractInfo, databaseManager: DatabaseManager) {
        self.characterId = characterId
        self.contract = contract
        self.databaseManager = databaseManager
    }
    
    func loadContractItems(forceRefresh: Bool = false) async {
        Logger.debug("开始加载合同物品 - 角色ID: \(characterId), 合同ID: \(contract.contract_id), 强制刷新: \(forceRefresh)")
        isLoading = true
        errorMessage = nil
        
        do {
            items = try await CharacterContractsAPI.shared.fetchContractItems(
                characterId: characterId,
                contractId: contract.contract_id,
                forceRefresh: forceRefresh
            )
            Logger.debug("成功加载合同物品 - 数量: \(items.count)")
            isLoading = false
        } catch {
            Logger.error("加载合同物品失败: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
    
    func loadContractParties() async {
        isLoadingNames = true
        var ids = Set<Int>()
        
        // 添加人物和军团ID
        Logger.debug("开始加载合同相关方信息 - 发起人ID: \(contract.issuer_id), 军团ID: \(contract.issuer_corporation_id)")
        
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
                self.issuerName = name
            } else {
                Logger.error("未找到发起人名称 - ID: \(contract.issuer_id)")
            }
            
            if let corpName = names[contract.issuer_corporation_id] {
                Logger.debug("获取到军团名称: \(corpName)")
                self.issuerCorpName = corpName
            } else {
                Logger.error("未找到军团名称 - ID: \(contract.issuer_corporation_id)")
            }
            
            if let assigneeId = contract.assignee_id,
               let assigneeName = names[assigneeId] {
                Logger.debug("获取到指定人名称: \(assigneeName)")
                self.assigneeName = assigneeName
            }
            
            if let acceptorId = contract.acceptor_id,
               let acceptorName = names[acceptorId] {
                Logger.debug("获取到接受人名称: \(acceptorName)")
                self.acceptorName = acceptorName
            }
            
            isLoadingNames = false
        } catch {
            Logger.error("加载合同相关方名称失败: \(error)")
            isLoadingNames = false
        }
    }
    
    func getItemDetails(for typeId: Int) -> (name: String, description: String, iconFileName: String)? {
        let query = """
            SELECT name, description, icon_filename
            FROM types
            WHERE type_id = ?
        """
        
        let result = databaseManager.executeQuery(query, parameters: [typeId])
        
        if case .success(let rows) = result,
           let row = rows.first,
           let name = row["name"] as? String,
           let description = row["description"] as? String,
           let iconFileName = row["icon_filename"] as? String {
            return (
                name: name,
                description: description,
                iconFileName: iconFileName.isEmpty ? DatabaseConfig.defaultItemIcon : iconFileName
            )
        }
        return nil
    }
}

struct ContractDetailView: View {
    let contract: ContractInfo
    @StateObject private var viewModel: ContractDetailViewModel
    
    init(characterId: Int, contract: ContractInfo, databaseManager: DatabaseManager) {
        self.contract = contract
        _viewModel = StateObject(wrappedValue: ContractDetailViewModel(
            characterId: characterId,
            contract: contract,
            databaseManager: databaseManager
        ))
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
                        VStack(alignment: .leading, spacing: 4) {
                            Text(NSLocalizedString("Contract_Type", comment: ""))
                            Text("\(NSLocalizedString("Contract_Type_\(contract.type)", comment: "")) [\(NSLocalizedString("Contract_Status_\(contract.status)", comment: ""))]")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(height: 36)
                        
                        // 地点信息
                        if let startInfo = viewModel.startLocationInfo {
                            if contract.start_location_id == contract.end_location_id {
                                // 如果起点和终点相同，显示单个地点
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(NSLocalizedString("Contract_Location", comment: ""))
                                    LocationInfoView(
                                        stationName: startInfo.stationName,
                                        solarSystemName: startInfo.solarSystemName,
                                        security: startInfo.security
                                    )
                                }
                                .frame(height: 36)
                            } else {
                                // 显示起点
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(NSLocalizedString("Contract_Start_Location", comment: ""))
                                    LocationInfoView(
                                        stationName: startInfo.stationName,
                                        solarSystemName: startInfo.solarSystemName,
                                        security: startInfo.security
                                    )
                                }
                                .frame(height: 36)
                                
                                // 显示终点（如果存在）
                                if let endInfo = viewModel.endLocationInfo {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(NSLocalizedString("Contract_End_Location", comment: ""))
                                        LocationInfoView(
                                            stationName: endInfo.stationName,
                                            solarSystemName: endInfo.solarSystemName,
                                            security: endInfo.security
                                        )
                                    }
                                    .frame(height: 36)
                                }
                            }
                        }
                        
                        // 合同发起人
                        VStack(alignment: .leading, spacing: 4) {
                            Text(NSLocalizedString("Contract_Issuer", comment: ""))
                            HStack(spacing: 4) {
                                Text(viewModel.issuerName.isEmpty ? "Unknown" : viewModel.issuerName)
                                if !viewModel.issuerCorpName.isEmpty {
                                    Text("[\(viewModel.issuerCorpName)]")
                                }
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        .frame(height: 36)
                        
                        // 合同对象（如果存在）
                        if !viewModel.assigneeName.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(NSLocalizedString("Contract_Assignee", comment: ""))
                                Text(viewModel.assigneeName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(height: 36)
                        }
                        
                        // 如果接收人存在且与对象不同，显示接收人
                        if let acceptorId = contract.acceptor_id,
                           acceptorId > 0,
                           !viewModel.acceptorName.isEmpty && 
                           viewModel.acceptorName != viewModel.assigneeName {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(NSLocalizedString("Contract_Acceptor", comment: ""))
                                Text(viewModel.acceptorName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(height: 36)
                        }
                        
                        // 合同价格（如果有）
                        if contract.price > 0 {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(NSLocalizedString("Contract_Price", comment: ""))
                                Text("\(FormatUtil.format(contract.price)) ISK")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(height: 36)
                        }
                        
                        // 合同报酬（如果有）
                        if contract.reward > 0 {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(NSLocalizedString("Contract_Reward", comment: ""))
                                Text("\(FormatUtil.format(contract.reward)) ISK")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(height: 36)
                        }
                        
                        // 保证金（如果有）
                        if contract.collateral > 0 {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(NSLocalizedString("Contract_Collateral", comment: ""))
                                Text("\(FormatUtil.format(contract.collateral)) ISK")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(height: 36)
                        }
                        
                        // 体积
//                        if contract.volume > 0 {
//                            VStack(alignment: .leading, spacing: 4) {
//                                Text(NSLocalizedString("Contract_Volume", comment: ""))
//                                Text("\(FormatUtil.format(contract.volume)) m3")
//                                    .font(.caption)
//                                    .foregroundColor(.secondary)
//                            }
//                            .frame(height: 36)
//                        }
                        
                        // 完成期限
                        if contract.days_to_complete > 0 {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(NSLocalizedString("Contract_Days_To_Complete", comment: ""))
                                Text("\(contract.days_to_complete)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(height: 36)
                        }
                    } header: {
                        Text(NSLocalizedString("Contract_Basic_Info", comment: ""))
                            .fontWeight(.bold)
                            .font(.system(size: 18))
                            .foregroundColor(.primary)
                            .textCase(.none)
                    }
                    
                    // 提供的物品列表
                    if !viewModel.sortedIncludedItems.isEmpty {
                        Section {
                            ForEach(viewModel.sortedIncludedItems) { item in
                                if let itemDetails = viewModel.getItemDetails(for: item.type_id) {
                                    ContractItemRow(item: item, itemDetails: itemDetails, databaseManager: viewModel.databaseManager)
                                        .frame(height: 36)
                                }
                            }
                        } header: {
                            Text(NSLocalizedString("Contract_Items_Included", comment: ""))
                                .fontWeight(.bold)
                                .font(.system(size: 18))
                                .foregroundColor(.primary)
                                .textCase(.none)
                        }
                    }
                    
                    // 需求的物品列表
                    if !viewModel.sortedRequiredItems.isEmpty {
                        Section {
                            ForEach(viewModel.sortedRequiredItems) { item in
                                if let itemDetails = viewModel.getItemDetails(for: item.type_id) {
                                    ContractItemRow(item: item, itemDetails: itemDetails, databaseManager: viewModel.databaseManager)
                                        .frame(height: 36)
                                }
                            }
                        } header: {
                            Text(NSLocalizedString("Contract_Items_Required", comment: ""))
                                .fontWeight(.bold)
                                .font(.system(size: 18))
                                .foregroundColor(.primary)
                                .textCase(.none)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .task {
            Logger.debug("ContractDetailView.task 开始执行")
            // 并行加载数据
            async let itemsTask: () = viewModel.loadContractItems()
            async let namesTask: () = viewModel.loadContractParties()
            await (_, _) = (itemsTask, namesTask)
            Logger.debug("ContractDetailView.task 执行完成")
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
