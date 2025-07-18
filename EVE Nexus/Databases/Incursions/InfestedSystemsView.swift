import SwiftUI

class SystemInfo: NSObject, Identifiable, @unchecked Sendable, ObservableObject {
    let id: Int
    let systemName: String
    let security: Double
    let systemId: Int
    var allianceId: Int?
    var factionId: Int?
    @Published var icon: Image?
    @Published var isLoadingIcon: Bool = false
    @Published var allianceName: String?

    init(systemName: String, security: Double, systemId: Int) {
        id = systemId
        self.systemName = systemName
        self.security = security
        self.systemId = systemId
        super.init()
    }
}

@MainActor
class InfestedSystemsViewModel: ObservableObject {
    @Published var systems: [SystemInfo] = []
    @Published var incursion_isLoading: Bool = false
    @Published var incursion_isRefreshing: Bool = false
    let databaseManager: DatabaseManager
    private var loadingTasks: [Int: Task<Void, Never>] = [:]
    private var systemIds: [Int] = []

    private var allianceToSystems: [Int: [SystemInfo]] = [:]
    private var factionToSystems: [Int: [SystemInfo]] = [:]

    // 修改缓存结构，只缓存星系ID
    private static var systemIdsCache: Set<Int> = []

    static func clearCache() {
        systemIdsCache.removeAll()
    }

    init(databaseManager: DatabaseManager, systemIds: [Int]) {
        self.databaseManager = databaseManager
        self.systemIds = systemIds

        // 检查是否需要重新加载
        let systemIdsSet = Set(systemIds)
        if systemIdsSet == Self.systemIdsCache {
            Logger.info("使用缓存的受影响星系ID列表: \(systemIds.count) 个星系")
        } else {
            Self.systemIdsCache = systemIdsSet
        }

        loadSystems(systemIds: systemIds)
    }

    // 修改刷新方法
    func refresh() async {
        guard !incursion_isRefreshing else { return }
        incursion_isRefreshing = true

        // 清除缓存
        Self.systemIdsCache.removeAll()

        // 取消所有现有的加载任务
        loadingTasks.values.forEach { $0.cancel() }
        loadingTasks.removeAll()

        // 清除现有映射
        allianceToSystems.removeAll()
        factionToSystems.removeAll()

        // 获取主权数据
        var sovereigntyData: [SovereigntyData]?
        do {
            sovereigntyData = try await SovereigntyDataAPI.shared.fetchSovereigntyData(
                forceRefresh: false)
        } catch {
            Logger.error("无法获取主权数据: \(error)")
        }

        // 更新缓存
        Self.systemIdsCache = Set(systemIds)

        // 一次性获取所有星系信息
        let systemInfoMap = await getBatchSolarSystemInfo(
            solarSystemIds: systemIds,
            databaseManager: databaseManager
        )

        var tempSystems: [SystemInfo] = []

        for systemId in systemIds {
            guard let info = systemInfoMap[systemId] else {
                continue
            }

            let systemInfo = SystemInfo(
                systemName: info.systemName,
                security: info.security,
                systemId: systemId
            )

            // 设置主权信息并建立映射关系
            if let sovereigntyData = sovereigntyData,
                let systemData = sovereigntyData.first(where: { $0.systemId == systemId })
            {
                systemInfo.allianceId = systemData.allianceId
                systemInfo.factionId = systemData.factionId

                // 建立联盟到星系的映射
                if let allianceId = systemData.allianceId {
                    allianceToSystems[allianceId, default: []].append(systemInfo)
                }
                // 建立派系到星系的映射
                if let factionId = systemData.factionId {
                    factionToSystems[factionId, default: []].append(systemInfo)
                }
            } else {
                Logger.warning("无法获取星系 \(systemId) 的主权信息")
            }

            tempSystems.append(systemInfo)
        }

        // 只按星系名称排序
        tempSystems.sort { $0.systemName < $1.systemName }

        systems = tempSystems

        // 开始加载图标
        loadAllIcons()

        incursion_isRefreshing = false
    }

    private func loadSystems(systemIds _: [Int]) {
        Task {
            incursion_isLoading = true
            await refresh()
            incursion_isLoading = false
        }
    }

    private func loadAllIcons() {
        // 加载联盟图标
        for (allianceId, systems) in allianceToSystems {
            let task = Task {
                if systems.first != nil {
                    do {
                        Logger.debug("开始加载联盟图标: \(allianceId)，影响 \(systems.count) 个星系")

                        // 使用AllianceAPI加载图标
                        let allianceImage = try await AllianceAPI.shared.fetchAllianceLogo(
                            allianceID: allianceId,
                            size: 64,
                            forceRefresh: false
                        )

                        Logger.debug("联盟图标加载成功: \(allianceId)")
                        // 更新所有使用这个联盟图标的星系
                        for system in systems {
                            system.icon = Image(uiImage: allianceImage)
                        }

                        // 加载联盟名称
                        if let allianceInfo = try? await AllianceAPI.shared.fetchAllianceInfo(
                            allianceId: allianceId)
                        {
                            for system in systems {
                                system.allianceName = allianceInfo.name
                            }
                            Logger.debug("联盟名称加载成功: \(allianceId)")
                        }
                    } catch {
                        Logger.error("加载联盟图标失败: \(allianceId), error: \(error)")
                    }

                    // 更新所有相关星系的加载状态
                    for system in systems {
                        system.isLoadingIcon = false
                    }
                }
            }
            loadingTasks[allianceId] = task
            // 设置所有相关星系的加载状态
            for system in systems {
                system.isLoadingIcon = true
            }
        }

        // 加载派系图标
        for (factionId, systems) in factionToSystems {
            if systems.first != nil {
                Logger.debug("开始加载派系图标: \(factionId)，影响 \(systems.count) 个星系")
                let query = "SELECT iconName, name FROM factions WHERE id = ?"
                if case let .success(rows) = databaseManager.executeQuery(
                    query, parameters: [factionId]
                ),
                    let row = rows.first,
                    let iconName = row["iconName"] as? String
                {
                    let icon = IconManager.shared.loadImage(for: iconName)
                    let factionName = row["name"] as? String
                    // 更新所有使用这个派系图标的星系
                    for system in systems {
                        system.icon = icon
                        system.allianceName = factionName
                    }
                    Logger.debug("派系图标和名称加载成功: \(factionId)")
                } else {
                    Logger.error("派系图标加载失败: \(factionId)")
                }
                // 更新所有相关星系的加载状态
                for system in systems {
                    system.isLoadingIcon = false
                }
            }
        }
    }

    deinit {
        loadingTasks.values.forEach { $0.cancel() }
    }
}

struct InfestedSystemsView: View {
    @StateObject private var viewModel: InfestedSystemsViewModel

    init(databaseManager: DatabaseManager, systemIds: [Int]) {
        _viewModel = StateObject(
            wrappedValue: InfestedSystemsViewModel(
                databaseManager: databaseManager, systemIds: systemIds
            ))
    }

    var body: some View {
        ZStack {
            if viewModel.incursion_isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(viewModel.systems) { system in
                        SystemRow(system: system)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    Logger.info("用户触发下拉刷新")
                    await viewModel.refresh()
                }
            }
        }
        .navigationTitle(NSLocalizedString("Main_Infested_Systems", comment: ""))
    }
}

struct SystemRow: View {
    @ObservedObject var system: SystemInfo

    var body: some View {
        HStack(spacing: 12) {
            // 左侧图标
            if system.isLoadingIcon {
                ProgressView()
                    .frame(width: 36, height: 36)
            } else if let icon = system.icon {
                icon
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                    .cornerRadius(6)
            }
            // 右侧文本区域
            VStack(alignment: .leading, spacing: 4) {
                // 第一行：安全等级和星系名称
                HStack(spacing: 8) {
                    Text(formatSystemSecurity(system.security))
                        .foregroundColor(getSecurityColor(system.security))
                        .font(.system(.body, design: .monospaced))
                    Text(system.systemName)
                        .fontWeight(.medium)
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = system.systemName
                            } label: {
                                Label(NSLocalizedString("Misc_Copy_Solar", comment: ""), systemImage: "doc.on.doc")
                            }
                        }
                }

                // 第二行：联盟/派系名称
                if let allianceName = system.allianceName {
                    Text(allianceName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
