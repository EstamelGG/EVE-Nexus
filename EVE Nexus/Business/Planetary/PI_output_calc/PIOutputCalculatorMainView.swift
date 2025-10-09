import Foundation
import SwiftUI

struct PIOutputCalculatorView: View {
    let characterId: Int?
    @State private var selectedSolarSystemId: Int? = nil
    @State private var selectedSolarSystemName: String = ""
    @State private var maxJumps: Int = 0
    @State private var showSolarSystemPicker = false
    // 存储星系范围内的所有星系ID
    @State private var systemsInRange: Set<Int> = []
    @State private var isCalculating = false
    // 存储P0资源信息
    @State private var p0Resources: [P0ResourceInfo] = []
    @State private var isLoadingP0Resources = false
    // 存储P1资源信息
    @State private var p1Resources: [P1ResourceInfo] = []
    @State private var isLoadingP1Resources = false
    // 存储P2资源信息
    @State private var p2Resources: [P2ResourceInfo] = []
    @State private var isLoadingP2Resources = false
    // 存储P3资源信息
    @State private var p3Resources: [P3ResourceInfo] = []
    @State private var isLoadingP3Resources = false
    // 存储P4资源信息
    @State private var p4Resources: [P4ResourceInfo] = []
    @State private var isLoadingP4Resources = false
    // 主权筛选
    @State private var selectedSovereigntyID: Int? = nil
    @State private var selectedSovereigntyName: String? = nil
    @State private var showSovereigntySelector = false

    private static let jumpRangeOptions = [0, 1, 2, 3, 4, 5]

    init(characterId: Int?) {
        self.characterId = characterId

        // 预加载资源缓存
        PIResourceCache.shared.preloadResourceInfo()
    }

    var body: some View {
        List {
            Section(header: Text(NSLocalizedString("PI_Output_Filter_Conditions", comment: ""))) {
                Button(action: {
                    showSolarSystemPicker = true
                }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(NSLocalizedString("PI_Output_Select_Solar_System", comment: ""))
                                .foregroundColor(.primary)
                            Text(
                                NSLocalizedString(
                                    "Planetary_System_Description", comment: "选择作为生产中心的星系"
                                )
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(
                            selectedSolarSystemName.isEmpty
                                ? NSLocalizedString("PI_Output_Not_Selected", comment: "")
                                : selectedSolarSystemName
                        )
                        .foregroundColor(.gray)
                        Image(systemName: "chevron.right")
                            .foregroundColor(.gray)
                    }
                }

                Picker(selection: $maxJumps) {
                    ForEach(PIOutputCalculatorView.jumpRangeOptions, id: \.self) { jumps in
                        Text("\(jumps) \(NSLocalizedString("Main_Planetary_Jumps", comment: "跳"))")
                            .tag(jumps)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("PI_Output_Max_Jumps", comment: ""))
                            .foregroundColor(.primary)
                        Text(
                            NSLocalizedString(
                                "Planetary_Jump_Description", comment: "最多允许在几跳范围内收集资源"
                            )
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
                .onChange(of: maxJumps) { _, _ in
                    if selectedSolarSystemId != nil {
                        calculateSystemsInRange()
                    }
                }

                // 只有当最大跳数大于0时才显示主权选择器
                if maxJumps > 0 {
                    Button {
                        showSovereigntySelector = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(
                                    NSLocalizedString(
                                        "Main_Planetary_Select_Sovereignty", comment: "选择主权"
                                    )
                                )
                                .foregroundColor(.primary)
                                Text(
                                    NSLocalizedString(
                                        "Planetary_Sovereignty_Description", comment: "要在哪个主权辖区生产"
                                    )
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            Spacer()
                            if let sovereigntyName = selectedSovereigntyName {
                                Text(sovereigntyName)
                                    .foregroundColor(.gray)
                            } else {
                                Text(
                                    NSLocalizedString("Main_Planetary_Not_Selected", comment: "未选择")
                                )
                                .foregroundColor(.gray)
                            }
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                    }
                }
            }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

            // 功能描述（当没有选择星系或正在计算时显示）
            if selectedSolarSystemId == nil && !isCalculating {
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(NSLocalizedString("PI_Output_Description_Title", comment: "行星工业产出计算器"))
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text(NSLocalizedString("PI_Output_Description_Text", comment: "功能描述"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // 添加显示计算结果的Section
            if isCalculating {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Text(NSLocalizedString("Misc_Calculating", comment: "计算中..."))
                            .foregroundColor(.gray)
                            .padding(.leading, 8)
                        Spacer()
                    }
                }
            } else if !systemsInRange.isEmpty {
                Section {
                    NavigationLink(
                        destination: SystemsListView(
                            title: NSLocalizedString("PI_Output_Systems_List", comment: "可用星系列表"),
                            systemIds: Array(systemsInRange),
                            selectedSystemId: selectedSolarSystemId
                        )
                    ) {
                        HStack {
                            Text(NSLocalizedString("PI_Output_View_Systems", comment: "查看星系列表"))
                            Spacer()
                            Text("\(systemsInRange.count)")
                                .foregroundColor(.gray)
                        }
                    }

                    NavigationLink(
                        destination: PlanetTypesSummaryView(
                            systemIds: Array(systemsInRange)
                        )
                    ) {
                        Text(NSLocalizedString("PI_Output_View_Planets", comment: "查看行星分布"))
                    }
                }

                // 添加资源列表入口
                Section(header: Text(NSLocalizedString("PI_Output_Resources", comment: "可用资源"))) {
                    // 检查是否有资源正在加载
                    if isLoadingP0Resources || isLoadingP1Resources || isLoadingP2Resources
                        || isLoadingP3Resources || isLoadingP4Resources
                    {
                        HStack {
                            Spacer()
                            ProgressView()
                            Text(
                                NSLocalizedString(
                                    "PI_Output_Loading_Resources", comment: "加载资源中..."
                                )
                            )
                            .foregroundColor(.gray)
                            .padding(.leading, 8)
                            Spacer()
                        }
                    } else {
                        // P0资源链接 - 仅当有可用P0资源时显示
                        if !p0Resources.isEmpty {
                            NavigationLink(
                                destination: PIResourcesListView(
                                    title: "P0",
                                    resources: p0Resources,
                                    systemIds: Array(systemsInRange),
                                    resourceLevel: 0,
                                    maxJumps: maxJumps,
                                    centerSystemId: selectedSolarSystemId
                                )
                            ) {
                                HStack {
                                    Text("P0")
                                    Spacer()
                                    Text(
                                        "\(p0Resources.count) \(NSLocalizedString("Types", comment: "种"))"
                                    )
                                    .foregroundColor(.gray)
                                }
                            }
                        }

                        // P1资源链接 - 仅当有可用P1资源时显示
                        let availableP1Resources = p1Resources.filter { $0.canProduce }
                        if !availableP1Resources.isEmpty {
                            NavigationLink(
                                destination: PIResourcesListView(
                                    title: "P1",
                                    resources: availableP1Resources,
                                    systemIds: Array(systemsInRange),
                                    resourceLevel: 1,
                                    maxJumps: maxJumps,
                                    centerSystemId: selectedSolarSystemId
                                )
                            ) {
                                HStack {
                                    Text("P1")
                                    Spacer()
                                    Text(
                                        "\(availableP1Resources.count) \(NSLocalizedString("Types", comment: "种"))"
                                    )
                                    .foregroundColor(.gray)
                                }
                            }
                        }

                        // P2资源链接 - 仅当有可用P2资源时显示
                        let availableP2Resources = p2Resources.filter { $0.canProduce }
                        if !availableP2Resources.isEmpty {
                            NavigationLink(
                                destination: PIResourcesListView(
                                    title: "P2",
                                    resources: availableP2Resources,
                                    systemIds: Array(systemsInRange),
                                    resourceLevel: 2,
                                    maxJumps: maxJumps,
                                    centerSystemId: selectedSolarSystemId
                                )
                            ) {
                                HStack {
                                    Text("P2")
                                    Spacer()
                                    Text(
                                        "\(availableP2Resources.count) \(NSLocalizedString("Types", comment: "种"))"
                                    )
                                    .foregroundColor(.gray)
                                }
                            }
                        }

                        // P3资源链接 - 仅当有可用P3资源时显示
                        let availableP3Resources = p3Resources.filter { $0.canProduce }
                        if !availableP3Resources.isEmpty {
                            NavigationLink(
                                destination: PIResourcesListView(
                                    title: "P3",
                                    resources: availableP3Resources,
                                    systemIds: Array(systemsInRange),
                                    resourceLevel: 3,
                                    maxJumps: maxJumps,
                                    centerSystemId: selectedSolarSystemId
                                )
                            ) {
                                HStack {
                                    Text("P3")
                                    Spacer()
                                    Text(
                                        "\(availableP3Resources.count) \(NSLocalizedString("Types", comment: "种"))"
                                    )
                                    .foregroundColor(.gray)
                                }
                            }
                        }

                        // P4资源链接 - 仅当有可用P4资源时显示
                        let availableP4Resources = p4Resources.filter { $0.canProduce }
                        if !availableP4Resources.isEmpty {
                            NavigationLink(
                                destination: PIResourcesListView(
                                    title: "P4",
                                    resources: availableP4Resources,
                                    systemIds: Array(systemsInRange),
                                    resourceLevel: 4,
                                    maxJumps: maxJumps,
                                    centerSystemId: selectedSolarSystemId
                                )
                            ) {
                                HStack {
                                    Text("P4")
                                    Spacer()
                                    Text(
                                        "\(availableP4Resources.count) \(NSLocalizedString("Types", comment: "种"))"
                                    )
                                    .foregroundColor(.gray)
                                }
                            }
                        }

                        // 如果没有任何可用资源，显示提示信息
                        if p0Resources.isEmpty && p1Resources.filter({ $0.canProduce }).isEmpty
                            && p2Resources.filter({ $0.canProduce }).isEmpty
                            && p3Resources.filter({ $0.canProduce }).isEmpty
                            && p4Resources.filter({ $0.canProduce }).isEmpty
                        {
                            Text(NSLocalizedString("PI_Output_No_Resources", comment: "没有找到可用资源"))
                                .foregroundColor(.gray)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                        }
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Main_Planetary_Output", comment: ""))
        .sheet(isPresented: $showSolarSystemPicker) {
            PISolarSystemSelectorSheet(
                title: NSLocalizedString("PI_Output_Select_Solar_System", comment: ""),
                currentSelection: selectedSolarSystemId,
                onSelect: { systemId, systemName in
                    selectedSolarSystemId = systemId
                    selectedSolarSystemName = systemName
                    showSolarSystemPicker = false
                    // 选择星系后计算范围内的星系
                    calculateSystemsInRange()
                },
                onCancel: {
                    showSolarSystemPicker = false
                }
            )
        }
        .sheet(isPresented: $showSovereigntySelector) {
            NavigationView {
                SovereigntySelectorView(
                    databaseManager: DatabaseManager.shared,
                    selectedSovereigntyID: $selectedSovereigntyID,
                    selectedSovereigntyName: $selectedSovereigntyName
                )
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(NSLocalizedString("Common_Cancel", comment: "取消")) {
                            showSovereigntySelector = false
                        }
                    }
                }
            }
            .onDisappear {
                // 当主权选择器关闭时重新计算星系范围
                if selectedSolarSystemId != nil {
                    calculateSystemsInRange()
                }
            }
        }
    }

    // 计算指定星系周围最大跳数范围内的所有星系
    private func calculateSystemsInRange() {
        guard let startSystemId = selectedSolarSystemId else { return }

        // 设置计算状态
        isCalculating = true
        systemsInRange.removeAll()
        p0Resources.removeAll()
        p1Resources.removeAll()
        p2Resources.removeAll()
        p3Resources.removeAll()
        p4Resources.removeAll()

        // 在后台线程执行
        DispatchQueue.global(qos: .userInitiated).async {
            // 加载星图数据
            guard let path = StaticResourceManager.shared.getMapDataPath(filename: "neighbors_data") else {
                Logger.error("无法找到星图文件路径")
                DispatchQueue.main.async {
                    isCalculating = false
                }
                return
            }

            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                guard let starMap = try JSONSerialization.jsonObject(with: data) as? [String: [Int]]
                else {
                    Logger.error("解析星图数据失败：数据格式不正确")
                    DispatchQueue.main.async {
                        isCalculating = false
                    }
                    return
                }

                // 使用BFS算法查找范围内的所有星系
                var result = Set<Int>()
                result.insert(startSystemId) // 包含起始星系

                // 如果最大跳数为0，那么只包含起始星系
                if maxJumps > 0 {
                    var visited = Set<Int>()
                    visited.insert(startSystemId)

                    var queue = [(systemId: startSystemId, distance: 0)]
                    var queueIndex = 0

                    // 使用BFS进行遍历
                    while queueIndex < queue.count {
                        let current = queue[queueIndex]
                        queueIndex += 1

                        // 如果达到最大跳数，不再继续
                        if current.distance >= maxJumps {
                            continue
                        }

                        // 获取当前星系的邻居
                        if let neighbors = starMap[String(current.systemId)] {
                            for neighbor in neighbors {
                                if !visited.contains(neighbor) {
                                    visited.insert(neighbor)
                                    result.insert(neighbor)
                                    queue.append(
                                        (systemId: neighbor, distance: current.distance + 1))
                                }
                            }
                        }
                    }
                }

                // 如果选择了主权筛选，应用主权筛选
                if let sovereigntyId = selectedSovereigntyID {
                    // 在 Task 之前捕获 result 的值
                    let capturedResult = result
                    Task {
                        do {
                            // 获取主权数据
                            let sovereigntyData = try await SovereigntyDataAPI.shared
                                .fetchSovereigntyData(forceRefresh: false)

                            // 根据主权ID筛选星系
                            let systemsUnderSovereignty = Set(
                                sovereigntyData.compactMap { data -> Int? in
                                    if data.allianceId == sovereigntyId
                                        || data.factionId == sovereigntyId
                                    {
                                        return data.systemId
                                    }
                                    return nil
                                })

                            // 取交集得到同时在范围内且属于指定主权的星系
                            let filteredResult = capturedResult.intersection(
                                systemsUnderSovereignty)

                            // 更新主线程UI
                            await MainActor.run {
                                systemsInRange = filteredResult
                                isCalculating = false
                                Logger.info(
                                    "根据主权筛选计算完成，在\(maxJumps)跳范围内找到\(capturedResult.count)个星系，其中\(filteredResult.count)个星系属于指定主权"
                                )

                                // 加载资源信息
                                loadResources(for: Array(filteredResult))
                            }
                        } catch {
                            Logger.error("获取主权数据失败：\(error)")
                            await MainActor.run {
                                systemsInRange = capturedResult
                                isCalculating = false
                                Logger.info(
                                    "获取主权数据失败，计算完成，在\(maxJumps)跳范围内找到\(capturedResult.count)个星系")

                                // 加载资源信息
                                loadResources(for: Array(capturedResult))
                            }
                        }
                    }
                } else {
                    // 没有主权筛选，直接更新UI
                    DispatchQueue.main.async {
                        systemsInRange = result
                        isCalculating = false
                        Logger.info("没有主权筛选，计算完成，在\(maxJumps)跳范围内找到\(result.count)个星系")

                        // 加载资源信息
                        loadResources(for: Array(result))
                    }
                }

            } catch {
                Logger.error("加载星图数据失败：\(error)")
                DispatchQueue.main.async {
                    isCalculating = false
                }
            }
        }
    }

    // 加载资源信息（P0、P1、P2、P3和P4）
    private func loadResources(for systemIds: [Int]) {
        // 先加载P0资源信息
        loadPIResources(level: .p0, for: systemIds, availablePIIds: Set<Int>()) { availableP0Ids in
            // 只有在有可用P0资源的情况下才加载P1资源
            if !availableP0Ids.isEmpty {
                // P0资源加载完成后，加载P1资源信息
                loadPIResources(level: .p1, for: systemIds, availablePIIds: availableP0Ids) {
                    availableP1Ids in
                    // 合并P0和P1的可用资源
                    let availableP0P1Ids = availableP0Ids.union(availableP1Ids)

                    // 只有在有可用P1资源的情况下才加载P2资源
                    if !availableP1Ids.isEmpty {
                        // P1资源加载完成后，加载P2资源信息
                        loadPIResources(
                            level: .p2, for: systemIds, availablePIIds: availableP0P1Ids
                        ) { availableP2Ids in
                            // 合并P0、P1和P2的可用资源
                            let availableP0P1P2Ids = availableP0P1Ids.union(availableP2Ids)

                            // 只有在有可用P2资源的情况下才加载P3资源
                            if !availableP2Ids.isEmpty {
                                // P2资源加载完成后，加载P3资源信息
                                loadPIResources(
                                    level: .p3, for: systemIds, availablePIIds: availableP0P1P2Ids
                                ) { availableP3Ids in
                                    // 合并P0、P1、P2和P3的可用资源
                                    let availableP0P1P2P3Ids = availableP0P1P2Ids.union(
                                        availableP3Ids)

                                    // 只有在有可用P3资源的情况下才加载P4资源
                                    if !availableP3Ids.isEmpty {
                                        // P3资源加载完成后，加载P4资源信息
                                        loadPIResources(
                                            level: .p4, for: systemIds,
                                            availablePIIds: availableP0P1P2P3Ids
                                        ) { _ in }
                                    } else {
                                        // 如果没有可用的P3资源，直接设置P4资源加载状态为完成
                                        DispatchQueue.main.async {
                                            isLoadingP4Resources = false
                                        }
                                    }
                                }
                            } else {
                                // 如果没有可用的P2资源，直接设置P3和P4资源加载状态为完成
                                DispatchQueue.main.async {
                                    isLoadingP3Resources = false
                                    isLoadingP4Resources = false
                                }
                            }
                        }
                    } else {
                        // 如果没有可用的P1资源，直接设置P2、P3和P4资源加载状态为完成
                        DispatchQueue.main.async {
                            isLoadingP2Resources = false
                            isLoadingP3Resources = false
                            isLoadingP4Resources = false
                        }
                    }
                }
            } else {
                // 如果没有可用的P0资源，直接设置P1、P2、P3和P4资源加载状态为完成
                DispatchQueue.main.async {
                    isLoadingP1Resources = false
                    isLoadingP2Resources = false
                    isLoadingP3Resources = false
                    isLoadingP4Resources = false
                }
            }
        }
    }

    // 统一的资源加载方法
    private func loadPIResources(
        level: PIResourceLevel, for systemIds: [Int], availablePIIds: Set<Int>,
        completion: @escaping (Set<Int>) -> Void
    ) {
        guard !systemIds.isEmpty else {
            completion(Set<Int>())
            return
        }

        // 设置加载状态
        DispatchQueue.main.async {
            switch level {
            case .p0:
                isLoadingP0Resources = true
                p0Resources.removeAll()
            case .p1:
                isLoadingP1Resources = true
                p1Resources.removeAll()
            case .p2:
                isLoadingP2Resources = true
                p2Resources.removeAll()
            case .p3:
                isLoadingP3Resources = true
                p3Resources.removeAll()
            case .p4:
                isLoadingP4Resources = true
                p4Resources.removeAll()
            }
        }

        DispatchQueue.global(qos: .userInitiated).async {
            // 处理P0特殊情况
            if level == .p0 {
                loadP0ResourcesImpl(for: systemIds) { p0Ids in
                    completion(p0Ids)
                }
                return
            }

            // 处理P4特殊情况（需要检查特定类型的行星）
            if level == .p4 {
                // 首先检查是否有温和(temperate)或贫瘠(barren)行星
                let planetQuery = """
                    SELECT COUNT(*) as count
                    FROM universe
                    WHERE solarsystem_id IN (\(systemIds.map { String($0) }.joined(separator: ",")))
                    AND (temperate > 0 OR barren > 0)
                """

                var hasRequiredPlanets = false

                if case let .success(planetRows) = DatabaseManager.shared.executeQuery(planetQuery) {
                    if let row = planetRows.first,
                       let count = row["count"] as? Int,
                       count > 0
                    {
                        hasRequiredPlanets = true
                    }
                }

                // 如果没有所需的行星类型，直接返回
                if !hasRequiredPlanets {
                    Logger.info("没有找到温和或贫瘠行星，无法生产P4资源")
                    DispatchQueue.main.async {
                        isLoadingP4Resources = false
                    }
                    completion(Set<Int>())
                    return
                }
            }

            // 获取资源ID和基本信息
            guard level.marketGroupId != nil else {
                completion(Set<Int>())
                return
            }

            // 使用PIResourceCache获取资源信息，而不是直接查询数据库
            var resourceIds: [Int] = []
            var resourceInfo: [Int: (name: String, iconFileName: String)] = [:]

            // 遍历所有资源，找出属于当前等级的
            for (typeId, info) in PIResourceCache.shared.getAllResourceInfo() {
                if let resourceLevel = PIResourceCache.shared.getResourceLevel(for: typeId),
                   resourceLevel == level
                {
                    resourceIds.append(typeId)
                    resourceInfo[typeId] = (
                        name: info.name,
                        iconFileName: info.iconFileName
                    )
                }
            }

            if !resourceIds.isEmpty {
                // 获取资源需要的输入资源
                var resourceToInputMap: [Int: Set<Int>] = [:]

                // 使用PIResourceCache获取配方信息
                for resourceId in resourceIds {
                    if let schematic = PIResourceCache.shared.getSchematic(for: resourceId) {
                        resourceToInputMap[resourceId] = Set(schematic.inputTypeIds)
                    }
                }

                // 创建资源信息列表和可用ID集合
                var resourceInfos: [Any] = [] // 使用Any类型暂存，然后在switch中转换
                var availableIds = Set<Int>()

                for (resourceId, info) in resourceInfo {
                    if let requiredInputIds = resourceToInputMap[resourceId] {
                        // 检查是否所有需要的输入资源都可用
                        let canProduce =
                            !requiredInputIds.isEmpty
                                && requiredInputIds.isSubset(of: availablePIIds)

                        // 只添加可以生产的资源
                        if canProduce {
                            switch level {
                            case .p1:
                                resourceInfos.append(
                                    P1ResourceInfo(
                                        resourceId: resourceId,
                                        resourceName: info.name,
                                        iconFileName: info.iconFileName,
                                        requiredP0Resources: Array(requiredInputIds),
                                        canProduce: true
                                    ))
                            case .p2:
                                resourceInfos.append(
                                    P2ResourceInfo(
                                        resourceId: resourceId,
                                        resourceName: info.name,
                                        iconFileName: info.iconFileName,
                                        requiredP1Resources: Array(requiredInputIds),
                                        canProduce: true
                                    ))
                            case .p3:
                                resourceInfos.append(
                                    P3ResourceInfo(
                                        resourceId: resourceId,
                                        resourceName: info.name,
                                        iconFileName: info.iconFileName,
                                        requiredP2Resources: Array(requiredInputIds),
                                        canProduce: true
                                    ))
                            case .p4:
                                resourceInfos.append(
                                    P4ResourceInfo(
                                        resourceId: resourceId,
                                        resourceName: info.name,
                                        iconFileName: info.iconFileName,
                                        requiredP3Resources: Array(requiredInputIds),
                                        canProduce: true
                                    ))
                            default:
                                break
                            }
                            availableIds.insert(resourceId)
                        }
                    } else {
                        Logger.error("\(level.levelName)资源 \(info.name) 没有找到所需的输入资源")
                    }
                }

                // 按照资源名称排序（P0按照行星数量排序在loadP0ResourcesImpl中处理）
                switch level {
                case .p1:
                    let typedResources = resourceInfos as! [P1ResourceInfo]
                    let sortedResources = typedResources.sorted {
                        $0.resourceName < $1.resourceName
                    }
                    DispatchQueue.main.async {
                        p1Resources = sortedResources
                        isLoadingP1Resources = false
                        completion(availableIds)
                    }
                case .p2:
                    let typedResources = resourceInfos as! [P2ResourceInfo]
                    let sortedResources = typedResources.sorted {
                        $0.resourceName < $1.resourceName
                    }
                    DispatchQueue.main.async {
                        p2Resources = sortedResources
                        isLoadingP2Resources = false
                        completion(availableIds)
                    }
                case .p3:
                    let typedResources = resourceInfos as! [P3ResourceInfo]
                    let sortedResources = typedResources.sorted {
                        $0.resourceName < $1.resourceName
                    }
                    DispatchQueue.main.async {
                        p3Resources = sortedResources
                        isLoadingP3Resources = false
                        completion(availableIds)
                    }
                case .p4:
                    let typedResources = resourceInfos as! [P4ResourceInfo]
                    let sortedResources = typedResources.sorted {
                        $0.resourceName < $1.resourceName
                    }
                    DispatchQueue.main.async {
                        p4Resources = sortedResources
                        isLoadingP4Resources = false
                        completion(availableIds)
                    }
                default:
                    DispatchQueue.main.async {
                        completion(availableIds)
                    }
                }
            } else {
                // 没有找到资源，设置加载完成状态
                DispatchQueue.main.async {
                    switch level {
                    case .p1: isLoadingP1Resources = false
                    case .p2: isLoadingP2Resources = false
                    case .p3: isLoadingP3Resources = false
                    case .p4: isLoadingP4Resources = false
                    default: break
                    }
                    completion(Set<Int>())
                }
            }
        }
    }

    // P0资源特殊处理实现（因为P0资源需要单独查询行星类型）
    private func loadP0ResourcesImpl(for systemIds: [Int], completion: @escaping (Set<Int>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            // 查询星系内的行星数量
            let query = """
                SELECT 
                    solarsystem_id,
                    temperate,
                    barren,
                    oceanic,
                    ice,
                    gas,
                    lava,
                    storm,
                    plasma
                FROM universe
                WHERE solarsystem_id IN (\(systemIds.map { String($0) }.joined(separator: ",")))
            """

            guard case let .success(rows) = DatabaseManager.shared.executeQuery(query) else {
                DispatchQueue.main.async {
                    isLoadingP0Resources = false
                    completion(Set<Int>())
                }
                return
            }

            // 获取所有P0资源ID
            let p0ResourceQuery = """
                SELECT DISTINCT ph.typeid, t.name, t.icon_filename 
                FROM planetResourceHarvest ph
                JOIN types t ON t.type_id = ph.typeid
            """

            var resourceIds: [Int] = []
            var resourceIconMap: [Int: String] = [:]

            if case let .success(resourceRows) = DatabaseManager.shared.executeQuery(
                p0ResourceQuery)
            {
                for row in resourceRows {
                    if let typeId = row["typeid"] as? Int,
                       let iconFileName = row["icon_filename"] as? String
                    {
                        resourceIds.append(typeId)
                        resourceIconMap[typeId] = iconFileName.isEmpty ? "not_found" : iconFileName
                    }
                }
            }

            if !resourceIds.isEmpty {
                // 获取资源可用的行星类型
                let resourceCalculator = PlanetaryResourceCalculator(
                    databaseManager: DatabaseManager.shared)
                let resourcePlanets = resourceCalculator.findResourcePlanets(for: resourceIds)

                // 创建资源ID到行星类型的映射
                var resourceToPlanetTypes: [Int: Set<Int>] = [:]
                var resourceInfo: [Int: (name: String, planetTypes: [Int], planetNames: [String])] =
                    [:]

                for result in resourcePlanets {
                    resourceToPlanetTypes[result.resourceId] = Set(
                        result.availablePlanets.map { $0.id })
                    resourceInfo[result.resourceId] = (
                        name: result.resourceName,
                        planetTypes: result.availablePlanets.map { $0.id },
                        planetNames: result.availablePlanets.map { $0.name }
                    )
                }

                // 计算每种资源在所有星系中可用的行星总数
                var resourcePlanetCounts: [Int: Int] = [:]

                for row in rows {
                    // 处理每个资源
                    for resourceId in resourceIds {
                        if let planetTypes = resourceToPlanetTypes[resourceId] {
                            var planetCount = 0

                            // 检查每种行星类型的数量
                            for planetType in planetTypes {
                                if let columnName = PlanetaryUtils.planetTypeToColumn[planetType],
                                   let count = row[columnName] as? Int
                                {
                                    planetCount += count
                                }
                            }

                            // 更新资源可用行星总数
                            if planetCount > 0 {
                                resourcePlanetCounts[resourceId] =
                                    (resourcePlanetCounts[resourceId] ?? 0) + planetCount
                            }
                        }
                    }
                }

                // 创建P0资源信息列表
                var p0ResourceInfos: [P0ResourceInfo] = []

                for (resourceId, count) in resourcePlanetCounts {
                    if let info = resourceInfo[resourceId] {
                        p0ResourceInfos.append(
                            P0ResourceInfo(
                                resourceId: resourceId,
                                resourceName: info.name,
                                planetTypes: info.planetTypes,
                                planetNames: info.planetNames,
                                availablePlanetCount: count,
                                iconFileName: resourceIconMap[resourceId] ?? "not_found"
                            ))
                    }
                }

                // 按照可用行星数量降序排序
                p0ResourceInfos.sort { $0.availablePlanetCount > $1.availablePlanetCount }

                // 获取可用的P0资源ID
                let availableP0Ids = Set(p0ResourceInfos.map { $0.resourceId })

                // 更新UI
                DispatchQueue.main.async {
                    p0Resources = p0ResourceInfos
                    isLoadingP0Resources = false
                    completion(availableP0Ids)
                }
            } else {
                DispatchQueue.main.async {
                    isLoadingP0Resources = false
                    completion(Set<Int>())
                }
            }
        }
    }
}
