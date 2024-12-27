import SwiftUI

// 导入必要的类型
typealias ContractItemInfo = CharacterContractsAPI.ContractItemInfo

@MainActor
final class ContractDetailViewModel: ObservableObject {
    @Published private(set) var items: [ContractItemInfo] = []
    @Published var isLoading = true
    @Published var errorMessage: String?
    
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
            
            // 合同物品列表
            if !viewModel.items.isEmpty {
                Section {
                    ForEach(viewModel.items) { item in
                        if let itemDetails = viewModel.getItemDetails(for: item.type_id) {
                            ContractItemRow(item: item, itemDetails: itemDetails)
                        }
                    }
                } header: {
                    Text(NSLocalizedString("Contract_Items", comment: ""))
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await viewModel.loadContractItems(forceRefresh: true)
        }
        .task {
            await viewModel.loadContractItems()
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
                    
                    Text(item.is_included ? NSLocalizedString("Contract_Item_Included", comment: "") : NSLocalizedString("Contract_Item_Required", comment: ""))
                        .font(.caption)
                        .foregroundColor(item.is_included ? .green : .red)
                }
            }
        }
        .padding(.vertical, 2)
    }
} 