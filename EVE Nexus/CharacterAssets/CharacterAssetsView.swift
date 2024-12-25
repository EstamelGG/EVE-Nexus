import SwiftUI

struct CharacterAssetsView: View {
    let characterId: Int
    @State private var isLoading = false
    @State private var loadingProgress: AssetLoadingProgress?
    @State private var searchText = ""
    @State private var isSearchActive = false
    @State private var assetTree: [AssetNode] = []
    @State private var locations: [AssetLocation] = []
    @State private var error: Error?
    
    // 按星域分组的位置
    private var locationsByRegion: [(region: String, locations: [AssetLocation])] {
        let grouped = Dictionary(grouping: locations) { location in
            // 如果没有solar system信息，归类到Unknown Region
            location.solarSystemInfo?.regionName ?? "Unknown Region"
        }
        
        // 将分组转换为数组并排序，确保Unknown Region在最后
        return grouped.filter { !$0.value.isEmpty }
            .map { (region: $0.key, locations: $0.value.sorted { 
                // 按照solar system名称排序，如果没有solar system信息则排在后面
                if let system1 = $0.solarSystemInfo?.systemName,
                   let system2 = $1.solarSystemInfo?.systemName {
                    return system1 < system2
                }
                // 如果其中一个没有solar system信息，将其排在后面
                return $0.solarSystemInfo?.systemName != nil
            })}
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
                ProgressView {
                    switch loadingProgress {
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
            } else {
                List {
                    ForEach(locationsByRegion, id: \.region) { regionGroup in
                        Section(header: Text(regionGroup.region)) {
                            ForEach(regionGroup.locations, id: \.locationId) { location in
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
                                        .font(.subheadline)
                                        .lineLimit(1)
                                        
                                        // 位置类型标识
                                        Text(String(format: NSLocalizedString("Assets_Item_Count", comment: ""), location.itemCount))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
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
            // 强制刷新资产数据
            await loadAssets(forceRefresh: true)
        }
        .task {
            // 首次加载
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
            
            // 构建资产树
            let newAssetTree = CharacterAssetsAPI.shared.buildAssetTree(assets: assets)
            
            // 处理位置信息
            let assetLocations = try await CharacterAssetsAPI.shared.processAssetLocations(
                assets: assets,
                characterId: characterId,
                databaseManager: DatabaseManager()
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

#Preview {
    CharacterAssetsView(characterId: 0)
}
