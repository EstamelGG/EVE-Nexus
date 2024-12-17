//
//  IncursionsView.swift
//  EVE Nexus
//
//  Created by GG Estamel on 2024/12/16.
//

import SwiftUI

// 视图模型
class IncursionsViewModel: ObservableObject {
    @Published var incursions: [Incursion] = []
    @Published private(set) var preparedIncursions: [(incursion: Incursion, faction: (iconName: String, name: String), location: (systemName: String, security: Double, constellationName: String, regionName: String))] = []
    @Published var isLoading = false
    let databaseManager: DatabaseManager
    
    // 缓存管理器
    private static let cache: NSCache<NSString, CacheEntry> = {
        let cache = NSCache<NSString, CacheEntry>()
        cache.countLimit = 1 // 只缓存最新的一次数据
        return cache
    }()
    
    private let cacheKey = "incursions_cache" as NSString
    private let validityDuration: TimeInterval = 8 * 3600 // 8小时缓存有效期
    
    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
        loadFromCache()
    }
    
    private func loadFromCache() {
        guard let entry = Self.cache.object(forKey: cacheKey),
              !entry.isExpired(validityDuration: validityDuration) else {
            Logger.info("ViewModel: [缓存] 缓存不存在或已过期")
            return
        }
        
        self.preparedIncursions = entry.data
        Logger.info("ViewModel: [缓存] 成功加载 \(entry.data.count) 条入侵数据")
    }
    
    private func saveToCache(_ data: [(Incursion, (String, String), (String, Double, String, String))]) {
        let entry = CacheEntry(data: data)
        Self.cache.setObject(entry, forKey: cacheKey)
        Logger.info("ViewModel: [缓存] 成功保存 \(data.count) 条入侵数据")
    }
    
    @MainActor
    func fetchIncursions(forceRefresh: Bool = false) async {
        // 如果不是强制刷新，且有有效缓存，直接使用缓存
        if !forceRefresh,
           let entry = Self.cache.object(forKey: cacheKey),
           !entry.isExpired(validityDuration: validityDuration) {
            self.preparedIncursions = entry.data
            Logger.info("ViewModel: [缓存] 使用缓存中的 \(entry.data.count) 条入侵数据")
            return
        }
        
        // 否则从网络加载
        await fetchFromNetwork()
    }
    
    @MainActor
    private func fetchFromNetwork() async {
        isLoading = true
        preparedIncursions = []
        
        Logger.info("ViewModel: [网络] 开始获取入侵数据")
        do {
            let decodedIncursions = try await NetworkManager.shared.fetchIncursions()
            Logger.info("ViewModel: [网络] 获取到 \(decodedIncursions.count) 条入侵数据")
            
            var prepared: [(Incursion, (String, String), (String, Double, String, String))] = []
            for incursion in decodedIncursions {
                guard let factionInfo = getFactionInfo(factionId: incursion.factionId) else {
                    Logger.error("ViewModel: [网络] 无法获取势力信息: factionId = \(incursion.factionId)")
                    continue
                }
                
                guard let locationInfo = getLocationInfo(solarSystemId: incursion.stagingSolarSystemId) else {
                    Logger.error("ViewModel: [网络] 无法获取位置信息: solarSystemId = \(incursion.stagingSolarSystemId)")
                    continue
                }
                
                prepared.append((incursion, factionInfo, locationInfo))
            }
            
            if !prepared.isEmpty {
                Logger.info("ViewModel: [网络] 成功准备 \(prepared.count) 条数据")
                preparedIncursions = prepared
                saveToCache(prepared)
            } else {
                Logger.error("ViewModel: [网络] 没有可显示的完整数据")
            }
        } catch {
            Logger.error("ViewModel: [网络] 获取入侵数据失败: \(error)")
        }
        
        isLoading = false
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
    
    func getLocationInfo(solarSystemId: Int) -> (systemName: String, security: Double, constellationName: String, regionName: String)? {
        // 从 universe 表获取 region_id、constellation_id 和 security
        let universeQuery = """
            SELECT region_id, constellation_id, system_security
            FROM universe
            WHERE solarsystem_id = ?
        """
        
        guard case .success(let universeRows) = databaseManager.executeQuery(universeQuery, parameters: [solarSystemId]),
              let universeRow = universeRows.first,
              let regionId = universeRow["region_id"] as? Int,
              let constellationId = universeRow["constellation_id"] as? Int,
              let security = universeRow["system_security"] as? Double else {
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

// 缓存条目
final class CacheEntry {
    let data: [(incursion: Incursion, faction: (iconName: String, name: String), location: (systemName: String, security: Double, constellationName: String, regionName: String))]
    private let timestamp: Date
    
    init(data: [(Incursion, (String, String), (String, Double, String, String))]) {
        self.data = data
        self.timestamp = Date()
    }
    
    func isExpired(validityDuration: TimeInterval) -> Bool {
        Date().timeIntervalSince(timestamp) >= validityDuration
    }
}

struct IncursionCell: View {
    let incursion: Incursion
    let factionInfo: (iconName: String, name: String)
    let locationInfo: (systemName: String, security: Double, constellationName: String, regionName: String)
    let databaseManager: DatabaseManager
    
    var body: some View {
        NavigationLink(destination: InfestedSystemsView(databaseManager: databaseManager, systemIds: incursion.infestedSolarSystems)) {
            HStack(spacing: 12) {
                // 势力图标
                IconManager.shared.loadImage(for: factionInfo.iconName)
                    .resizable()
                    .frame(width: 48, height: 48)
                    .cornerRadius(6)
                
                VStack(alignment: .leading, spacing: 4) {
                    // 势力名称
                    HStack(spacing: 4) {
                        Text(factionInfo.name)
                        Text("[\(String(format: "%.1f", incursion.influence * 100))%]")
                            .foregroundColor(.secondary)
                        if incursion.hasBoss {
                            IconManager.shared.loadImage(for: "items_4_64_7.png")
                                .resizable()
                                .frame(width: 18, height: 18)
                        }
                    }
                    .font(.headline)
                    
                    // 位置信息
                    VStack(alignment: .leading, spacing: 2) {
                        // 安全等级和星系名
                        HStack(spacing: 4) {
                            Text(formatSecurity(locationInfo.security))
                                .foregroundColor(getSecurityColor(locationInfo.security))
                            Text(locationInfo.systemName)
                                .fontWeight(.bold)
                        }
                        
                        // 星座和星域
                        Text("\(locationInfo.constellationName) / \(locationInfo.regionName)")
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
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                } else if viewModel.preparedIncursions.isEmpty {
                    Text("Can not get incursions data")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(viewModel.preparedIncursions, id: \.incursion.constellationId) { prepared in
                        IncursionCell(
                            incursion: prepared.incursion,
                            factionInfo: prepared.faction,
                            locationInfo: prepared.location,
                            databaseManager: viewModel.databaseManager
                        )
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .task {
            // 页面加载时，优先使用缓存
            await viewModel.fetchIncursions()
        }
        .refreshable {
            // 下拉刷新时，强制从网络获取新数据
            await viewModel.fetchIncursions(forceRefresh: true)
        }
        .navigationTitle(NSLocalizedString("Main_Incursions", comment: ""))
    }
}
