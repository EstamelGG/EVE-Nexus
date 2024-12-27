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

// 加载进度视图
private struct LoadingProgressView: View {
    let progress: AssetLoadingProgress?
    
    var body: some View {
        ProgressView {
            if let progress = progress {
                switch progress {
                case .fetchingPage(let page):
                    Text(String(format: NSLocalizedString("Assets_Loading_Page", comment: ""), page))
                case .calculatingJson:
                    Text(NSLocalizedString("Assets_Loading_Calculating", comment: ""))
                case .fetchingNames:
                    Text(NSLocalizedString("Assets_Loading_Fetching_Names", comment: ""))
                }
            } else {
                Text(NSLocalizedString("Assets_Loading", comment: ""))
            }
        }
    }
}

// 搜索结果行视图
private struct SearchResultRowView: View {
    let result: AssetSearchResult
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // 物品图标
                IconManager.shared.loadImage(for: result.iconFileName)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)
                
                VStack(alignment: .leading, spacing: 2) {
                    // 物品名称
                    Text(result.itemName)
                        .font(.headline)
                    
                    // 位置路径（只显示到倒数第二个项目）
                    HStack(spacing: 4) {
                        ForEach(Array(result.path.dropLast().enumerated()), id: \.offset) { index, pathNode in
                            if index > 0 {
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                                    .imageScale(.small)
                            }
                            
                            // 节点名称
                            Text(pathNode.node.name ?? NSLocalizedString("Assets_Unknown_Location", comment: ""))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .lineLimit(1)
                }
            }
        }
    }
}

struct CharacterAssetsView: View {
    @StateObject private var viewModel: CharacterAssetsViewModel
    @State private var searchText = ""
    @State private var showingSearchResults = false
    @State private var searchTask: Task<Void, Never>?
    
    init(characterId: Int) {
        _viewModel = StateObject(wrappedValue: CharacterAssetsViewModel(characterId: characterId))
    }
    
    var body: some View {
        VStack {
            if viewModel.isLoading && viewModel.assetLocations.isEmpty {
                LoadingProgressView(progress: viewModel.loadingProgress)
            } else if !searchText.isEmpty && !viewModel.searchResults.isEmpty {
                // 搜索结果列表
                List {
                    ForEach(viewModel.searchResults, id: \.path.last?.node.item_id) { result in
                        if let containerNode = result.containerNode {
                            NavigationLink(
                                destination: LocationAssetsView(location: containerNode)
                                    .navigationTitle(containerNode.name ?? "Unknown Location")
                            ) {
                                SearchResultRowView(result: result)
                            }
                        }
                    }
                }
            } else {
                LocationsList(
                    locationsByRegion: viewModel.locationsByRegion,
                    searchText: ""  // 不再使用searchText过滤位置列表
                )
            }
        }
        .navigationTitle(NSLocalizedString("Main_Assets", comment: ""))
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text(NSLocalizedString("Main_Database_Search", comment: ""))
        )
        .onChange(of: searchText) { old, newValue in
            // 取消之前的搜索任务
            searchTask?.cancel()
            
            // 创建新的搜索任务
            searchTask = Task {
                // 等待500毫秒
                try? await Task.sleep(nanoseconds: 500_000_000)
                
                // 如果任务没有被取消，执行搜索
                if !Task.isCancelled {
                    // 使用闭包捕获当前的搜索文本
                    let currentSearchText = newValue
                    await viewModel.searchAssets(query: currentSearchText)
                }
            }
        }
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
