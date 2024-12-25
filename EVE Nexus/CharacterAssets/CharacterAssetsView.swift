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
                    .frame(width: 36, height: 36)
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
            if let systemName = location.system_name,
               let security = location.security_status {
                Text(formatSecurity(security))
                    .foregroundColor(getSecurityColor(security))
                
                // 位置名称处理
                if let name = location.name, name.hasPrefix(systemName) {
                    Text(systemName)
                        .fontWeight(.bold) +
                    Text(name.dropFirst(systemName.count))
                } else {
                    Text(location.name ?? "Unknown Location")
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
    @StateObject private var viewModel: CharacterAssetsViewModel
    @State private var searchText = ""
    
    init(characterId: Int) {
        _viewModel = StateObject(wrappedValue: CharacterAssetsViewModel(characterId: characterId))
    }
    
    var body: some View {
        VStack {
            if viewModel.isLoading && viewModel.assetLocations.isEmpty {
                ProgressView {
                    Text(NSLocalizedString("Assets_Loading", comment: ""))
                }
            } else {
                LocationsList(
                    locationsByRegion: viewModel.locationsByRegion,
                    searchText: searchText
                )
            }
        }
        .navigationTitle(NSLocalizedString("Main_Assets", comment: ""))
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text(NSLocalizedString("Main_Database_Search", comment: ""))
        )
        .refreshable {
            await viewModel.loadAssets(forceRefresh: true)
        }
        .task {
            if viewModel.assetLocations.isEmpty {
                await viewModel.loadAssets()
            }
        }
    }
}

// 位置列表视图
private struct LocationsList: View {
    let locationsByRegion: [(region: String, locations: [AssetTreeNode])]
    let searchText: String
    
    private var filteredLocations: [(region: String, locations: [AssetTreeNode])] {
        if searchText.isEmpty {
            return locationsByRegion
        }
        
        return locationsByRegion.compactMap { region, locations in
            let filteredLocs = locations.filter { location in
                let searchString = [
                    location.name,
                    location.system_name,
                    location.region_name
                ].compactMap { $0 }.joined(separator: " ")
                
                return searchString.localizedCaseInsensitiveContains(searchText)
            }
            
            return filteredLocs.isEmpty ? nil : (region: region, locations: filteredLocs)
        }
    }
    
    var body: some View {
        List {
            ForEach(filteredLocations, id: \.region) { regionGroup in
                Section(header: Text(regionGroup.region)) {
                    ForEach(regionGroup.locations, id: \.item_id) { location in
                        NavigationLink(
                            destination: LocationAssetsView(location: location)
                        ) {
                            LocationRowView(location: location)
                        }
                    }
                }
            }
        }
    }
}
