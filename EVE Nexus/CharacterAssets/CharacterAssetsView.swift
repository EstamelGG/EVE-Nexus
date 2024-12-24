import SwiftUI

struct CharacterAssetsView: View {
    let characterId: Int
    @State private var isLoading = false
    @State private var loadingProgress: AssetLoadingProgress?
    
    var body: some View {
        VStack {
            if isLoading {
                ProgressView {
                    switch loadingProgress {
                    case .fetchingAPI(let page, _):
                        Text("正在获取资产数据 (第\(page)页)")
                    case .buildingTree(let step, let total):
                        Text("正在构建资产树 (\(step)/\(total))")
                    case .complete:
                        Text("加载完成")
                    case .none:
                        Text("加载中...")
                    }
                }
            } else {
                Text("资产列表")
                    .font(.title)
            }
        }
        .task {
            await loadAssets()
        }
    }
    
    private func loadAssets() async {
        guard !isLoading else { return }
        
        isLoading = true
        
        do {
            let assets = try await CharacterAssetsAPI.shared.fetchAllAssets(
                characterId: characterId,
                progressCallback: { progress in
                    Task { @MainActor in
                        loadingProgress = progress
                    }
                }
            )
            
            // 构建资产树
            let assetTree = CharacterAssetsAPI.shared.buildAssetTree(assets: assets)
            
            // 在日志中打印树状结构
            for node in assetTree {
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
