import Foundation
import SwiftUI

struct RegionSystemMapView: View {
    @ObservedObject var databaseManager: DatabaseManager
    let regionId: Int
    let regionName: String
    let highlightSystemIds: [Int]

    @StateObject private var zoom = StarMapZoomController()
    @State private var systemNodes: [SystemNodeData] = []
    @State private var graph: MapGraph = .empty
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var isSearchActive = false
    @State private var filteredNodes: [SystemNodeData] = []
    @State private var selectedSystemId: Int?
    @State private var focusNodeId: Int?
    @State private var selectedFilter: PlanetFilter = .all
    @State private var filteredSystemIds: Set<Int> = []
    @State private var resetToken = 0
    @State private var graphRevision = 0
    @State private var didLoad = false
    @State private var skipNextSearchChange = false
    /// 当前处于入侵影响范围的星系 ID
    @State private var invadedSystemIds: Set<Int> = []
    @State private var incursionTask: Task<Void, Never>?

    enum PlanetFilter: String, CaseIterable {
        case all, gas, temperate, barren, oceanic, ice, lava, storm, plasma, jove

        var displayName: String {
            switch self {
            case .all:
                return NSLocalizedString("StarMap_Filter_All", comment: "All")
            case .gas:
                return NSLocalizedString("StarMap_Filter_Gas", comment: "Planet (Gas)")
            case .temperate:
                return NSLocalizedString("StarMap_Filter_Temperate", comment: "Planet (Temperate)")
            case .barren:
                return NSLocalizedString("StarMap_Filter_Barren", comment: "Planet (Barren)")
            case .oceanic:
                return NSLocalizedString("StarMap_Filter_Oceanic", comment: "Planet (Oceanic)")
            case .ice:
                return NSLocalizedString("StarMap_Filter_Ice", comment: "Planet (Ice)")
            case .lava:
                return NSLocalizedString("StarMap_Filter_Lava", comment: "Planet (Lava)")
            case .storm:
                return NSLocalizedString("StarMap_Filter_Storm", comment: "Planet (Storm)")
            case .plasma:
                return NSLocalizedString("StarMap_Filter_Plasma", comment: "Planet (Plasma)")
            case .jove:
                return NSLocalizedString("StarMap_Filter_Jove", comment: "Jove Observatory")
            }
        }

        var color: Color {
            switch self {
            case .all: return .clear
            case .gas: return Color(red: 182 / 255, green: 180 / 255, blue: 164 / 255)
            case .temperate: return Color(red: 86 / 255, green: 113 / 255, blue: 112 / 255)
            case .barren: return Color(red: 183 / 255, green: 171 / 255, blue: 152 / 255)
            case .oceanic: return Color(red: 59 / 255, green: 98 / 255, blue: 103 / 255)
            case .ice: return Color(red: 107 / 255, green: 113 / 255, blue: 122 / 255)
            case .lava: return Color(red: 190 / 255, green: 118 / 255, blue: 70 / 255)
            case .storm: return Color(red: 87 / 255, green: 106 / 255, blue: 120 / 255)
            case .plasma: return Color(red: 102 / 255, green: 194 / 255, blue: 194 / 255)
            case .jove: return Color(red: 229 / 255, green: 228 / 255, blue: 173 / 255)
            }
        }

        var databaseField: String {
            switch self {
            case .all: return ""
            case .gas: return "gas"
            case .temperate: return "temperate"
            case .barren: return "barren"
            case .oceanic: return "oceanic"
            case .ice: return "ice"
            case .lava: return "lava"
            case .storm: return "storm"
            case .plasma: return "plasma"
            case .jove: return "jove"
            }
        }
    }

    private var searchResults: [StarMapSearchResult] {
        filteredNodes.map { node in
            StarMapSearchResult(
                id: node.systemId,
                title: node.name,
                subtitle: formatSystemSecurity(node.security),
                accent: getSecurityColor(node.security)
            )
        }
    }

    var body: some View {
        ZStack {
            ZoomableMapView(
                graph: graph,
                resetToken: resetToken,
                focusNodeId: focusNodeId,
                zoomController: zoom,
                onNodeTap: { systemId in
                    guard let node = systemNodes.first(where: { $0.systemId == systemId }),
                          !node.isExternal
                    else { return }
                    selectedSystemId = systemId
                    rebuildGraph(focus: false)
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
                    Text(
                        NSLocalizedString(
                            "StarMap_Load_Failed", comment: "Failed to load star map data"
                        )
                    )
                    .foregroundColor(.red)
                    Button(NSLocalizedString("StarMap_Retry", comment: "Retry")) {
                        loadData()
                    }
                }
            }

            if !isLoading, !systemNodes.isEmpty {
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
            prompt: Text(NSLocalizedString("StarMap_Search_System", comment: "搜索星系"))
        )
        .onChange(of: searchText) { _, _ in
            if skipNextSearchChange {
                skipNextSearchChange = false
                return
            }
            filterSystems()
        }
        .starMapChrome(title: regionName)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 14) {
                    Menu {
                        ForEach(PlanetFilter.allCases, id: \.self) { filter in
                            Button {
                                selectedFilter = filter
                                applyFilter()
                            } label: {
                                HStack {
                                    Text(filter.displayName)
                                    if selectedFilter == filter {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(selectedFilter == .all ? Color.accentColor : StarMapTheme.chipAccent)
                    }
                    .disabled(isLoading || systemNodes.isEmpty)

                    Button {
                        searchText = ""
                        selectedSystemId = nil
                        focusNodeId = nil
                        filteredNodes = []
                        selectedFilter = .all
                        filteredSystemIds.removeAll()
                        rebuildGraph(focus: false)
                        resetToken += 1
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .disabled(isLoading || systemNodes.isEmpty)
                    .help(NSLocalizedString("StarMap_Reset_View", comment: "Reset View"))
                }
            }
        }
        .task {
            guard !didLoad else { return }
            didLoad = true
            selectedFilter = .all
            filteredSystemIds.removeAll()
            loadData()
            await loadIncursionState()
        }
        .onAppear {
            guard didLoad else { return } // 首次由 .task 处理
            incursionTask?.cancel()
            incursionTask = Task {
                await loadIncursionState()
            }
        }
    }

    private func selectSearchResult(_ item: StarMapSearchResult) {
        // 跳过 searchText 变化触发的过滤，保留选中状态
        skipNextSearchChange = true
        selectedSystemId = item.id
        filteredNodes = systemNodes.filter { $0.systemId == item.id }
        rebuildGraph(focus: true)
        // 显示选择的名称，并退出搜索态（结果浮层随之隐藏）
        searchText = item.title
        isSearchActive = false
    }

    // MARK: - Data

    private func loadIncursionState() async {
        let systemIds = await StarMapIncursions.fetchInvadedSystemIDs()
        guard !Task.isCancelled else { return }

        invadedSystemIds = systemIds
        rebuildGraph(focus: false)
    }

    private func loadData() {
        isLoading = true
        let regionId = self.regionId
        let highlightIds = Set(highlightSystemIds)

        DispatchQueue.global(qos: .userInitiated).async {
            guard let mapData = Self.loadMapData(regionId: regionId) else {
                DispatchQueue.main.async { self.isLoading = false }
                return
            }

            let localIds = Array(mapData.systems.keys).compactMap { Int($0) }
            let systemInfo = self.querySystemInfo(systemIds: localIds)
            let nodes = self.buildSystemNodes(mapData: mapData, systemInfo: systemInfo)

            let matchedNodes: [SystemNodeData] = highlightIds.isEmpty
                ? []
                : nodes.filter { highlightIds.contains($0.systemId) }

            DispatchQueue.main.async {
                // 如果入侵数据已加载则直接纳入；否则 loadIncursionState 回来后会重建
                var built = StarMapGraphBuilder.buildSystemGraph(
                    systems: nodes,
                    selectedId: nil,
                    searchMatchedIds: Set(matchedNodes.map(\.systemId)),
                    filterMatchedIds: nil,
                    filter: .all,
                    incursionSystemIds: self.invadedSystemIds
                )
                self.systemNodes = nodes
                self.filteredNodes = matchedNodes
                self.graphRevision += 1
                built.revision = self.graphRevision
                self.graph = built
                self.isLoading = false
                if self.selectedFilter != .all {
                    self.applyFilter()
                }
            }
        }
    }

    private static func loadMapData(regionId: Int) -> SystemMapData? {
        guard let url = StaticResourceManager.shared.getMapDataURL(filename: "systems_data"),
              let data = try? Data(contentsOf: url),
              let allSystemsData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let regionData = allSystemsData[String(regionId)] as? [String: Any],
              let jsonData = try? JSONSerialization.data(withJSONObject: regionData),
              let mapData = try? JSONDecoder().decode(SystemMapData.self, from: jsonData)
        else {
            Logger.error("无法加载星域 \(regionId) 的地图数据")
            return nil
        }
        Logger.success("成功加载星域 \(regionId) 的地图数据（\(mapData.systems.count) 个星系）")
        return mapData
    }

    private func querySystemInfo(systemIds: [Int]) -> [Int: (
        name: String, security: Double, regionId: Int, planetCounts: PlanetCounts
    )] {
        guard !systemIds.isEmpty else { return [:] }

        let placeholders = String(repeating: "?,", count: systemIds.count).dropLast()
        let sql = """
            SELECT solarsystem_id, system_security, region_id,
                   gas, temperate, barren, oceanic, ice, lava, storm, plasma, jove
            FROM universe
            WHERE solarsystem_id IN (\(placeholders))
        """

        guard
            case let .success(rows) = databaseManager.executeQuery(
                sql, parameters: systemIds.map { $0 as Any }
            )
        else {
            Logger.error("查询星系信息失败")
            return [:]
        }

        var systemInfo:
            [Int: (name: String, security: Double, regionId: Int, planetCounts: PlanetCounts)] = [:]
        for row in rows {
            guard let id = row["solarsystem_id"] as? Int,
                  let security = row["system_security"] as? Double,
                  let regionId = row["region_id"] as? Int,
                  let names = SDEMemoryStore.solarSystemNames[id]
            else { continue }

            let name = names.resolved()
            guard !name.isEmpty else { continue }

            systemInfo[id] = (
                name: name,
                security: security,
                regionId: regionId,
                planetCounts: PlanetCounts(
                    gas: row["gas"] as? Int ?? 0,
                    temperate: row["temperate"] as? Int ?? 0,
                    barren: row["barren"] as? Int ?? 0,
                    oceanic: row["oceanic"] as? Int ?? 0,
                    ice: row["ice"] as? Int ?? 0,
                    lava: row["lava"] as? Int ?? 0,
                    storm: row["storm"] as? Int ?? 0,
                    plasma: row["plasma"] as? Int ?? 0,
                    jove: row["jove"] as? Int ?? 0
                )
            )
        }
        return systemInfo
    }

    private func buildSystemNodes(
        mapData: SystemMapData,
        systemInfo: [Int: (
            name: String, security: Double, regionId: Int, planetCounts: PlanetCounts
        )]
    ) -> [SystemNodeData] {
        var nodes: [SystemNodeData] = []
        for (systemIdStr, position) in mapData.systems {
            guard let systemId = Int(systemIdStr), let info = systemInfo[systemId] else { continue }
            nodes.append(
                SystemNodeData(
                    systemId: systemId,
                    name: info.name,
                    security: info.security,
                    regionId: info.regionId,
                    position: CGPoint(x: position.x, y: position.y),
                    connections: mapData.jumps[systemIdStr]?.compactMap { Int($0) } ?? [],
                    planetCounts: info.planetCounts
                )
            )
        }
        return nodes
    }

    private func rebuildGraph(focus: Bool) {
        graphRevision += 1
        var built = StarMapGraphBuilder.buildSystemGraph(
            systems: systemNodes,
            selectedId: selectedSystemId,
            searchMatchedIds: Set(filteredNodes.map(\.systemId)),
            filterMatchedIds: selectedFilter == .all ? nil : filteredSystemIds,
            filter: selectedFilter,
            incursionSystemIds: invadedSystemIds
        )
        built.revision = graphRevision
        graph = built

        if focus, let selectedSystemId {
            focusNodeId = selectedSystemId
        }
    }

    private func filterSystems() {
        if searchText.isEmpty {
            filteredNodes = []
            selectedSystemId = nil
            focusNodeId = nil
            rebuildGraph(focus: false)
            return
        }

        filteredNodes = systemNodes.filter { system in
            guard !system.isExternal else { return false }
            if SDEMemoryStore.solarSystemNames[system.systemId]?.matchesSearch(searchText) == true {
                return true
            }
            return formatSystemSecurity(system.security).contains(searchText)
        }

        if filteredNodes.count == 1 {
            selectedSystemId = filteredNodes[0].systemId
            rebuildGraph(focus: true)
        } else {
            selectedSystemId = nil
            focusNodeId = nil
            rebuildGraph(focus: false)
        }
    }

    private func applyFilter() {
        if selectedFilter == .all {
            filteredSystemIds.removeAll()
            rebuildGraph(focus: false)
        } else {
            loadFilteredSystems()
        }
    }

    private func loadFilteredSystems() {
        let systemIds = systemNodes.map(\.systemId)
        guard !systemIds.isEmpty, selectedFilter != .all else {
            filteredSystemIds.removeAll()
            rebuildGraph(focus: false)
            return
        }

        let placeholders = String(repeating: "?,", count: systemIds.count).dropLast()
        let field = selectedFilter.databaseField
        let sql = """
            SELECT solarsystem_id
            FROM universe
            WHERE solarsystem_id IN (\(placeholders))
            AND \(field) > 0
        """

        guard
            case let .success(rows) = databaseManager.executeQuery(
                sql, parameters: systemIds.map { $0 as Any }
            )
        else {
            Logger.error("筛选星系失败")
            return
        }

        filteredSystemIds = Set(rows.compactMap { $0["solarsystem_id"] as? Int })
        rebuildGraph(focus: false)
    }
}
