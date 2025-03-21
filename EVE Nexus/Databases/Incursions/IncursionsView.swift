//
//  IncursionsView.swift
//  EVE Panel
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
        let systemId: Int
        let systemName: String
        let security: Double
        let constellationId: Int
        let constellationName: String
        let regionId: Int
        let regionName: String
    }

    init(incursion: Incursion, faction: FactionInfo, location: LocationInfo) {
        id = incursion.constellationId
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
            Logger.debug("正在从 UserDefaults 读取键: \(key)")
            guard let data = storage.data(forKey: key),
                let cache = try? JSONDecoder().decode(CacheContainer.self, from: data),
                !cache.isExpired(validityDuration: validityDuration)
            else {
                return nil
            }
            return cache.value
        }
        set {
            guard let value = newValue else {
                Logger.debug("正在从 UserDefaults 删除键: \(key)")
                storage.removeObject(forKey: key)
                return
            }
            let cache = CacheContainer(value: value)
            if let data = try? JSONEncoder().encode(cache) {
                Logger.debug("正在写入 UserDefaults，键: \(key), 数据大小: \(data.count) bytes")
                storage.set(data, forKey: key)
            }
        }
    }

    private struct CacheContainer: Codable {
        let value: Value
        let timestamp: Date

        init(value: Value) {
            self.value = value
            timestamp = Date()
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
    @Published var isLoading = true
    @Published var errorMessage: String?

    let databaseManager: DatabaseManager
    private var loadingTask: Task<Void, Never>?
    private var lastFetchTime: Date?
    private let cacheTimeout: TimeInterval = 300  // 5分钟缓存

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    deinit {
        loadingTask?.cancel()
    }

    func fetchIncursionsData(forceRefresh: Bool = false) async {
        // 如果不是强制刷新，且缓存未过期，且已有数据，则直接返回
        if !forceRefresh,
            let lastFetch = lastFetchTime,
            Date().timeIntervalSince(lastFetch) < cacheTimeout,
            !preparedIncursions.isEmpty
        {
            Logger.debug("使用缓存的入侵数据，跳过加载")
            return
        }

        // 取消之前的加载任务
        loadingTask?.cancel()

        // 创建新的加载任务
        loadingTask = Task {
            isLoading = true
            errorMessage = nil

            do {
                Logger.info("开始获取入侵数据")
                let incursions = try await IncursionsAPI.shared.fetchIncursions(
                    forceRefresh: forceRefresh)

                if Task.isCancelled { return }

                await processIncursions(incursions)

                if Task.isCancelled { return }

                self.lastFetchTime = Date()
                self.isLoading = false

            } catch {
                Logger.error("获取入侵数据失败: \(error)")
                if !Task.isCancelled {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }

        // 等待任务完成
        await loadingTask?.value
    }

    private func processIncursions(_ incursions: [Incursion]) async {
        // 提取所有需要查询的星系ID
        let solarSystemIds = incursions.map { $0.stagingSolarSystemId }

        // 一次性获取所有星系信息
        let systemInfoMap = await getBatchSolarSystemInfo(
            solarSystemIds: solarSystemIds,
            databaseManager: databaseManager
        )

        var prepared: [PreparedIncursion] = []

        for incursion in incursions {
            // 获取派系信息
            guard let faction = await self.getFactionInfo(factionId: incursion.factionId) else {
                continue
            }

            // 获取星系信息
            guard let systemInfo = systemInfoMap[incursion.stagingSolarSystemId] else {
                continue
            }

            let locationInfo = PreparedIncursion.LocationInfo(
                systemId: systemInfo.systemId,
                systemName: systemInfo.systemName,
                security: systemInfo.security,
                constellationId: systemInfo.constellationId,
                constellationName: systemInfo.constellationName,
                regionId: systemInfo.regionId,
                regionName: systemInfo.regionName
            )

            let preparedIncursion = PreparedIncursion(
                incursion: incursion,
                faction: .init(iconName: faction.iconName, name: faction.name),
                location: locationInfo
            )

            prepared.append(preparedIncursion)
        }

        // 多重排序条件：
        // 1. 按影响力从大到小
        // 2. 同等影响力下，有boss的优先
        // 3. boss状态相同时，按星系名称字母顺序
        prepared.sort { a, b in
            if a.incursion.influence != b.incursion.influence {
                return a.incursion.influence > b.incursion.influence
            }
            if a.incursion.hasBoss != b.incursion.hasBoss {
                return a.incursion.hasBoss
            }
            return a.location.systemName < b.location.systemName
        }

        if !prepared.isEmpty {
            Logger.info("成功准备 \(prepared.count) 条数据")
            preparedIncursions = prepared
        } else {
            Logger.error("没有可显示的完整数据")
        }
    }

    private func getFactionInfo(factionId: Int) async -> (iconName: String, name: String)? {
        let iconName = factionId == 500_019 ? "corporations_44_128_2.png" : "corporations_default"

        let query = "SELECT name FROM factions WHERE id = ?"
        guard
            case let .success(rows) = databaseManager.executeQuery(query, parameters: [factionId]),
            let row = rows.first,
            let name = row["name"] as? String
        else {
            return nil
        }
        return (iconName, name)
    }
}

// MARK: - Views

struct IncursionCell: View {
    let incursion: PreparedIncursion
    let databaseManager: DatabaseManager

    var body: some View {
        NavigationLink(
            destination: InfestedSystemsView(
                databaseManager: databaseManager,
                systemIds: incursion.incursion.infestedSolarSystems
            )
        ) {
            HStack(spacing: 12) {
                IconManager.shared.loadImage(for: incursion.faction.iconName)
                    .resizable()
                    .frame(width: 52, height: 52)
                    .cornerRadius(6)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(incursion.faction.name)
                        Text("[\(String(format: "%.1f", incursion.incursion.influence * 100))%]")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                        if incursion.incursion.hasBoss {
                            IconManager.shared.loadImage(for: "items_4_64_7.png")
                                .resizable()
                                .frame(width: 18, height: 18)
                        }
                    }
                    .font(.headline)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(formatSystemSecurity(incursion.location.security))
                                .foregroundColor(getSecurityColor(incursion.location.security))
                                .font(.system(.subheadline, design: .monospaced))
                            Text(incursion.location.systemName)
                                .fontWeight(.bold)
                                .font(.subheadline)
                        }

                        Text(
                            "\(incursion.location.constellationName) / \(incursion.location.regionName)"
                        )
                        .foregroundColor(.secondary)
                        .font(.caption)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
}

struct IncursionsView: View {
    @StateObject private var viewModel: IncursionsViewModel

    init(databaseManager: DatabaseManager) {
        let vm = IncursionsViewModel(databaseManager: databaseManager)
        _viewModel = StateObject(wrappedValue: vm)

        // 在初始化时立即开始加载数据
        Task {
            await vm.fetchIncursionsData()
        }
    }

    var body: some View {
        List {
            Section {
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if viewModel.preparedIncursions.isEmpty {
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
                    ForEach(viewModel.preparedIncursions) { incursion in
                        IncursionCell(
                            incursion: incursion, databaseManager: viewModel.databaseManager
                        )
                    }
                }
            } footer: {
                if !viewModel.preparedIncursions.isEmpty {
                    Text(
                        "\(viewModel.preparedIncursions.count) \(NSLocalizedString("Main_Setting_Static_Resource_Incursions_num", comment: ""))"
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await viewModel.fetchIncursionsData(forceRefresh: true)
        }
        .navigationTitle(NSLocalizedString("Main_Incursions", comment: ""))
    }
}
