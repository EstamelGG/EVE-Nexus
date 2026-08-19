import Foundation
import SwiftUI

struct P0ResourceDetailView: View {
    let resourceId: Int
    let resourceName: String
    let systemIds: [Int]
    @State private var systemPlanets:
        [(
            systemId: Int, systemName: String, security: Double,
            planets: [(type: Int, count: Int, iconFileName: String, typeName: String)]
        )] = []
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
                ForEach(systemPlanets, id: \.systemId) { system in
                    Section(
                        header: HStack {
                            Text(formatSystemSecurity(system.security))
                                .foregroundColor(getSecurityColor(system.security))
                                .font(.system(.body, design: .monospaced))
                                .padding(.trailing, 4)

                            Text(system.systemName)
                                .font(.headline)
                        }
                    ) {
                        ForEach(system.planets, id: \.type) { planet in
                            HStack {
                                Image(
                                    uiImage: IconManager.shared.loadUIImage(
                                        for: planet.iconFileName
                                    )
                                )
                                .resizable()
                                .scaledToFit()
                                .frame(width: 32, height: 32)
                                .cornerRadius(4)

                                Text(planet.typeName)
                                Spacer()
                                Text(
                                    "\(String.localizedStringWithFormat(NSLocalizedString("Planetary_Resource_Planet_Count", comment: ""), "\(planet.count)"))"
                                )
                                .foregroundColor(.secondary)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
            }
        }
        .navigationTitle("\(resourceName)")
        .onAppear {
            loadSystemPlanets()
        }
    }

    private func loadSystemPlanets() {
        guard !systemIds.isEmpty else {
            isLoading = false
            return
        }

        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async {
            var loadedSystemPlanets:
                [(
                    systemId: Int, systemName: String, security: Double,
                    planets: [(type: Int, count: Int, iconFileName: String, typeName: String)]
                )] = []

            // 获取资源可用的行星类型
            let resourceCalculator = PlanetaryResourceCalculator(
                databaseManager: DatabaseManager.shared
            )
            let resourcePlanets = resourceCalculator.findResourcePlanets(for: [resourceId])

            guard let resourceInfo = resourcePlanets.first else {
                DispatchQueue.main.async {
                    isLoading = false
                }
                return
            }

            // 创建行星类型到图标文件名的映射
            var planetTypeToIcon: [Int: String] = [:]
            for planet in resourceInfo.availablePlanets {
                planetTypeToIcon[planet.id] = planet.iconFileName
            }

            let availablePlanetTypes = Set(resourceInfo.availablePlanets.map { $0.id })

            // 查询行星类型名称
            var planetTypeNames: [Int: String] = [:]
            for typeId in availablePlanetTypes {
                if let name = ItemInfoMap.typeName(for: typeId) {
                    planetTypeNames[typeId] = name
                }
            }

            // 内存索引取星系行星数量与安等
            for systemId in systemIds {
                guard let info = SDEMemoryStore.universeSystems[systemId],
                      let systemName = SDEMemoryStore.solarSystemName(for: systemId)
                else { continue }
                let security = info.security

                var planetCounts:
                    [(type: Int, count: Int, iconFileName: String, typeName: String)] = []

                // 检查每种行星类型的数量
                for planetType in availablePlanetTypes {
                    if let columnName = PlanetaryUtils.planetTypeToColumn[planetType],
                       let count = info.planetCounts[columnName],
                       count > 0,
                       let iconFileName = planetTypeToIcon[planetType],
                       let typeName = planetTypeNames[planetType]
                    {
                        planetCounts.append(
                            (
                                type: planetType,
                                count: count,
                                iconFileName: iconFileName,
                                typeName: typeName
                            )
                        )
                    }
                }

                if !planetCounts.isEmpty {
                    // 按type_id排序行星列表
                    planetCounts.sort { $0.type < $1.type }

                    loadedSystemPlanets.append(
                        (
                            systemId: systemId,
                            systemName: systemName,
                            security: security,
                            planets: planetCounts
                        )
                    )
                }
            }

            // 更新UI
            DispatchQueue.main.async {
                systemPlanets = loadedSystemPlanets.sorted {
                    $0.systemName.localizedStandardCompare($1.systemName) == .orderedAscending
                }
                isLoading = false

                // 加载主权数据
                Task {
                    viewModel.loadSovereigntyData(forSystemIds: systemIds)
                }
            }
        }
    }
}
