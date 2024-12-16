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
                let uiImage = try await NetworkManager.shared.fetchAllianceLogo(allianceId: allianceId)
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
    let databaseManager: DatabaseManager
    private var loadingTasks: [Int: Task<Void, Never>] = [:]
    
    init(databaseManager: DatabaseManager, systemIds: [Int]) {
        self.databaseManager = databaseManager
        loadSystems(systemIds: systemIds)
    }
    
    private func loadSystems(systemIds: [Int]) {
        isLoading = true
        var tempSystems: [SystemInfo] = []
        
        // 取消所有现有的加载任务
        loadingTasks.values.forEach { $0.cancel() }
        loadingTasks.removeAll()
        
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
            
            // 设置主权信息
            if let sovereigntyData = NetworkManager.shared.getCachedSovereigntyData(),
               let systemData = sovereigntyData.first(where: { $0.systemId == systemId }) {
                systemInfo.allianceId = systemData.allianceId
                systemInfo.factionId = systemData.factionId
                
                // 创建加载任务
                let task = Task {
                    await systemInfo.loadIcon(databaseManager: databaseManager)
                }
                loadingTasks[systemId] = task
            }
            
            tempSystems.append(systemInfo)
        }
        
        // 按安全等级排序
        tempSystems.sort { $0.security > $1.security }
        systems = tempSystems
        isLoading = false
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
            .navigationTitle(NSLocalizedString("Main_Infested_Systems", comment: ""))
        }
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
