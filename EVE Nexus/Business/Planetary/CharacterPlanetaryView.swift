import SwiftUI

struct CharacterPlanetaryView: View {
    let characterId: Int
    @State private var planets: [CharacterPlanetaryInfo] = []
    @State private var planetNames: [Int: String] = [:]
    @State private var planetTypeInfo: [Int: (name: String, icon: String)] = [:]
    @State private var isRefreshing = false
    @State private var hasLoadedData = false  // 添加标记，用于跟踪是否已加载数据

    private let typeIdMapping = [
        "temperate": 11,
        "barren": 2016,
        "oceanic": 2014,
        "ice": 12,
        "gas": 13,
        "lava": 2015,
        "storm": 2017,
        "plasma": 2063,
    ]

    var body: some View {
        List {
            if planets.isEmpty {
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
                Section {
                    ForEach(planets, id: \.planetId) { planet in
                        NavigationLink(
                            destination: PlanetDetailView(
                                characterId: characterId,
                                planetId: planet.planetId,
                                planetName: planetNames[planet.planetId]
                                    ?? NSLocalizedString(
                                        "Main_Planetary_Unknown_Planet", comment: ""
                                    )
                            )
                        ) {
                            HStack {
                                if let typeInfo = planetTypeInfo[
                                    typeIdMapping[planet.planetType] ?? 0
                                ] {
                                    Image(
                                        uiImage: IconManager.shared.loadUIImage(for: typeInfo.icon)
                                    )
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(6)
                                }

                                VStack(alignment: .leading) {
                                    Text(
                                        planetNames[planet.planetId]
                                            ?? NSLocalizedString(
                                                "Main_Planetary_Unknown_Planet", comment: ""
                                            )
                                    )
                                    .font(.headline)
                                    Text(
                                        planetTypeInfo[typeIdMapping[planet.planetType] ?? 0]?.name
                                            ?? NSLocalizedString(
                                                "Main_Planetary_Unknown_Type", comment: ""
                                            )
                                    )
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                }
                            }
                        }
                    }
                } footer: {
                    Text(
                        String(
                            format: NSLocalizedString("Main_Planetary_Total_Count", comment: ""),
                            planets.count
                        ))
                }
            }
        }
        .navigationTitle(NSLocalizedString("Main_Planetary_Title", comment: ""))
        .refreshable {
            await refreshData()
        }
        .onAppear {
            if !hasLoadedData {  // 只在第一次加载数据
                Task {
                    await loadPlanets()
                    hasLoadedData = true
                }
            }
        }
    }

    private func loadPlanets(forceRefresh: Bool = false) async {
        do {
            // 获取行星信息
            planets = try await CharacterPlanetaryAPI.fetchCharacterPlanetary(
                characterId: characterId, forceRefresh: forceRefresh
            )

            // 获取所有行星类型ID
            let typeIds = planets.compactMap { typeIdMapping[$0.planetType] }
            let typeIdsString = typeIds.sorted().map { String($0) }.joined(separator: ",")

            // 获取所有行星ID
            let planetIds = planets.map { $0.planetId }
            let planetIdsString = planetIds.sorted().map { String($0) }.joined(separator: ",")

            // 从数据库获取行星类型信息
            let typeQuery =
                "SELECT type_id, name, icon_filename FROM types WHERE type_id IN (\(typeIdsString))"
            if case let .success(rows) = DatabaseManager.shared.executeQuery(typeQuery) {
                for row in rows {
                    if let typeId = row["type_id"] as? Int,
                        let name = row["name"] as? String,
                        let iconFilename = row["icon_filename"] as? String
                    {
                        planetTypeInfo[typeId] = (name: name, icon: iconFilename)
                    }
                }
            }

            // 获取行星名称
            let nameQuery =
                "SELECT itemID, itemName FROM invNames WHERE itemID IN (\(planetIdsString))"
            if case let .success(rows) = DatabaseManager.shared.executeQuery(nameQuery) {
                for row in rows {
                    if let itemId = row["itemID"] as? Int,
                        let itemName = row["itemName"] as? String
                    {
                        planetNames[itemId] = itemName
                    }
                }
            }
        } catch {
            print("Error loading planets: \(error)")
        }
    }

    private func refreshData() async {
        isRefreshing = true
        await loadPlanets(forceRefresh: true)
        isRefreshing = false
    }
}
