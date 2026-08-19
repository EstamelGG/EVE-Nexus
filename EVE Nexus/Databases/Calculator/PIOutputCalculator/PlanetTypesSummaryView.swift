import SwiftUI

/// 行星类型汇总视图
struct PlanetTypesSummaryView: View {
    let systemIds: [Int]
    @State private var planetTypeSummary:
        [(typeId: Int, name: String, count: Int, iconFileName: String)] = []
    @State private var isLoading = true

    var body: some View {
        List {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Text(NSLocalizedString("Misc_Loading", comment: "加载中..."))
                        .foregroundColor(.gray)
                        .padding(.leading, 8)
                    Spacer()
                }
            } else if planetTypeSummary.isEmpty {
                HStack {
                    Spacer()
                    Text(NSLocalizedString("PI_Output_No_Resources", comment: "没有找到可用资源"))
                        .foregroundColor(.gray)
                    Spacer()
                }
            } else {
                Section {
                    ForEach(planetTypeSummary, id: \.typeId) { planet in
                        HStack {
                            Image(uiImage: IconManager.shared.loadUIImage(for: planet.iconFileName))
                                .resizable()
                                .scaledToFit()
                                .frame(width: 32, height: 32)
                                .cornerRadius(4)

                            Text(planet.name)
                                .font(.body)

                            Spacer()

                            Text(
                                String(
                                    format: NSLocalizedString(
                                        "Planetary_Resource_Planet_Count", comment: ""
                                    ),
                                    "\(planet.count)"
                                )
                            )
                            .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            }
        }
        .navigationTitle(NSLocalizedString("PI_Output_Planet_Distribution", comment: "行星分布"))
        .onAppear {
            loadPlanetTypeSummary()
        }
    }

    private func loadPlanetTypeSummary() {
        guard !systemIds.isEmpty else {
            isLoading = false
            return
        }

        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async {
            // 内存索引聚合星系行星数量（原 SUM 查询）
            var sums: [String: Int] = [:]
            for systemId in systemIds {
                guard let info = SDEMemoryStore.universeSystems[systemId] else { continue }
                for (column, count) in info.planetCounts {
                    sums[column, default: 0] += count
                }
            }

            // 获取行星类型名称（内存索引）
            let planetTypeIds = PlanetaryUtils.planetTypeToColumn.keys
            var typeIdToName: [Int: (name: String, iconFileName: String)] = [:]
            for typeId in planetTypeIds {
                guard let info = SDEMemoryStore.type(for: typeId) else { continue }
                typeIdToName[typeId] = (name: info.name, iconFileName: info.iconFilename)
            }

            // 收集行星总数
            var summary: [(typeId: Int, name: String, count: Int, iconFileName: String)] = []

            for (typeId, columnName) in PlanetaryUtils.planetTypeToColumn {
                if let count = sums[columnName],
                   count > 0,
                   let typeInfo = typeIdToName[typeId]
                {
                    summary.append(
                        (
                            typeId: typeId,
                            name: typeInfo.name,
                            count: count,
                            iconFileName: typeInfo.iconFileName
                        )
                    )
                }
            }

            // 按行星数量降序排序
            summary.sort { $0.count > $1.count }

            DispatchQueue.main.async {
                planetTypeSummary = summary
                isLoading = false
            }
        }
    }
}
