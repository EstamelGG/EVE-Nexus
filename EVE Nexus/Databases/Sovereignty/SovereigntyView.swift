import SwiftUI

// MARK: - ViewModel

@MainActor
final class SovereigntyViewModel: ObservableObject {
    @Published private(set) var preparedCampaigns: [PreparedSovereignty] = []
    @Published var isLoading = true
    @Published var errorMessage: String?

    private let databaseManager: DatabaseManager
    private var loadingTask: Task<Void, Never>?
    private var iconLoadingTasks: [Int: Task<Void, Never>] = [:]

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    deinit {
        loadingTask?.cancel()
        iconLoadingTasks.values.forEach { $0.cancel() }
    }

    func fetchSovereignty(forceRefresh: Bool = false) async {
        // 取消之前的加载任务
        loadingTask?.cancel()

        // 创建新的加载任务
        loadingTask = Task {
            isLoading = true
            errorMessage = nil

            do {
                Logger.info("开始获取主权争夺数据")
                let campaigns = try await SovereigntyCampaignsAPI.shared.fetchSovereigntyCampaigns(
                    forceRefresh: forceRefresh)

                if Task.isCancelled { return }

                await processCampaigns(campaigns)

                if Task.isCancelled { return }

                self.isLoading = false

            } catch {
                Logger.error("获取主权争夺数据失败: \(error)")
                if !Task.isCancelled {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }

        // 等待任务完成
        await loadingTask?.value
    }

    private func processCampaigns(_ campaigns: [SovereigntyCampaign]) async {
        // 取消所有现有的图标加载任务
        iconLoadingTasks.values.forEach { $0.cancel() }
        iconLoadingTasks.removeAll()

        let prepared = await withTaskGroup(of: PreparedSovereignty?.self) { group in
            for campaign in campaigns {
                group.addTask {
                    guard
                        let location = await self.getLocationInfo(
                            solarSystemId: campaign.solar_system_id)
                    else {
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
            Logger.info("成功准备 \(prepared.count) 条数据")
            preparedCampaigns = prepared
            // 加载所有联盟图标
            loadAllIcons()
        } else {
            Logger.error("没有可显示的完整数据")
        }
    }

    private func loadAllIcons() {
        // 按联盟ID分组
        let allianceGroups = Dictionary(grouping: preparedCampaigns) { $0.campaign.defender_id }

        // 加载联盟图标
        for (allianceId, campaigns) in allianceGroups {
            let task = Task {
                if campaigns.first != nil {
                    do {
                        Logger.debug("开始加载联盟图标: \(allianceId)，影响 \(campaigns.count) 个战役")
                        let uiImage = try await AllianceAPI.shared.fetchAllianceLogo(
                            allianceID: allianceId)

                        if Task.isCancelled { return }

                        let icon = Image(uiImage: uiImage)
                        // 更新所有使用这个联盟图标的战役
                        for campaign in campaigns {
                            campaign.icon = icon
                        }
                        Logger.debug("联盟图标加载成功: \(allianceId)")
                    } catch {
                        if (error as NSError).code == NSURLErrorCancelled {
                            Logger.debug("联盟图标加载已取消: \(allianceId)")
                        } else {
                            Logger.error("加载联盟图标失败: \(allianceId), error: \(error)")
                        }
                    }
                    // 更新所有相关战役的加载状态
                    if !Task.isCancelled {
                        for campaign in campaigns {
                            campaign.isLoadingIcon = false
                        }
                    }
                }
            }
            iconLoadingTasks[allianceId] = task
            // 设置所有相关战役的加载状态
            for campaign in campaigns {
                campaign.isLoadingIcon = true
            }
        }
    }

    func getLocationInfo(solarSystemId: Int) async -> PreparedSovereignty.LocationInfo? {
        if let info = await getSolarSystemInfo(
            solarSystemId: solarSystemId, databaseManager: databaseManager
        ) {
            return PreparedSovereignty.LocationInfo(
                systemName: info.systemName,
                security: info.security,
                constellationName: info.constellationName,
                regionName: info.regionName,
                regionId: info.regionId
            )
        }
        return nil
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
                    .trim(from: 0, to: CGFloat(sovereignty.campaign.attackers_score ?? 0))
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
                        .clipShape(Circle())
                }
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(getEventTypeText(sovereignty.campaign.event_type))
                    Text(
                        "[\(String(format: "%.1f", (sovereignty.campaign.attackers_score ?? 0) * 100))%]"
                    )
                    .foregroundColor(.secondary)
                    Text("[\(sovereignty.remainingTimeText)]")
                        .foregroundColor(.secondary)
                }
                .font(.headline)
                .lineLimit(1)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(formatSystemSecurity(sovereignty.location.security))
                            .foregroundColor(getSecurityColor(sovereignty.location.security))
                        Text(sovereignty.location.systemName)
                            .fontWeight(.bold)
                    }

                    Text(
                        "\(sovereignty.location.constellationName) / \(sovereignty.location.regionName)"
                    )
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
        _viewModel = StateObject(
            wrappedValue: SovereigntyViewModel(databaseManager: databaseManager))
    }

    var body: some View {
        let groupedCampaigns = Dictionary(grouping: viewModel.preparedCampaigns) {
            $0.location.regionName
        }

        List {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if viewModel.preparedCampaigns.isEmpty {
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
                ForEach(Array(groupedCampaigns.keys.sorted()), id: \.self) { regionName in
                    Section(
                        header: Text(regionName)
                            .fontWeight(.bold)
                            .font(.system(size: 18))
                            .foregroundColor(.primary)
                            .textCase(.none)
                    ) {
                        ForEach(
                            groupedCampaigns[regionName]?.sorted(by: {
                                $0.location.systemName < $1.location.systemName
                            }) ?? []
                        ) { campaign in
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
            await viewModel.fetchSovereignty()
        }
        .navigationTitle(NSLocalizedString("Main_Sovereignty", comment: ""))
    }
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
