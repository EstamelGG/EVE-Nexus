//
//  IncursionsView.swift
//  EVE Nexus
//
//  Created by GG Estamel on 2024/12/16.
//

import SwiftUI

// MARK: - Models
struct PreparedIncursion: Identifiable, Codable {
    let id: Int
    let incursion: Incursion
    let faction: FactionInfo
    let location: LocationInfo
    
    struct FactionInfo: Codable {
        let iconName: String
        let name: String
    }
    
    struct LocationInfo: Codable {
        let systemName: String
        let security: Double
        let constellationName: String
        let regionName: String
    }
    
    init(incursion: Incursion, faction: FactionInfo, location: LocationInfo) {
        self.id = incursion.constellationId
        self.incursion = incursion
        self.faction = faction
        self.location = location
    }
}

// MARK: - Cache
@propertyWrapper
struct Cache<Value: Codable> {
    private let key: String
    private let validityDuration: TimeInterval
    private let storage: UserDefaults
    
    init(key: String, validityDuration: TimeInterval, storage: UserDefaults = .standard) {
        self.key = key
        self.validityDuration = validityDuration
        self.storage = storage
    }
    
    var wrappedValue: Value? {
        get {
            guard let data = storage.data(forKey: key),
                  let cache = try? JSONDecoder().decode(CacheContainer.self, from: data),
                  !cache.isExpired(validityDuration: validityDuration) else {
                return nil
            }
            return cache.value
        }
        set {
            guard let value = newValue else {
                storage.removeObject(forKey: key)
                return
            }
            let cache = CacheContainer(value: value)
            if let data = try? JSONEncoder().encode(cache) {
                storage.set(data, forKey: key)
            }
        }
    }
    
    private struct CacheContainer: Codable {
        let value: Value
        let timestamp: Date
        
        init(value: Value) {
            self.value = value
            self.timestamp = Date()
        }
        
        func isExpired(validityDuration: TimeInterval) -> Bool {
            Date().timeIntervalSince(timestamp) >= validityDuration
        }
    }
}

// MARK: - ViewModel
@MainActor
final class IncursionsViewModel: ObservableObject {
    @Published private(set) var preparedIncursions: [PreparedIncursion] = []
    @Published var incursion_isLoading = false
    @Published var incursion_isRefreshing = false
    
    let databaseManager: DatabaseManager
    
    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }
    
    func fetchIncursions(forceRefresh: Bool = false, silent: Bool = false) async {
        if !silent {
            if preparedIncursions.isEmpty {
                incursion_isLoading = true
            } else {
                incursion_isRefreshing = true
            }
        }
        
        defer {
            if !silent {
                incursion_isLoading = false
                incursion_isRefreshing = false
            }
        }
        
        Logger.info("ViewModel: 开始获取入侵数据")
        do {
            let incursions = try await StaticResourceManager.shared.fetchIncursionsData(forceRefresh: forceRefresh)
            await processIncursions(incursions)
        } catch {
            Logger.error("ViewModel: 获取入侵数据失败: \(error)")
        }
    }
    
    private func processIncursions(_ incursions: [Incursion]) async {
        let prepared = await withTaskGroup(of: PreparedIncursion?.self) { group in
            for incursion in incursions {
                group.addTask {
                    guard let faction = await self.getFactionInfo(factionId: incursion.factionId),
                          let location = await self.getLocationInfo(solarSystemId: incursion.stagingSolarSystemId) else {
                        return nil
                    }
                    
                    return PreparedIncursion(
                        incursion: incursion,
                        faction: .init(iconName: faction.iconName, name: faction.name),
                        location: .init(
                            systemName: location.systemName,
                            security: location.security,
                            constellationName: location.constellationName,
                            regionName: location.regionName
                        )
                    )
                }
            }
            
            var result: [PreparedIncursion] = []
            for await prepared in group {
                if let prepared = prepared {
                    result.append(prepared)
                }
            }
            
            // 按影响力从大到小排序
            result.sort { $0.incursion.influence > $1.incursion.influence }
            return result
        }
        
        if !prepared.isEmpty {
            Logger.info("ViewModel: 成功准备 \(prepared.count) 条数据")
            preparedIncursions = prepared
        } else {
            Logger.error("ViewModel: 没有可显示的完整数据")
        }
    }
    
    func getFactionInfo(factionId: Int) async -> (iconName: String, name: String)? {
        let iconName = factionId == 500019 ? "corporations_44_128_2.png" : "items_7_64_4.png"
        
        let query = "SELECT name FROM factions WHERE id = ?"
        guard case .success(let rows) = databaseManager.executeQuery(query, parameters: [factionId]),
              let row = rows.first,
              let name = row["name"] as? String else {
            return nil
        }
        return (iconName, name)
    }
    
    func getLocationInfo(solarSystemId: Int) async -> (systemName: String, security: Double, constellationName: String, regionName: String)? {
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
              let regionName = row["regionName"] as? String else {
            return nil
        }
        
        return (systemName, security, constellationName, regionName)
    }
}

// MARK: - Views
struct IncursionCell: View {
    let incursion: PreparedIncursion
    let databaseManager: DatabaseManager
    
    var body: some View {
        NavigationLink(destination: InfestedSystemsView(databaseManager: databaseManager, systemIds: incursion.incursion.infestedSolarSystems)) {
            HStack(spacing: 12) {
                IconManager.shared.loadImage(for: incursion.faction.iconName)
                    .resizable()
                    .frame(width: 48, height: 48)
                    .cornerRadius(6)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(incursion.faction.name)
                        Text("[\(String(format: "%.1f", incursion.incursion.influence * 100))%]")
                            .foregroundColor(.secondary)
                        if incursion.incursion.hasBoss {
                            IconManager.shared.loadImage(for: "items_4_64_7.png")
                                .resizable()
                                .frame(width: 18, height: 18)
                        }
                    }
                    .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(formatSecurity(incursion.location.security))
                                .foregroundColor(getSecurityColor(incursion.location.security))
                            Text(incursion.location.systemName)
                                .fontWeight(.bold)
                        }
                        
                        Text("\(incursion.location.constellationName) / \(incursion.location.regionName)")
                            .foregroundColor(.secondary)
                    }
                    .font(.subheadline)
                }
            }
            .padding(.vertical, 8)
        }
    }
}

struct IncursionsView: View {
    @StateObject private var viewModel: IncursionsViewModel
    
    init(databaseManager: DatabaseManager) {
        _viewModel = StateObject(wrappedValue: IncursionsViewModel(databaseManager: databaseManager))
    }
    
    var body: some View {
        List {
            Section {
                if viewModel.incursion_isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if viewModel.preparedIncursions.isEmpty {
                    Text("Can not get incursions data")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(viewModel.preparedIncursions) { incursion in
                        IncursionCell(incursion: incursion, databaseManager: viewModel.databaseManager)
                    }
                }
            } footer: {
                if !viewModel.preparedIncursions.isEmpty {
                    Text("\(viewModel.preparedIncursions.count) incursions found")
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await viewModel.fetchIncursions(forceRefresh: true)
        }
        .task {
            if viewModel.preparedIncursions.isEmpty {
                await viewModel.fetchIncursions()
            }
        }
        .navigationTitle(NSLocalizedString("Main_Incursions", comment: ""))
    }
}
