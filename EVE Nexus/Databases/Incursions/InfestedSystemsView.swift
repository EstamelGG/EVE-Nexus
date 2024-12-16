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
    @Published var shouldShowIcon: Bool = false
    
    init(systemName: String, security: Double, systemId: Int) {
        self.id = systemId
        self.systemName = systemName
        self.security = security
        self.systemId = systemId
        super.init()
    }
}

@MainActor
class InfestedSystemsViewModel: ObservableObject {
    @Published var systems: [SystemInfo] = []
    @Published var isLoading: Bool = false
    let databaseManager: DatabaseManager
    private var allianceIconTasks: [Int: Task<Void, Never>] = [:]
    
    init(databaseManager: DatabaseManager, systemIds: [Int]) {
        self.databaseManager = databaseManager
        loadSystems(systemIds: systemIds)
    }
    
    private func loadSystems(systemIds: [Int]) {
        isLoading = true
        var tempSystems: [SystemInfo] = []
        
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
            
            // 获取主权信息
            if let sovereigntyData = NetworkManager.shared.getCachedSovereigntyData(),
               let systemData = sovereigntyData.first(where: { $0.systemId == systemId }) {
                if let allianceId = systemData.allianceId {
                    // 有联盟ID，设置联盟ID
                    systemInfo.allianceId = allianceId
                } else if let factionId = systemData.factionId {
                    // 没有联盟ID但有派系ID，设置派系ID
                    systemInfo.factionId = factionId
                } else {
                    // 都没有，设置派系ID为1
                    systemInfo.factionId = 1
                }
            } else {
                // 找不到主权数据，设置派系ID为1
                systemInfo.factionId = 1
            }
            
            tempSystems.append(systemInfo)
        }
        
        // 按安全等级排序
        tempSystems.sort { $0.security > $1.security }
        
        systems = tempSystems
        isLoading = false
        loadIcons()
    }
    
    private func loadIcons() {
        // 获取所有不重复的联盟ID
        let uniqueAllianceIds = Set(systems.compactMap { $0.allianceId })
        
        // 为每个联盟异步加载图标
        for allianceId in uniqueAllianceIds {
            let systemIds = systems.filter { $0.allianceId == allianceId }.map { $0.systemId }
            let task = Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                // 设置加载状态
                for systemId in systemIds {
                    if let system = self.systems.first(where: { $0.systemId == systemId }) {
                        system.isLoadingIcon = true
                        system.shouldShowIcon = false
                        system.icon = nil
                    }
                }
                
                do {
                    let uiImage = try await NetworkManager.shared.fetchAllianceLogo(allianceId: allianceId)
                    Logger.debug("成功获取联盟图标: \(allianceId)")
                    let image = Image(uiImage: uiImage)
                    Logger.debug("成功转换为SwiftUI Image: \(allianceId)")
                    updateAllianceIcon(allianceId: allianceId, image: image, shouldShow: true)
                    Logger.debug("已更新联盟图标: \(allianceId), shouldShow: true")
                } catch {
                    Logger.error("加载联盟图标失败: \(allianceId), error: \(error)")
                    updateAllianceIcon(allianceId: allianceId, image: nil, shouldShow: false)
                }
                
                // 重置加载状态
                for systemId in systemIds {
                    if let system = self.systems.first(where: { $0.systemId == systemId }) {
                        system.isLoadingIcon = false
                    }
                }
            }
            allianceIconTasks[allianceId] = task
        }
        
        // 加载派系图标
        for system in systems {
            if let factionId = system.factionId {
                let systemId = system.systemId
                system.isLoadingIcon = true
                system.shouldShowIcon = false
                system.icon = nil
                
                let query = "SELECT iconName FROM factions WHERE id = ?"
                if case .success(let rows) = databaseManager.executeQuery(query, parameters: [factionId]),
                   let row = rows.first,
                   let iconName = row["iconName"] as? String {
                    if let system = self.systems.first(where: { $0.systemId == systemId }) {
                        system.icon = IconManager.shared.loadImage(for: iconName)
                        system.shouldShowIcon = true
                        system.isLoadingIcon = false
                    }
                } else {
                    // 如果查询失败，不显示任何图标
                    if let system = self.systems.first(where: { $0.systemId == systemId }) {
                        system.icon = nil
                        system.shouldShowIcon = false
                        system.isLoadingIcon = false
                    }
                }
            }
        }
    }
    
    private func updateAllianceIcon(allianceId: Int, image: Image?, shouldShow: Bool) {
        var updatedCount = 0
        for system in systems {
            if system.allianceId == allianceId {
                DispatchQueue.main.async {
                    system.icon = image
                    system.shouldShowIcon = shouldShow
                }
                updatedCount += 1
            }
        }
        Logger.debug("更新了 \(updatedCount) 个系统的联盟图标 \(allianceId)")
    }
    
    deinit {
        // 取消所有未完成的图标加载任务
        for task in allianceIconTasks.values {
            task.cancel()
        }
    }
}

struct InfestedSystemsView: View {
    @StateObject private var viewModel: InfestedSystemsViewModel
    
    init(databaseManager: DatabaseManager, systemIds: [Int]) {
        _viewModel = StateObject(wrappedValue: InfestedSystemsViewModel(databaseManager: databaseManager, systemIds: systemIds))
    }
    
    var body: some View {
        if viewModel.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(viewModel.systems) { system in
                    SystemRow(system: system)
                        .environmentObject(viewModel)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(NSLocalizedString("Main_Infested_Systems", comment: ""))
        }
    }
}

struct SystemRow: View {
    @ObservedObject var system: SystemInfo
    @EnvironmentObject private var viewModel: InfestedSystemsViewModel
    @StateObject private var iconLoadManager = IconLoadManager.shared
    
    var body: some View {
        HStack {
            Text(formatSecurity(system.security))
                .foregroundColor(getSecurityColor(system.security))
            Text(system.systemName)
                .fontWeight(.medium)
            Spacer()
            if let allianceId = system.allianceId {
                let (icon, isLoading) = iconLoadManager.getAllianceIcon(allianceId: allianceId)
                if isLoading {
                    ProgressView()
                        .frame(width: 32, height: 32)
                } else if let icon = icon {
                    icon
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                }
            } else if let factionId = system.factionId {
                let (icon, isLoading) = iconLoadManager.getFactionIcon(factionId: factionId)
                if isLoading {
                    ProgressView()
                        .frame(width: 32, height: 32)
                } else if let icon = icon {
                    icon
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                }
            }
        }
        .onAppear {
            loadIcon()
        }
    }
    
    private func loadIcon() {
        if let allianceId = system.allianceId {
            iconLoadManager.loadAllianceIcon(allianceId: allianceId)
        } else if let factionId = system.factionId {
            iconLoadManager.loadFactionIcon(factionId: factionId, databaseManager: viewModel.databaseManager)
        }
    }
}

@MainActor
class IconLoadManager: ObservableObject {
    static let shared = IconLoadManager()
    
    @Published private var allianceIcons: [Int: (Image?, Bool)] = [:]  // [allianceId: (icon, isLoading)]
    @Published private var factionIcons: [Int: (Image?, Bool)] = [:]   // [factionId: (icon, isLoading)]
    private var loadingTasks: [Int: Task<Void, Never>] = [:]
    
    private init() {}
    
    func getAllianceIcon(allianceId: Int) -> (Image?, Bool) {
        allianceIcons[allianceId] ?? (nil, false)
    }
    
    func getFactionIcon(factionId: Int) -> (Image?, Bool) {
        factionIcons[factionId] ?? (nil, false)
    }
    
    func loadAllianceIcon(allianceId: Int) {
        // 如果已经在加载或已经加载完成，直接返回
        if allianceIcons[allianceId] != nil || loadingTasks[allianceId] != nil {
            return
        }
        
        // 标记为正在加载
        allianceIcons[allianceId] = (nil, true)
        
        let task = Task { @MainActor in
            do {
                let uiImage = try await NetworkManager.shared.fetchAllianceLogo(allianceId: allianceId)
                if !Task.isCancelled {
                    allianceIcons[allianceId] = (Image(uiImage: uiImage), false)
                }
            } catch {
                Logger.error("加载联盟图标失败: \(allianceId), error: \(error)")
                if !Task.isCancelled {
                    allianceIcons[allianceId] = (nil, false)
                }
            }
            loadingTasks[allianceId] = nil
        }
        loadingTasks[allianceId] = task
    }
    
    func loadFactionIcon(factionId: Int, databaseManager: DatabaseManager) {
        // 如果已经在加载或已经加载完成，直接返回
        if factionIcons[factionId] != nil {
            return
        }
        
        // 标记为正在加载
        factionIcons[factionId] = (nil, true)
        
        let query = "SELECT iconName FROM factions WHERE id = ?"
        if case .success(let rows) = databaseManager.executeQuery(query, parameters: [factionId]),
           let row = rows.first,
           let iconName = row["iconName"] as? String {
            factionIcons[factionId] = (IconManager.shared.loadImage(for: iconName), false)
        } else {
            factionIcons[factionId] = (nil, false)
        }
    }
    
    private func cleanupTasks() {
        for task in loadingTasks.values {
            task.cancel()
        }
        loadingTasks.removeAll()
        allianceIcons.removeAll()
        factionIcons.removeAll()
    }
    
    func cancelAllTasks() {
        Task { @MainActor in
            cleanupTasks()
        }
    }
    
    deinit {
        for task in loadingTasks.values {
            task.cancel()
        }
    }
}
