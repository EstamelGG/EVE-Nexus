import SwiftUI

// MARK: - 常量定义

struct FactionColors {
    static let caldari = Color(red: 0/255, green: 172/255, blue: 209/255)    // 卡达里蓝
    static let minmatar = Color(red: 254/255, green: 55/255, blue: 67/255)   // 米玛塔尔红
    static let amarr = Color(red: 205/255, green: 146/255, blue: 59/255)     // 艾玛金
    static let gallente = Color(red: 55/255, green: 186/255, blue: 91/255)   // 盖伦特绿
    
    static func color(for factionId: Int) -> Color {
        switch factionId {
        case 500001: return caldari
        case 500002: return minmatar
        case 500003: return amarr
        case 500004: return gallente
        default: return .gray.opacity(0.5)
        }
    }
    
    static func enemyColor(for factionId: Int) -> Color {
        switch factionId {
        case 500001: return gallente
        case 500002: return amarr
        case 500003: return minmatar
        case 500004: return caldari
        default: return .gray.opacity(0.5)
        }
    }
}

// MARK: - 数据模型

enum SystemType: String {
    case frontline = "Main_frontline"
    case command = "Main_secondline"
    case reserve = "Main_thirdline"
    case all = "Main_Search_Filter_All"
    
    var localizedString: String {
        NSLocalizedString(rawValue, comment: "")
    }
    
    static var allCases: [SystemType] {
        [.frontline, .command, .reserve, .all]
    }
}

@MainActor
final class PreparedFWSystem: ObservableObject, Identifiable {
    let id: Int
    let system: FWSystem
    @Published var location: LocationInfo
    @Published var ownerIcon: UIImage?
    @Published var occupierIcon: UIImage?
    @Published var isLoadingOwnerIcon = false
    @Published var isLoadingOccupierIcon = false
    @Published var systemType: SystemType = .reserve
    
    struct LocationInfo {
        let systemId: Int
        let systemName: String
        let security: Double
        let constellationId: Int
        let constellationName: String
        let regionId: Int
        let regionName: String
    }
    
    init(system: FWSystem, info: SolarSystemInfo) {
        self.id = system.solar_system_id
        self.system = system
        
        self.location = LocationInfo(
            systemId: info.systemId,
            systemName: info.systemName,
            security: info.security,
            constellationId: info.constellationId,
            constellationName: info.constellationName,
            regionId: info.regionId,
            regionName: info.regionName
        )
    }
}

// 添加通知名称
extension Notification.Name {
    static let systemLocationUpdated = Notification.Name("systemLocationUpdated")
}

// MARK: - ViewModel

@MainActor
final class FactionWarDetailViewModel: ObservableObject {
    @Published private(set) var preparedSystems: [PreparedFWSystem] = []
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var filterType: SystemType = .all
    @Published var searchText = ""
    @Published private var systemNameCache: [Int: (en: String, zh: String)] = [:]
    
    private let faction: FactionInfo
    private let wars: [FWWar]
    private let allFactions: [FactionInfo]
    private let databaseManager: DatabaseManager
    private let systemNeighbours: SystemNeighbours
    private var loadingTask: Task<Void, Never>?
    private var iconLoadingTasks: [Int: Task<Void, Never>] = [:]
    
    var filteredSystems: [PreparedFWSystem] {
        // 首先过滤出与当前势力及其敌对势力相关的星系
        let relevantSystems = preparedSystems.filter { system in
            // 获取当前势力的敌对势力ID
            let enemyFactionIds = wars.filter { war in
                war.faction_id == faction.id || war.against_id == faction.id
            }.map { war in
                war.faction_id == faction.id ? war.against_id : war.faction_id
            }
            
            // 检查星系是否属于当前势力或其敌对势力
            return system.system.owner_faction_id == faction.id ||
                   system.system.occupier_faction_id == faction.id ||
                   enemyFactionIds.contains(system.system.owner_faction_id) ||
                   enemyFactionIds.contains(system.system.occupier_faction_id)
        }
        
        // 应用过滤条件
        let filteredResults = if !searchText.isEmpty {
            // 在内存中搜索匹配的星系
            relevantSystems.filter { system in
                // 检查中文名称
                if system.location.systemName.localizedCaseInsensitiveContains(searchText) {
                    return true
                }
                // 检查英文名称
                if let nameEn = systemNameCache[system.id]?.en,
                   nameEn.localizedCaseInsensitiveContains(searchText) {
                    return true
                }
                return false
            }
        } else if filterType != .all {
            relevantSystems.filter { $0.systemType == filterType }
        } else {
            relevantSystems
        }
        
        // 最后进行排序
        return filteredResults.sorted { system1, system2 in
            system1.location.systemName.localizedStandardCompare(system2.location.systemName) == .orderedAscending
        }
    }
    
    func cycleFilterType() {
        let currentIndex = SystemType.allCases.firstIndex(of: filterType) ?? 0
        let nextIndex = (currentIndex + 1) % SystemType.allCases.count
        filterType = SystemType.allCases[nextIndex]
    }
    
    init(faction: FactionInfo, wars: [FWWar], allFactions: [FactionInfo], databaseManager: DatabaseManager, systemNeighbours: SystemNeighbours) {
        self.faction = faction
        self.wars = wars
        self.allFactions = allFactions
        self.databaseManager = databaseManager
        self.systemNeighbours = systemNeighbours
        
        // 同步加载数据
        Task {
            await loadData()
        }
    }
    
    deinit {
        loadingTask?.cancel()
        iconLoadingTasks.values.forEach { $0.cancel() }
    }
    
    func loadData(forceRefresh: Bool = false) async {
        // 取消之前的加载任务
        loadingTask?.cancel()
        
        // 创建新的加载任务
        loadingTask = Task {
            isLoading = true
            errorMessage = nil
            
            do {
                Logger.info("开始获取FW星系数据")
                let (systems, _) = try await FWAPI.shared.fetchFWData(forceRefresh: forceRefresh)
                
                if Task.isCancelled { return }
                
                // 获取所有星系ID
                let systemIds = systems.map { $0.solar_system_id }
                
                // 获取星系基本信息
                let systemInfoMap = await getBatchSolarSystemInfo(
                    solarSystemIds: systemIds,
                    databaseManager: databaseManager
                )
                
                // 获取星系中英文名称
                let query = "SELECT solarSystemID, solarSystemName, solarSystemName_en FROM solarsystems WHERE solarSystemID IN (\(String(repeating: "?,", count: systemIds.count).dropLast()))"
                if case let .success(rows) = databaseManager.executeQuery(query, parameters: systemIds) {
                    systemNameCache = Dictionary(uniqueKeysWithValues: rows.compactMap { row in
                        guard let id = row["solarSystemID"] as? Int,
                              let name = row["solarSystemName"] as? String,
                              let nameEn = row["solarSystemName_en"] as? String else {
                            return nil
                        }
                        return (id, (en: nameEn, zh: name))
                    })
                }
                
                // 创建PreparedFWSystem对象
                var prepared: [PreparedFWSystem] = []
                
                for system in systems {
                    if let info = systemInfoMap[system.solar_system_id] {
                        let preparedSystem = PreparedFWSystem(
                            system: system,
                            info: info
                        )
                        
                        // 从state中获取systemType
                        if let state = FWSystemStateManager.shared.getSystemState(for: system.solar_system_id) {
                            preparedSystem.systemType = state.systemType
                        }
                        
                        prepared.append(preparedSystem)
                    }
                }
                
                if !prepared.isEmpty {
                    Logger.info("成功准备 \(prepared.count) 条数据")
                    preparedSystems = prepared
                    
                    // 加载所有势力图标
                    loadAllIcons()
                } else {
                    Logger.error("没有可显示的完整数据")
                }
                
                if Task.isCancelled { return }
                
                self.isLoading = false
                
            } catch {
                Logger.error("加载FW星系数据失败: \(error)")
                if !Task.isCancelled {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
        
        // 等待任务完成
        await loadingTask?.value
    }
    
    private func loadAllIcons() {
        // 收集所有需要的势力ID（包括所有者和占领者）
        let allFactionIds = Set(
            preparedSystems.flatMap { system in
                [system.system.owner_faction_id, system.system.occupier_faction_id]
            }
        )
        
        Logger.info("需要加载的势力图标数量: \(allFactionIds.count)")
        
        // 为每个势力ID加载图标
        for factionId in allFactionIds {
            let task = Task {
                if let faction = allFactions.first(where: { $0.id == factionId }) {
                    Logger.info("开始加载势力图标: \(faction.name) (ID: \(factionId))")
                    let uiImage = IconManager.shared.loadUIImage(for: faction.iconName)
                    
                    if Task.isCancelled { return }
                    
                    // 更新所有相关星系的图标
                    for system in preparedSystems {
                        await MainActor.run {
                            // 如果是占领者，设置occupierIcon
                            if system.system.occupier_faction_id == factionId {
                                system.occupierIcon = uiImage
                                system.isLoadingOccupierIcon = false
                            }
                            // 如果是所有者，设置ownerIcon
                            if system.system.owner_faction_id == factionId {
                                system.ownerIcon = uiImage
                                system.isLoadingOwnerIcon = false
                            }
                        }
                    }
                    Logger.info("完成加载势力图标: \(faction.name) (ID: \(factionId))")
                } else {
                    Logger.error("未找到势力信息: \(factionId)")
                }
            }
            iconLoadingTasks[factionId] = task
            
            // 设置相关星系的加载状态
            for system in preparedSystems {
                if system.system.occupier_faction_id == factionId {
                    system.isLoadingOccupierIcon = true
                }
                if system.system.owner_faction_id == factionId {
                    system.isLoadingOwnerIcon = true
                }
            }
        }
    }
}

// MARK: - Views

struct FWSystemCell: View {
    @ObservedObject var system: PreparedFWSystem
    let allFactions: [FactionInfo]
    
    init(system: PreparedFWSystem, allFactions: [FactionInfo]) {
        self.system = system
        self.allFactions = allFactions
    }
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .center) {
                // 背景圆环 - 使用占领者势力颜色
                Circle()
                    .stroke(FactionColors.color(for: system.system.occupier_faction_id), lineWidth: 4)
                    .frame(width: 56, height: 56)
                
                // 进度圆环 - 使用敌人势力颜色
                Circle()
                    .trim(from: 0, to: CGFloat(system.system.victory_points) / CGFloat(system.system.victory_points_threshold))
                    .stroke(FactionColors.enemyColor(for: system.system.occupier_faction_id), lineWidth: 5)
                    .frame(width: 56, height: 56)
                    .rotationEffect(.degrees(-90))
                
                // 主要图标 - 优先显示 occupier 图标，如果没有则显示 owner 图标
                if system.isLoadingOccupierIcon {
                    ProgressView()
                        .frame(width: 48, height: 48)
                } else if let icon = system.occupierIcon {
                    Image(uiImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())
                } else if system.isLoadingOwnerIcon {
                    ProgressView()
                        .frame(width: 48, height: 48)
                } else if let icon = system.ownerIcon {
                    Image(uiImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())
                }
            }
            .frame(width: 56, height: 56)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(formatSystemSecurity(system.location.security))
                        .foregroundColor(getSecurityColor(system.location.security))
                        .font(.system(.subheadline, design: .monospaced))
                    Text(system.location.systemName)
                        .fontWeight(.bold)
                        .textSelection(.enabled)
                }
                
                Text("\(system.location.constellationName) / \(system.location.regionName)")
                    .foregroundColor(.secondary)
                    .font(.caption)
                
                HStack(spacing: 8) {
                    if system.system.contested == "contested" || system.system.contested == "vulnerable",
                       let occupierFaction = allFactions.first(where: { $0.id == system.system.occupier_faction_id }) {
                        Text("\(occupierFaction.name): \(String(format: "%.2f", Double(system.system.victory_points) / Double(system.system.victory_points_threshold) * 100))% \(NSLocalizedString("Main_\(system.system.contested)", comment: ""))")
                            .foregroundColor(.red)
                            .font(.caption)
                            .fontWeight(.bold)
                    } else {
                        Text("\(String(format: "%.1f", Double(system.system.victory_points) / Double(system.system.victory_points_threshold) * 100))% \(NSLocalizedString("Main_\(system.system.contested)", comment: ""))")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }
                Text(NSLocalizedString("Main_system_fw_status", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary) +
                Text(system.systemType.localizedString)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(system.systemType == .frontline ? .red : .secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

struct FactionWarDetailView: View {
    let faction: FactionInfo
    let wars: [FWWar]
    let allFactions: [FactionInfo]
    let databaseManager: DatabaseManager
    let systemNeighbours: SystemNeighbours
    @StateObject private var viewModel: FactionWarDetailViewModel
    @State private var isSearchActive = false
    
    init(faction: FactionInfo, wars: [FWWar], allFactions: [FactionInfo], databaseManager: DatabaseManager, systemNeighbours: SystemNeighbours) {
        self.faction = faction
        self.wars = wars
        self.allFactions = allFactions
        self.databaseManager = databaseManager
        self.systemNeighbours = systemNeighbours
        _viewModel = StateObject(wrappedValue: FactionWarDetailViewModel(
            faction: faction,
            wars: wars,
            allFactions: allFactions,
            databaseManager: databaseManager,
            systemNeighbours: systemNeighbours
        ))
    }
    
    var body: some View {
        List {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
            } else if viewModel.preparedSystems.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 30))
                                .foregroundColor(.gray)
                            Text(NSLocalizedString("Orders_No_Data", comment: ""))
                                .foregroundColor(.gray)
                        }
                        .padding()
                        Spacer()
                    }
                }
            } else {
                Section {
                    if viewModel.filteredSystems.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 30))
                                    .foregroundColor(.gray)
                                Text(NSLocalizedString("Orders_No_Data", comment: ""))
                                    .foregroundColor(.gray)
                            }
                            .padding()
                            Spacer()
                        }
                    } else {
                        ForEach(viewModel.filteredSystems) { system in
                            FWSystemCell(system: system, allFactions: allFactions)
                        }
                    }
                } header: {
                    HStack {
                        Text(NSLocalizedString("Main_WarZone", comment: "Main_WarZone"))
                            .font(.headline)
                        Spacer()
                        Button(action: {
                            viewModel.cycleFilterType()
                        }) {
                            Text(viewModel.filterType.localizedString)
                                .font(.subheadline)
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(faction.name)
        .searchable(
            text: $viewModel.searchText,
            isPresented: $isSearchActive,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: NSLocalizedString("Main_Database_Search", comment: "")
        )
        .task {
            await viewModel.loadData()
        }
        .refreshable {
            await viewModel.loadData(forceRefresh: true)
        }
    }
}
