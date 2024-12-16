//
//  IncursionsView.swift
//  Neocom III
//
//  Created by GG Estamel on 2024/12/16.
//

import SwiftUI

// 视图模型
class IncursionsViewModel: ObservableObject {
    @Published var incursions: [Incursion] = []
    let databaseManager: DatabaseManager
    
    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }
    
    func fetchIncursions() async {
        do {
            let decodedIncursions = try await NetworkManager.shared.fetchIncursions()
            await MainActor.run {
                self.incursions = decodedIncursions
            }
        } catch {
            Logger.error("Error fetching incursions: \(error)")
        }
    }
    
    func getFactionInfo(factionId: Int) -> (iconName: String, name: String)? {
        // 根据 faction_id 确定图标
        let iconName = factionId == 500019 ? "corporations_44_128_2.png" : "items_7_64_4.png"
        
        // 获取势力名称
        let query = "SELECT name FROM factions WHERE id = ?"
        if case .success(let rows) = databaseManager.executeQuery(query, parameters: [factionId]),
           let row = rows.first,
           let name = row["name"] as? String {
            return (iconName, name)
        }
        return nil
    }
    
    func getLocationInfo(solarSystemId: Int) -> (systemName: String, constellationName: String, regionName: String)? {
        // 从 universe 表获取 region_id 和 constellation_id
        let universeQuery = """
            SELECT region_id, constellation_id
            FROM universe
            WHERE solarsystem_id = ?
        """
        
        guard case .success(let universeRows) = databaseManager.executeQuery(universeQuery, parameters: [solarSystemId]),
              let universeRow = universeRows.first,
              let regionId = universeRow["region_id"] as? Int,
              let constellationId = universeRow["constellation_id"] as? Int else {
            return nil
        }
        
        // 获取星系名称
        let systemQuery = "SELECT solarSystemName FROM solarsystems WHERE solarSystemID = ?"
        guard case .success(let systemRows) = databaseManager.executeQuery(systemQuery, parameters: [solarSystemId]),
              let systemRow = systemRows.first,
              let systemName = systemRow["solarSystemName"] as? String else {
            return nil
        }
        
        // 获取星座名称
        let constellationQuery = "SELECT constellationName FROM constellations WHERE constellationID = ?"
        guard case .success(let constellationRows) = databaseManager.executeQuery(constellationQuery, parameters: [constellationId]),
              let constellationRow = constellationRows.first,
              let constellationName = constellationRow["constellationName"] as? String else {
            return nil
        }
        
        // 获取星域名称
        let regionQuery = "SELECT regionName FROM regions WHERE regionID = ?"
        guard case .success(let regionRows) = databaseManager.executeQuery(regionQuery, parameters: [regionId]),
              let regionRow = regionRows.first,
              let regionName = regionRow["regionName"] as? String else {
            return nil
        }
        
        return (systemName, constellationName, regionName)
    }
}

struct IncursionCell: View {
    let incursion: Incursion
    let viewModel: IncursionsViewModel
    
    var body: some View {
        HStack(spacing: 12) {
            // 势力图标
            if let factionInfo = viewModel.getFactionInfo(factionId: incursion.factionId) {
                IconManager.shared.loadImage(for: factionInfo.iconName)
                    .resizable()
                    .frame(width: 48, height: 48)
                    .cornerRadius(6)
                
                VStack(alignment: .leading, spacing: 4) {
                    // 势力名称
                    Text(factionInfo.name)
                        .font(.headline)
                    
                    // 位置信息
                    if let locationInfo = viewModel.getLocationInfo(solarSystemId: incursion.stagingSolarSystemId) {
                        Text("\(locationInfo.systemName) / \(locationInfo.constellationName) / \(locationInfo.regionName)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
}

struct IncursionsView: View {
    @StateObject private var viewModel: IncursionsViewModel
    
    init(databaseManager: DatabaseManager) {
        _viewModel = StateObject(wrappedValue: IncursionsViewModel(databaseManager: databaseManager))
    }
    
    var body: some View {
        List {
            Section(header: Text("")) {
                ForEach(viewModel.incursions, id: \.constellationId) { incursion in
                    IncursionCell(incursion: incursion, viewModel: viewModel)
                }
            }
        }
        .listStyle(.insetGrouped)
        .task {
            await viewModel.fetchIncursions()
        }
        .refreshable {
            await viewModel.fetchIncursions()
        }
        .navigationTitle(NSLocalizedString("Main_Incursions", comment: ""))
    }
}

#Preview {
    IncursionsView(databaseManager: DatabaseManager())
}

