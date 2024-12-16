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
    
    init(databaseManager: DatabaseManager, systemIds: [Int]) {
        self.databaseManager = databaseManager
        loadSystems(systemIds: systemIds)
    }
    
    private func loadSystems(systemIds: [Int]) {
        isLoading = true
        var tempSystems: [SystemInfo] = []
        
        // 重置图标管理器
        IconLoadManager.shared.reset()
        
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
            
            // 注册系统的图标信息
            if let sovereigntyData = NetworkManager.shared.getCachedSovereigntyData(),
               let systemData = sovereigntyData.first(where: { $0.systemId == systemId }) {
                if let allianceId = systemData.allianceId {
                    systemInfo.allianceId = allianceId
                    IconLoadManager.shared.registerSystem(systemId: systemId, allianceId: allianceId, factionId: nil)
                } else if let factionId = systemData.factionId {
                    systemInfo.factionId = factionId
                    IconLoadManager.shared.registerSystem(systemId: systemId, allianceId: nil, factionId: factionId)
                }
            }
            
            tempSystems.append(systemInfo)
        }
        
        // 按安全等级排序
        tempSystems.sort { $0.security > $1.security }
        
        systems = tempSystems
        isLoading = false
        
        // 开始加载所有图标
        IconLoadManager.shared.startLoadingIcons(databaseManager: databaseManager)
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
            let (icon, isLoading) = iconLoadManager.getIconState(systemId: system.systemId)
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
}

@MainActor
class IconLoadManager: ObservableObject {
    static let shared = IconLoadManager()
    
    // 存储图标加载状态和结果
    @Published private var iconCache: [IconKey: IconState] = [:]
    @Published private var loadingTasks: [IconKey: Task<Void, Never>] = [:]
    // 存储ID到系统的映射关系
    private var systemMapping: [IconKey: Set<Int>] = [:]
    
    private init() {}
    
    // 图标的唯一标识
    enum IconKey: Hashable {
        case alliance(Int)
        case faction(Int)
    }
    
    // 图标状态
    struct IconState {
        var image: Image?
        var isLoading: Bool
    }
    
    // 注册系统和其对应的图标ID
    func registerSystem(systemId: Int, allianceId: Int?, factionId: Int?) {
        if let allianceId = allianceId {
            let key = IconKey.alliance(allianceId)
            var systems = systemMapping[key] ?? Set<Int>()
            systems.insert(systemId)
            systemMapping[key] = systems
        } else if let factionId = factionId {
            let key = IconKey.faction(factionId)
            var systems = systemMapping[key] ?? Set<Int>()
            systems.insert(systemId)
            systemMapping[key] = systems
        }
    }
    
    // 获取系统对应的图标状态
    func getIconState(systemId: Int) -> (Image?, Bool) {
        for (key, systems) in systemMapping {
            if systems.contains(systemId) {
                if let state = iconCache[key] {
                    let isLoading = loadingTasks[key] != nil
                    return (state.image, isLoading)
                } else {
                    // 如果缓存中没有状态，返回加载中状态
                    return (nil, true)
                }
            }
        }
        return (nil, false)
    }
    
    // 开始加载所有注册的图标
    func startLoadingIcons(databaseManager: DatabaseManager) {
        // 取消所有现有任务
        for task in loadingTasks.values {
            task.cancel()
        }
        loadingTasks.removeAll()
        
        // 清除缓存状态
        iconCache.removeAll()
        
        // 重新加载所有图标
        let uniqueKeys = Set(systemMapping.keys)
        for key in uniqueKeys {
            switch key {
            case .alliance(let allianceId):
                loadAllianceIcon(allianceId: allianceId)
            case .faction(let factionId):
                loadFactionIcon(factionId: factionId, databaseManager: databaseManager)
            }
        }
    }
    
    private func loadAllianceIcon(allianceId: Int) {
        let key = IconKey.alliance(allianceId)
        
        // 如果已经有任务在运行，不要创建新任务
        guard loadingTasks[key] == nil else { return }
        
        let task = Task { @MainActor in
            do {
                let uiImage = try await NetworkManager.shared.fetchAllianceLogo(allianceId: allianceId)
                if !Task.isCancelled {
                    withAnimation {
                        iconCache[key] = IconState(image: Image(uiImage: uiImage), isLoading: false)
                    }
                    Logger.debug("联盟图标加载成功: \(allianceId)")
                }
            } catch {
                if !Task.isCancelled {
                    if (error as NSError).code == NSURLErrorCancelled {
                        Logger.debug("联盟图标加载已取消: \(allianceId)")
                    } else {
                        Logger.error("加载联盟图标失败: \(allianceId), error: \(error)")
                        withAnimation {
                            iconCache[key] = IconState(image: nil, isLoading: false)
                        }
                    }
                }
            }
            
            if !Task.isCancelled {
                withAnimation {
                    loadingTasks.removeValue(forKey: key)
                }
            }
        }
        
        loadingTasks[key] = task
    }
    
    private func loadFactionIcon(factionId: Int, databaseManager: DatabaseManager) {
        let key = IconKey.faction(factionId)
        
        let query = "SELECT iconName FROM factions WHERE id = ?"
        if case .success(let rows) = databaseManager.executeQuery(query, parameters: [factionId]),
           let row = rows.first,
           let iconName = row["iconName"] as? String {
            withAnimation {
                iconCache[key] = IconState(image: IconManager.shared.loadImage(for: iconName), isLoading: false)
            }
            Logger.debug("派系图标加载成功: \(factionId)")
        } else {
            withAnimation {
                iconCache[key] = IconState(image: nil, isLoading: false)
            }
            Logger.error("派系图标加载失败: \(factionId)")
        }
    }
    
    func reset() {
        Task { @MainActor in
            // 取消所有任务
            for task in loadingTasks.values {
                task.cancel()
            }
            
            // 清除所有状态
            withAnimation {
                loadingTasks.removeAll()
                iconCache.removeAll()
                systemMapping.removeAll()
            }
        }
    }
    
    deinit {
        Task { @MainActor in
            for task in loadingTasks.values {
                task.cancel()
            }
        }
    }
}
