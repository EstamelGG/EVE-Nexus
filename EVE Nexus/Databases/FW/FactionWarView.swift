import Foundation
import SwiftUI

// MARK: - 数据模型

struct FactionInfo: Identifiable {
    let id: Int
    let name: String
    let iconName: String
}

// MARK: - ViewModel

@MainActor
final class FactionWarViewModel: ObservableObject {
    @Published private(set) var systems: [FWSystem] = []
    @Published private(set) var wars: [FWWar] = []
    @Published private(set) var factions: [FactionInfo] = []
    @Published private(set) var systemNeighbours: SystemNeighbours = [:]
    @Published private(set) var insurgencyCampaigns: [InsurgencyCampaign] = []
    @Published var isLoading = true
    @Published var errorMessage: String?
    
    // 添加计算属性获取海盗势力列表
    var pirateFactions: [FactionInfo] {
        let pirateIds = Set(insurgencyCampaigns.map { $0.pirateFaction.id })
        
        // 查询海盗势力信息
        let placeholders = String(repeating: "?,", count: pirateIds.count).dropLast()
        let query = "SELECT id, name, iconName FROM factions WHERE id IN (\(placeholders))"
        
        let result = databaseManager.executeQuery(query, parameters: Array(pirateIds))
        
        switch result {
        case let .success(rows):
            return rows.compactMap { row in
                guard let id = row["id"] as? Int,
                      let name = row["name"] as? String,
                      let iconName = row["iconName"] as? String else {
                    Logger.error("数据转换失败: \(row)")
                    return nil
                }
                return FactionInfo(id: id, name: name, iconName: iconName)
            }.sorted { $0.id < $1.id }
            
        case let .error(error):
            Logger.error("查询海盗势力信息失败: \(error)")
            return []
        }
    }
    
    private let databaseManager: DatabaseManager
    private var loadingTask: Task<Void, Never>?
    private var lastFetchTime: Date?
    private let cacheTimeout: TimeInterval = 300  // 5分钟缓存
    
    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }
    
    deinit {
        loadingTask?.cancel()
    }
    
    func loadData(forceRefresh: Bool = false) async {
        // 如果不是强制刷新，且缓存未过期，且已有数据，则直接返回
        if !forceRefresh,
           let lastFetch = lastFetchTime,
           Date().timeIntervalSince(lastFetch) < cacheTimeout,
           !factions.isEmpty {
            Logger.debug("使用缓存的FW数据，跳过加载")
            return
        }
        
        // 取消之前的加载任务
        loadingTask?.cancel()
        
        // 创建新的加载任务
        loadingTask = Task {
            isLoading = true
            errorMessage = nil
            
            do {
                Logger.info("开始获取FW数据")
                async let fwDataTask = FWAPI.shared.fetchFWData(forceRefresh: forceRefresh)
                async let insurgencyTask = FWAPI.shared.fetchInsurgencyData(forceRefresh: forceRefresh)
                
                let (systems, wars) = try await fwDataTask
                
                // 单独处理叛乱数据，即使失败也不影响其他功能
                do {
                    let insurgencyCampaigns = try await insurgencyTask
                    if !Task.isCancelled {
                        self.insurgencyCampaigns = insurgencyCampaigns
                    }
                } catch {
                    Logger.error("加载叛乱数据失败: \(error)")
                    // 清空叛乱数据
                    self.insurgencyCampaigns = []
                }
                
                if Task.isCancelled { return }
                
                self.systems = systems
                self.wars = wars
                
                // 获取邻居星系数据
                self.systemNeighbours = await FWAPI.shared.getSystemNeighbours()
                
                // 计算所有星系状态
                await FWSystemStateManager.shared.calculateSystemStates(
                    systems: systems,
                    wars: wars,
                    systemNeighbours: systemNeighbours,
                    databaseManager: databaseManager,
                    forceRefresh: forceRefresh
                )
                
                // 从星系数据中获取所有不重复的势力ID
                let factionIds = Set(systems.flatMap { [$0.occupier_faction_id, $0.owner_faction_id] }).sorted()
                
                // 查询势力信息
                let placeholders = String(repeating: "?,", count: factionIds.count).dropLast()
                let query = "SELECT id, name, iconName FROM factions WHERE id IN (\(placeholders))"
                
                let result = databaseManager.executeQuery(query, parameters: factionIds)
                
                if Task.isCancelled { return }
                
                switch result {
                case let .success(rows):
                    self.factions = rows.compactMap { row in
                        guard let id = row["id"] as? Int,
                              let name = row["name"] as? String,
                              let iconName = row["iconName"] as? String else {
                            Logger.error("数据转换失败: \(row)")
                            return nil
                        }
                        return FactionInfo(id: id, name: name, iconName: iconName)
                    }.sorted { $0.id < $1.id }
                    
                case let .error(error):
                    Logger.error("查询势力信息失败: \(error)")
                    if !Task.isCancelled {
                        self.errorMessage = error
                    }
                }
                
                if !Task.isCancelled {
                    self.lastFetchTime = Date()
                    self.isLoading = false
                }
                
            } catch {
                Logger.error("加载FW数据失败: \(error)")
                if !Task.isCancelled {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
        
        // 等待任务完成
        await loadingTask?.value
    }
}

// MARK: - View

struct FactionWarView: View {
    @StateObject private var viewModel: FactionWarViewModel
    let databaseManager: DatabaseManager
    
    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
        let vm = FactionWarViewModel(databaseManager: databaseManager)
        _viewModel = StateObject(wrappedValue: vm)
        
        // 在初始化时立即开始加载数据
        Task {
            await vm.loadData()
        }
    }
    
    var body: some View {
        List {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
            } else if viewModel.factions.isEmpty {
                Text(NSLocalizedString("Misc_No_Data", comment: ""))
                    .foregroundColor(.gray)
            } else {
                // 前线势力部分
                Section {
                    ForEach(viewModel.factions) { faction in
                        NavigationLink {
                            FactionWarDetailView(
                                faction: faction,
                                wars: viewModel.wars,
                                allFactions: viewModel.factions,
                                databaseManager: databaseManager,
                                systemNeighbours: viewModel.systemNeighbours
                            )
                        } label: {
                            HStack {
                                IconManager.shared.loadImage(for: faction.iconName)
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(4)
                                Text(faction.name)
                                    .font(.body)
                            }
                        }
                    }
                } header: {
                    Text(NSLocalizedString("Main_Faction_War", comment: ""))
                        .font(.headline)
                }
                
                // 海盗势力部分
                Section {
                    if viewModel.pirateFactions.isEmpty {
                        Text(NSLocalizedString("Misc_No_Insurgency", comment: ""))
                            .foregroundColor(.gray)
                    } else {
                        ForEach(viewModel.pirateFactions) { faction in
                            NavigationLink {
                                InsurgencyView(
                                    campaigns: viewModel.insurgencyCampaigns.filter { $0.pirateFaction.id == faction.id },
                                    databaseManager: databaseManager,
                                    factionName: faction.name
                                )
                            } label: {
                                HStack {
                                    IconManager.shared.loadImage(for: faction.iconName)
                                        .resizable()
                                        .frame(width: 32, height: 32)
                                        .cornerRadius(4)
                                    Text(faction.name)
                                        .font(.body)
                                    Spacer()
                                }
                            }
                        }
                    }
                } header: {
                    Text(NSLocalizedString("Main_Section_Insurgency", comment: ""))
                        .font(.headline)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("Main_frontline", comment: ""))
        .refreshable {
            await viewModel.loadData(forceRefresh: true)
        }
    }
}
