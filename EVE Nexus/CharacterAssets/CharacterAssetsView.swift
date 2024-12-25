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
    private var locationsByRegion: [String: [AssetLocation]] {
        Dictionary(grouping: locations) { location in
            location.solarSystemInfo?.regionName ?? "Unknown Region"
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
                    ForEach(Array(locationsByRegion.keys.sorted()), id: \.self) { region in
                        Section(header: Text(region)) {
                            ForEach(locationsByRegion[region] ?? [], id: \.locationId) { location in
                                if let systemInfo = location.solarSystemInfo {
                                    HStack {
                                        // 空间站图标
                                        if let iconFileName = location.iconFileName {
                                            IconManager.shared.loadImage(for: iconFileName)
                                                .resizable()
                                                .frame(width: 32, height: 32)
                                                .cornerRadius(6)
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            // 安全等级和空间站名称
                                            HStack(spacing: 4) {
                                                Text(formatSecurity(systemInfo.security))
                                                    .foregroundColor(getSecurityColor(systemInfo.security))
                                                
                                                // 空间站名称处理
                                                if location.displayName.hasPrefix(systemInfo.systemName) {
                                                    Text(systemInfo.systemName)
                                                        .fontWeight(.bold) +
                                                    Text(location.displayName.dropFirst(systemInfo.systemName.count))
                                                } else {
                                                    Text(location.displayName)
                                                }
                                            }.lineLimit(1)
                                            .font(.subheadline)
                                        }
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
