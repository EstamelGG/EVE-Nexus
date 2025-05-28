import SwiftUI

// 主权列表视图
struct SovereigntyListView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var searchText = ""
    @State private var sovereignties: [SovereigntyInfo] = []
    @State private var isLoading = true
    @State private var isSearchActive = false
    @State private var errorMessage: String? = nil
    @State private var showError: Bool = false
    @StateObject private var iconLoader = AllianceIconLoader()

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
                    // 过滤并显示主权列表
                    ForEach(filteredSovereignties, id: \.id) { sovereignty in
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
        .navigationTitle(NSLocalizedString("Sovereignty_List", comment: "主权势力列表"))
        .refreshable {
            await refreshSovereigntyData()
        }
        .onAppear {
            loadSovereigntyData()
        }
        .onDisappear {
            iconLoader.cancelAllTasks()
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

    // 过滤后的主权列表
    private var filteredSovereignties: [SovereigntyInfo] {
        if searchText.isEmpty {
            return sovereignties
        } else {
            return sovereignties.filter { sovereignty in
                sovereignty.name.localizedCaseInsensitiveContains(searchText) ||
                sovereignty.en_name.localizedCaseInsensitiveContains(searchText) ||
                sovereignty.zh_name.localizedCaseInsensitiveContains(searchText)
            }
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

        // 更新UI显示主权列表（可能部分联盟图标尚未加载）
        await MainActor.run {
            sovereignties = tempSovereignties

            // 开始加载图标
            iconLoader.loadIcons(for: allianceIds)
        }
    }
}
