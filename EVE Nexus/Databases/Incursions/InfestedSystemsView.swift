import SwiftUI

class SystemInfo: NSObject, Identifiable, @unchecked Sendable, ObservableObject {
    let id: Int
    let systemName: String
    let security: Double
    let systemId: Int
    let influence: Double
    let regionName: String
    let constellationName: String
    var allianceId: Int?
    var factionId: Int?
    @Published var icon: Image?
    @Published var isLoadingIcon: Bool = false
    
    init(systemName: String, security: Double, systemId: Int, influence: Double, regionName: String, constellationName: String) {
        self.id = systemId
        self.systemName = systemName
        self.security = security
        self.systemId = systemId
        self.influence = influence
        self.regionName = regionName
        self.constellationName = constellationName
        super.init()
    }
    
    @MainActor
    func loadIcon(databaseManager: DatabaseManager) async {
        guard !isLoadingIcon else { return }
        isLoadingIcon = true
        
        if let allianceId = allianceId {
            do {
                Logger.debug("开始加载联盟图标: \(allianceId)")
                let uiImage = try await AllianceAPI.shared.fetchAllianceLogo(allianceID: allianceId)
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
    @Published var incursion_isLoading: Bool = false
    @Published var incursion_isRefreshing: Bool = false
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
        guard !incursion_isRefreshing else { return }
        incursion_isRefreshing = true
        
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
        
        // 获取入侵数据以获取影响力信息
        var influence: Double = 0.0
        do {
            let incursions = try await StaticResourceManager.shared.fetchIncursionsData()
            if let incursion = incursions.first(where: { $0.infestedSolarSystems.contains(where: { $0 == systemIds.first }) }) {
                influence = incursion.influence
            }
        } catch {
            Logger.error("无法获取入侵数据: \(error)")
        }
        
        for systemId in systemIds {
            // 从 universe 表获取安全等级和其他信息
            let universeQuery = """
                SELECT u.system_security, u.constellation_id, u.region_id,
                       s.solarSystemName,
                       c.constellationName,
                       r.regionName
                FROM universe u
                JOIN solarsystems s ON s.solarSystemID = u.solarsystem_id
                JOIN constellations c ON c.constellationID = u.constellation_id
                JOIN regions r ON r.regionID = u.region_id
                WHERE u.solarsystem_id = ?
            """
            
            guard case .success(let universeRows) = databaseManager.executeQuery(universeQuery, parameters: [systemId]),
                  let universeRow = universeRows.first,
                  let security = universeRow["system_security"] as? Double,
                  let systemName = universeRow["solarSystemName"] as? String,
                  let regionName = universeRow["regionName"] as? String,
                  let constellationName = universeRow["constellationName"] as? String else {
                continue
            }
            
            let systemInfo = SystemInfo(
                systemName: systemName,
                security: security,
                systemId: systemId,
                influence: influence,
                regionName: regionName,
                constellationName: constellationName
            )
            
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
        
        // 多级排序：影响力 > 星域名称 > 安全等级 > 星座名称
        tempSystems.sort { s1, s2 in
            // 首先按影响力从大到小排序
            if s1.influence != s2.influence {
                return s1.influence > s2.influence
            }
            // 然后按星域名称排序
            if s1.regionName != s2.regionName {
                return s1.regionName < s2.regionName
            }
            // 然后按安全等级从高到低排序
            if s1.security != s2.security {
                return s1.security > s2.security
            }
            // 最后按星座名称排序
            return s1.constellationName < s2.constellationName
        }
        
        systems = tempSystems
        
        // 开始加载图标
        loadAllIcons()
        
        // 更新缓存
        Self.systemsCache[systemIds.hashValue] = tempSystems
        
        incursion_isRefreshing = false
    }
    
    private func loadSystems(systemIds: [Int]) {
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
                        let uiImage = try await AllianceAPI.shared.fetchAllianceLogo(allianceID: allianceId)
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
            if viewModel.incursion_isLoading {
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
