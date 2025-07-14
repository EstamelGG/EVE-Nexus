import SwiftUI

// 主权势力星系详情视图
struct SovereigntySystemsView: View {
    @ObservedObject var databaseManager: DatabaseManager
    let sovereigntyInfo: SovereigntyInfo
    
    @State private var systems: [SystemInfo] = []
    @State private var groupedSystems: [String: [SystemInfo]] = [:]
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var isSearchActive = false
    @State private var errorMessage: String? = nil
    @State private var showError: Bool = false
    
    // 星系信息结构
    struct SystemInfo: Identifiable {
        let id: Int
        let systemId: Int
        let systemName: String
        let systemNameEn: String
        let systemNameZh: String
        let regionName: String
        let regionId: Int
        let security: Double
        let constellationName: String
    }
    
    init(databaseManager: DatabaseManager, sovereigntyInfo: SovereigntyInfo) {
        self.databaseManager = databaseManager
        self.sovereigntyInfo = sovereigntyInfo
    }
    
    var body: some View {
        VStack {
            if isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(1.5)
                    .padding()
                Text(NSLocalizedString("Loading_Systems", comment: "加载星系中..."))
                    .foregroundColor(.gray)
                Spacer()
            } else {
                List {
                    // 按星域分组显示星系
                    ForEach(Array(filteredGroupedSystems.keys.sorted()), id: \.self) { regionName in
                        Section(
                            header: Text(regionName)
                                .fontWeight(.semibold)
                                .font(.system(size: 16))
                                .foregroundColor(.primary)
                                .textCase(.none)
                        ) {
                            ForEach(filteredGroupedSystems[regionName] ?? []) { system in
                                SovSystemRow(system: system)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .searchable(
            text: $searchText,
            isPresented: $isSearchActive,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: NSLocalizedString("System_Search_Placeholder", comment: "搜索星系...")
        )
        .navigationTitle(sovereigntyInfo.name)
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await refreshSystemsData()
        }
        .onAppear {
            loadSystemsData()
        }
        .alert(
            NSLocalizedString("Load_Error", comment: "加载错误"), 
            isPresented: $showError,
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
            }
        )
    }
    
    // 过滤后的分组星系
    private var filteredGroupedSystems: [String: [SystemInfo]] {
        if searchText.isEmpty {
            return groupedSystems
        } else {
            var filtered: [String: [SystemInfo]] = [:]
            for (regionName, regionSystems) in groupedSystems {
                let filteredSystems = regionSystems.filter { system in
                    // 搜索星系名称（中英文）
                    system.systemName.localizedCaseInsensitiveContains(searchText) ||
                    system.systemNameEn.localizedCaseInsensitiveContains(searchText) ||
                    system.systemNameZh.localizedCaseInsensitiveContains(searchText) ||
                    // 搜索星域和星座名称
                    system.regionName.localizedCaseInsensitiveContains(searchText) ||
                    system.constellationName.localizedCaseInsensitiveContains(searchText)
                }
                if !filteredSystems.isEmpty {
                    filtered[regionName] = filteredSystems
                }
            }
            return filtered
        }
    }
    
    // 加载星系数据
    private func loadSystemsData() {
        isLoading = true
        
        Task {
            do {
                try await loadSystemsDataInternal(forceRefresh: false)
            } catch {
                Logger.error("加载星系数据失败: \(error.localizedDescription)")
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isLoading = false
                }
            }
        }
    }
    
    // 刷新星系数据
    private func refreshSystemsData() async {
        do {
            try await loadSystemsDataInternal(forceRefresh: true)
        } catch {
            Logger.error("刷新星系数据失败: \(error.localizedDescription)")
            await MainActor.run {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
    
    // 内部加载方法
    private func loadSystemsDataInternal(forceRefresh: Bool) async throws {
        // 获取主权数据
        let sovereigntyData = try await SovereigntyDataAPI.shared.fetchSovereigntyData(
            forceRefresh: forceRefresh
        )
        
        // 筛选出该势力控制的星系ID
        var controlledSystemIds: [Int] = []
        
        for data in sovereigntyData {
            if sovereigntyInfo.isAlliance {
                // 如果是联盟，检查联盟ID
                if data.allianceId == sovereigntyInfo.id {
                    controlledSystemIds.append(data.systemId)
                }
            } else {
                // 如果是派系，检查派系ID
                if data.factionId == sovereigntyInfo.id {
                    controlledSystemIds.append(data.systemId)
                }
            }
        }
        
        // 如果没有控制的星系，直接返回
        guard !controlledSystemIds.isEmpty else {
            await MainActor.run {
                systems = []
                groupedSystems = [:]
                isLoading = false
            }
            return
        }
        
        // 批量获取星系基本信息
        let systemInfoMap = await getBatchSolarSystemInfo(
            solarSystemIds: controlledSystemIds,
            databaseManager: databaseManager
        )
        
        // 批量获取星系中英文名称
        let systemNamesMap = await getBatchSolarSystemNames(
            solarSystemIds: controlledSystemIds,
            databaseManager: databaseManager
        )
        
        // 转换为SystemInfo数组
        var systemInfoList: [SystemInfo] = []
        for systemId in controlledSystemIds {
            if let info = systemInfoMap[systemId],
               let names = systemNamesMap[systemId] {
                systemInfoList.append(
                    SystemInfo(
                        id: systemId,
                        systemId: systemId,
                        systemName: info.systemName,
                        systemNameEn: names.nameEn,
                        systemNameZh: names.nameZh,
                        regionName: info.regionName,
                        regionId: info.regionId,
                        security: info.security,
                        constellationName: info.constellationName
                    )
                )
            }
        }
        
        // 按星域分组
        let grouped = Dictionary(grouping: systemInfoList) { $0.regionName }
        
        // 对每个星域内的星系按名称排序
        var sortedGrouped: [String: [SystemInfo]] = [:]
        for (regionName, regionSystems) in grouped {
            sortedGrouped[regionName] = regionSystems.sorted { $0.systemName < $1.systemName }
        }
        
        await MainActor.run {
            systems = systemInfoList
            groupedSystems = sortedGrouped
            isLoading = false
        }
    }
}

// 星系行视图
struct SovSystemRow: View {
    let system: SovereigntySystemsView.SystemInfo
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(formatSystemSecurity(system.security))
                        .foregroundColor(getSecurityColor(system.security))
                        .font(.system(.subheadline, design: .monospaced))
                        .fontWeight(.medium)
                    
                    Text(system.systemName)
                        .fontWeight(.semibold)
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = system.systemName
                            } label: {
                                Label(NSLocalizedString("Misc_Copy_Location", comment: ""), systemImage: "doc.on.doc")
                            }
                        }
                }
                
                Text("\(system.constellationName) / \(system.regionName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
} 
