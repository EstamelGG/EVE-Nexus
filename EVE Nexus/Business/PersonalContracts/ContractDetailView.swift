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
    @Published private(set) var assigneeName: String = ""
    @Published private(set) var acceptorName: String = ""
    @Published private(set) var startLocationInfo: LocationInfo?
    @Published private(set) var endLocationInfo: LocationInfo?
    @Published var isLoadingNames = true
    
    private let characterId: Int
    private let contract: ContractInfo
    private let databaseManager: DatabaseManager
    
    struct LocationInfo {
        let stationName: String
        let solarSystemName: String?
        let security: Double?
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
        isLoading = true
        errorMessage = nil
        
        do {
            items = try await CharacterContractsAPI.shared.fetchContractItems(
                characterId: characterId,
                contractId: contract.contract_id,
                forceRefresh: forceRefresh
            )
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
    
    // 获取空间站信息
    private func fetchStationInfo(stationId: Int) async throws -> (name: String?, systemName: String?, regionName: String?, securityStatus: Double?) {
        let query = """
            SELECT stationID, stationTypeID, stationName, regionID, solarSystemID, security
            FROM stations
            WHERE stationID = ?
        """
        
        let result = databaseManager.executeQuery(query, parameters: [stationId])
        
        switch result {
        case .success(let rows):
            guard let row = rows.first,
                  let stationName = row["stationName"] as? String,
                  let solarSystemID = row["solarSystemID"] as? Int,
                  let security = row["security"] as? Double else {
                return (nil, nil, nil, nil)
            }
            
            // 获取星系和星域信息
            if let systemInfo = await getSolarSystemInfo(solarSystemId: solarSystemID) {
                return (stationName, systemInfo.systemName, systemInfo.regionName, security)
            }
            
            return (stationName, nil, nil, security)
            
        case .error(let error):
            Logger.error("从数据库获取空间站信息失败: \(error)")
            return (nil, nil, nil, nil)
        }
    }
    
    // 获取星系信息
    private func getSolarSystemInfo(solarSystemId: Int) async -> (systemName: String, regionName: String)? {
        let query = """
            SELECT s.solarSystemName, r.regionName
            FROM solarSystems s
            LEFT JOIN regions r ON s.regionID = r.regionID
            WHERE s.solarSystemID = ?
        """
        
        let result = databaseManager.executeQuery(query, parameters: [solarSystemId])
        
        if case .success(let rows) = result,
           let row = rows.first,
           let systemName = row["solarSystemName"] as? String,
           let regionName = row["regionName"] as? String {
            return (systemName: systemName, regionName: regionName)
        }
        return nil
    }
    
    // 获取建筑物信息
    private func fetchStructureInfo(structureId: Int) async throws -> (name: String?, systemId: Int?) {
        let urlString = "https://esi.evetech.net/latest/universe/structures/\(structureId)/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        do {
            let data = try await NetworkManager.shared.fetchDataWithToken(from: url, characterId: characterId)
            let structure = try JSONDecoder().decode(UniverseStructureInfo.self, from: data)
            return (structure.name, structure.solar_system_id)
        } catch {
            Logger.error("获取建筑物信息失败: \(error)")
            throw error
        }
    }
    
    private struct UniverseStructureInfo: Codable {
        let name: String
        let solar_system_id: Int
    }
    
    private func fetchLocationInfo(locationId: Int) async -> LocationInfo? {
        // 先尝试从数据库获取空间站信息
        let query = """
                SELECT s.stationName, ss.solarSystemName, u.system_security as security
                FROM stations s
                JOIN solarSystems ss ON s.solarSystemID = ss.solarSystemID
                JOIN universe u ON u.solarsystem_id = ss.solarSystemID
                WHERE s.stationID = ?
        """
        
        if case .success(let rows) = databaseManager.executeQuery(query, parameters: [String(locationId)]),
           let row = rows.first,
           let stationName = row["stationName"] as? String,
           let solarSystemName = row["solarSystemName"] as? String,
           let security = row["security"] as? Double {
            return LocationInfo(
                stationName: stationName,
                solarSystemName: solarSystemName,
                security: security
            )
        }
        
        // 如果数据库中找不到，说明可能是玩家建筑物，通过API获取
        do {
            let structureInfo = try await UniverseStructureAPI.shared.fetchStructureInfo(
                structureId: Int64(locationId),
                characterId: characterId
            )
            
            // 获取星系信息
            let systemQuery = """
                    SELECT ss.solarSystemName, u.system_security as security
                    FROM solarSystems ss
                    JOIN universe u ON u.solarsystem_id = ss.solarSystemID
                    WHERE ss.solarSystemID = ?
            """
            
            if case .success(let rows) = databaseManager.executeQuery(systemQuery, parameters: [String(structureInfo.solar_system_id)]),
               let row = rows.first,
               let solarSystemName = row["solarSystemName"] as? String,
               let security = row["security"] as? Double {
                return LocationInfo(
                    stationName: structureInfo.name,
                    solarSystemName: solarSystemName,
                    security: security
                )
            }
        } catch {
            Logger.error("获取建筑物信息失败 - ID: \(locationId), 错误: \(error)")
        }
        
        return nil
    }
    
    func loadContractParties() async {
        isLoadingNames = true
        var ids = Set<Int>()
        
        // 添加人物ID
        if contract.issuer_id != 0 {
            ids.insert(contract.issuer_id)
        }
        if let assigneeId = contract.assignee_id, assigneeId != 0 {
            ids.insert(assigneeId)
        }
        if let acceptorId = contract.acceptor_id,
           let assigneeId = contract.assignee_id,
           acceptorId != assigneeId,
           acceptorId != 0 {
            ids.insert(acceptorId)
        }
        
        // 获取人物名称
        if !ids.isEmpty {
            do {
                let names = try await UniverseNameCache.shared.getNames(for: ids)
                
                if contract.issuer_id != 0 {
                    issuerName = names[contract.issuer_id] ?? ""
                }
                if let assigneeId = contract.assignee_id, assigneeId != 0 {
                    assigneeName = names[assigneeId] ?? ""
                }
                if let acceptorId = contract.acceptor_id, acceptorId != 0 {
                    acceptorName = names[acceptorId] ?? ""
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        
        // 获取地点信息
        if contract.start_location_id != 0 {
            startLocationInfo = await fetchLocationInfo(locationId: Int(contract.start_location_id))
        }
        
        if contract.end_location_id != 0 && contract.end_location_id != contract.start_location_id {
            endLocationInfo = await fetchLocationInfo(locationId: Int(contract.end_location_id))
        }
        
        isLoadingNames = false
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
                        HStack {
                            Text(NSLocalizedString("Contract_Type", comment: ""))
                            Spacer()
                            Text(NSLocalizedString("Contract_Type_\(contract.type)", comment: ""))
                                .foregroundColor(.secondary)
                        }
                        
                        // 合同状态
                        HStack {
                            Text(NSLocalizedString("Contract_Status", comment: ""))
                            Spacer()
                            Text(NSLocalizedString("Contract_Status_\(contract.status)", comment: ""))
                                .foregroundColor(.secondary)
                        }
                        
                        // 合同发起人（如果 ID 不为 0）
                        if contract.issuer_id != 0 {
                            HStack {
                                Text(NSLocalizedString("Contract_Issuer", comment: ""))
                                Spacer()
                                Text(viewModel.issuerName)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // 合同对象（如果存在且 ID 不为 0）
                        if let assigneeId = contract.assignee_id, assigneeId != 0 {
                            HStack {
                                Text(NSLocalizedString("Contract_Assignee", comment: ""))
                                Spacer()
                                Text(viewModel.assigneeName)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // 如果接收人存在且与对象不同，且 ID 不为 0，显示接收人
                        if let acceptorId = contract.acceptor_id,
                           let assigneeId = contract.assignee_id,
                           acceptorId != assigneeId,
                           acceptorId != 0 {
                            HStack {
                                Text(NSLocalizedString("Contract_Acceptor", comment: ""))
                                Spacer()
                                Text(viewModel.acceptorName)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
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
                                }
                            }
                        }
                        
                        // 合同价格（如果有）
                        if contract.price > 0 {
                            HStack {
                                Text(NSLocalizedString("Contract_Price", comment: ""))
                                Spacer()
                                Text("\(FormatUtil.format(contract.price)) ISK")
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // 合同报酬（如果有）
                        if contract.reward > 0 {
                            HStack {
                                Text(NSLocalizedString("Contract_Reward", comment: ""))
                                Spacer()
                                Text("\(FormatUtil.format(contract.reward)) ISK")
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // 保证金（如果有）
                        if contract.collateral > 0 {
                            HStack {
                                Text(NSLocalizedString("Contract_Collateral", comment: ""))
                                Spacer()
                                Text("\(FormatUtil.format(contract.collateral)) ISK")
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // 体积
                        if contract.volume > 0 {
                            HStack {
                                Text(NSLocalizedString("Contract_Volume", comment: ""))
                                Spacer()
                                Text("\(FormatUtil.format(contract.volume)) m³")
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // 完成期限
                        if contract.days_to_complete > 0 {
                            HStack {
                                Text(NSLocalizedString("Contract_Days_To_Complete", comment: ""))
                                Spacer()
                                Text("\(contract.days_to_complete)")
                                    .foregroundColor(.secondary)
                            }
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
                                    ContractItemRow(item: item, itemDetails: itemDetails)
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
                                    ContractItemRow(item: item, itemDetails: itemDetails)
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
                .refreshable {
                    await viewModel.loadContractItems(forceRefresh: true)
                    await viewModel.loadContractParties()
                }
            }
        }
        .task {
            // 并行加载数据
            async let itemsTask: () = viewModel.loadContractItems()
            async let namesTask: () = viewModel.loadContractParties()
            await (_, _) = (itemsTask, namesTask)
        }
        .navigationTitle(contract.title.isEmpty ? NSLocalizedString("Contract_Details", comment: "") : contract.title)
    }
}

struct ContractItemRow: View {
    let item: ContractItemInfo
    let itemDetails: (name: String, description: String, iconFileName: String)
    
    var body: some View {
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
