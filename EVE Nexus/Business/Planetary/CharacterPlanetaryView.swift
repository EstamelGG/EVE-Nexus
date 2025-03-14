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
    private let characterId: Int
    private var initialLoadDone = false
    
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
    
    init(characterId: Int) {
        self.characterId = characterId
        
        // 在初始化时立即开始加载数据
        loadingTask = Task {
            await loadPlanets()
        }
    }
    
    deinit {
        loadingTask?.cancel()
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
                // 获取行星信息
                let planetsList = try await CharacterPlanetaryAPI.fetchCharacterPlanetary(
                    characterId: characterId, forceRefresh: forceRefresh
                )
                
                if Task.isCancelled { return }
                
                // 获取所有行星类型ID
                let typeIds = planetsList.compactMap { typeIdMapping[$0.planetType] }
                let typeIdsString = typeIds.sorted().map { String($0) }.joined(separator: ",")
                
                // 获取所有行星ID
                let planetIds = planetsList.map { $0.planetId }
                let planetIdsString = planetIds.sorted().map { String($0) }.joined(separator: ",")
                
                if Task.isCancelled { return }
                
                var tempPlanetTypeInfo: [Int: PlanetTypeInfo] = [:]
                var tempPlanetNames: [Int: String] = [:]
                
                // 从数据库获取行星类型信息
                let typeQuery =
                    "SELECT type_id, name, icon_filename FROM types WHERE type_id IN (\(typeIdsString))"
                if case let .success(rows) = DatabaseManager.shared.executeQuery(typeQuery) {
                    for row in rows {
                        if let typeId = row["type_id"] as? Int,
                           let name = row["name"] as? String,
                           let iconFilename = row["icon_filename"] as? String
                        {
                            tempPlanetTypeInfo[typeId] = PlanetTypeInfo(name: name, icon: iconFilename)
                        }
                    }
                }
                
                if Task.isCancelled { return }
                
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
                    self.planetTypeInfo = tempPlanetTypeInfo
                    self.isLoading = false
                    self.initialLoadDone = true
                }
                
            } catch {
                print("加载行星数据失败: \(error.localizedDescription)")
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
        if let typeId = typeIdMapping[planetType], let info = planetTypeInfo[typeId] {
            return info
        }
        return nil
    }
    
    func getPlanetName(for planetId: Int) -> String {
        return planetNames[planetId] ?? NSLocalizedString("Main_Planetary_Unknown_Planet", comment: "")
    }
}

struct CharacterPlanetaryView: View {
    let characterId: Int
    @StateObject private var viewModel: CharacterPlanetaryViewModel
    
    init(characterId: Int) {
        self.characterId = characterId
        _viewModel = StateObject(wrappedValue: CharacterPlanetaryViewModel(characterId: characterId))
    }

    var body: some View {
        List {
            if viewModel.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(.circular)
                    Spacer()
                }
            } else if viewModel.planets.isEmpty {
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
                    ForEach(viewModel.planets, id: \.planetId) { planet in
                        NavigationLink(
                            destination: PlanetDetailView(
                                characterId: characterId,
                                planetId: planet.planetId,
                                planetName: viewModel.getPlanetName(for: planet.planetId)
                            )
                        ) {
                            HStack {
                                if let typeInfo = viewModel.getPlanetTypeInfo(for: planet.planetType) {
                                    Image(
                                        uiImage: IconManager.shared.loadUIImage(for: typeInfo.icon)
                                    )
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(6)
                                }

                                VStack(alignment: .leading) {
                                    Text(viewModel.getPlanetName(for: planet.planetId))
                                        .font(.headline)
                                    
                                    if let typeInfo = viewModel.getPlanetTypeInfo(for: planet.planetType) {
                                        Text(typeInfo.name)
                                            .font(.subheadline)
                                            .foregroundColor(.gray)
                                    } else {
                                        Text(NSLocalizedString("Main_Planetary_Unknown_Type", comment: ""))
                                            .font(.subheadline)
                                            .foregroundColor(.gray)
                                    }
                                }
                            }
                        }
                    }
                } footer: {
                    Text(
                        String(
                            format: NSLocalizedString("Main_Planetary_Total_Count", comment: ""),
                            viewModel.planets.count
                        ))
                }
            }
        }
        .navigationTitle(NSLocalizedString("Main_Planetary_Title", comment: ""))
        .refreshable {
            await viewModel.loadPlanets(forceRefresh: true)
        }
    }
}
