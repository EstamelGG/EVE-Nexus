import SwiftUI

struct LocationAssetsView: View {
    let location: AssetTreeNode
    @StateObject private var viewModel: LocationAssetsViewModel
    @State private var searchText = ""
    
    init(location: AssetTreeNode) {
        self.location = location
        _viewModel = StateObject(wrappedValue: LocationAssetsViewModel(location: location))
    }
    
    var body: some View {
        List {
            ForEach(viewModel.filteredAssets(searchText: searchText), id: \.item_id) { node in
                if let items = node.items, !items.isEmpty {
                    // 如果有子资产，使用导航链接
                    NavigationLink {
                        SubLocationAssetsView(parentNode: node)
                    } label: {
                        AssetItemView(node: node, itemInfo: viewModel.itemInfo(for: node.type_id))
                    }
                } else {
                    // 如果没有子资产，只显示资产信息
                    AssetItemView(node: node, itemInfo: viewModel.itemInfo(for: node.type_id))
                }
            }
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text(NSLocalizedString("Main_Database_Search", comment: ""))
        )
        .navigationTitle(location.name ?? location.system_name ?? NSLocalizedString("Unknown_System", comment: ""))
        .task {
            await viewModel.loadItemInfo()
        }
    }
}

// 单个资产项的视图
struct AssetItemView: View {
    let node: AssetTreeNode
    let itemInfo: ItemInfo?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // 资产图标
                IconManager.shared.loadImage(for: itemInfo?.iconFileName ?? DatabaseConfig.defaultItemIcon)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)
                VStack(alignment: .leading, spacing: 2) {
                    // 资产名称和自定义名称
                    HStack(spacing: 4) {
                        if let itemInfo = itemInfo {
                            Text(itemInfo.name)
                            if let customName = node.name {
                                Text("[\(customName)]")
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text("Type ID: \(node.type_id)")
                        }
                    }
                    
                    // 数量信息
                    if node.quantity > 1 {
                        Text("数量：\(node.quantity)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // 如果有子资产，显示子资产数量
                    if let items = node.items, !items.isEmpty {
                        Text(String(format: NSLocalizedString("Assets_Item_Count", comment: ""), items.count))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(height: 36)
        }
    }
}

// 子位置资产视图
struct SubLocationAssetsView: View {
    let parentNode: AssetTreeNode
    @StateObject private var viewModel: LocationAssetsViewModel
    @State private var searchText = ""
    
    init(parentNode: AssetTreeNode) {
        self.parentNode = parentNode
        _viewModel = StateObject(wrappedValue: LocationAssetsViewModel(location: parentNode))
    }
    
    var body: some View {
        List {
            if parentNode.items != nil {
                ForEach(viewModel.filteredAssets(searchText: searchText), id: \.item_id) { node in
                    if let subitems = node.items, !subitems.isEmpty {
                        NavigationLink {
                            SubLocationAssetsView(parentNode: node)
                        } label: {
                            AssetItemView(node: node, itemInfo: viewModel.itemInfo(for: node.type_id))
                        }
                    } else {
                        AssetItemView(node: node, itemInfo: viewModel.itemInfo(for: node.type_id))
                    }
                }
            }
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text(NSLocalizedString("Main_Database_Search", comment: ""))
        )
        .navigationTitle(parentNode.name ?? viewModel.itemInfo(for: parentNode.type_id)?.name ?? String(parentNode.type_id))
        .task {
            await viewModel.loadItemInfo()
        }
    }
}

// LocationAssetsViewModel
class LocationAssetsViewModel: ObservableObject {
    private let location: AssetTreeNode
    private var itemInfoCache: [Int: ItemInfo] = [:]
    private let databaseManager: DatabaseManager
    
    init(location: AssetTreeNode, databaseManager: DatabaseManager = DatabaseManager()) {
        self.location = location
        self.databaseManager = databaseManager
    }
    
    func itemInfo(for typeId: Int) -> ItemInfo? {
        itemInfoCache[typeId]
    }
    
    func filteredAssets(searchText: String) -> [AssetTreeNode] {
        guard let items = location.items else { return [] }
        
        if searchText.isEmpty {
            return items
        }
        
        return items.filter { node in
            if let itemInfo = itemInfoCache[node.type_id] {
                return itemInfo.name.localizedCaseInsensitiveContains(searchText)
            }
            return String(node.type_id).contains(searchText)
        }
    }
    
    // 从数据库加载物品信息
    @MainActor
    func loadItemInfo() async {
        guard let items = location.items else { return }
        
        let typeIds = Set(items.map { $0.type_id })
        let query = """
            SELECT type_id, name, icon_filename
            FROM types
            WHERE type_id IN (\(typeIds.map { String($0) }.joined(separator: ",")))
        """
        
        if case .success(let rows) = databaseManager.executeQuery(query) {
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                   let name = row["name"] as? String {
                    let iconFileName = (row["icon_filename"] as? String) ?? DatabaseConfig.defaultItemIcon
                    itemInfoCache[typeId] = ItemInfo(name: name, iconFileName: iconFileName)
                }
            }
            objectWillChange.send()
        }
    }
}
