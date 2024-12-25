import SwiftUI
import Foundation

struct CharacterAssetsView: View {
    let characterId: Int
    @StateObject private var viewModel: CharacterAssetsViewModel
    @State private var searchText = ""
    
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
                    // 已知星域的资产
                    ForEach(viewModel.regionGroups.sorted(by: { $0.key < $1.key }), id: \.key) { regionName, nodes in
                        Section(header: RegionHeader(name: regionName, nodes: nodes)) {
                            ForEach(nodes, id: \.item_id) { node in
                                NavigationLink(destination: LocationAssetsView(node: node)) {
                                    LocationRow(node: node)
                                }
                            }
                        }
                    }
                    
                    // 未知星域的资产
                    if !viewModel.unknownRegionNodes.isEmpty {
                        Section(header: RegionHeader(name: "未知星域", nodes: viewModel.unknownRegionNodes)) {
                            ForEach(viewModel.unknownRegionNodes, id: \.item_id) { node in
                                NavigationLink(destination: LocationAssetsView(node: node)) {
                                    LocationRow(node: node)
                                }
                            }
                        }
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

// 星域标题视图
struct RegionHeader: View {
    let name: String
    let nodes: [AssetTreeNode]
    
    var body: some View {
        HStack {
            Text(name)
            Spacer()
            Text("\(nodes.count)个位置")
                .foregroundColor(.secondary)
                .font(.caption)
        }
    }
}

// 位置行视图
struct LocationRow: View {
    let node: AssetTreeNode
    
    var body: some View {
        HStack {
            if let iconName = node.icon_name {
                IconManager.shared.loadImage(for: iconName)
                    .resizable()
                    .frame(width: 32, height: 32)
            }
            
            VStack(alignment: .leading) {
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
            }
        }
    }
}

// 位置资产视图
struct LocationAssetsView: View {
    let node: AssetTreeNode
    @State private var searchText = ""
    @State private var expandedNodes = Set<Int64>()
    
    var filteredItems: [AssetTreeNode] {
        guard let items = node.items else { return [] }
        if searchText.isEmpty {
            return items
        }
        return items.filter { item in
            containsSearchText(node: item, searchText: searchText.lowercased())
        }
    }
    
    var body: some View {
        List {
            ForEach(filteredItems, id: \.item_id) { item in
                if let subitems = item.items {
                    NavigationLink(destination: LocationAssetsView(node: item)) {
                        AssetItemRow(node: item)
                    }
                } else {
                    AssetItemRow(node: item)
                }
            }
        }
        .searchable(text: $searchText, prompt: "搜索资产")
        .navigationTitle(node.name ?? node.type_name ?? String(node.type_id))
    }
    
    // 递归搜索节点
    private func containsSearchText(node: AssetTreeNode, searchText: String) -> Bool {
        if let name = node.name?.lowercased(),
           name.contains(searchText) {
            return true
        }
        if let typeName = node.type_name?.lowercased(),
           typeName.contains(searchText) {
            return true
        }
        if let items = node.items {
            return items.contains { containsSearchText(node: $0, searchText: searchText) }
        }
        return false
    }
}

// 资产项行视图
struct AssetItemRow: View {
    let node: AssetTreeNode
    
    var body: some View {
        HStack {
            if let iconName = node.icon_name {
                IconManager.shared.loadImage(for: iconName)
                    .resizable()
                    .frame(width: 24, height: 24)
            }
            
            VStack(alignment: .leading) {
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
    }
}

class CharacterAssetsViewModel: ObservableObject {
    private let characterId: Int
    @Published var regionGroups: [String: [AssetTreeNode]] = [:]
    @Published var unknownRegionNodes: [AssetTreeNode] = []
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
            
            // 按星域分组
            var groups: [String: [AssetTreeNode]] = [:]
            var unknown: [AssetTreeNode] = []
            
            for node in nodes {
                if let regionName = node.region_name {
                    groups[regionName, default: []].append(node)
                } else {
                    unknown.append(node)
                }
            }
            
            await MainActor.run {
                self.regionGroups = groups
                self.unknownRegionNodes = unknown
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
