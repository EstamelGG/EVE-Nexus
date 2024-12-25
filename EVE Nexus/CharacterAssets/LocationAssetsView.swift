import SwiftUI
import Foundation

struct LocationAssetsView: View {
    @StateObject private var viewModel = LocationAssetsViewModel()
    @State private var searchText = ""
    @State private var selectedNode: AssetTreeNode?
    @State private var expandedNodes = Set<Int64>()
    
    var body: some View {
        VStack {
            if viewModel.isLoading {
                ProgressView("加载资产数据...")
            } else if let error = viewModel.error {
                Text("加载失败: \(error.localizedDescription)")
                    .foregroundColor(.red)
            } else {
                List {
                    ForEach(viewModel.rootNodes, id: \.item_id) { node in
                        LocationRow(node: node, expandedNodes: $expandedNodes)
                    }
                }
                .searchable(text: $searchText, prompt: "搜索资产")
            }
        }
        .navigationTitle("资产")
        .task {
            await viewModel.loadAssets()
        }
    }
}

class LocationAssetsViewModel: ObservableObject {
    @Published var rootNodes: [AssetTreeNode] = []
    @Published var isLoading = false
    @Published var error: Error?
    
    func loadAssets() async {
        isLoading = true
        error = nil
        
        do {
            guard let characterId = UserDefaults.standard.object(forKey: "SelectedCharacterID") as? Int else {
                throw AssetError.invalidData("No character selected")
            }
            
            let jsonString = try await CharacterAssetsAPI.shared.fetchAssetTreeJson(characterId: characterId)
            guard let jsonData = jsonString.data(using: String.Encoding.utf8) else {
                throw AssetError.invalidData("Failed to encode JSON string to data")
            }
            
            let nodes = try JSONDecoder().decode([AssetTreeNode].self, from: jsonData)
            await MainActor.run {
                self.rootNodes = nodes
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error
                self.isLoading = false
            }
        }
    }
}

struct LocationAssetsView_Previews: PreviewProvider {
    static var previews: some View {
        LocationAssetsView()
    }
}
