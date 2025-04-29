import SwiftUI

struct PlanetaryProduct: Identifiable {
    let id: Int
    let name: String
    let icon: String

    init(typeId: Int, name: String, icon: String) {
        self.id = typeId
        self.name = name
        self.icon = icon
    }
}

// 主权势力信息
struct SovereigntyInfo: Identifiable {
    let id: Int
    let name: String
    let icon: Image?
    let systemCount: Int
    let isAlliance: Bool  // true为联盟，false为派系
}

// 图标加载器
class AllianceIconLoader: ObservableObject {
    @Published var icons: [Int: Image] = [:]
    @Published var loadingIconIds: Set<Int> = []
    private var tasks: [Int: Task<Void, Never>] = [:]
    private var pendingIds: [Int] = []
    private let maxConcurrentTasks = 5  // 最大并发

    func loadIcon(for id: Int) {
        guard !icons.keys.contains(id) && !loadingIconIds.contains(id) else { return }

        // 如果已经有三个任务在执行，则加入等待队列
        if loadingIconIds.count >= maxConcurrentTasks {
            if !pendingIds.contains(id) {
                pendingIds.append(id)
            }
            return
        }

        loadingIconIds.insert(id)

        let task = Task {
            do {
                let allianceImage = try await AllianceAPI.shared.fetchAllianceLogo(
                    allianceID: id,
                    size: 64,
                    forceRefresh: false
                )

                try Task.checkCancellation()

                _ = await MainActor.run {
                    icons[id] = Image(uiImage: allianceImage)
                    loadingIconIds.remove(id)

                    // 检查等待队列，继续加载下一个
                    checkPendingQueue()
                }
            } catch {
                if !Task.isCancelled {
                    Logger.error("加载联盟图标失败: \(error.localizedDescription)")
                    _ = await MainActor.run {
                        loadingIconIds.remove(id)

                        // 即使失败也要继续加载等待队列中的下一个
                        checkPendingQueue()
                    }
                }
            }
        }

        tasks[id] = task
    }

    private func checkPendingQueue() {
        // 从等待队列中取出下一个ID并加载
        if let nextId = pendingIds.first, loadingIconIds.count < maxConcurrentTasks {
            pendingIds.removeFirst()
            loadIcon(for: nextId)
        }
    }

    func loadIcons(for ids: [Int]) {
        for id in ids {
            loadIcon(for: id)
        }
    }

    func cancelAllTasks() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        pendingIds.removeAll()
        loadingIconIds.removeAll()
    }

    deinit {
        cancelAllTasks()
    }
}

// 主权选择视图
struct SovereigntySelectorView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var sovereignties: [SovereigntyInfo] = []
    @State private var isLoading = true
    @Binding var selectedSovereigntyID: Int?
    @Binding var selectedSovereigntyName: String?
    @State private var isSearchActive = false
    @StateObject private var iconLoader = AllianceIconLoader()

    var body: some View {
        VStack {
            if isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(1.5)
                    .padding()
                Text(NSLocalizedString("Loading_Sovereignty", comment: "加载主权信息中..."))
                    .foregroundColor(.gray)
                Spacer()
            } else {
                List {
                    // 添加"所有主权"选项
                    Button(action: {
                        selectedSovereigntyID = nil
                        selectedSovereigntyName = nil
                        dismiss()
                    }) {
                        HStack {
                            Text(NSLocalizedString("Sovereignty_All", comment: "所有主权"))
                                .foregroundColor(.primary)
                            Spacer()
                            if selectedSovereigntyID == nil {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }

                    // 过滤并显示主权列表
                    ForEach(filteredSovereignties, id: \.id) { sovereignty in
                        Button(action: {
                            selectedSovereigntyID = sovereignty.id
                            selectedSovereigntyName = sovereignty.name
                            dismiss()
                        }) {
                            HStack {
                                if let icon = iconLoader.icons[sovereignty.id] ?? sovereignty.icon {
                                    icon
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 32, height: 32)
                                        .cornerRadius(6)
                                } else {
                                    // 显示加载中的图标
                                    ProgressView()
                                        .frame(width: 32, height: 32)
                                        .background(Color.gray.opacity(0.1))
                                        .cornerRadius(6)
                                }

                                VStack(alignment: .leading) {
                                    Text(sovereignty.name)
                                        .foregroundColor(.primary)
                                    Text(
                                        "\(sovereignty.systemCount) \(NSLocalizedString("Sovereignty_Systems", comment: "个星系"))"
                                    )
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                }

                                Spacer()

                                if selectedSovereigntyID == sovereignty.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
            }
        }
        .searchable(
            text: $searchText,
            isPresented: $isSearchActive,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: NSLocalizedString("Sovereignty_Search_Placeholder", comment: "搜索主权势力...")
        )
        .navigationTitle(NSLocalizedString("Sovereignty_Search_Title", comment: "选择主权"))
        .onAppear {
            loadSovereigntyData()
        }
        .onDisappear {
            iconLoader.cancelAllTasks()
        }
    }

    // 过滤后的主权列表
    private var filteredSovereignties: [SovereigntyInfo] {
        if searchText.isEmpty {
            return sovereignties
        } else {
            return sovereignties.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }

    // 加载主权数据
    private func loadSovereigntyData() {
        isLoading = true

        Task {
            do {
                // 获取主权数据
                let sovereigntyData = try await SovereigntyDataAPI.shared.fetchSovereigntyData(
                    forceRefresh: false)

                // 处理主权数据
                var allianceToSystems: [Int: Int] = [:]  // 联盟ID -> 星系数量
                var factionToSystems: [Int: Int] = [:]  // 派系ID -> 星系数量

                // 统计每个联盟和派系拥有的星系数量
                for data in sovereigntyData {
                    if let allianceId = data.allianceId {
                        allianceToSystems[allianceId, default: 0] += 1
                    }
                    if let factionId = data.factionId {
                        factionToSystems[factionId, default: 0] += 1
                    }
                }

                // 创建主权信息列表（先不包含图标）
                var tempSovereignties: [SovereigntyInfo] = []
                var allianceIds: [Int] = []

                // 获取联盟名称
                allianceIds = Array(allianceToSystems.keys)
                let allianceNamesWithCategories = try await UniverseAPI.shared.getNamesWithFallback(
                    ids: allianceIds)

                // 添加联盟信息（暂无图标）
                for (allianceId, systemCount) in allianceToSystems {
                    if let allianceName = allianceNamesWithCategories[allianceId]?.name {
                        tempSovereignties.append(
                            SovereigntyInfo(
                                id: allianceId,
                                name: allianceName,
                                icon: nil,
                                systemCount: systemCount,
                                isAlliance: true
                            ))
                    }
                }

                // 加载派系信息
                let factionQuery = """
                        SELECT id, iconName, name 
                        FROM factions 
                        WHERE id IN (\(factionToSystems.keys.map { String($0) }.joined(separator: ",")))
                    """

                if case let .success(rows) = databaseManager.executeQuery(factionQuery) {
                    for row in rows {
                        if let factionId = row["id"] as? Int,
                            let iconName = row["iconName"] as? String,
                            let name = row["name"] as? String,
                            let systemCount = factionToSystems[factionId]
                        {

                            let icon = IconManager.shared.loadImage(for: iconName)

                            tempSovereignties.append(
                                SovereigntyInfo(
                                    id: factionId,
                                    name: name,
                                    icon: icon,
                                    systemCount: systemCount,
                                    isAlliance: false
                                ))
                        }
                    }
                }

                // 按星系数量排序
                tempSovereignties.sort { $0.systemCount > $1.systemCount }

                // 更新UI显示主权列表（可能部分联盟图标尚未加载）
                await MainActor.run {
                    sovereignties = tempSovereignties
                    isLoading = false

                    // 开始加载图标
                    iconLoader.loadIcons(for: allianceIds)
                }

            } catch {
                Logger.error("加载主权数据失败: \(error.localizedDescription)")
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }
}

// 星系搜索结果
struct SystemSearchResult: Identifiable {
    let id: Int
    let systemId: Int
    let systemName: String
    let regionName: String
    let security: Double
    let score: Double
    let availableResources: [Int: Int]
    let additionalResources: [Int: (resourceId: Int, jumps: Int)]
    let missingResources: [Int]
    let coverage: Double
}

struct PlanetarySiteFinder: View {
    let characterId: Int?
    @State private var selectedProduct: PlanetaryProduct?
    @State private var selectedRegionID: Int? = nil
    @State private var selectedRegionName: String? = nil
    @State private var selectedSovereigntyID: Int? = nil
    @State private var selectedSovereigntyName: String? = nil
    @State private var selectedJumpRange: Int = 0  // 默认0跳
    @State private var showProductSelector = false
    @State private var showRegionSelector = false
    @State private var showSovereigntySelector = false
    @State private var isCalculating = false
    @State private var searchResults: [SystemSearchResult] = []  // 存储搜索结果
    @State private var showResults = false  // 控制结果显示
    @State private var showSelected = false  // 选物品时不显示右侧选中标记
    @StateObject private var databaseManager = DatabaseManager.shared
    private let resourceCalculator: PlanetaryResourceCalculator

    private static let allowedMarketGroups: Set<Int> = [1334, 1335, 1336, 1337]
    private static let jumpRangeOptions = [0, 1, 2, 3, 4, 5]

    init(characterId: Int?) {
        self.characterId = characterId
        self.resourceCalculator = PlanetaryResourceCalculator(
            databaseManager: DatabaseManager.shared)
    }

    // 判断是否可以开始计算
    private var isCalculationEnabled: Bool {
        // 如果正在计算中，按钮不可用
        if isCalculating {
            return false
        }

        // 必须选择产品
        guard selectedProduct != nil else {
            return false
        }

        // 必须选择星域或主权势力
        guard selectedRegionID != nil || selectedSovereigntyID != nil else {
            return false
        }

        return true
    }

    var body: some View {
        VStack {
            List {
                Section(
                    header: Text(NSLocalizedString("Main_Planetary_Filter_Conditions", comment: ""))
                ) {
                    // 选择行星产品
                    Button {
                        showProductSelector = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(
                                    NSLocalizedString("Main_Planetary_Select_Product", comment: "")
                                )
                                .foregroundColor(.primary)
                                Text(
                                    NSLocalizedString(
                                        "Planetary_Product_Description", comment: "要生产什么产品")
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            Spacer()
                            if let product = selectedProduct {
                                HStack {
                                    Image(
                                        uiImage: IconManager.shared.loadUIImage(for: product.icon)
                                    )
                                    .resizable()
                                    .frame(width: 24, height: 24)
                                    Text(product.name)
                                }
                                .foregroundColor(.gray)
                            } else {
                                Text(NSLocalizedString("Main_Planetary_Not_Selected", comment: ""))
                                    .foregroundColor(.gray)
                            }
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                    }

                    // 选择星域
                    Button {
                        showRegionSelector = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(NSLocalizedString("Main_Planetary_Select_Region", comment: ""))
                                    .foregroundColor(.primary)
                                Text(
                                    NSLocalizedString(
                                        "Planetary_Region_Description", comment: "要在哪个星域生产")
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            Spacer()
                            if let regionName = selectedRegionName {
                                Text(regionName)
                                    .foregroundColor(.gray)
                            } else {
                                Text(NSLocalizedString("Main_Planetary_Not_Selected", comment: ""))
                                    .foregroundColor(.gray)
                            }
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                    }

                    Button {
                        showSovereigntySelector = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(
                                    NSLocalizedString(
                                        "Main_Planetary_Select_Sovereignty", comment: "")
                                )
                                .foregroundColor(.primary)
                                Text(
                                    NSLocalizedString(
                                        "Planetary_Sovereignty_Description", comment: "要在哪个主权辖区生产")
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            Spacer()
                            if let sovereigntyName = selectedSovereigntyName {
                                Text(sovereigntyName)
                                    .foregroundColor(.gray)
                            } else {
                                Text(NSLocalizedString("Main_Planetary_Not_Selected", comment: ""))
                                    .foregroundColor(.gray)
                            }
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                    }

                    // 选择星系范围
                    Picker(selection: $selectedJumpRange) {
                        ForEach(PlanetarySiteFinder.jumpRangeOptions, id: \.self) { jumps in
                            Text(
                                "\(jumps) \(NSLocalizedString("Main_Planetary_Jumps", comment: "跳"))"
                            )
                            .tag(jumps)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(NSLocalizedString("Main_Planetary_Jump_Range", comment: "星系范围"))
                                .foregroundColor(.primary)
                            Text(
                                NSLocalizedString(
                                    "Planetary_Jump_Description", comment: "最多允许在几跳范围内收集资源")
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            }

            // 底部计算按钮
            Button(action: {
                calculatePlanetarySites()
            }) {
                HStack {
                    if isCalculating {
                        ProgressView()
                            .scaleEffect(0.8)
                            .padding(.trailing, 8)
                    }
                    Text(NSLocalizedString("Main_Planetary_Calculate", comment: ""))
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(isCalculationEnabled ? Color.blue : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .disabled(!isCalculationEnabled || isCalculating)
            .padding()
        }
        .navigationTitle(NSLocalizedString("Main_Planetary_location_calc", comment: ""))
        .sheet(isPresented: $showProductSelector) {
            NavigationView {
                MarketItemSelectorIntegratedView(
                    databaseManager: databaseManager,
                    title: NSLocalizedString("Main_Planetary_Select_Product", comment: ""),
                    allowedMarketGroups: PlanetarySiteFinder.allowedMarketGroups,
                    allowTypeIDs: [],
                    existingItems: [],
                    onItemSelected: { item in
                        selectedProduct = PlanetaryProduct(
                            typeId: item.id,
                            name: item.name,
                            icon: item.iconFileName
                        )
                        showProductSelector = false
                    },
                    onItemDeselected: { _ in },
                    onDismiss: { showProductSelector = false },
                    showSelected: showSelected
                )
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(isPresented: $showRegionSelector) {
            NavigationView {
                RegionSearchView(
                    databaseManager: databaseManager,
                    selectedRegionID: $selectedRegionID,
                    selectedRegionName: $selectedRegionName
                )
            }
        }
        .sheet(isPresented: $showSovereigntySelector) {
            NavigationView {
                SovereigntySelectorView(
                    databaseManager: databaseManager,
                    selectedSovereigntyID: $selectedSovereigntyID,
                    selectedSovereigntyName: $selectedSovereigntyName
                )
            }
        }
        .navigationDestination(isPresented: $showResults) {
            PlanetarySearchResultView(results: searchResults)
        }
    }

    private func calculatePlanetarySites() {
        isCalculating = true
        searchResults = []  // 清空之前的结果
        showResults = false

        // 首先确保已选择产品
        guard let product = selectedProduct else {
            Logger.error("未选择产品")
            isCalculating = false
            return
        }

        // 计算基础资源需求
        let baseResources = resourceCalculator.calculateBaseResources(for: product.id)

        // 如果找到了基础资源，才继续查询可用行星
        if !baseResources.isEmpty {
            // 查找每种资源可用的行星类型
            let resourcePlanets = resourceCalculator.findResourcePlanets(
                for: baseResources.map { $0.typeId })

            // 加载星图数据
            guard let path = Bundle.main.path(forResource: "neighbours_data", ofType: "json") else {
                Logger.error("无法找到星图文件路径")
                isCalculating = false
                return
            }

            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                guard let starMap = try JSONSerialization.jsonObject(with: data) as? [String: [Int]]
                else {
                    Logger.error("解析星图数据失败：数据格式不正确")
                    isCalculating = false
                    return
                }

                // 筛选符合条件的星系
                var filteredSystems = Set(starMap.keys.compactMap { Int($0) })

                // 如果选择了星域，筛选该星域内的星系
                if let regionId = selectedRegionID {
                    let query = "SELECT solarsystem_id FROM universe WHERE region_id = ?"
                    if case let .success(rows) = databaseManager.executeQuery(
                        query, parameters: [regionId])
                    {
                        let systemsInRegion = Set(
                            rows.compactMap { row in
                                row["solarsystem_id"] as? Int
                            })
                        filteredSystems = filteredSystems.intersection(systemsInRegion)
                    }
                }

                // 如果选择了主权，筛选该主权下的星系
                if let sovereigntyId = selectedSovereigntyID {
                    Task {
                        do {
                            // 获取主权数据
                            let sovereigntyData = try await SovereigntyDataAPI.shared
                                .fetchSovereigntyData(forceRefresh: false)

                            // 根据是否为联盟ID筛选
                            let systemsUnderSovereignty = Set(
                                sovereigntyData.compactMap { data -> Int? in
                                    if data.allianceId == sovereigntyId
                                        || data.factionId == sovereigntyId
                                    {
                                        return data.systemId
                                    }
                                    return nil
                                })

                            filteredSystems = filteredSystems.intersection(systemsUnderSovereignty)

                            // 计算星系评分
                            let scoredSystems = resourceCalculator.calculateSystemScores(
                                for: filteredSystems,
                                requiredResources: baseResources,
                                resourcePlanets: resourcePlanets,
                                maxJumps: selectedJumpRange,
                                starMap: starMap
                            )

                            // 转换结果为SystemSearchResult数组
                            var results: [SystemSearchResult] = []
                            for (index, system) in scoredSystems.prefix(10).enumerated() {
                                // 计算资源覆盖率
                                var coveredResources = Set<Int>()
                                for (resourceId, _) in system.availableResources {
                                    coveredResources.insert(resourceId)
                                }
                                for (_, info) in system.additionalResources {
                                    coveredResources.insert(info.resourceId)
                                }

                                let coveredCount = coveredResources.count
                                let totalCount = baseResources.count
                                let coverage = Double(coveredCount) / Double(totalCount) * 100

                                results.append(
                                    SystemSearchResult(
                                        id: index,
                                        systemId: system.systemId,
                                        systemName: system.systemName,
                                        regionName: system.regionName,
                                        security: system.security,
                                        score: system.score,
                                        availableResources: system.availableResources,
                                        additionalResources: system.additionalResources,
                                        missingResources: system.missingResources,
                                        coverage: coverage
                                    ))
                            }

                            // 更新UI
                            await MainActor.run {
                                searchResults = results
                                showResults = true
                                isCalculating = false
                            }
                        } catch {
                            Logger.error("获取主权数据失败：\(error)")
                            isCalculating = false
                        }
                    }
                } else {
                    // 如果没有选择主权，直接计算评分
                    let scoredSystems = resourceCalculator.calculateSystemScores(
                        for: filteredSystems,
                        requiredResources: baseResources,
                        resourcePlanets: resourcePlanets,
                        maxJumps: selectedJumpRange,
                        starMap: starMap
                    )

                    // 转换结果为SystemSearchResult数组
                    var results: [SystemSearchResult] = []
                    for (index, system) in scoredSystems.prefix(20).enumerated() {  // 保留 top 20
                        // 计算资源覆盖率
                        var coveredResources = Set<Int>()
                        for (resourceId, _) in system.availableResources {
                            coveredResources.insert(resourceId)
                        }
                        for (_, info) in system.additionalResources {
                            coveredResources.insert(info.resourceId)
                        }

                        let coveredCount = coveredResources.count
                        let totalCount = baseResources.count
                        let coverage = Double(coveredCount) / Double(totalCount) * 100

                        results.append(
                            SystemSearchResult(
                                id: index,
                                systemId: system.systemId,
                                systemName: system.systemName,
                                regionName: system.regionName,
                                security: system.security,
                                score: system.score,
                                availableResources: system.availableResources,
                                additionalResources: system.additionalResources,
                                missingResources: system.missingResources,
                                coverage: coverage
                            ))
                    }

                    // 更新UI
                    searchResults = results
                    showResults = true
                    isCalculating = false
                }
            } catch {
                Logger.error("加载星图数据失败：\(error)")
                isCalculating = false
            }
        } else {
            Logger.warning("未找到基础资源")
            isCalculating = false
            return
        }
    }
}
