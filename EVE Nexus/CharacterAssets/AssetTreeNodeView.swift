import SwiftUI

struct LocationRow: View {
    let node: AssetTreeNode
    @Binding var expandedNodes: Set<Int64>
    
    var body: some View {
        VStack(alignment: .leading) {
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
                
                Spacer()
                
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
            
            if expandedNodes.contains(node.item_id), let items = node.items {
                ForEach(items, id: \.item_id) { item in
                    AssetItemRow(node: item, expandedNodes: $expandedNodes)
                        .padding(.leading)
                }
            }
        }
    }
}

struct AssetTreeNodeView: View {
    let node: AssetTreeNode
    let databaseManager: DatabaseManager
    @State private var searchText = ""
    @State private var expandedNodes = Set<Int64>()
    
    // 过滤后的子项
    private var filteredItems: [AssetTreeNode] {
        guard let items = node.items else { return [] }
        if searchText.isEmpty {
            return items
        }
        return items.filter { item in
            if let name = item.name {
                return name.localizedCaseInsensitiveContains(searchText)
            }
            if let typeName = item.type_name {
                return typeName.localizedCaseInsensitiveContains(searchText)
            }
            return false
        }
    }
    
    var body: some View {
        List {
            ForEach(filteredItems, id: \.item_id) { item in
                AssetItemRow(node: item, expandedNodes: $expandedNodes)
            }
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text(NSLocalizedString("Main_Database_Search", comment: ""))
        )
        .navigationTitle(node.name ?? node.type_name ?? String(node.type_id))
    }
}

private struct AssetItemRow: View {
    let node: AssetTreeNode
    @Binding var expandedNodes: Set<Int64>
    
    var body: some View {
        VStack(alignment: .leading) {
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
                
                Spacer()
                
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
            
            if expandedNodes.contains(node.item_id), let items = node.items {
                ForEach(items, id: \.item_id) { item in
                    AssetItemRow(node: item, expandedNodes: $expandedNodes)
                        .padding(.leading)
                }
            }
        }
    }
} 