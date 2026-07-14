import SwiftUI

/// 添加星系列表视图
struct SystemsListView: View {
    let title: String
    let systemIds: [Int]
    let selectedSystemId: Int?

    @State private var systems: [(id: Int, security: Double, regionId: Int)] = []
    @State private var isLoading = true
    @StateObject private var viewModel = PlanetarySearchResultViewModel()

    var body: some View {
        List {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Text(NSLocalizedString("Misc_Loading", comment: ""))
                        .foregroundColor(.gray)
                        .padding(.leading, 8)
                    Spacer()
                }
            } else {
                ForEach(systems, id: \.id) { system in
                    HStack(spacing: 8) {
                        // 主权图标区域
                        ZStack(alignment: .center) {
                            if viewModel.isLoadingIconForSystem(system.id) {
                                ProgressView()
                                    .frame(width: 32, height: 32)
                            } else if let icon = viewModel.getIconForSystem(system.id) {
                                icon
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(4)
                            } else {
                                Image("faction_default")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(4)
                            }
                        }

                        // 星系信息
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(formatSystemSecurity(system.security))
                                    .foregroundColor(getSecurityColor(system.security))
                                    .font(.system(.body, design: .monospaced))
                                    .padding(.trailing, 4)

                                Text(SDEMemoryStore.solarSystemName(for: system.id) ?? "System \(system.id)")
                                    .font(.headline)
                            }

                            // 第二行显示星域名和拥有者（如果有）
                            HStack(spacing: 4) {
                                Text(SDEMemoryStore.regionName(for: system.regionId) ?? "Region \(system.regionId)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                if let ownerName = viewModel.getOwnerNameForSystem(system.id) {
                                    Text("・")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Text(ownerName)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            }
        }
        .navigationTitle(title)
        .onAppear {
            loadSystems()
        }
    }

    private func loadSystems() {
        guard !systemIds.isEmpty else {
            isLoading = false
            return
        }

        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async {
            let query = """
                SELECT solarsystem_id, system_security, region_id
                FROM universe
                WHERE solarsystem_id IN (\(systemIds.map { String($0) }.joined(separator: ",")))
            """

            var loadedSystems: [(id: Int, security: Double, regionId: Int)] = []

            if case let .success(rows) = DatabaseManager.shared.executeQuery(query) {
                for row in rows {
                    guard let systemId = row["solarsystem_id"] as? Int,
                          let security = row["system_security"] as? Double,
                          let regionId = row["region_id"] as? Int
                    else { continue }
                    loadedSystems.append(
                        (
                            id: systemId,
                            security: security,
                            regionId: regionId
                        )
                    )
                }
            }

            loadedSystems.sort {
                let name0 = SDEMemoryStore.solarSystemName(for: $0.id) ?? ""
                let name1 = SDEMemoryStore.solarSystemName(for: $1.id) ?? ""
                return name0.localizedStandardCompare(name1) == .orderedAscending
            }

            // 更新UI
            DispatchQueue.main.async {
                systems = loadedSystems
                isLoading = false

                // 加载主权数据
                Task {
                    viewModel.loadSovereigntyData(forSystemIds: systemIds)
                }
            }
        }
    }
}
