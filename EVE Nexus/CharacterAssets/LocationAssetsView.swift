import SwiftUI

// 物品信息结构体
fileprivate struct ItemInfo {
    let name: String
    let iconFileName: String
}

struct LocationAssetsView: View {
    let location: AssetLocation
    let assetTree: [AssetNode]
    let databaseManager: DatabaseManager
    @State private var searchText = ""
    @State fileprivate var itemInfoCache: [Int: ItemInfo] = [:]
    
    // 获取该位置下的所有二级资产
    private var assetsInLocation: [AssetNode] {
        assetTree.filter { $0.asset.location_id == location.locationId }
    }
    
    // 过滤后的资产
    private var filteredAssets: [AssetNode] {
        if searchText.isEmpty {
            return assetsInLocation
        }
        return assetsInLocation.filter { node in
            if let itemInfo = itemInfoCache[node.asset.type_id] {
                return itemInfo.name.localizedCaseInsensitiveContains(searchText)
            }
            return String(node.asset.type_id).contains(searchText)
        }
    }
    
    var body: some View {
        List {
            ForEach(filteredAssets, id: \.asset.item_id) { node in
                if !node.children.isEmpty {
                    // 如果有子资产，使用导航链接
                    NavigationLink {
                        SubLocationAssetsView(parentNode: node, databaseManager: databaseManager)
                    } label: {
                        AssetItemView(node: node, itemInfo: itemInfoCache[node.asset.type_id])
                    }
                } else {
                    // 如果没有子资产，只显示资产信息
                    AssetItemView(node: node, itemInfo: itemInfoCache[node.asset.type_id])
                }
            }
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text(NSLocalizedString("Main_Database_Search", comment: ""))
        )
        .navigationTitle(location.solarSystemInfo?.systemName ?? NSLocalizedString("Unknown_System", comment: ""))
        .task {
            await loadItemInfo()
        }
    }
    
    // 从数据库加载物品信息
    private func loadItemInfo() async {
        let typeIds = Set(assetsInLocation.map { $0.asset.type_id })
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
        }
    }
}

// 单个资产项的视图
struct AssetItemView: View {
    let node: AssetNode
    fileprivate let itemInfo: ItemInfo?
    
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
                            Text("Type ID: \(node.asset.type_id)")
                        }
                    }
                    
                    // 数量信息
                    if node.asset.quantity > 1 {
                        Text("数量：\(node.asset.quantity)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // 如果有子资产，显示子资产数量
                    if !node.children.isEmpty {
                        Text(String(format: NSLocalizedString("Assets_Item_Count", comment: ""), node.children.count))
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
    let parentNode: AssetNode
    let databaseManager: DatabaseManager
    @State private var searchText = ""
    @State fileprivate var itemInfoCache: [Int: ItemInfo] = [:]
    
    // 过滤后的子资产
    private var filteredAssets: [AssetNode] {
        if searchText.isEmpty {
            return parentNode.children
        }
        return parentNode.children.filter { node in
            if let itemInfo = itemInfoCache[node.asset.type_id] {
                return itemInfo.name.localizedCaseInsensitiveContains(searchText)
            }
            return String(node.asset.type_id).contains(searchText)
        }
    }
    
    var body: some View {
        List {
            ForEach(filteredAssets, id: \.asset.item_id) { node in
                if !node.children.isEmpty {
                    NavigationLink {
                        SubLocationAssetsView(parentNode: node, databaseManager: databaseManager)
                    } label: {
                        AssetItemView(node: node, itemInfo: itemInfoCache[node.asset.type_id])
                    }
                } else {
                    AssetItemView(node: node, itemInfo: itemInfoCache[node.asset.type_id])
                }
            }
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text(NSLocalizedString("Main_Database_Search", comment: ""))
        )
        .navigationTitle(parentNode.name ?? itemInfoCache[parentNode.asset.type_id]?.name ?? String(parentNode.asset.type_id))
        .task {
            await loadItemInfo()
        }
    }
    
    // 从数据库加载物品信息
    private func loadItemInfo() async {
        let typeIds = Set(parentNode.children.map { $0.asset.type_id })
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
        }
    }
}
