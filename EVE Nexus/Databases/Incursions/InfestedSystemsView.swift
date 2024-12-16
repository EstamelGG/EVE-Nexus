import SwiftUI

class SystemInfo: Identifiable {
    let id: Int
    let systemName: String
    let security: Double
    let systemId: Int
    var allianceId: Int?
    var factionId: Int?
    var icon: Image?
    
    init(systemName: String, security: Double, systemId: Int) {
        self.id = systemId
        self.systemName = systemName
        self.security = security
        self.systemId = systemId
    }
}

class InfestedSystemsViewModel: ObservableObject {
    @Published var systems: [SystemInfo] = []
    let databaseManager: DatabaseManager
    private var allianceIconTasks: [Int: Task<Void, Never>] = [:]
    
    init(databaseManager: DatabaseManager, systemIds: [Int]) {
        self.databaseManager = databaseManager
        loadSystems(systemIds: systemIds)
    }
    
    private func loadSystems(systemIds: [Int]) {
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
        
        DispatchQueue.main.async {
            self.systems = tempSystems
            self.loadIcons()
        }
    }
    
    private func loadIcons() {
        // 获取所有不重复的联盟ID
        let uniqueAllianceIds = Set(systems.compactMap { $0.allianceId })
        
        // 为每个联盟异步加载图标
        for allianceId in uniqueAllianceIds {
            let task = Task {
                do {
                    let uiImage = try await NetworkManager.shared.fetchAllianceLogo(allianceId: allianceId)
                    let image = Image(uiImage: uiImage)
                    updateAllianceIcon(allianceId: allianceId, image: image)
                } catch {
                    // 如果加载失败，使用默认图标
                    updateAllianceIcon(allianceId: allianceId, image: IconManager.shared.loadImage(for: "corporations_1.png"))
                }
            }
            allianceIconTasks[allianceId] = task
        }
        
        // 加载派系图标
        for system in systems {
            if let factionId = system.factionId {
                let query = "SELECT iconName FROM factions WHERE id = ?"
                if case .success(let rows) = databaseManager.executeQuery(query, parameters: [factionId]),
                   let row = rows.first,
                   let iconName = row["iconName"] as? String {
                    DispatchQueue.main.async {
                        system.icon = IconManager.shared.loadImage(for: iconName)
                    }
                }
            }
        }
    }
    
    private func updateAllianceIcon(allianceId: Int, image: Image) {
        DispatchQueue.main.async {
            for system in self.systems {
                if system.allianceId == allianceId {
                    system.icon = image
                }
            }
        }
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
        List {
            ForEach(viewModel.systems) { system in
                HStack {
                    if let icon = system.icon {
                        icon
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 32)
                    }
                    Text(formatSecurity(system.security))
                        .foregroundColor(getSecurityColor(system.security))
                    Text(system.systemName)
                        .fontWeight(.medium)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("Main_Infested_Systems", comment: ""))
    }
} 
