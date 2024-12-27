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
    
    private let characterId: Int
    private let contract: ContractInfo
    private let databaseManager: DatabaseManager
    
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
    
    func loadContractParties() async {
        var ids = Set<Int>()
        
        // 只有当 issuer_id 不为 0 时才添加
        if contract.issuer_id != 0 {
            ids.insert(contract.issuer_id)
        }
        
        // 只有当 assignee_id 存在且不为 0 时才添加
        if let assigneeId = contract.assignee_id, assigneeId != 0 {
            ids.insert(assigneeId)
        }
        
        // 只有当 acceptor_id 和 assignee_id 都存在且不为 0，且不相等时才添加 acceptor_id
        if let acceptorId = contract.acceptor_id,
           let assigneeId = contract.assignee_id,
           acceptorId != assigneeId,
           acceptorId != 0 {
            ids.insert(acceptorId)
        }
        
        // 如果没有有效的 ID 则直接返回
        guard !ids.isEmpty else { return }
        
        do {
            let url = URL(string: "https://esi.evetech.net/latest/universe/names/?datasource=tranquility")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            
            let jsonData = try JSONEncoder().encode(Array(ids))
            request.httpBody = jsonData
            
            let (data, _) = try await URLSession.shared.data(for: request)
            let names = try JSONDecoder().decode([UniverseNameResponse].self, from: data)
            
            for name in names {
                if contract.issuer_id != 0 && name.id == contract.issuer_id {
                    issuerName = name.name
                }
                if let assigneeId = contract.assignee_id, assigneeId != 0, name.id == assigneeId {
                    assigneeName = name.name
                }
                if let acceptorId = contract.acceptor_id, acceptorId != 0, name.id == acceptorId {
                    acceptorName = name.name
                }
            }
        } catch {
            errorMessage = error.localizedDescription
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
            }
            
            // 提供的物品列表
            if !viewModel.items.filter({ $0.is_included }).isEmpty {
                Section {
                    ForEach(viewModel.items.filter { $0.is_included }) { item in
                        if let itemDetails = viewModel.getItemDetails(for: item.type_id) {
                            ContractItemRow(item: item, itemDetails: itemDetails)
                                .frame(height: 36)
                        }
                    }
                } header: {
                    Text(NSLocalizedString("Contract_Items_Included", comment: ""))
                }
            }
            
            // 需求的物品列表
            if !viewModel.items.filter({ !$0.is_included }).isEmpty {
                Section {
                    ForEach(viewModel.items.filter { !$0.is_included }) { item in
                        if let itemDetails = viewModel.getItemDetails(for: item.type_id) {
                            ContractItemRow(item: item, itemDetails: itemDetails)
                                .frame(height: 36)
                        }
                    }
                } header: {
                    Text(NSLocalizedString("Contract_Items_Required", comment: ""))
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await viewModel.loadContractItems(forceRefresh: true)
            await viewModel.loadContractParties()
        }
        .task {
            await viewModel.loadContractItems()
            await viewModel.loadContractParties()
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
            VStack(alignment: .leading, spacing: 2) {
                // 物品名称
                Text(itemDetails.name)
                    .font(.body)
                
                // 物品数量和包含状态
                HStack {
                    Text("\(item.quantity) \(NSLocalizedString("Misc_number_item", comment: ""))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if item.is_singleton {
                        Text(NSLocalizedString("Contract_Item_Singleton", comment: ""))
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
} 
