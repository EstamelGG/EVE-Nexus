import SwiftUI

// 行星类型汇总视图
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
                                        "Planetary_Resource_Planet_Count", comment: ""),
                                    "\(planet.count)")
                            )
                            .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
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
            // 查询星系内的行星数量
            let query = """
                    SELECT 
                        SUM(u.temperate) as temperate,
                        SUM(u.barren) as barren,
                        SUM(u.oceanic) as oceanic,
                        SUM(u.ice) as ice,
                        SUM(u.gas) as gas,
                        SUM(u.lava) as lava,
                        SUM(u.storm) as storm,
                        SUM(u.plasma) as plasma
                    FROM universe u
                    WHERE u.solarsystem_id IN (\(systemIds.map { String($0) }.joined(separator: ",")))
                """

            if case let .success(rows) = DatabaseManager.shared.executeQuery(query),
                let row = rows.first
            {

                // 获取行星类型名称
                let planetTypeIds = PlanetaryUtils.planetTypeToColumn.keys
                let planetTypeQuery = """
                        SELECT type_id, name, icon_filename
                        FROM types
                        WHERE type_id IN (\(planetTypeIds.map { String($0) }.joined(separator: ",")))
                    """

                var typeIdToName: [Int: (name: String, iconFileName: String)] = [:]

                if case let .success(typeRows) = DatabaseManager.shared.executeQuery(
                    planetTypeQuery)
                {
                    for typeRow in typeRows {
                        if let typeId = typeRow["type_id"] as? Int,
                            let name = typeRow["name"] as? String,
                            let iconFileName = typeRow["icon_filename"] as? String
                        {
                            typeIdToName[typeId] = (
                                name: name,
                                iconFileName: iconFileName.isEmpty ? "not_found" : iconFileName
                            )
                        }
                    }
                }

                // 收集行星总数
                var summary: [(typeId: Int, name: String, count: Int, iconFileName: String)] = []

                for (typeId, columnName) in PlanetaryUtils.planetTypeToColumn {
                    if let count = row[columnName] as? Int,
                        count > 0,
                        let typeInfo = typeIdToName[typeId]
                    {
                        summary.append(
                            (
                                typeId: typeId,
                                name: typeInfo.name,
                                count: count,
                                iconFileName: typeInfo.iconFileName
                            ))
                    }
                }

                // 按行星数量降序排序
                summary.sort { $0.count > $1.count }

                DispatchQueue.main.async {
                    planetTypeSummary = summary
                    isLoading = false
                }
            } else {
                DispatchQueue.main.async {
                    isLoading = false
                }
            }
        }
    }
}
