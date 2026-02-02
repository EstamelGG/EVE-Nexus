import SwiftUI

// 共用的图标尺寸常量
private enum IconSize {
    static let location: CGFloat = 36
}

// 位置行视图
private struct LocationRowView: View {
    let location: AssetTreeNode
    @EnvironmentObject private var viewModel: CorporationAssetsViewModel

    var body: some View {
        HStack {
            // 位置图标
            if let iconFileName = location.icon_name {
                AssetIconView(iconName: iconFileName, size: IconSize.location)
            } else if location.name == nil {
                // 位置未知时显示默认图标（ID为0）
                Image("not_found")
                    .resizable()
                    .frame(width: IconSize.location, height: IconSize.location)
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
    @EnvironmentObject private var viewModel: CorporationAssetsViewModel

    var body: some View {
        LocationInfoView(
            stationName: location.getLocationName(stationNameCache: viewModel.stationNameCache),
            solarSystemName: getSolarSystemName(),
            security: location.security_status,
            locationId: location.location_id,
            font: .body,
            textColor: .primary,
            inSpaceNote: location.location_type == "solar_system"
                ? NSLocalizedString("Character_in_space", comment: "") : nil
        )
    }

    // 获取星系名称，优先使用缓存
    private func getSolarSystemName() -> String? {
        if let systemId = location.system_id,
           let name = viewModel.solarSystemNameCache[systemId]
        {
            return name
        }
        return nil
    }
}

// 数据加载时间视图
private struct DataLoadTimeView: View {
    let loadTime: Date

    var body: some View {
        Text(formatDate(loadTime))
            .font(.caption2)
            .foregroundColor(.secondary)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        formatter.locale = Locale.current
        return formatter.string(from: date)
    }
}

// 搜索结果行视图
private struct SearchResultRowView: View {
    let result: AssetSearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // 物品图标
                AssetIconView(iconName: result.itemInfo.iconFileName)

                VStack(alignment: .leading, spacing: 2) {
                    // 物品名称和数量
                    HStack(spacing: 4) {
                        Text(result.itemInfo.name)

                        // 显示数量（如果大于1）
                        if result.totalQuantity > 1 {
                            Text("×\(result.totalQuantity)")
                                .foregroundColor(.secondary)
                        }
                    }

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

// 包装视图，用于获取军团ID
struct CorporationAssetsViewWrapper: View {
    let characterId: Int
    @State private var corporationId: Int?
    @State private var isLoading = true
    @State private var error: Error?

    var body: some View {
        Group {
            if let corporationId = corporationId {
                CorporationAssetsView(corporationId: corporationId, characterId: characterId)
            } else if isLoading {
                ProgressView()
                    .navigationTitle(NSLocalizedString("Main_Corporation_Assets", comment: ""))
            } else if let error = error {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.orange)
                    Text(NSLocalizedString("Assets_Loading_Error", comment: ""))
                        .font(.headline)
                    Text(error.localizedDescription)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .navigationTitle(NSLocalizedString("Main_Corporation_Assets", comment: ""))
            }
        }
        .task {
            await loadCorporationId()
        }
    }

    private func loadCorporationId() async {
        do {
            if let corpId = try await CharacterDatabaseManager.shared.getCharacterCorporationId(
                characterId: characterId
            ) {
                await MainActor.run {
                    self.corporationId = corpId
                    self.isLoading = false
                }
            } else {
                await MainActor.run {
                    self.error = NSError(
                        domain: "CorporationAssetsError",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "无法获取军团ID"]
                    )
                    self.isLoading = false
                }
            }
        } catch {
            await MainActor.run {
                self.error = error
                self.isLoading = false
            }
        }
    }
}

struct CorporationAssetsView: View {
    @StateObject private var viewModel: CorporationAssetsViewModel
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var isRefreshing = false
    @AppStorage("enableLogging") private var enableLogging: Bool = false

    init(corporationId: Int, characterId: Int) {
        // 创建ViewModel并立即开始加载资产
        let vm = CorporationAssetsViewModel(corporationId: corporationId, characterId: characterId)
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
                                        "Assets_Loading_Processing_Locations", comment: ""
                                    )
                                case let .fetchingStructureInfo(current, total):
                                    String(
                                        format: NSLocalizedString(
                                            "Assets_Loading_Fetching_Location_Info", comment: ""
                                        ), current, total
                                    )
                                case .preparingContainers:
                                    NSLocalizedString(
                                        "Assets_Loading_Preparing_Containers", comment: ""
                                    )
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
                    NoDataSection()
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
                                Text(NSLocalizedString("ESI_Status_Retry", comment: ""))
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
                            preloadedItemInfo: viewModel.itemInfoCache,
                            stationNameCache: viewModel.stationNameCache,
                            solarSystemNameCache: viewModel.solarSystemNameCache
                        )
                    ) {
                        SearchResultRowView(result: result)
                    }
                }
            }
            // 正常的资产列表
            else if !viewModel.isLoading && !viewModel.assetLocations.isEmpty {
                // 置顶位置section
                if !viewModel.pinnedLocations.isEmpty {
                    Section(
                        header: HStack {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                                .font(.system(size: 16))
                            Text(NSLocalizedString("Assets_Pinned_Locations", comment: ""))
                                .fontWeight(.semibold)
                                .font(.system(size: 18))
                                .foregroundColor(.primary)
                        }
                        .textCase(.none)
                    ) {
                        ForEach(viewModel.pinnedLocations, id: \.item_id) { location in
                            NavigationLink(
                                destination: LocationAssetsView(
                                    location: location,
                                    preloadedItemInfo: viewModel.itemInfoCache,
                                    stationNameCache: viewModel.stationNameCache,
                                    solarSystemNameCache: viewModel.solarSystemNameCache
                                )
                            ) {
                                LocationRowView(location: location)
                                    .environmentObject(viewModel)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    viewModel.togglePinLocation(location)
                                } label: {
                                    Label(
                                        NSLocalizedString("Assets_Unpin", comment: ""),
                                        systemImage: "pin.slash"
                                    )
                                }
                                .tint(.red)
                            }
                        }
                    }
                }

                // 其他位置按星域分组
                ForEach(viewModel.unpinnedLocationsByRegion, id: \.region) { group in
                    Section(
                        header: Text(group.region)
                            .fontWeight(.semibold)
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
                                    location: location,
                                    preloadedItemInfo: viewModel.itemInfoCache,
                                    stationNameCache: viewModel.stationNameCache,
                                    solarSystemNameCache: viewModel.solarSystemNameCache
                                )
                            ) {
                                LocationRowView(location: location)
                                    .environmentObject(viewModel)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    viewModel.togglePinLocation(location)
                                } label: {
                                    Label(
                                        NSLocalizedString("Assets_Pin", comment: ""),
                                        systemImage: "pin"
                                    )
                                }
                                .tint(.blue)
                            }
                        }
                    }
                }
            }

            // 数据加载时间信息（仅在debug模式下显示）
            if enableLogging, let loadTime = viewModel.dataLoadTime, !viewModel.isLoading {
                Section {
                    HStack {
                        Spacer()
                        DataLoadTimeView(loadTime: loadTime)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
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
        .navigationTitle(NSLocalizedString("Main_Corporation_Assets", comment: ""))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    refreshData()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                        .animation(
                            isRefreshing
                                ? .linear(duration: 1).repeatForever(autoreverses: false)
                                : .default, value: isRefreshing
                        )
                }
                .disabled(isRefreshing || viewModel.isLoading)
            }
        }
    }

    private func refreshData() {
        isRefreshing = true

        Task {
            await viewModel.loadAssets(forceRefresh: true)
            isRefreshing = false
        }
    }
}
