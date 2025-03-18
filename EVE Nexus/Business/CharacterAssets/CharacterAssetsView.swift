import SwiftUI

private struct DatabaseManagerKey: EnvironmentKey {
    static let defaultValue: DatabaseManager = .shared
}

extension EnvironmentValues {
    var databaseManager: DatabaseManager {
        get { self[DatabaseManagerKey.self] }
        set { self[DatabaseManagerKey.self] = newValue }
    }
}

// 位置行视图
private struct LocationRowView: View {
    let location: AssetTreeNode
    @EnvironmentObject private var viewModel: CharacterAssetsViewModel

    var body: some View {
        HStack {
            // 位置图标
            if let iconFileName = location.icon_name {
                IconManager.shared.loadImage(for: iconFileName)
                    .resizable()
                    .frame(width: 36, height: 36)
                    .cornerRadius(6)
            } else if location.name == nil {
                // 位置未知时显示默认图标（ID为0）
                Image("not_found")
                    .resizable()
                    .frame(width: 36, height: 36)
                    .cornerRadius(6)
            }

            VStack(alignment: .leading, spacing: 4) {
                // 安全等级和位置名称
                LocationNameView(location: location)
                    .font(.subheadline)
                    .lineLimit(1)
                    .environmentObject(viewModel)

                // 物品数量
                if let items = location.items {
                    Text(
                        String(
                            format: NSLocalizedString("Assets_Item_Count", comment: ""), items.count
                        )
                    )
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
    @AppStorage("useEnglishSystemNames") private var useEnglishSystemNames = false
    @State private var solarSystemName: String?
    @Environment(\.databaseManager) private var databaseManager
    @EnvironmentObject private var viewModel: CharacterAssetsViewModel

    var body: some View {
        LocationInfoView(
            stationName: location.name,
            solarSystemName: solarSystemName ?? "Unknown loc (\(location.location_id))",
            security: location.security_status,
            locationId: location.location_id,
            font: .body,
            textColor: .primary,
            inSpaceNote: location.location_type == "solar_system"
                ? NSLocalizedString("Character_in_space", comment: "") : nil
        )
        .task {
            if let systemId = location.system_id {
                // 首先尝试从ViewModel的缓存中获取
                if let systemInfo = viewModel.systemInfoCache[systemId] {
                    solarSystemName = systemInfo.systemName
                } else {
                    // 如果缓存中没有，再查询数据库
                    if let systemInfo = await getSolarSystemInfo(
                        solarSystemId: systemId,
                        databaseManager: databaseManager
                    ) {
                        solarSystemName = systemInfo.systemName
                    }
                }
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
                IconManager.shared.loadImage(for: result.itemInfo.iconFileName)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)

                VStack(alignment: .leading, spacing: 2) {
                    // 物品名称
                    Text(result.itemInfo.name)
                        .font(.headline)

                    // 完整位置路径
                    Text(result.formattedPath)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
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
        // 创建ViewModel并立即开始加载资产
        let vm = CharacterAssetsViewModel(characterId: characterId)
        _viewModel = StateObject(wrappedValue: vm)
        // 在初始化时启动资产加载任务
        Task {
            await vm.loadAssets()
        }
    }

    var body: some View {
        List {
            // 加载进度部分
            if viewModel.isLoading || viewModel.loadingProgress != nil {
                Section {
                    HStack {
                        Spacer()
                        if let progress = viewModel.loadingProgress {
                            let text: String =
                                switch progress {
                                case let .loading(page):
                                    String(
                                        format: NSLocalizedString(
                                            "Assets_Loading_Fetching", comment: ""
                                        ), page
                                    )
                                case .buildingTree:
                                    NSLocalizedString("Assets_Loading_Building_Tree", comment: "")
                                case .processingLocations:
                                    NSLocalizedString(
                                        "Assets_Loading_Processing_Locations", comment: "")
                                case let .fetchingStructureInfo(current, total):
                                    String(
                                        format: NSLocalizedString(
                                            "Assets_Loading_Fetching_Location_Info", comment: ""
                                        ), current, total
                                    )
                                case .preparingContainers:
                                    NSLocalizedString(
                                        "Assets_Loading_Preparing_Containers", comment: "")
                                case let .loadingNames(current, total):
                                    String(
                                        format: NSLocalizedString(
                                            "Assets_Loading_Names", comment: ""
                                        ), current, total
                                    )
                                case .savingCache:
                                    NSLocalizedString("Assets_Loading_Saving", comment: "")
                                case .completed:
                                    NSLocalizedString("Assets_Loading_Complete", comment: "")
                                }

                            Text(text)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(Color(.secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }

            // 搜索结果为空的提示
            if !searchText.isEmpty && viewModel.searchResults.isEmpty && !viewModel.isLoading {
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
            }
            // 显示错误信息
            else if let error = viewModel.error,
                !viewModel.isLoading && viewModel.assetLocations.isEmpty
            {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 40))
                                .foregroundColor(.orange)
                            Text(NSLocalizedString("Assets_Loading_Error", comment: ""))
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text(error.localizedDescription)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            Button(action: {
                                Task {
                                    await viewModel.loadAssets(forceRefresh: true)
                                }
                            }) {
                                Text(NSLocalizedString("Main_Retry", comment: ""))
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 8)
                                    .background(Color.accentColor)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                            .padding(.top, 8)
                        }
                        .padding()
                        Spacer()
                    }
                }
            }
            // 搜索结果
            else if !searchText.isEmpty {
                ForEach(viewModel.searchResults) { result in
                    NavigationLink(
                        destination: LocationAssetsView(
                            location: result.containerNode,
                            preloadedItemInfo: viewModel.itemInfoCache)
                    ) {
                        SearchResultRowView(result: result)
                    }
                }
            }
            // 正常的资产列表
            else if !viewModel.isLoading && !viewModel.assetLocations.isEmpty {
                ForEach(viewModel.locationsByRegion, id: \.region) { group in
                    Section(
                        header: Text(group.region)
                            .fontWeight(.bold)
                            .font(.system(size: 18))
                            .foregroundColor(.primary)
                            .textCase(.none)
                    ) {
                        ForEach(
                            group.locations.sorted(by: { $0.location_id < $1.location_id }),
                            id: \.item_id
                        ) { location in
                            NavigationLink(
                                destination: LocationAssetsView(
                                    location: location, preloadedItemInfo: viewModel.itemInfoCache)
                            ) {
                                LocationRowView(location: location)
                                    .environmentObject(viewModel)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text(NSLocalizedString("Main_Database_Search", comment: ""))
        )
        .onChange(of: searchText) { _, newValue in
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
        }
        .navigationTitle(NSLocalizedString("Main_Assets", comment: ""))
    }
}
