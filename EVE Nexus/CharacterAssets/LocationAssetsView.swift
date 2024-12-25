import SwiftUI

struct LocationAssetsView: View {
    let location: AssetLocation
    let assetTree: [AssetNode]
    @State private var searchText = ""
    
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
            // TODO: 添加资产名称的搜索，需要从数据库获取type_id对应的名称
            String(node.asset.type_id).contains(searchText)
        }
    }
    
    var body: some View {
        List {
            ForEach(filteredAssets, id: \.asset.item_id) { node in
                if !node.children.isEmpty {
                    // 如果有子资产，使用导航链接
                    NavigationLink {
                        SubLocationAssetsView(parentNode: node)
                    } label: {
                        AssetItemView(node: node)
                    }
                } else {
                    // 如果没有子资产，只显示资产信息
                    AssetItemView(node: node)
                }
            }
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text(NSLocalizedString("Main_Database_Search", comment: ""))
        )
        .navigationTitle(location.solarSystemInfo?.systemName ?? NSLocalizedString("Unknown_System", comment: ""))
    }
}

// 单个资产项的视图
struct AssetItemView: View {
    let node: AssetNode
    
    var body: some View {
        HStack(spacing: 12) {
            // 资产图标
            IconManager.shared.loadImage(for: DatabaseConfig.defaultItemIcon)
                .resizable()
                .frame(width: 32, height: 32)
                .cornerRadius(4)
            
            VStack(alignment: .leading, spacing: 4) {
                // 资产名称和数量
                HStack {
                    if let name = node.name {
                        Text(name)
                            .font(.headline)
                    } else {
                        Text("Type ID: \(node.asset.type_id)")  // TODO: 从数据库获取物品名称
                            .font(.headline)
                    }
                    
                    if node.asset.quantity > 1 {
                        Text("x\(node.asset.quantity)")
                            .foregroundColor(.secondary)
                    }
                }
                
                // 如果有子资产，显示子资产数量
                if !node.children.isEmpty {
                    Text(String(format: NSLocalizedString("Assets_Item_Count", comment: ""), node.children.count))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // 如果有子资产，显示箭头
            if !node.children.isEmpty {
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// 子位置资产视图
struct SubLocationAssetsView: View {
    let parentNode: AssetNode
    @State private var searchText = ""
    
    // 过滤后的子资产
    private var filteredAssets: [AssetNode] {
        if searchText.isEmpty {
            return parentNode.children
        }
        return parentNode.children.filter { node in
            // TODO: 添加资产名称的搜索
            String(node.asset.type_id).contains(searchText)
        }
    }
    
    var body: some View {
        List {
            ForEach(filteredAssets, id: \.asset.item_id) { node in
                if !node.children.isEmpty {
                    NavigationLink {
                        SubLocationAssetsView(parentNode: node)
                    } label: {
                        AssetItemView(node: node)
                    }
                } else {
                    AssetItemView(node: node)
                }
            }
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text(NSLocalizedString("Main_Database_Search", comment: ""))
        )
        .navigationTitle(parentNode.name ?? String(parentNode.asset.type_id))
    }
}

#Preview {
    NavigationView {
        LocationAssetsView(
            location: AssetLocation(
                locationId: 0,
                locationType: "station",
                stationInfo: nil,
                structureInfo: nil,
                solarSystemInfo: nil,
                iconFileName: nil,
                error: nil,
                itemCount: 0
            ),
            assetTree: []
        )
    }
} 