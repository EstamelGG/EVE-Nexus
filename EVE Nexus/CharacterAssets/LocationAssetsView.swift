import SwiftUI

struct LocationAssetsView: View {
    let location: AssetLocation
    let assetTree: [AssetNode]
    @State private var searchText = ""
    
    // 获取该位置下的所有资产
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
                AssetNodeView(node: node)
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

// 单个资产节点的视图
struct AssetNodeView: View {
    let node: AssetNode
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                // 展开/折叠按钮
                if !node.children.isEmpty {
                    Button(action: { isExpanded.toggle() }) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    }
                } else {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .padding(.horizontal, 8)
                }
                
                // 资产图标
                IconManager.shared.loadImage(for: DatabaseConfig.defaultItemIcon)
                    .resizable()
                    .frame(width: 24, height: 24)
                    .cornerRadius(4)
                
                VStack(alignment: .leading) {
                    // 资产名称和数量
                    HStack {
                        if let name = node.name {
                            Text(name)
                        } else {
                            Text("Type ID: \(node.asset.type_id)")  // TODO: 从数据库获取物品名称
                        }
                        if node.asset.quantity > 1 {
                            Text("x\(node.asset.quantity)")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // 资产位置标识
                    Text(node.asset.location_flag)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // 子资产
            if isExpanded {
                ForEach(node.children, id: \.asset.item_id) { child in
                    AssetNodeView(node: child)
                        .padding(.leading)
                }
            }
        }
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