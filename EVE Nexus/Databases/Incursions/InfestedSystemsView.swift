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
    
    init(systemName: String, security: Double, systemId: Int) {
        self.id = systemId
        self.systemName = systemName
        self.security = security
        self.systemId = systemId
        super.init()
    }
    
    @MainActor
    func loadIcon(databaseManager: DatabaseManager) async {
        guard !isLoadingIcon else { return }
        isLoadingIcon = true
        
        if let allianceId = allianceId {
            do {
                Logger.debug("开始加载联盟图标: \(allianceId)")
                let uiImage = try await NetworkManager.shared.fetchAllianceLogo(allianceID: allianceId)
                if !Task.isCancelled {
                    icon = Image(uiImage: uiImage)
                    Logger.debug("联盟图标加载成功: \(allianceId)")
                }
            } catch {
                if (error as NSError).code == NSURLErrorCancelled {
                    Logger.debug("联盟图标加载已取消: \(allianceId)")
                } else {
                    Logger.error("加载联盟图标失败: \(allianceId), error: \(error)")
                }
            }
        } else if let factionId = factionId {
            let query = "SELECT iconName FROM factions WHERE id = ?"
            if case .success(let rows) = databaseManager.executeQuery(query, parameters: [factionId]),
               let row = rows.first,
               let iconName = row["iconName"] as? String {
                Logger.debug("开始加载派系图标: \(factionId)")
                icon = IconManager.shared.loadImage(for: iconName)
                Logger.debug("派系图标加载成功: \(factionId)")
            } else {
                Logger.error("派系图标加载失败: \(factionId)")
            }
        }
        
        isLoadingIcon = false
    }
}

@MainActor
class InfestedSystemsViewModel: ObservableObject {
    @Published var systems: [SystemInfo] = []
    @Published var isLoading: Bool = false
    @Published var isRefreshing: Bool = false
    let databaseManager: DatabaseManager
    private var loadingTasks: [Int: Task<Void, Never>] = [:]
    private var systemIds: [Int] = []  // 保存系统ID列表
    
    // 存储联盟ID到系统的映射
    private var allianceToSystems: [Int: [SystemInfo]] = [:]
    // 存储派系ID到系统的映射
    private var factionToSystems: [Int: [SystemInfo]] = [:]
    
    private static var systemsCache: [Int: [SystemInfo]] = [:]
    
    // 添加公共的清理缓存方法
    static func clearCache() {
        systemsCache.removeAll()
    }
    
    init(databaseManager: DatabaseManager, systemIds: [Int]) {
        self.databaseManager = databaseManager
        self.systemIds = systemIds  // 保存系统ID列表
        
        // 先尝试从缓存加载
        if let cachedSystems = Self.systemsCache[systemIds.hashValue] {
            self.systems = cachedSystems
            Logger.info("使用缓存的受影响星系数据: \(systemIds.count) 个星系")
        } else {
            loadSystems(systemIds: systemIds)
        }
    }
    
    // 修改刷新方法
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        
        // 清除缓存
        Self.systemsCache.removeValue(forKey: systemIds.hashValue)
        
        var tempSystems: [SystemInfo] = []
        
        // 取消所有现有的加载任务
        loadingTasks.values.forEach { $0.cancel() }
        loadingTasks.removeAll()
        
        // 清除现有映射
        allianceToSystems.removeAll()
        factionToSystems.removeAll()
        
        // 获取主权数据
        var sovereigntyData: [SovereigntyData]?
        do {
            sovereigntyData = try await StaticResourceManager.shared.fetchSovereigntyData()
        } catch {
            Logger.error("无法获取主权数据: \(error)")
        }
        
        for systemId in systemIds {
            // 从 universe 表获取安全等级
            let universeQuery = """
                SELECT system_security
                FROM universe
                WHERE solarsystem_id = ?
            """
            
            guard case .success(let universeRows) = databaseManager.executeQuery(universeQuery, parameters: [systemId]),
                  let universeRow = universeRows.first,
                  let security = universeRow["system_security"] as? Double else {
                continue
            }
            
            // 获取星系名称
            let systemQuery = "SELECT solarSystemName FROM solarsystems WHERE solarSystemID = ?"
            guard case .success(let systemRows) = databaseManager.executeQuery(systemQuery, parameters: [systemId]),
                  let systemRow = systemRows.first,
                  let systemName = systemRow["solarSystemName"] as? String else {
                continue
            }
            
            let systemInfo = SystemInfo(systemName: systemName, security: security, systemId: systemId)
            
            // 设置主权信息并建立映射关系
            if let sovereigntyData = sovereigntyData,
               let systemData = sovereigntyData.first(where: { $0.systemId == systemId }) {
                systemInfo.allianceId = systemData.allianceId
                systemInfo.factionId = systemData.factionId
                
                // 建立联盟到系统的映射
                if let allianceId = systemData.allianceId {
                    allianceToSystems[allianceId, default: []].append(systemInfo)
                }
                // 建立派系到系统的映射
                if let factionId = systemData.factionId {
                    factionToSystems[factionId, default: []].append(systemInfo)
                }
            } else {
                Logger.warning("无法获取星系 \(systemId) 的主权信息")
            }
            
            tempSystems.append(systemInfo)
        }
        
        // 按星系名称字母顺序排序
        tempSystems.sort { $0.systemName < $1.systemName }
        systems = tempSystems
        
        // 开始加载图标
        loadAllIcons()
        
        // 更新缓存
        Self.systemsCache[systemIds.hashValue] = tempSystems
        
        isRefreshing = false
    }
    
    private func loadSystems(systemIds: [Int]) {
        Task {
            isLoading = true
            await refresh()
            isLoading = false
        }
    }
    
    private func loadAllIcons() {
        // 加载联盟图标
        for (allianceId, systems) in allianceToSystems {
            let task = Task {
                if systems.first != nil {
                    do {
                        Logger.debug("开始加载联盟图标: \(allianceId)，影响 \(systems.count) 个星系")
                        let uiImage = try await NetworkManager.shared.fetchAllianceLogo(allianceID: allianceId)
                        if !Task.isCancelled {
                            let icon = Image(uiImage: uiImage)
                            // 更新所有使用这个联盟图标的系统
                            for system in systems {
                                system.icon = icon
                            }
                            Logger.debug("联盟图标加载成功: \(allianceId)")
                        }
                    } catch {
                        if (error as NSError).code == NSURLErrorCancelled {
                            Logger.debug("联盟图标加载已取消: \(allianceId)")
                        } else {
                            Logger.error("加载联盟图标失败: \(allianceId), error: \(error)")
                        }
                    }
                    // 更新所有相关系统的加载状态
                    for system in systems {
                        system.isLoadingIcon = false
                    }
                }
            }
            loadingTasks[allianceId] = task
            // 设置所有相关系统的加载状态
            for system in systems {
                system.isLoadingIcon = true
            }
        }
        
        // 加载派系图标
        for (factionId, systems) in factionToSystems {
            if systems.first != nil {
                Logger.debug("开始加载派系图标: \(factionId)，影响 \(systems.count) 个星系")
                let query = "SELECT iconName FROM factions WHERE id = ?"
                if case .success(let rows) = databaseManager.executeQuery(query, parameters: [factionId]),
                   let row = rows.first,
                   let iconName = row["iconName"] as? String {
                    let icon = IconManager.shared.loadImage(for: iconName)
                    // 更新所有使用这个派系图标的系统
                    for system in systems {
                        system.icon = icon
                    }
                    Logger.debug("派系图标加载成功: \(factionId)")
                } else {
                    Logger.error("派系图标加载失败: \(factionId)")
                }
                // 更新所有相关系统的加载状态
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
        _viewModel = StateObject(wrappedValue: InfestedSystemsViewModel(databaseManager: databaseManager, systemIds: systemIds))
    }
    
    var body: some View {
        ZStack {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(viewModel.systems) { system in
                        SystemRow(system: system)
                    }
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
        HStack {
            Text(formatSecurity(system.security))
                .foregroundColor(getSecurityColor(system.security))
            Text(system.systemName)
                .fontWeight(.medium)
            Spacer()
            if system.isLoadingIcon {
                ProgressView()
                    .frame(width: 32, height: 32)
            } else if let icon = system.icon {
                icon
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
            }
        }
    }
}
