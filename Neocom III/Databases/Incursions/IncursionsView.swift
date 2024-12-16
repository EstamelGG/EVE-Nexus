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
        let query = "SELECT iconName, name FROM factions WHERE id = ?"
        if case .success(let rows) = databaseManager.executeQuery(query, parameters: [factionId]),
           let row = rows.first,
           let iconName = row["iconName"] as? String,
           let name = row["name"] as? String {
            return (iconName, name)
        }
        return nil
    }
    
    func getSystemInfo(solarSystemId: Int) -> (systemName: String, security: String, constellationName: String, regionName: String)? {
        // 从 universe 表获取所有需要的 ID 和安全等级
        let universeQuery = """
            SELECT region_id, constellation_id, solarsystem_id, system_security
            FROM universe
            WHERE solarsystem_id = ?
        """
        
        guard case .success(let universeRows) = databaseManager.executeQuery(universeQuery, parameters: [solarSystemId]),
              let universeRow = universeRows.first,
              let regionId = universeRow["region_id"] as? Int,
              let constellationId = universeRow["constellation_id"] as? Int,
              let security = universeRow["system_security"] as? String else {
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
        
        return (systemName, security, constellationName, regionName)
    }
}

struct IncursionCell: View {
    let incursion: Incursion
    let viewModel: IncursionsViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 第一行
            HStack(spacing: 12) {
                // 势力图标
                if let factionInfo = viewModel.getFactionInfo(factionId: incursion.factionId) {
                    IconManager.shared.loadImage(for: factionInfo.iconName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    // 势力名称和Boss图标
                    HStack {
                        if let factionInfo = viewModel.getFactionInfo(factionId: incursion.factionId) {
                            Text(factionInfo.name)
                                .font(.headline)
                        }
                        if incursion.hasBoss {
                            IconManager.shared.loadImage(for: "items_4_64_7.png")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                        }
                    }
                    
                    // 状态和位置信息
                    if let systemInfo = viewModel.getSystemInfo(solarSystemId: incursion.stagingSolarSystemId) {
                        Text("\(incursion.state.capitalized) - \(systemInfo.security) \(systemInfo.systemName) - \(systemInfo.constellationName) (\(systemInfo.regionName))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // 第二行 - 进度条
            ProgressView(value: incursion.influence)
                .tint(.red)
                .overlay(
                    Text("\(Int(incursion.influence * 100))%")
                        .font(.caption)
                        .foregroundColor(.white)
                )
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
    }
}

struct IncursionsView: View {
    @StateObject private var viewModel: IncursionsViewModel
    
    init(databaseManager: DatabaseManager) {
        _viewModel = StateObject(wrappedValue: IncursionsViewModel(databaseManager: databaseManager))
    }
    
    var body: some View {
        List {
            ForEach(viewModel.incursions, id: \.constellationId) { incursion in
                IncursionCell(incursion: incursion, viewModel: viewModel)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .task {
            await viewModel.fetchIncursions()
        }
        .refreshable {
            await viewModel.fetchIncursions()
        }
        .navigationTitle("入侵")
    }
}

#Preview {
    IncursionsView(databaseManager: DatabaseManager())
}

