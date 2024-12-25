import SwiftUI
import Foundation

struct CharacterAssetsView: View {
    let characterId: Int
    @StateObject private var viewModel: CharacterAssetsViewModel
    @State private var searchText = ""
    @State private var expandedNodes = Set<Int64>()
    
    init(characterId: Int) {
        self.characterId = characterId
        self._viewModel = StateObject(wrappedValue: CharacterAssetsViewModel(characterId: characterId))
    }
    
    var body: some View {
        VStack {
            if viewModel.isLoading {
                ProgressView("加载资产数据...")
            } else if let error = viewModel.error {
                Text("加载失败: \(error.localizedDescription)")
                    .foregroundColor(.red)
            } else {
                List {
                    ForEach(filteredNodes, id: \.item_id) { node in
                        AssetNodeRow(node: node, expandedNodes: $expandedNodes)
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
    
    // 过滤后的节点
    private var filteredNodes: [AssetTreeNode] {
        if searchText.isEmpty {
            return viewModel.rootNodes
        }
        return viewModel.rootNodes.filter { node in
            containsSearchText(node: node, searchText: searchText.lowercased())
        }
    }
    
    // 递归搜索节点
    private func containsSearchText(node: AssetTreeNode, searchText: String) -> Bool {
        // 检查当前节点
        if let name = node.name?.lowercased(),
           name.contains(searchText) {
            return true
        }
        if let typeName = node.type_name?.lowercased(),
           typeName.contains(searchText) {
            return true
        }
        if let systemName = node.system_name?.lowercased(),
           systemName.contains(searchText) {
            return true
        }
        
        // 递归检查子节点
        if let items = node.items {
            return items.contains { containsSearchText(node: $0, searchText: searchText) }
        }
        
        return false
    }
}

// 统一的资产节点行视图
struct AssetNodeRow: View {
    let node: AssetTreeNode
    @Binding var expandedNodes: Set<Int64>
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                // 图标
                if let iconName = node.icon_name {
                    IconManager.shared.loadImage(for: iconName)
                        .resizable()
                        .frame(width: node.location_flag == "root" ? 32 : 24, height: node.location_flag == "root" ? 32 : 24)
                }
                
                // 内容
                VStack(alignment: .leading) {
                    if node.location_flag == "root" {
                        // 位置节点（空间站、建筑物等）
                        if let name = node.name {
                            Text(name)
                                .font(.headline)
                        }
                        
                        HStack {
                            if let systemName = node.system_name {
                                Text(systemName)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            if let securityStatus = node.security_status {
                                Text(String(format: "%.1f", securityStatus))
                                    .font(.subheadline)
                                    .foregroundColor(securityStatus >= 0.5 ? .green : securityStatus >= 0.0 ? .orange : .red)
                            }
                        }
                    } else {
                        // 普通物品节点
                        HStack {
                            if let typeName = node.type_name {
                                Text(typeName)
                                    .font(.subheadline)
                            }
                            if let name = node.name {
                                Text("[\(name)]")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Text("\(node.quantity)x")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // 展开/折叠指示器
                if let items = node.items, !items.isEmpty {
                    Image(systemName: expandedNodes.contains(node.item_id) ? "chevron.down" : "chevron.right")
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if let items = node.items, !items.isEmpty {
                    if expandedNodes.contains(node.item_id) {
                        expandedNodes.remove(node.item_id)
                    } else {
                        expandedNodes.insert(node.item_id)
                    }
                }
            }
            
            // 子项
            if expandedNodes.contains(node.item_id), let items = node.items {
                ForEach(items, id: \.item_id) { item in
                    AssetNodeRow(node: item, expandedNodes: $expandedNodes)
                        .padding(.leading)
                }
            }
        }
    }
}

class CharacterAssetsViewModel: ObservableObject {
    private let characterId: Int
    @Published var rootNodes: [AssetTreeNode] = []
    @Published var isLoading = false
    @Published var error: Error?
    
    init(characterId: Int) {
        self.characterId = characterId
    }
    
    func loadAssets() async {
        isLoading = true
        error = nil
        
        do {
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

struct CharacterAssetsView_Previews: PreviewProvider {
    static var previews: some View {
        CharacterAssetsView(characterId: 0)
    }
}
