import SwiftUI

struct RegionMapView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @StateObject private var zoom = StarMapZoomController()
    @State private var regions: [RegionData] = []
    @State private var graph: MapGraph = .empty
    @State private var regionNames: [Int: String] = [:]
    @State private var isLoading = true
    @State private var navTarget: RegionNavigation?
    @State private var resetToken = 0
    @State private var didLoad = false
    @State private var searchText = ""
    @State private var isSearchActive = false
    @State private var matchedRegionIds: Set<Int> = []
    @State private var searchResults: [StarMapSearchResult] = []
    @State private var graphRevision = 0
    @State private var searchTask: Task<Void, Never>?
    @State private var skipNextSearchChange = false
    /// 按星域分组的匹配星系 ID（performSearch 中收集，供导航到星域地图时高亮）
    @State private var regionSystemIds: [Int: [Int]] = [:]
    /// 包含入侵星系的星域 ID
    @State private var invadedRegionIds: Set<Int> = []
    @State private var incursionTask: Task<Void, Never>?

    private var searchPlaceholder: String {
        "\(NSLocalizedString("StarMap_Search_Region", comment: "搜索星域")) / \(NSLocalizedString("StarMap_Search_System", comment: "搜索星系"))"
    }

    var body: some View {
        ZStack {
            ZoomableMapView(
                graph: graph,
                resetToken: resetToken,
                zoomController: zoom,
                onNodeTap: { regionId in
                    guard let name = regionNames[regionId] else { return }
                    // 只有点击高亮星域时才传入待高亮的星系 ID 列表
                    let systemIds = matchedRegionIds.contains(regionId) ? (regionSystemIds[regionId] ?? []) : []
                    navTarget = .regionMap(regionId, name, systemIds)
                }
            )
            .ignoresSafeArea(edges: .top)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: 60)
            }
            .allowsHitTesting(!isLoading && !graph.nodes.isEmpty)

            if isLoading {
                ProgressView(NSLocalizedString("StarMap_Loading", comment: "Loading star map"))
                    .tint(.white)
            } else if graph.nodes.isEmpty {
                VStack(spacing: 12) {
                    Text(NSLocalizedString("StarMap_Load_Failed", comment: "Failed to load star map data"))
                        .foregroundColor(.red)
                    Button(NSLocalizedString("StarMap_Retry", comment: "Retry")) {
                        loadData()
                    }
                }
            }

            if !isLoading, !graph.nodes.isEmpty {
                // 搜索结果浮层（搜索激活时覆盖在地图上方）
                if isSearchActive, !searchText.isEmpty {
                    VStack {
                        StarMapSearchResultsOverlay(
                            results: searchResults,
                            onSelect: selectSearchResult
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                        Spacer(minLength: 0)
                            .allowsHitTesting(false)
                    }
                }

                // 底部横向缩放条
                VStack {
                    Spacer(minLength: 0)
                        .allowsHitTesting(false)

                    StarMapZoomOverlay(zoom: zoom)
                        .padding(.horizontal, 48)
                        .padding(.bottom, 12)
                }
            }
        }
        .searchable(
            text: $searchText,
            isPresented: $isSearchActive,
            prompt: Text(searchPlaceholder)
        )
        .onChange(of: searchText) { _, _ in
            if skipNextSearchChange {
                skipNextSearchChange = false
                return
            }
            scheduleSearch()
        }
        .starMapChrome(title: NSLocalizedString("StarMap_Title", comment: "Star Map"))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    clearSearch()
                    resetToken += 1
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .disabled(isLoading || graph.nodes.isEmpty)
                .help(NSLocalizedString("StarMap_Reset_View", comment: "Reset View"))
            }
        }
        .navigationDestination(item: $navTarget) { navigation in
            switch navigation {
            case let .regionMap(regionId, regionName, systemIds):
                RegionSystemMapView(
                    databaseManager: databaseManager,
                    regionId: regionId,
                    regionName: regionName,
                    highlightSystemIds: systemIds
                )
            }
        }
        .task {
            guard !didLoad else { return }
            didLoad = true
            loadData()
            await loadIncursionState()
        }
        .onAppear {
            guard didLoad else { return }
            incursionTask?.cancel()
            incursionTask = Task {
                await loadIncursionState()
            }
        }
        .onDisappear {
            searchTask?.cancel()
        }
    }

    private func clearSearch() {
        searchTask?.cancel()
        searchText = ""
        matchedRegionIds = []
        searchResults = []
        regionSystemIds = [:]
        rebuildGraph()
    }

    private func selectSearchResult(_ item: StarMapSearchResult) {
        // 跳过 searchText 变化触发的搜索，保留高亮状态
        skipNextSearchChange = true
        searchTask?.cancel()
        matchedRegionIds = [item.regionToHighlight]
        searchResults = [item]
        rebuildGraph()
        // 显示选择的名称，并退出搜索态（结果浮层随之隐藏）
        searchText = item.title
        isSearchActive = false
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let query = searchText
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 160_000_000)
            guard !Task.isCancelled else { return }
            await performSearch(query: query)
        }
    }

    @MainActor
    private func performSearch(query raw: String) async {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            matchedRegionIds = []
            searchResults = []
            regionSystemIds = [:]
            rebuildGraph()
            return
        }

        let availableRegionIds = Set(regions.map(\.region_id))
        var matched = Set<Int>()
        var hits: [StarMapSearchResult] = []
        var systemsByRegion: [Int: [Int]] = [:]

        for region in regions {
            let id = region.region_id
            guard let text = SDEMemoryStore.regionNames[id], text.matchesSearch(query) else {
                continue
            }
            let name = regionNames[id] ?? text.resolved()
            matched.insert(id)
            hits.append(
                StarMapSearchResult(
                    id: id,
                    highlightRegionId: id,
                    title: name,
                    subtitle: NSLocalizedString("Main_Language_Map_Type_Region", comment: "星域"),
                    accent: StarMapTheme.chipAccent
                )
            )
        }

        let regionHitsCount = hits.count
        let systemMatches: [(id: Int, name: String)] = await Task.detached(priority: .userInitiated) {
            var list: [(Int, String)] = []
            for (systemId, text) in SDEMemoryStore.solarSystemNames {
                guard text.matchesSearch(query) else { continue }
                list.append((systemId, text.resolved()))
            }
            list.sort { $0.1.localizedCompare($1.1) == .orderedAscending }
            return Array(list.prefix(40))
        }.value

        guard !Task.isCancelled else { return }

        let regionBySystem = lookupRegions(for: systemMatches.map(\.id))
        for match in systemMatches {
            guard let regionId = regionBySystem[match.id],
                  availableRegionIds.contains(regionId)
            else { continue }
            matched.insert(regionId)
            systemsByRegion[regionId, default: []].append(match.id)
            hits.append(
                StarMapSearchResult(
                    id: match.id,
                    highlightRegionId: regionId,
                    title: match.name,
                    subtitle: regionNames[regionId] ?? "",
                    accent: .secondary
                )
            )
        }

        // 结果列表：星域在前，星系最多再留 8 条给下拉
        let regionPart = Array(hits.prefix(regionHitsCount))
        let systemPart = Array(hits.suffix(from: regionHitsCount).prefix(8))
        searchResults = regionPart + systemPart
        matchedRegionIds = matched
        regionSystemIds = systemsByRegion
        rebuildGraph()
    }

    private func lookupRegions(for systemIds: [Int]) -> [Int: Int] {
        guard !systemIds.isEmpty else { return [:] }
        let placeholders = String(repeating: "?,", count: systemIds.count).dropLast()
        let sql = """
            SELECT solarsystem_id, region_id
            FROM universe
            WHERE solarsystem_id IN (\(placeholders))
        """
        guard
            case let .success(rows) = databaseManager.executeQuery(
                sql, parameters: systemIds.map { $0 as Any }
            )
        else {
            return [:]
        }
        var map: [Int: Int] = [:]
        for row in rows {
            guard let sid = row["solarsystem_id"] as? Int,
                  let rid = row["region_id"] as? Int
            else { continue }
            map[sid] = rid
        }
        return map
    }

    private func rebuildGraph() {
        graphRevision += 1
        var built = StarMapGraphBuilder.buildRegionGraph(
            regions: regions,
            names: regionNames,
            searchMatchedIds: matchedRegionIds,
            incursionRegionIds: invadedRegionIds
        )
        built.revision = graphRevision
        graph = built
    }

    private func loadIncursionState() async {
        let systemIds = await StarMapIncursions.fetchInvadedSystemIDs()
        guard !Task.isCancelled else { return }

        let regionIds = Set(lookupRegions(for: systemIds.sorted()).values)
        guard !Task.isCancelled else { return }

        invadedRegionIds = regionIds
        rebuildGraph()
    }

    private func loadData() {
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async {
            let regions = self.loadRegionData()
            guard !regions.isEmpty else {
                DispatchQueue.main.async { self.isLoading = false }
                return
            }

            var names: [Int: String] = [:]
            for region in regions {
                guard let text = SDEMemoryStore.regionNames[region.region_id] else { continue }
                names[region.region_id] = text.resolved()
            }

            DispatchQueue.main.async {
                var built = StarMapGraphBuilder.buildRegionGraph(
                    regions: regions,
                    names: names,
                    incursionRegionIds: self.invadedRegionIds
                )
                built.revision = 1
                self.regions = regions
                self.regionNames = names
                self.graph = built
                self.graphRevision = 1
                self.isLoading = false
            }
        }
    }

    private func loadRegionData() -> [RegionData] {
        guard let url = StaticResourceManager.shared.getMapDataURL(filename: "regions_data"),
              let data = try? Data(contentsOf: url),
              let regions = try? JSONDecoder().decode([RegionData].self, from: data)
        else {
            Logger.error("无法加载 regions_data.json")
            return []
        }
        Logger.success("成功加载 \(regions.count) 个星域数据")
        return regions
    }
}
