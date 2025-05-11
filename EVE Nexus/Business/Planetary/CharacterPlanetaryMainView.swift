import SwiftUI

// 行星信息模型
struct PlanetTypeInfo {
    let name: String
    let icon: String
}

@MainActor
final class CharacterPlanetaryViewModel: ObservableObject {
    @Published private(set) var planets: [CharacterPlanetaryInfo] = []
    @Published private(set) var planetNames: [Int: String] = [:]
    @Published private(set) var planetTypeInfo: [Int: PlanetTypeInfo] = [:]
    @Published var isLoading = true
    @Published var errorMessage: String?

    private var loadingTask: Task<Void, Never>?
    private let characterId: Int?
    private var initialLoadDone = false

    init(characterId: Int?) {
        self.characterId = characterId

        // 在初始化时立即开始加载数据
        loadingTask = Task {
            await loadPlanets()
        }
    }

    deinit {
        loadingTask?.cancel()
    }

    private func loadPlanetTypeInfo() async throws -> [Int: PlanetTypeInfo] {
        let typeIds = Array(PlanetaryUtils.planetTypeToColumn.keys).sorted()
        let typeIdsString = typeIds.map { String($0) }.joined(separator: ",")

        var tempPlanetTypeInfo: [Int: PlanetTypeInfo] = [:]

        // 从数据库获取行星类型信息
        let typeQuery =
            "SELECT type_id, name, icon_filename FROM types WHERE type_id IN (\(typeIdsString))"
        if case let .success(rows) = DatabaseManager.shared.executeQuery(typeQuery) {
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                    let name = row["name"] as? String,
                    let iconFilename = row["icon_filename"] as? String
                {
                    tempPlanetTypeInfo[typeId] = PlanetTypeInfo(
                        name: name, icon: iconFilename)
                }
            }
        }

        return tempPlanetTypeInfo
    }

    func loadPlanets(forceRefresh: Bool = false) async {
        // 如果已经加载过且不是强制刷新，则跳过
        if initialLoadDone && !forceRefresh {
            return
        }

        // 取消之前的加载任务
        loadingTask?.cancel()

        // 创建新的加载任务
        loadingTask = Task {
            isLoading = true
            errorMessage = nil

            do {
                // 首先加载行星类型信息（静态数据）
                let planetTypeInfo = try await loadPlanetTypeInfo()

                if let characterId = characterId {
                    // 获取行星信息（动态数据）
                    let planetsList = try await CharacterPlanetaryAPI.fetchCharacterPlanetary(
                        characterId: characterId, forceRefresh: forceRefresh
                    )

                    if Task.isCancelled { return }

                    // 获取所有行星ID
                    let planetIds = planetsList.map { $0.planetId }
                    let planetIdsString = planetIds.sorted().map { String($0) }.joined(
                        separator: ",")

                    if Task.isCancelled { return }

                    var tempPlanetNames: [Int: String] = [:]

                    // 获取行星名称
                    let nameQuery =
                        "SELECT itemID, itemName FROM invNames WHERE itemID IN (\(planetIdsString))"
                    if case let .success(rows) = DatabaseManager.shared.executeQuery(nameQuery) {
                        for row in rows {
                            if let itemId = row["itemID"] as? Int,
                                let itemName = row["itemName"] as? String
                            {
                                tempPlanetNames[itemId] = itemName
                            }
                        }
                    }

                    if Task.isCancelled { return }

                    await MainActor.run {
                        self.planets = planetsList
                        self.planetNames = tempPlanetNames
                        self.planetTypeInfo = planetTypeInfo
                        self.isLoading = false
                        self.initialLoadDone = true
                    }
                } else {
                    // 如果没有选择角色，只加载静态数据
                    await MainActor.run {
                        self.planets = []
                        self.planetNames = [:]
                        self.planetTypeInfo = planetTypeInfo
                        self.isLoading = false
                        self.initialLoadDone = true
                    }
                }
            } catch {
                Logger.error("加载行星数据失败: \(error.localizedDescription)")
                if !Task.isCancelled {
                    await MainActor.run {
                        self.errorMessage = error.localizedDescription
                        self.isLoading = false
                    }
                }
            }
        }

        // 等待任务完成
        await loadingTask?.value
    }

    func getPlanetTypeInfo(for planetType: String) -> PlanetTypeInfo? {
        // 通过columnToPlanetType找到对应的行星类型ID
        if let typeId = PlanetaryUtils.columnToPlanetType[planetType],
            let info = planetTypeInfo[typeId]
        {
            return info
        }
        return nil
    }

    func getPlanetName(for planetId: Int) -> String {
        return planetNames[planetId]
            ?? NSLocalizedString("Main_Planetary_Unknown_Planet", comment: "")
    }
}

struct CharacterPlanetaryView: View {
    let characterId: Int?
    @StateObject private var viewModel: CharacterPlanetaryViewModel

    init(characterId: Int?) {
        self.characterId = characterId
        _viewModel = StateObject(
            wrappedValue: CharacterPlanetaryViewModel(characterId: characterId))
    }

    var body: some View {
        List {
            // 行星开发计算器功能
            Section(NSLocalizedString("Main_Planetary_calc", comment: "")) {
                NavigationLink {
                    PlanetarySiteFinder(characterId: characterId)
                } label: {
                    Text(NSLocalizedString("Main_Planetary_location_calc", comment: ""))
                }
                NavigationLink {
                    PIOutputCalculatorView(characterId: characterId)
                } label: {
                    Text(NSLocalizedString("Main_Planetary_Output", comment: ""))
                }
            }
            if viewModel.isLoading {
                Section(header: Text(NSLocalizedString("Main_Planetary_of_Mine", comment: ""))) {
                    HStack {
                        Spacer()
                        ProgressView()
                            .progressViewStyle(.circular)
                        Spacer()
                    }
                }
            } else {
                if characterId != nil {
                    if viewModel.planets.isEmpty {
                        Section(
                            header: Text(NSLocalizedString("Main_Planetary_of_Mine", comment: ""))
                        ) {
                            NoDataSection()
                        }
                    } else {
                        Section(
                            header: Text(NSLocalizedString("Main_Planetary_of_Mine", comment: "")),
                            footer: Text(
                                String(
                                    format: NSLocalizedString(
                                        "Main_Planetary_Total_Count", comment: ""),
                                    viewModel.planets.count))
                        ) {
                            ForEach(viewModel.planets, id: \.planetId) { planet in
                                NavigationLink(
                                    destination: PlanetDetailView(
                                        characterId: characterId!,
                                        planetId: planet.planetId,
                                        planetName: viewModel.getPlanetName(for: planet.planetId)
                                    )
                                ) {
                                    HStack {
                                        if let typeInfo = viewModel.getPlanetTypeInfo(
                                            for: planet.planetType)
                                        {
                                            Image(
                                                uiImage: IconManager.shared.loadUIImage(
                                                    for: typeInfo.icon)
                                            )
                                            .resizable()
                                            .frame(width: 32, height: 32)
                                            .cornerRadius(6)
                                        }

                                        VStack(alignment: .leading) {
                                            Text(viewModel.getPlanetName(for: planet.planetId))
                                                .font(.headline)

                                            if let typeInfo = viewModel.getPlanetTypeInfo(
                                                for: planet.planetType)
                                            {
                                                Text(typeInfo.name)
                                                    .font(.subheadline)
                                                    .foregroundColor(.gray)
                                            } else {
                                                Text(
                                                    NSLocalizedString(
                                                        "Main_Planetary_Unknown_Type", comment: "")
                                                )
                                                .font(.subheadline)
                                                .foregroundColor(.gray)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Main_Planetary_Title", comment: ""))
        .refreshable {
            await viewModel.loadPlanets(forceRefresh: true)
        }
    }
}
