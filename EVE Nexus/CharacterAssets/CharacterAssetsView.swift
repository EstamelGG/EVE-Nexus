import SwiftUI

// 位置行视图
private struct LocationRowView: View {
    let location: AssetLocation
    
    var body: some View {
        HStack {
            // 位置图标
            if let iconFileName = location.iconFileName {
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
                Text(String(format: NSLocalizedString("Assets_Item_Count", comment: ""), location.itemCount))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// 位置名称视图
private struct LocationNameView: View {
    let location: AssetLocation
    
    var body: some View {
        HStack(spacing: 4) {
            if let systemInfo = location.solarSystemInfo {
                Text(formatSecurity(systemInfo.security))
                    .foregroundColor(getSecurityColor(systemInfo.security))
                
                // 位置名称处理
                if location.displayName.hasPrefix(systemInfo.systemName) {
                    Text(systemInfo.systemName)
                        .fontWeight(.bold) +
                    Text(location.displayName.dropFirst(systemInfo.systemName.count))
                } else {
                    Text(location.displayName)
                }
            } else {
                // 对于未知位置，直接显示displayName
                Text(location.displayName)
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
    @State private var assetTree: [AssetNode] = []
    @State private var locations: [AssetLocation] = []
    @State private var error: Error?
    private let databaseManager = DatabaseManager()
    
    // 按星域分组的位置
    private var locationsByRegion: [(region: String, locations: [AssetLocation])] {
        // 1. 按区域分组
        let grouped = groupLocationsByRegion()
        // 2. 转换为排序后的数组
        return sortGroupedLocations(grouped)
    }
    
    // 将位置按区域分组
    private func groupLocationsByRegion() -> [String: [AssetLocation]] {
        Dictionary(grouping: locations) { location in
            location.solarSystemInfo?.regionName ?? "Unknown Region"
        }
    }
    
    // 对位置进行排序
    private func sortLocations(_ locations: [AssetLocation]) -> [AssetLocation] {
        locations.sorted { loc1, loc2 in
            // 按照solar system名称排序，如果没有solar system信息则排在后面
            if let system1 = loc1.solarSystemInfo?.systemName,
               let system2 = loc2.solarSystemInfo?.systemName {
                return system1 < system2
            }
            // 如果其中一个没有solar system信息，将其排在后面
            return loc1.solarSystemInfo?.systemName != nil
        }
    }
    
    // 对分组后的位置进行排序
    private func sortGroupedLocations(_ grouped: [String: [AssetLocation]]) -> [(region: String, locations: [AssetLocation])] {
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
            if isLoading && assetTree.isEmpty {
                CustomLoadingView(progress: loadingProgress)
            } else {
                LocationsList(
                    locationsByRegion: locationsByRegion,
                    assetTree: assetTree,
                    databaseManager: databaseManager
                )
            }
        }
        .searchable(
            text: $searchText,
            isPresented: $isSearchActive,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text(NSLocalizedString("Main_Database_Search", comment: ""))
        )
        .navigationTitle(NSLocalizedString("Main_Assets", comment: ""))
        .refreshable {
            await loadAssets(forceRefresh: true)
        }
        .task {
            if assetTree.isEmpty {
                await loadAssets()
            }
        }
    }
    
    private func loadAssets(forceRefresh: Bool = false) async {
        guard !isLoading else { return }
        
        isLoading = true
        error = nil
        
        do {
            let assets = try await CharacterAssetsAPI.shared.fetchAllAssets(
                characterId: characterId,
                forceRefresh: forceRefresh,
                progressCallback: { progress in
                    Task { @MainActor in
                        loadingProgress = progress
                    }
                }
            )
            
            // 处理位置信息和资产树
            let (newAssetTree, assetLocations) = try await CharacterAssetsAPI.shared.processAssetLocations(
                assets: assets,
                characterId: characterId,
                databaseManager: databaseManager,
                forceRefresh: forceRefresh
            )
            
            // 更新UI
            await MainActor.run {
                self.assetTree = newAssetTree
                self.locations = assetLocations
            }
            
            // 在日志中打印树状结构
            for node in newAssetTree {
                Logger.info("\n资产树结构：\n\(node.displayAssetTree())")
            }
            
        } catch {
            Logger.error("加载资产失败: \(error)")
            self.error = error
        }
        
        isLoading = false
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

// 位置列表视图
private struct LocationsList: View {
    let locationsByRegion: [(region: String, locations: [AssetLocation])]
    let assetTree: [AssetNode]
    let databaseManager: DatabaseManager
    
    var body: some View {
        List {
            ForEach(locationsByRegion, id: \.region) { regionGroup in
                Section(header: Text(regionGroup.region)) {
                    ForEach(regionGroup.locations, id: \.locationId) { location in
                        NavigationLink(
                            destination: LocationAssetsView(
                                location: location,
                                assetTree: assetTree,
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
