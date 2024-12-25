import SwiftUI

struct CharacterAssetsView: View {
    let characterId: Int
    @State private var isLoading = false
    @State private var loadingProgress: AssetLoadingProgress?
    @State private var searchText = ""
    @State private var isSearchActive = false
    @State private var assetTree: [AssetNode] = []
    
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
                    Text("资产列表")
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
            
            // 更新UI
            await MainActor.run {
                self.assetTree = newAssetTree
            }
            
            // 在日志中打印树状结构
            for node in newAssetTree {
                Logger.info("\n资产树结构：\n\(node.displayAssetTree())")
            }
            
        } catch {
            Logger.error("加载资产失败: \(error)")
        }
        
        isLoading = false
    }
}

#Preview {
    CharacterAssetsView(characterId: 0)
}
