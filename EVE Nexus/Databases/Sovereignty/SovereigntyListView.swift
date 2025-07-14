import SwiftUI

// 主权列表视图
struct SovereigntyListView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var searchText = ""
    @State private var sovereignties: [SovereigntyInfo] = []
    @State private var sovereigntyControlledSystems: [Int: [(systemId: Int, name: String, nameEn: String, nameZh: String)]] = [:] // 主权势力ID -> 控制的星系信息列表
    @State private var isLoading = true
    @State private var isSearchActive = false
    @State private var errorMessage: String? = nil
    @State private var showError: Bool = false
    @StateObject private var iconLoader = AllianceIconLoader()
    
    // 数据加载状态管理，避免重复加载
    @State private var hasLoadedInitialData = false
    
    // 主权相关状态（用于星系搜索结果）
    @State private var sovereigntyData: [SovereigntyData] = []
    @StateObject private var systemAllianceIconLoader = AllianceIconLoader()
    @State private var systemFactionIcons: [Int: Image] = [:]
    @State private var systemAllianceNames: [Int: String] = [:]
    @State private var systemFactionNames: [Int: String] = [:]
    
    // 星系搜索结果状态
    @State private var matchedSystems: [SystemInfo] = []
    @State private var isLoadingSystemSearch = false

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

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
                    // 如果有搜索内容，显示分类搜索结果
                    if !searchText.isEmpty {
                        // 主权势力搜索结果
                        if !filteredSovereignties.isEmpty {
                            Section(
                                header: Text("\(NSLocalizedString("Sovereignty_Search_Results_Factions", comment: "主权势力")) (\(filteredSovereignties.count))")
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                    .textCase(.none)
                            ) {
                                ForEach(filteredSovereignties, id: \.id) { sovereignty in
                                    NavigationLink(
                                        destination: SovereigntySystemsView(
                                            databaseManager: databaseManager,
                                            sovereigntyInfo: sovereignty
                                        )
                                    ) {
                                        sovereigntyRow(sovereignty)
                                    }
                                }
                            }
                        }
                        
                        // 星系搜索结果
                        if !matchedSystems.isEmpty {
                            Section(
                                header: Text("\(NSLocalizedString("Sovereignty_Search_Results_Systems", comment: "星系")) (\(matchedSystems.count))")
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                    .textCase(.none)
                            ) {
                                ForEach(matchedSystems, id: \.id) { system in
                                    systemRowFromSystemInfo(system)
                                }
                            }
                        }
                    } else {
                        // 没有搜索内容时，显示所有主权列表
                        ForEach(filteredSovereignties, id: \.id) { sovereignty in
                            NavigationLink(
                                destination: SovereigntySystemsView(
                                    databaseManager: databaseManager,
                                    sovereigntyInfo: sovereignty
                                )
                            ) {
                                sovereigntyRow(sovereignty)
                            }
                        }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }
                }
            }
        }
        .searchable(
            text: $searchText,
            isPresented: $isSearchActive,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: NSLocalizedString("Sovereignty_Search_Placeholder", comment: "搜索主权势力...")
        )
        .onChange(of: searchText) { _, newValue in
            Task {
                await updateSystemSearchResults()
            }
        }
        .navigationTitle(NSLocalizedString("Sovereignty_List", comment: "主权势力列表"))
        .refreshable {
            await refreshSovereigntyData()
        }
        .onAppear {
            // 只在第一次加载时执行数据加载，避免从详情页返回时重新加载
            if !hasLoadedInitialData {
                loadSovereigntyData()
                hasLoadedInitialData = true
            }
        }
        .onDisappear {
            iconLoader.cancelAllTasks()
            systemAllianceIconLoader.cancelAllTasks()
        }
        .alert(
            NSLocalizedString("Load_Error", comment: "加载错误"), isPresented: $showError,
            actions: {
                Button(NSLocalizedString("OK", comment: "确定"), role: .cancel) {
                    showError = false
                }
            },
            message: {
                if let errorMsg = errorMessage {
                    Text(errorMsg)
                } else {
                    Text(NSLocalizedString("Unknown_Error", comment: "未知错误"))
                }
            })

    }

    // 过滤后的主权列表（只匹配主权势力名称）
    private var filteredSovereignties: [SovereigntyInfo] {
        if searchText.isEmpty {
            return sovereignties
        } else {            
            let filtered = sovereignties.filter { sovereignty in
                // 只搜索主权势力名称，不包括星系名称
                let nameMatch = sovereignty.name.localizedCaseInsensitiveContains(searchText) ||
                    sovereignty.en_name.localizedCaseInsensitiveContains(searchText) ||
                    sovereignty.zh_name.localizedCaseInsensitiveContains(searchText)
                
                return nameMatch
            }
            
            return filtered
        }
    }

    // 加载主权数据
    private func loadSovereigntyData() {
        isLoading = true

        Task {
            do {
                try await loadSovereigntyDataInternal(forceRefresh: false)
            } catch {
                Logger.error("加载主权数据失败: \(error.localizedDescription)")
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }

            isLoading = false
        }
    }

    // 刷新主权数据
    private func refreshSovereigntyData() async {
        // 重置状态
        iconLoader.cancelAllTasks()
        await MainActor.run {
            sovereigntyControlledSystems.removeAll()
        }
        do {
            try await loadSovereigntyDataInternal(forceRefresh: true)
        } catch {
            Logger.error("刷新主权数据失败: \(error.localizedDescription)")
            await MainActor.run {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    // 内部加载方法，避免代码重复
    private func loadSovereigntyDataInternal(forceRefresh: Bool) async throws {
        // 获取主权数据
        let sovereigntyData = try await SovereigntyDataAPI.shared.fetchSovereigntyData(
            forceRefresh: forceRefresh)

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
                        en_name: allianceName,
                        zh_name: allianceName,
                        icon: nil,
                        systemCount: systemCount,
                        isAlliance: true
                    ))
            }
        }

        // 加载派系信息
        let factionQuery = """
                SELECT id, iconName, name, en_name, zh_name 
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
                    let en_name = row["en_name"] as? String ?? name
                    let zh_name = row["zh_name"] as? String ?? name

                    tempSovereignties.append(
                        SovereigntyInfo(
                            id: factionId,
                            name: name,
                            en_name: en_name,
                            zh_name: zh_name,
                            icon: icon,
                            systemCount: systemCount,
                            isAlliance: false
                        ))
                }
            }
        }

        // 按星系数量排序
        tempSovereignties.sort { $0.systemCount > $1.systemCount }

        // 建立主权势力到星系信息的映射关系
        var sovereigntyToSystems: [Int: [(systemId: Int, name: String, nameEn: String, nameZh: String)]] = [:]
        
        // 获取所有星系ID
        let allSystemIds = sovereigntyData.map { $0.systemId }
        
        // 批量查询星系中英文名称
        if !allSystemIds.isEmpty {
            let systemNamesMap = await getBatchSolarSystemNames(
                solarSystemIds: allSystemIds,
                databaseManager: databaseManager
            )
            
            Logger.info("获取到 \(systemNamesMap.count) 个星系名称数据")
            
            // 为每个主权势力建立其控制的星系信息列表
            for data in sovereigntyData {
                if let systemNames = systemNamesMap[data.systemId] {
                    let systemInfo = (
                        systemId: data.systemId,
                        name: systemNames.name,
                        nameEn: systemNames.nameEn,
                        nameZh: systemNames.nameZh
                    )
                    
                    if let allianceId = data.allianceId {
                        sovereigntyToSystems[allianceId, default: []].append(systemInfo)
                    }
                    if let factionId = data.factionId {
                        sovereigntyToSystems[factionId, default: []].append(systemInfo)
                    }
                }
            }
        }

        // 更新UI显示主权列表（可能部分联盟图标尚未加载）
        await MainActor.run {
            sovereignties = tempSovereignties
            sovereigntyControlledSystems = sovereigntyToSystems
            
            // 同时更新星系主权数据
            self.sovereigntyData = sovereigntyData

            // 开始加载图标
            iconLoader.loadIcons(for: allianceIds)
            
            // 加载星系主权图标和名称
            loadSystemSovereigntyInfo(sovereigntyData: sovereigntyData)
        }
    }
    
    // 更新星系搜索结果
    private func updateSystemSearchResults() async {
        if searchText.isEmpty {
            await MainActor.run {
                matchedSystems = []
                isLoadingSystemSearch = false
            }
            return
        }
        
        await MainActor.run {
            isLoadingSystemSearch = true
        }
        
        let systems = await getMatchedJumpSystems()
        
        await MainActor.run {
            matchedSystems = systems
            isLoadingSystemSearch = false
        }
    }

    
    // 获取匹配的星系数据（用于搜索结果显示）
    private func getMatchedJumpSystems() async -> [SystemInfo] {
        guard !searchText.isEmpty else {
            return []
        }
        
        // 收集所有匹配搜索文本的星系ID和基本信息
        var matchedSystemsInfo: [(systemId: Int, name: String, nameEn: String, nameZh: String)] = []
        
        // 从主权数据中查找匹配的星系
        for (_, systems) in sovereigntyControlledSystems {
            for systemInfo in systems {
                let nameMatch = systemInfo.name.localizedCaseInsensitiveContains(searchText) ||
                               systemInfo.nameEn.localizedCaseInsensitiveContains(searchText) ||
                               systemInfo.nameZh.localizedCaseInsensitiveContains(searchText)
                
                if nameMatch {
                    matchedSystemsInfo.append(systemInfo)
                }
            }
        }
        
        // 去重
        let uniqueSystemIds: [Int] = Array(Set(matchedSystemsInfo.map { $0.systemId }))
        let uniqueSystemsInfo = uniqueSystemIds.compactMap { systemId -> (systemId: Int, name: String, nameEn: String, nameZh: String)? in
            matchedSystemsInfo.first { $0.systemId == systemId }
        }
        
        // 批量查询星系详细信息
        let systemDetailsMap = await getBatchSystemDetailInfo(systemIds: uniqueSystemIds)
        
        // 构建最终的SystemInfo数组
        let matchedSystems: [SystemInfo] = uniqueSystemsInfo.compactMap { systemInfo -> SystemInfo? in
            guard let systemDetail = systemDetailsMap[systemInfo.systemId] else {
                return nil
            }
            
            return SystemInfo(
                id: systemInfo.systemId,
                name: systemInfo.name,
                nameEN: systemInfo.nameEn,
                nameZH: systemInfo.nameZh,
                security: systemDetail.security,
                region: systemDetail.region
            )
        }.sorted { (lhs: SystemInfo, rhs: SystemInfo) -> Bool in
            return lhs.name < rhs.name
        }
        
        return matchedSystems
    }
    
    // 批量获取星系详细信息（安全等级、星域等）
    private func getBatchSystemDetailInfo(systemIds: [Int]) async -> [Int: (security: Double, region: String)] {
        guard !systemIds.isEmpty else {
            return [:]
        }
        
        // 使用 SolarSystem.swift 中的批量查询函数
        let systemInfoMap = await getBatchSolarSystemInfo(
            solarSystemIds: systemIds,
            databaseManager: databaseManager
        )
        
        // 转换为所需的格式
        var result: [Int: (security: Double, region: String)] = [:]
        for (systemId, systemInfo) in systemInfoMap {
            result[systemId] = (security: systemInfo.security, region: systemInfo.regionName)
        }
        
        return result
    }
    
    // 星系信息结构体
    struct SystemInfo: Hashable {
        let id: Int
        let name: String
        let nameEN: String
        let nameZH: String
        let security: Double
        let region: String
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
        
        static func == (lhs: SystemInfo, rhs: SystemInfo) -> Bool {
            return lhs.id == rhs.id
        }
    }
    

    
    // 主权势力行视图
    @ViewBuilder
    private func sovereigntyRow(_ sovereignty: SovereigntyInfo) -> some View {
        HStack {
            if let icon = iconLoader.icons[sovereignty.id] ?? sovereignty.icon {
                icon
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)
            } else {
                ProgressView()
                    .frame(width: 32, height: 32)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(6)
            }

            VStack(alignment: .leading) {
                Text(sovereignty.name)
                    .foregroundColor(.primary)
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = sovereignty.name
                        } label: {
                            Label(NSLocalizedString("Misc_Copy", comment: ""), systemImage: "doc.on.doc")
                        }
                    }
                Text(
                    "\(sovereignty.systemCount) \(NSLocalizedString("Sovereignty_Systems", comment: "个星系"))"
                )
                .font(.caption)
                .foregroundColor(.gray)
            }
            
            Spacer()
        }
    }
    
    // 星系行视图（基于 SystemInfo）
    @ViewBuilder
    private func systemRowFromSystemInfo(_ system: SystemInfo) -> some View {
        HStack(spacing: 12) {
            // 主权势力图标
            if let sovereigntyInfo = getSystemSovereigntyInfo(for: system.id) {
                if let icon = sovereigntyInfo.icon {
                    icon
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                        .cornerRadius(6)
                } else {
                    // 有主权但图标未加载，显示加载指示器
                    ProgressView()
                        .frame(width: 32, height: 32)
                }
            } else {
                // 无主权占位符
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 32, height: 32)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(formatSystemSecurity(system.security))
                        .foregroundColor(getSecurityColor(system.security))
                        .font(.system(.body, design: .monospaced))

                    Text(system.name)
                        .foregroundColor(.primary)
                        .fontWeight(.semibold)
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = system.name
                            } label: {
                                Label(NSLocalizedString("Misc_Copy_Location", comment: ""), systemImage: "doc.on.doc")
                            }
                        }
                        
                    Spacer()
                }
                
                Text(system.region)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
    
    // 获取星系的主权信息
    private func getSystemSovereigntyInfo(for systemId: Int) -> (name: String, icon: Image?)? {
        // 查找该星系的主权数据
        guard let systemSovereignty = sovereigntyData.first(where: { $0.systemId == systemId }) else {
            return nil
        }
        
        // 优先检查联盟主权 - 复用主权势力列表的图标
        if let allianceId = systemSovereignty.allianceId {
            // 先尝试从主权势力列表的图标加载器获取
            if let icon = iconLoader.icons[allianceId] {
                let name = systemAllianceNames[allianceId] ?? "\(allianceId)"
                return (name: name, icon: icon)
            }
            // 如果主权势力列表没有，再从星系专用的图标加载器获取
            else if let icon = systemAllianceIconLoader.icons[allianceId] {
                let name = systemAllianceNames[allianceId] ?? "\(allianceId)"
                return (name: name, icon: icon)
            }
            // 如果都没有，返回名称但没有图标
            else {
                let name = systemAllianceNames[allianceId] ?? "\(allianceId)"
                return (name: name, icon: nil)
            }
        }
        
        // 检查派系主权 - 复用主权势力列表的图标
        if let factionId = systemSovereignty.factionId {
            // 先尝试从主权势力列表获取派系图标
            if let sovereignty = sovereignties.first(where: { $0.id == factionId && !$0.isAlliance }) {
                let name = sovereignty.name
                return (name: name, icon: sovereignty.icon)
            }
            // 如果主权势力列表没有，再从星系专用的图标获取
            else if let icon = systemFactionIcons[factionId] {
                let name = systemFactionNames[factionId] ?? "\(factionId)"
                return (name: name, icon: icon)
            }
            // 如果都没有，返回名称但没有图标
            else {
                let name = systemFactionNames[factionId] ?? "\(factionId)"
                return (name: name, icon: nil)
            }
        }
        
        return nil
    }
    
    // 加载星系主权信息
    private func loadSystemSovereigntyInfo(sovereigntyData: [SovereigntyData]) {
        // 提取需要加载的联盟和派系ID
        let allAllianceIds = Set(sovereigntyData.compactMap { $0.allianceId })
        let allFactionIds = Set(sovereigntyData.compactMap { $0.factionId })
        
        // 过滤出还没有加载的联盟ID（不在主权势力列表中的）
        let existingAllianceIds = Set(sovereignties.filter { $0.isAlliance }.map { $0.id })
        let newAllianceIds = allAllianceIds.subtracting(existingAllianceIds)
        
        // 过滤出还没有加载的派系ID（不在主权势力列表中的）
        let existingFactionIds = Set(sovereignties.filter { !$0.isAlliance }.map { $0.id })
        let newFactionIds = allFactionIds.subtracting(existingFactionIds)
        
        // 只加载新的联盟信息
        if !newAllianceIds.isEmpty {
            Task {
                await loadSystemAllianceInfo(for: Array(newAllianceIds))
            }
        }
        
        // 只加载新的派系信息
        if !newFactionIds.isEmpty {
            Task {
                await loadSystemFactionInfo(for: Array(newFactionIds))
            }
        }
        
        Logger.info("星系主权图标加载：复用现有联盟 \(existingAllianceIds.count) 个，新加载联盟 \(newAllianceIds.count) 个；复用现有派系 \(existingFactionIds.count) 个，新加载派系 \(newFactionIds.count) 个")
    }
    
    // 加载星系联盟信息
    private func loadSystemAllianceInfo(for allianceIds: [Int]) async {
        do {
            let allianceNamesWithCategories = try await UniverseAPI.shared.getNamesWithFallback(ids: allianceIds)
            
            await MainActor.run {
                for (allianceId, nameInfo) in allianceNamesWithCategories {
                    systemAllianceNames[allianceId] = nameInfo.name
                }
                
                // 使用独立的 AllianceIconLoader 加载联盟图标
                systemAllianceIconLoader.loadIcons(for: allianceIds)
            }
        } catch {
            Logger.error("加载星系联盟名称失败: \(error)")
        }
    }
    
    // 加载星系派系信息
    private func loadSystemFactionInfo(for factionIds: [Int]) async {
        guard !factionIds.isEmpty else { return }
        
        let query = """
            SELECT id, iconName, name 
            FROM factions 
            WHERE id IN (\(factionIds.map { String($0) }.joined(separator: ",")))
        """
        
        if case let .success(rows) = databaseManager.executeQuery(query) {
            await MainActor.run {
                for row in rows {
                    if let factionId = row["id"] as? Int,
                       let iconName = row["iconName"] as? String,
                       let name = row["name"] as? String {
                        
                        systemFactionNames[factionId] = name
                        let icon = IconManager.shared.loadImage(for: iconName)
                        systemFactionIcons[factionId] = icon
                    }
                }
            }
        }
    }
}
