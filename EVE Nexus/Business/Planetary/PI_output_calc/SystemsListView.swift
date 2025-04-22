import SwiftUI

// 添加星系列表视图
struct SystemsListView: View {
    let title: String
    let systemIds: [Int]
    let selectedSystemId: Int?

    @State private var systems: [(id: Int, name: String, security: Double, region: String)] = []
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
                                // 无主权或图标加载失败时显示的占位符
                                Color.clear
                                    .frame(width: 32, height: 32)
                            }
                        }

                        // 星系信息
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(formatSystemSecurity(system.security))
                                    .foregroundColor(getSecurityColor(system.security))
                                    .font(.system(.body, design: .monospaced))
                                    .padding(.trailing, 4)

                                Text(system.name)
                                    .font(.headline)
                            }

                            // 第二行显示星域名和拥有者（如果有）
                            HStack(spacing: 4) {
                                Text(system.region)
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
            // 查询星系信息
            let query = """
                    SELECT s.solarSystemID, s.solarSystemName, u.system_security, r.regionName
                    FROM solarsystems s
                    JOIN universe u ON s.solarSystemID = u.solarsystem_id
                    JOIN regions r ON r.regionID = u.region_id
                    WHERE s.solarSystemID IN (\(systemIds.map { String($0) }.joined(separator: ",")))
                    ORDER BY s.solarSystemName
                """

            var loadedSystems: [(id: Int, name: String, security: Double, region: String)] = []

            if case let .success(rows) = DatabaseManager.shared.executeQuery(query) {
                for row in rows {
                    if let systemId = row["solarSystemID"] as? Int,
                        let systemName = row["solarSystemName"] as? String,
                        let security = row["system_security"] as? Double,
                        let regionName = row["regionName"] as? String
                    {
                        loadedSystems.append(
                            (
                                id: systemId,
                                name: systemName,
                                security: security,
                                region: regionName
                            ))
                    }
                }
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
