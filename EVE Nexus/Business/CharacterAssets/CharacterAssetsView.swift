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
        LocationInfoView(
            stationName: location.name,
            solarSystemName: location.system_name,
            security: location.security_status,
            font: .body,
            textColor: .primary
        )
    }
}

// 搜索结果行视图
private struct SearchResultRowView: View {
    let result: AssetSearchResult
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // 物品图标
                IconManager.shared.loadImage(for: result.itemInfo.iconFileName)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)
                
                VStack(alignment: .leading, spacing: 2) {
                    // 物品名称
                    Text(result.itemInfo.name)
                        .font(.headline)
                    
                    // 位置信息
                    Text(result.locationName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

struct CharacterAssetsView: View {
    @StateObject private var viewModel: CharacterAssetsViewModel
    @State private var searchText = ""
    @State private var isSearching = false
    
    init(characterId: Int) {
        _viewModel = StateObject(wrappedValue: CharacterAssetsViewModel(characterId: characterId))
    }
    
    var body: some View {
        List {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if !searchText.isEmpty && viewModel.searchResults.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 30))
                                .foregroundColor(.gray)
                            Text(NSLocalizedString("Orders_No_Data", comment: ""))
                                .foregroundColor(.gray)
                        }
                        .padding()
                        Spacer()
                    }
                }
            } else if !searchText.isEmpty {
                ForEach(viewModel.searchResults) { result in
                    NavigationLink(
                        destination: LocationAssetsView(location: result.node)
                    ) {
                        SearchResultRowView(result: result)
                    }
                }
            } else {
                ForEach(viewModel.locationsByRegion, id: \.region) { group in
                    Section(header: Text(group.region)
                        .fontWeight(.bold)
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                        .textCase(.none)
                    ) {
                        ForEach(group.locations, id: \.item_id) { location in
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
        .listStyle(.insetGrouped)
        .searchable(text: $searchText)
        .onChange(of: searchText) { oldValue, newValue in
            Task {
                isSearching = true
                await viewModel.searchAssets(query: newValue)
                isSearching = false
            }
        }
        .refreshable {
            Task {
                await viewModel.loadAssets(forceRefresh: true)
            }
            return
        }
        .navigationTitle(NSLocalizedString("Main_Assets", comment: ""))
        .toolbar {
            if viewModel.loadingProgress == .loading {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
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
