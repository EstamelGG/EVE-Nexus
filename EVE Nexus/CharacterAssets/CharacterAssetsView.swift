import SwiftUI

// 位置行视图
private struct LocationRowView: View {
    let location: AssetTreeNode
    
    var body: some View {
        HStack {
            // 位置图标
            if let iconFileName = location.icon_name {
                IconManager.shared.loadImage(for: iconFileName)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                // 安全等级和位置名称
                LocationNameView(location: location)
                    .font(.subheadline)
                    .lineLimit(1)
                
                // 物品数量
                if let items = location.items {
                    Text(String(format: NSLocalizedString("Assets_Item_Count", comment: ""), items.count))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// 位置名称视图
private struct LocationNameView: View {
    let location: AssetTreeNode
    
    var body: some View {
        HStack(spacing: 4) {
            if let security = location.security_status {
                Text(formatSecurity(security))
                    .foregroundColor(getSecurityColor(security))
                
                // 位置名称处理
                if let systemName = location.system_name,
                   let name = location.name {
                    if name.hasPrefix(systemName) {
                        Text(systemName)
                            .fontWeight(.bold) +
                        Text(name.dropFirst(systemName.count))
                    } else {
                        Text(name)
                    }
                }
            } else {
                // 对于未知位置，直接显示名称
                Text(location.name ?? "Unknown Location")
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct CharacterAssetsView: View {
    let characterId: Int
    @State private var isLoading = false
    @State private var loadingProgress: AssetLoadingProgress?
    @State private var searchText = ""
    @State private var isSearchActive = false
    @State private var assetNodes: [AssetTreeNode] = []
    @State private var error: Error?
    private let databaseManager = DatabaseManager()
    
    // 按星域分组的位置
    private var locationsByRegion: [(region: String, locations: [AssetTreeNode])] {
        // 1. 按区域分组
        let grouped = groupLocationsByRegion()
        // 2. 转换为排序后的数组
        return sortGroupedLocations(grouped)
    }
    
    // 将位置按区域分组
    private func groupLocationsByRegion() -> [String: [AssetTreeNode]] {
        Dictionary(grouping: assetNodes) { node in
            node.region_name ?? "Unknown Region"
        }
    }
    
    // 对位置进行排序
    private func sortLocations(_ locations: [AssetTreeNode]) -> [AssetTreeNode] {
        locations.sorted { loc1, loc2 in
            // 按照solar system名称排序，如果没有solar system信息则排在后面
            if let system1 = loc1.system_name,
               let system2 = loc2.system_name {
                return system1 < system2
            }
            // 如果其中一个没有solar system信息，将其排在后面
            return loc1.system_name != nil
        }
    }
    
    // 对分组后的位置进行排序
    private func sortGroupedLocations(_ grouped: [String: [AssetTreeNode]]) -> [(region: String, locations: [AssetTreeNode])] {
        grouped.filter { !$0.value.isEmpty }
            .map { (region: $0.key, locations: sortLocations($0.value)) }
            .sorted { pair1, pair2 in
                // 确保Unknown Region始终在最后
                if pair1.region == "Unknown Region" { return false }
                if pair2.region == "Unknown Region" { return true }
                return pair1.region < pair2.region
            }
    }
    
    var body: some View {
        VStack {
            if isLoading && assetNodes.isEmpty {
                CustomLoadingView(progress: loadingProgress)
            } else {
                LocationsList(
                    locationsByRegion: locationsByRegion,
                    databaseManager: databaseManager
                )
            }
        }
        .navigationTitle(NSLocalizedString("Main_Assets", comment: ""))
        .refreshable {
            await loadAssets(forceRefresh: true)
        }
        .task {
            if assetNodes.isEmpty {
                await loadAssets()
            }
        }
    }
    
    private func loadAssets(forceRefresh: Bool = false) async {
        guard !isLoading else { return }
        
        isLoading = true
        error = nil
        
        do {
            let jsonString = try await CharacterAssetsAPI.shared.fetchAssetTreeJson(
                characterId: characterId,
                forceRefresh: forceRefresh,
                progressCallback: { progress in
                    Task { @MainActor in
                        loadingProgress = progress
                    }
                }
            )
            
            // 解析JSON
            if let jsonData = jsonString.data(using: .utf8),
               let nodes = try? JSONDecoder().decode([AssetTreeNode].self, from: jsonData) {
                await MainActor.run {
                    self.assetNodes = nodes
                }
            } else {
                throw AssetError.decodingError(NSError(domain: "", code: -1))
            }
            
        } catch {
            Logger.error("加载资产失败: \(error)")
            self.error = error
        }
        
        isLoading = false
    }
}

// 位置列表视图
private struct LocationsList: View {
    let locationsByRegion: [(region: String, locations: [AssetTreeNode])]
    let databaseManager: DatabaseManager
    
    var body: some View {
        List {
            ForEach(locationsByRegion, id: \.region) { regionGroup in
                Section(header: Text(regionGroup.region)) {
                    ForEach(regionGroup.locations, id: \.item_id) { location in
                        NavigationLink(
                            destination: AssetTreeNodeView(
                                node: location,
                                databaseManager: databaseManager
                            )
                        ) {
                            LocationRowView(location: location)
                        }
                    }
                }
            }
        }
    }
}

// 自定义加载视图
private struct CustomLoadingView: View {
    let progress: AssetLoadingProgress?
    
    var body: some View {
        ProgressView {
            switch progress {
            case .fetchingAPI(let page, _):
                Text(String(format: NSLocalizedString("Assets_Loading_Fetching", comment: ""), page))
            case .buildingTree(let step, let total):
                Text(String(format: NSLocalizedString("Assets_Loading_Building_Tree", comment: ""), step, total))
            case .complete:
                Text(NSLocalizedString("Assets_Loading_Complete", comment: ""))
            case .none:
                Text(NSLocalizedString("Assets_Loading", comment: ""))
            }
        }
    }
}
