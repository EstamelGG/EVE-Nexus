import SwiftUI

// MARK: - Models
struct SovereigntyCampaign: Codable {
    let attackersScore: Double
    let campaignId: Int
    let constellationId: Int
    let defenderId: Int
    let defenderScore: Double
    let eventType: String
    let solarSystemId: Int
    let startTime: String
    let structureId: Int64
    
    enum CodingKeys: String, CodingKey {
        case attackersScore = "attackers_score"
        case campaignId = "campaign_id"
        case constellationId = "constellation_id"
        case defenderId = "defender_id"
        case defenderScore = "defender_score"
        case eventType = "event_type"
        case solarSystemId = "solar_system_id"
        case startTime = "start_time"
        case structureId = "structure_id"
    }
}

struct PreparedSovereignty: Identifiable {
    let id: Int
    let campaign: SovereigntyCampaign
    let location: LocationInfo
    
    struct LocationInfo: Codable {
        let systemName: String
        let security: Double
        let constellationName: String
        let regionName: String
        let regionId: Int
    }
}

// MARK: - ViewModel
@MainActor
final class SovereigntyViewModel: ObservableObject {
    @Published private(set) var preparedCampaigns: [PreparedSovereignty] = []
    @Published var isLoading = false
    @Published var isRefreshing = false
    
    let databaseManager: DatabaseManager
    
    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
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
            let urlString = "https://esi.evetech.net/latest/sovereignty/campaigns/?datasource=tranquility"
            guard let url = URL(string: urlString) else {
                Logger.error("无效的URL")
                return
            }
            
            let data = try await NetworkManager.shared.fetchData(from: url)
            let campaigns = try JSONDecoder().decode([SovereigntyCampaign].self, from: data)
            await processCampaigns(campaigns)
        } catch {
            Logger.error("ViewModel: 获取主权争夺数据失败: \(error)")
        }
    }
    
    private func processCampaigns(_ campaigns: [SovereigntyCampaign]) async {
        let prepared = await withTaskGroup(of: PreparedSovereignty?.self) { group in
            for campaign in campaigns {
                group.addTask {
                    guard let location = await self.getLocationInfo(solarSystemId: campaign.solarSystemId) else {
                        return nil
                    }
                    
                    return PreparedSovereignty(
                        id: campaign.campaignId,
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
        } else {
            Logger.error("ViewModel: 没有可显示的完整数据")
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
    
    func getEventTypeText(_ type: String) -> String {
        switch type {
        case "tcu_defense": return "TCU"
        case "ihub_defense": return "IHub"
        case "station_defense": return "Station"
        case "station_freeport": return "Freeport"
        default: return type
        }
    }
}

// MARK: - Views
struct SovereigntyCell: View {
    let sovereignty: PreparedSovereignty
    
    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: "https://images.evetech.net/alliances/\(sovereignty.campaign.defenderId)/logo?size=64")) { image in
                image
                    .resizable()
                    .frame(width: 48, height: 48)
                    .cornerRadius(6)
            } placeholder: {
                ProgressView()
                    .frame(width: 48, height: 48)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(sovereignty.campaign.eventType)
                    Text("[\(String(format: "%.1f", sovereignty.campaign.attackersScore * 100))%]")
                        .foregroundColor(.secondary)
                }
                .font(.headline)
                
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
                        ForEach(groupedCampaigns[regionName] ?? []) { campaign in
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
        .overlay {
            if viewModel.isRefreshing {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: 60)
                    .background(Color(.systemBackground).opacity(0.8))
            }
        }
        .task {
            if viewModel.preparedCampaigns.isEmpty {
                await viewModel.fetchSovereignty()
            }
        }
        .navigationTitle(NSLocalizedString("Main_Sovereignty", comment: ""))
    }
} 