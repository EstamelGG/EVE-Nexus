import SwiftUI

// 搜索结果视图模型
class PlanetarySearchResultViewModel: ObservableObject {
    @Published var sovereigntyData: [SovereigntyData] = []
    @Published var isLoadingSovereignty: Bool = false

    // 图标和名称缓存
    @Published var allianceIcons: [Int: Image] = [:]
    @Published var factionIcons: [Int: Image] = [:]
    @Published var allianceNames: [Int: String] = [:]
    @Published var factionNames: [Int: String] = [:]

    // 跟踪正在加载的系统
    @Published var loadingSystemIcons: Set<Int> = []

    // 主权映射
    private var allianceToSystems: [Int: [Int]] = [:]
    private var factionToSystems: [Int: [Int]] = [:]

    // 加载任务管理
    private var loadingTasks: [Int: Task<Void, Never>] = [:]

    func loadSovereigntyData(forSystemIds systemIds: [Int]) {
        Task { @MainActor in
            isLoadingSovereignty = true

            do {
                // 获取主权数据
                let data = try await SovereigntyDataAPI.shared.fetchSovereigntyData(
                    forceRefresh: false)

                // 确保在主线程更新UI
                sovereigntyData = data

                // 建立主权映射关系
                setupSovereigntyMapping(systemIds: systemIds)

                // 加载图标和名称
                await loadAllIcons()

                isLoadingSovereignty = false
            } catch {
                Logger.error("无法获取主权数据: \(error)")
                isLoadingSovereignty = false
            }
        }
    }

    @MainActor
    func setupSovereigntyMapping(systemIds: [Int]) {
        // 清除现有映射
        allianceToSystems.removeAll()
        factionToSystems.removeAll()

        // 为每个系统ID查找主权信息并建立映射
        for systemId in systemIds {
            if let systemData = sovereigntyData.first(where: { $0.systemId == systemId }) {
                // 标记系统正在加载图标
                loadingSystemIcons.insert(systemId)

                // 建立联盟到系统的映射
                if let allianceId = systemData.allianceId {
                    allianceToSystems[allianceId, default: []].append(systemId)
                }
                // 建立派系到系统的映射
                else if let factionId = systemData.factionId {
                    factionToSystems[factionId, default: []].append(systemId)
                } else {
                    // 如果既没有联盟也没有派系，移除加载状态
                    loadingSystemIcons.remove(systemId)
                }
            }
        }
    }

    func loadAllIcons() async {
        // 加载联盟图标和名称
        for (allianceId, systems) in allianceToSystems {
            let task = Task {
                do {
                    Logger.debug("开始加载联盟图标: \(allianceId)，影响 \(systems.count) 个星系")

                    // 加载联盟名称
                    if let allianceInfo = try? await AllianceAPI.shared.fetchAllianceInfo(
                        allianceId: allianceId)
                    {
                        await MainActor.run {
                            allianceNames[allianceId] = allianceInfo.name
                        }
                        Logger.debug("联盟名称加载成功: \(allianceId)")
                    }

                    // 加载联盟图标
                    do {
                        let uiImage = try await AllianceAPI.shared.fetchAllianceLogo(
                            allianceID: allianceId,
                            size: 64
                        )

                        // 在主线程处理结果和更新UI
                        await MainActor.run {
                            // 保存图标到缓存
                            self.allianceIcons[allianceId] = Image(uiImage: uiImage)

                            // 更新所有使用这个联盟图标的系统的加载状态
                            for systemId in systems {
                                self.loadingSystemIcons.remove(systemId)
                            }
                            Logger.debug("联盟图标加载成功: \(allianceId)")
                        }
                    } catch {
                        Logger.error("加载联盟图标失败: \(allianceId), error: \(error)")
                        // 更新加载状态
                        await MainActor.run {
                            for systemId in systems {
                                self.loadingSystemIcons.remove(systemId)
                            }
                        }
                    }
                }
            }
            loadingTasks[allianceId] = task
        }

        // 加载派系图标和名称
        for (factionId, systems) in factionToSystems {
            let task = Task {
                Logger.debug("开始加载派系图标: \(factionId)，影响 \(systems.count) 个星系")

                let query = "SELECT iconName, name FROM factions WHERE id = ?"
                if case let .success(rows) = DatabaseManager.shared.executeQuery(
                    query, parameters: [factionId]),
                    let row = rows.first,
                    let iconName = row["iconName"] as? String
                {

                    let icon = IconManager.shared.loadImage(for: iconName)
                    let factionName = row["name"] as? String

                    // 保存到缓存 - 确保在主线程更新UI
                    await MainActor.run {
                        factionIcons[factionId] = icon
                        if let name = factionName {
                            factionNames[factionId] = name
                        }

                        // 更新所有使用这个派系图标的系统的加载状态
                        for systemId in systems {
                            loadingSystemIcons.remove(systemId)
                        }
                    }
                    Logger.debug("派系图标和名称加载成功: \(factionId)")
                } else {
                    Logger.error("派系图标加载失败: \(factionId)")

                    // 更新加载状态
                    await MainActor.run {
                        for systemId in systems {
                            loadingSystemIcons.remove(systemId)
                        }
                    }
                }
            }
            loadingTasks[factionId] = task
        }

        // 等待所有任务完成
        for task in loadingTasks.values {
            _ = await task.value
        }
    }

    // 获取系统的主权信息
    func getSovereigntyForSystem(_ systemId: Int) -> SovereigntyData? {
        return sovereigntyData.first(where: { $0.systemId == systemId })
    }

    // 检查系统是否正在加载图标
    func isLoadingIconForSystem(_ systemId: Int) -> Bool {
        return loadingSystemIcons.contains(systemId)
    }

    // 获取系统的图标
    func getIconForSystem(_ systemId: Int) -> Image? {
        if let sovereignty = getSovereigntyForSystem(systemId) {
            if let allianceId = sovereignty.allianceId {
                return allianceIcons[allianceId]
            } else if let factionId = sovereignty.factionId {
                return factionIcons[factionId]
            }
        }
        return nil
    }

    // 获取系统的拥有者名称
    func getOwnerNameForSystem(_ systemId: Int) -> String? {
        if let sovereignty = getSovereigntyForSystem(systemId) {
            if let allianceId = sovereignty.allianceId {
                return allianceNames[allianceId]
            } else if let factionId = sovereignty.factionId {
                return factionNames[factionId]
            }
        }
        return nil
    }

    deinit {
        // 取消所有加载任务
        loadingTasks.values.forEach { $0.cancel() }
    }
}

// 搜索结果视图
struct PlanetarySearchResultView: View {
    let results: [SystemSearchResult]
    @StateObject private var viewModel = PlanetarySearchResultViewModel()
    @State private var systemNames: [Int: String] = [:]  // 存储系统ID到系统名称的映射
    @State private var resourceInfo: [Int: (name: String, iconFileName: String)] = [:]  // 存储资源ID到名称和图标的映射

    var body: some View {
        List {
            // 提示信息Section
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString("Planetary_Search_Tip_1", comment: ""))
                        .font(.footnote)
                    Text(NSLocalizedString("Planetary_Search_Tip_2", comment: ""))
                        .font(.footnote)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            if results.isEmpty {
                // 无搜索结果时显示的提示信息
                Section {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 50))
                            .foregroundColor(.yellow)
                            .padding(.top, 20)

                        Text(
                            NSLocalizedString(
                                "Planetary_Search_No_Results", comment: "没有找到能够生产所需资源的星系")
                        )
                        .font(.headline)
                        .multilineTextAlignment(.center)

                        Text(
                            NSLocalizedString(
                                "Planetary_Search_No_Results_Tips",
                                comment: "请考虑以下调整方案:\n• 增加星系跳数范围\n• 选择其他星域或主权\n• 选择其他可能更容易生产的产品")
                        )
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 20)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
            } else {
                // 搜索结果Sections
                ForEach(results) { result in
                    Section {
                        // 星系信息
                        HStack(spacing: 4) {
                            // 左侧图标
                            if viewModel.isLoadingIconForSystem(result.systemId) {
                                ProgressView()
                                    .frame(width: 36, height: 36)
                            } else if let icon = viewModel.getIconForSystem(result.systemId) {
                                icon
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 36, height: 36)
                                    .cornerRadius(6)
                            }

                            // 右侧文本区域
                            VStack(alignment: .leading, spacing: 4) {
                                // 第一行：安全等级和星系名称
                                HStack(spacing: 4) {
                                    Text(formatSystemSecurity(result.security))
                                        .foregroundColor(getSecurityColor(result.security))
                                        .font(.system(.body, design: .monospaced))
                                    Text(result.systemName)
                                        .fontWeight(.medium)
                                        .textSelection(.enabled)
                                    Text("（\(result.regionName)）")
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                }

                                // 第二行：联盟/派系名称
                                if let ownerName = viewModel.getOwnerNameForSystem(result.systemId)
                                {
                                    Text(ownerName)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        // 资源信息
                        VStack(alignment: .leading, spacing: 4) {
                            if !result.availableResources.isEmpty {
                                Text(NSLocalizedString("Planetary_Local_Resources", comment: ""))
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                ForEach(Array(result.availableResources.keys).sorted(), id: \.self)
                                { resourceId in
                                    if let count = result.availableResources[resourceId] {
                                        HStack {
                                            // 添加资源图标
                                            if let iconFileName = resourceInfo[resourceId]?
                                                .iconFileName
                                            {
                                                Image(
                                                    uiImage: IconManager.shared.loadUIImage(
                                                        for: iconFileName)
                                                )
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: 24, height: 24)
                                                .cornerRadius(4)
                                            }

                                            Text(
                                                "- \(resourceInfo[resourceId]?.name ?? "未知资源"): \(String(format: NSLocalizedString("Planetary_Resource_Planet_Count", comment: ""), "\(count)"))"
                                            )
                                            .font(.subheadline)
                                        }
                                    }
                                }
                            }

                            if !result.additionalResources.isEmpty {
                                Text(NSLocalizedString("Planetary_Nearby_Resources", comment: ""))
                                    .font(.subheadline)
                                    .foregroundColor(.gray)

                                // 分组并排序后显示
                                let groupedResources = groupAdditionalResourcesByType(
                                    result.additionalResources)
                                ForEach(groupedResources, id: \.resourceId) { group in
                                    VStack(alignment: .leading) {
                                        Text("- \(getResourceName(for: group.resourceId)):")
                                            .font(.subheadline)

                                        // 显示提供该资源的所有星系
                                        ForEach(
                                            group.systems.sorted(by: { $0.jumps < $1.jumps }),
                                            id: \.systemId
                                        ) { systemInfo in
                                            let systemName =
                                                systemNames[systemInfo.systemId]
                                                ?? "\(systemInfo.systemId)"
                                            Text(
                                                "  • \(String(format: NSLocalizedString("Planetary_Resource_System_Format", comment: ""), systemName, systemInfo.jumps))"
                                            )
                                            .font(.caption)
                                            .padding(.leading, 8)
                                        }
                                    }
                                }
                            }

                            Text(
                                String(
                                    format: NSLocalizedString("Planetary_Coverage", comment: ""),
                                    result.coverage)
                            )
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        }
                        .padding(.top, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }
        }
        .navigationTitle(NSLocalizedString("Main_Planetary_Search_Results", comment: "搜索结果"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let systemIds = results.map { $0.systemId }
            Task {
                viewModel.loadSovereigntyData(forSystemIds: systemIds)
                loadSystemNames(forAdditionalResources: results)
                loadResourceInfo(forResults: results)
            }
        }
    }

    // 加载星系名称
    private func loadSystemNames(forAdditionalResources results: [SystemSearchResult]) {
        // 收集所有需要获取名称的系统ID
        var systemIds: Set<Int> = []
        for result in results {
            for systemId in result.additionalResources.keys {
                systemIds.insert(systemId)
            }
        }

        if systemIds.isEmpty {
            return
        }

        // 查询系统名称
        let query = """
                SELECT solarSystemID, solarSystemName 
                FROM solarsystems 
                WHERE solarSystemID IN (\(systemIds.map { String($0) }.joined(separator: ",")))
            """

        if case let .success(rows) = DatabaseManager.shared.executeQuery(query) {
            var tempNames: [Int: String] = [:]
            for row in rows {
                if let systemId = row["solarSystemID"] as? Int,
                    let name = row["solarSystemName"] as? String
                {
                    tempNames[systemId] = name
                }
            }

            // 在主线程更新UI数据
            DispatchQueue.main.async {
                self.systemNames = tempNames
            }
        }
    }

    // 加载资源信息
    private func loadResourceInfo(forResults results: [SystemSearchResult]) {
        // 收集所有需要获取信息的资源ID
        var resourceIds: Set<Int> = []
        for result in results {
            // 添加本地资源ID
            resourceIds.formUnion(result.availableResources.keys)
            // 添加相邻系统资源ID
            for (_, info) in result.additionalResources {
                resourceIds.insert(info.resourceId)
            }
        }

        if resourceIds.isEmpty {
            return
        }

        // 一次性查询所有资源信息
        let query = """
                SELECT type_id, name, icon_filename 
                FROM types 
                WHERE type_id IN (\(resourceIds.map { String($0) }.joined(separator: ",")))
            """

        if case let .success(rows) = DatabaseManager.shared.executeQuery(query) {
            var tempInfo: [Int: (name: String, iconFileName: String)] = [:]
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                    let name = row["name"] as? String,
                    let iconFileName = row["icon_filename"] as? String
                {
                    tempInfo[typeId] = (
                        name: name, iconFileName: iconFileName.isEmpty ? "not_found" : iconFileName
                    )
                }
            }

            // 在主线程更新UI数据
            DispatchQueue.main.async {
                self.resourceInfo = tempInfo
            }
        }
    }

    // 获取资源名称的辅助函数
    private func getResourceName(for resourceId: Int) -> String {
        return resourceInfo[resourceId]?.name ?? "未知资源"
    }

    // 将相邻系统资源按resourceId分组
    private func groupAdditionalResourcesByType(
        _ additionalResources: [Int: (resourceId: Int, jumps: Int)]
    ) -> [(resourceId: Int, systems: [(systemId: Int, jumps: Int)])] {
        // 创建一个以resourceId为键的字典
        var resourceGroups: [Int: [(systemId: Int, jumps: Int)]] = [:]

        for (systemId, info) in additionalResources {
            let resourceId = info.resourceId
            let jumps = info.jumps

            if resourceGroups[resourceId] == nil {
                resourceGroups[resourceId] = []
            }

            resourceGroups[resourceId]?.append((systemId: systemId, jumps: jumps))
        }

        // 将字典转换为数组并按resourceId排序
        return resourceGroups.map { (resourceId: $0.key, systems: $0.value) }
            .sorted(by: { $0.resourceId < $1.resourceId })
    }
}
