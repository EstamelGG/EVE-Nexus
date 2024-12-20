import SwiftUI

// MARK: - ViewModel
@MainActor
final class SovereigntyViewModel: ObservableObject {
    @Published private(set) var preparedCampaigns: [PreparedSovereignty] = []
    @Published var isLoading = false
    @Published var isRefreshing = false
    private var loadingTasks: [Int: Task<Void, Never>] = [:]
    
    let databaseManager: DatabaseManager
    
    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }
    
    deinit {
        loadingTasks.values.forEach { $0.cancel() }
    }
    
    func fetchSovereignty(forceRefresh: Bool = false, silent: Bool = false) async {
        if !silent {
            if preparedCampaigns.isEmpty {
                isLoading = true
            } else {
                isRefreshing = true
            }
        }
        
        defer {
            if !silent {
                isLoading = false
                isRefreshing = false
            }
        }
        
        Logger.info("ViewModel: 开始获取主权争夺数据")
        do {
            let campaigns = try await NetworkManager.shared.fetchSovereigntyCampaigns(forceRefresh: forceRefresh)
            await processCampaigns(campaigns)
        } catch {
            Logger.error("ViewModel: 获取主权争夺数据失败: \(error)")
        }
    }
    
    private func processCampaigns(_ campaigns: [SovereigntyCampaign]) async {
        // 取消所有现有的加载任务
        loadingTasks.values.forEach { $0.cancel() }
        loadingTasks.removeAll()
        
        let prepared = await withTaskGroup(of: PreparedSovereignty?.self) { group in
            for campaign in campaigns {
                group.addTask {
                    guard let location = await self.getLocationInfo(solarSystemId: campaign.solarSystemId) else {
                        return nil
                    }
                    
                    return PreparedSovereignty(
                        campaign: campaign,
                        location: location
                    )
                }
            }
            
            var result: [PreparedSovereignty] = []
            for await prepared in group {
                if let prepared = prepared {
                    result.append(prepared)
                }
            }
            
            // 按星域名称排序
            result.sort { $0.location.regionName < $1.location.regionName }
            return result
        }
        
        if !prepared.isEmpty {
            Logger.info("ViewModel: 成功准备 \(prepared.count) 条数据")
            preparedCampaigns = prepared
            // 加载所有联盟图标
            loadAllIcons()
        } else {
            Logger.error("ViewModel: 没有可显示的完整数据")
        }
    }
    
    private func loadAllIcons() {
        // 按联盟ID分组
        let allianceGroups = Dictionary(grouping: preparedCampaigns) { $0.campaign.defenderId }
        
        // 加载联盟图标
        for (allianceId, campaigns) in allianceGroups {
            let task = Task {
                if campaigns.first != nil {
                    do {
                        Logger.debug("开始加载联盟图标: \(allianceId)，影响 \(campaigns.count) 个战役")
                        let uiImage = try await NetworkManager.shared.fetchAllianceLogo(allianceID:allianceId)
                        if !Task.isCancelled {
                            let icon = Image(uiImage: uiImage)
                            // 更新所有使用这个联盟图标的战役
                            for campaign in campaigns {
                                campaign.icon = icon
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
                    // 更新所有相关战役的加载状态
                    for campaign in campaigns {
                        campaign.isLoadingIcon = false
                    }
                }
            }
            loadingTasks[allianceId] = task
            // 设置所有相关战役的加载状态
            for campaign in campaigns {
                campaign.isLoadingIcon = true
            }
        }
    }
    
    func getLocationInfo(solarSystemId: Int) async -> PreparedSovereignty.LocationInfo? {
        let universeQuery = """
            SELECT u.region_id, u.constellation_id, u.system_security,
                   s.solarSystemName, c.constellationName, r.regionName
            FROM universe u
            JOIN solarsystems s ON s.solarSystemID = u.solarsystem_id
            JOIN constellations c ON c.constellationID = u.constellation_id
            JOIN regions r ON r.regionID = u.region_id
            WHERE u.solarsystem_id = ?
        """
        
        guard case .success(let rows) = databaseManager.executeQuery(universeQuery, parameters: [solarSystemId]),
              let row = rows.first,
              let security = row["system_security"] as? Double,
              let systemName = row["solarSystemName"] as? String,
              let constellationName = row["constellationName"] as? String,
              let regionName = row["regionName"] as? String,
              let regionId = row["region_id"] as? Int else {
            return nil
        }
        
        return PreparedSovereignty.LocationInfo(
            systemName: systemName,
            security: security,
            constellationName: constellationName,
            regionName: regionName,
            regionId: regionId
        )
    }
} 

// MARK: - Views
struct SovereigntyCell: View {
    @ObservedObject var sovereignty: PreparedSovereignty
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .center) {
                // 背景圆环
                Circle()
                    .stroke(Color.cyan.opacity(0.3), lineWidth: 4)
                    .frame(width: 56, height: 56)
                
                // 进度圆环
                Circle()
                    .trim(from: 0, to: sovereignty.campaign.attackersScore)
                    .stroke(Color.red, lineWidth: 4)
                    .frame(width: 56, height: 56)
                    .rotationEffect(.degrees(-90))
                
                // 联盟图标
                if sovereignty.isLoadingIcon {
                    ProgressView()
                        .frame(width: 48, height: 48)
                } else if let icon = sovereignty.icon {
                    icon
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                }
            }
            .frame(width: 56, height: 56)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(getEventTypeText(sovereignty.campaign.eventType))
                    Text("[\(String(format: "%.1f", sovereignty.campaign.attackersScore * 100))%]")
                        .foregroundColor(.secondary)
                    Text("[\(sovereignty.remainingTimeText)]")
                        .foregroundColor(.secondary)
                }
                .font(.headline)
                .lineLimit(1)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(formatSecurity(sovereignty.location.security))
                            .foregroundColor(getSecurityColor(sovereignty.location.security))
                        Text(sovereignty.location.systemName)
                            .fontWeight(.bold)
                    }
                    
                    Text("\(sovereignty.location.constellationName) / \(sovereignty.location.regionName)")
                        .foregroundColor(.secondary)
                }
                .font(.subheadline)
            }
        }
        .padding(.vertical, 8)
    }
    
    private func getEventTypeText(_ type: String) -> String {
        switch type {
        case "tcu_defense": return "TCU"
        case "ihub_defense": return "IHub"
        case "station_defense": return "Station"
        case "station_freeport": return "Freeport"
        default: return type
        }
    }
}

struct SovereigntyView: View {
    @StateObject private var viewModel: SovereigntyViewModel
    
    init(databaseManager: DatabaseManager) {
        _viewModel = StateObject(wrappedValue: SovereigntyViewModel(databaseManager: databaseManager))
    }
    
    var body: some View {
        let groupedCampaigns = Dictionary(grouping: viewModel.preparedCampaigns) { $0.location.regionName }
        
        List {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if viewModel.preparedCampaigns.isEmpty {
                Text("Can not get sovereignty data")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(Array(groupedCampaigns.keys.sorted()), id: \.self) { regionName in
                    Section(header: Text(regionName)
                        .fontWeight(.bold)
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                        .textCase(.none)
                    ) {
                        ForEach(groupedCampaigns[regionName]?.sorted(by: { $0.location.systemName < $1.location.systemName }) ?? []) { campaign in
                            SovereigntyCell(sovereignty: campaign)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await viewModel.fetchSovereignty(forceRefresh: true)
        }
        .task {
            if viewModel.preparedCampaigns.isEmpty {
                await viewModel.fetchSovereignty()
            }
        }
        .navigationTitle(NSLocalizedString("Main_Sovereignty", comment: ""))
    }
} 
