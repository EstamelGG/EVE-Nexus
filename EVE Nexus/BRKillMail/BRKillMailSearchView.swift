import SwiftUI

struct BRKillMailSearchView: View {
    let characterId: Int
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = BRKillMailSearchViewModel()
    @State private var showSearchSheet = false
    
    var body: some View {
        List {
            Button {
                showSearchSheet = true
            } label: {
                HStack {
                    Image(systemName: "magnifyingglass")
                    Text(NSLocalizedString("KillMail_Search_Prompt", comment: ""))
                }
            }
            
            if !viewModel.searchResults.isEmpty {
                ForEach(viewModel.categories, id: \.self) { category in
                    if let results = viewModel.searchResults[category], !results.isEmpty {
                        Section(header: Text(category.localizedTitle)) {
                            ForEach(results) { result in
                                KMSearchResultRow(result: result)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("KillMail_Search_Title", comment: ""))
        .sheet(isPresented: $showSearchSheet) {
            SearchInputSheet(characterId: characterId, viewModel: viewModel)
        }
    }
}

// 搜索输入sheet
struct SearchInputSheet: View {
    let characterId: Int
    @ObservedObject var viewModel: BRKillMailSearchViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    
    var body: some View {
        NavigationStack {
            VStack {
                TextField(NSLocalizedString("KillMail_Search_Input_Prompt", comment: ""), text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()
                
                if viewModel.isSearching {
                    ProgressView()
                        .padding()
                }
                
                Spacer()
            }
            .navigationTitle(NSLocalizedString("KillMail_Search", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("KillMail_Cancel", comment: "")) {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("KillMail_Search", comment: "")) {
                        Task {
                            await viewModel.search(characterId: characterId, searchText: searchText)
                            dismiss()
                        }
                    }
                    .disabled(searchText.isEmpty || viewModel.isSearching)
                }
            }
        }
    }
}

// 搜索结果行视图
struct KMSearchResultRow: View {
    let result: SearchResult
    
    var body: some View {
        HStack {
            if let image = result.icon {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
            } else {
                IconManager.shared.loadImage(for: result.iconFileName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
            }
            
            VStack(alignment: .leading) {
                Text(result.name)
                Text(result.category.rawValue)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// 搜索结果类别
enum SearchResultCategory: String {
    case alliance
    case character
    case corporation
    case inventory_type
    case solar_system
    case region
    
    var localizedTitle: String {
        switch self {
        case .alliance: return NSLocalizedString("KillMail_Search_Alliance", comment: "")
        case .character: return NSLocalizedString("KillMail_Search_Character", comment: "")
        case .corporation: return NSLocalizedString("KillMail_Search_Corporation", comment: "")
        case .inventory_type: return NSLocalizedString("KillMail_Search_Item", comment: "")
        case .solar_system: return NSLocalizedString("KillMail_Search_System", comment: "")
        case .region: return NSLocalizedString("KillMail_Search_Region", comment: "")
        }
    }
}

// 搜索结果模型
struct SearchResult: Identifiable {
    let id: Int
    let name: String
    let category: SearchResultCategory
    let iconFileName: String
    var icon: UIImage?
}

@MainActor
class BRKillMailSearchViewModel: ObservableObject {
    @Published var searchResults: [SearchResultCategory: [SearchResult]] = [:]
    @Published var isSearching = false
    
    let categories: [SearchResultCategory] = [
        .character, .corporation, .alliance,
        .inventory_type, .solar_system, .region
    ]
    
    func search(characterId: Int, searchText: String) async {
        guard !searchText.isEmpty else { return }
        
        isSearching = true
        defer { isSearching = false }
        
        do {
            // 1. 使用searchEveItems进行搜索
            let apiResults = try await KbEvetoolAPI.shared.searchEveItems(
                characterId: characterId,
                searchText: searchText
            )
            
            // 2. 收集所有ID
            var allIds: [Int] = []
            for (_, ids) in apiResults {
                allIds.append(contentsOf: ids)
            }
            
            // 3. 批量获取名称
            let names = try await UniverseAPI.shared.getNamesWithFallback(ids: allIds)
            
            // 4. 处理solar_system的图标
            var systemIcons: [Int: String] = [:]
            if let solarSystems = apiResults["solar_system"], !solarSystems.isEmpty {
                let systemIds = solarSystems.map(String.init).joined(separator: ",")
                let query = """
                    SELECT u.solarsystem_id, t.icon_filename
                    FROM universe u
                    JOIN types t ON u.system_type = t.type_id
                    WHERE u.solarsystem_id IN (\(systemIds))
                """
                if case .success(let rows) = DatabaseManager.shared.executeQuery(query) {
                    for row in rows {
                        if let systemId = row["solarsystem_id"] as? Int,
                           let iconFileName = row["icon_filename"] as? String {
                            systemIcons[systemId] = iconFileName
                        }
                    }
                }
            }
            
            // 5. 获取inventory_type的图标
            var itemIcons: [Int: String] = [:]
            if let items = apiResults["inventory_type"], !items.isEmpty {
                let itemIds = items.map(String.init).joined(separator: ",")
                let query = "SELECT type_id, icon_filename FROM types WHERE type_id IN (\(itemIds))"
                if case .success(let rows) = DatabaseManager.shared.executeQuery(query) {
                    for row in rows {
                        if let typeId = row["type_id"] as? Int,
                           let iconFileName = row["icon_filename"] as? String {
                            itemIcons[typeId] = iconFileName
                        }
                    }
                }
            }
            
            // 6. 加载角色、军团、联盟的图标
            var characterIcons: [Int: UIImage] = [:]
            var corporationIcons: [Int: UIImage] = [:]
            var allianceIcons: [Int: UIImage] = [:]
            
            // 加载角色图标
            if let characters = apiResults["character"] {
                for id in characters {
                    if let url = URL(string: "https://images.evetech.net/characters/\(id)/portrait?size=64"),
                       let data = try? await NetworkManager.shared.fetchData(from: url),
                       let image = UIImage(data: data) {
                        characterIcons[id] = image
                    }
                }
            }
            
            // 加载军团图标
            if let corporations = apiResults["corporation"] {
                for id in corporations {
                    if let url = URL(string: "https://images.evetech.net/corporations/\(id)/logo?size=64"),
                       let data = try? await NetworkManager.shared.fetchData(from: url),
                       let image = UIImage(data: data) {
                        corporationIcons[id] = image
                    }
                }
            }
            
            // 加载联盟图标
            if let alliances = apiResults["alliance"] {
                for id in alliances {
                    if let url = URL(string: "https://images.evetech.net/alliances/\(id)/logo?size=64"),
                       let data = try? await NetworkManager.shared.fetchData(from: url),
                       let image = UIImage(data: data) {
                        allianceIcons[id] = image
                    }
                }
            }
            
            // 7. 整理最终结果
            var finalResults: [SearchResultCategory: [SearchResult]] = [:]
            
            for category in categories {
                let categoryStr = category.rawValue
                if let ids = apiResults[categoryStr] {
                    var results: [SearchResult] = []
                    for id in ids {
                        if let name = names[id]?.name {
                            var iconFileName = ""
                            var icon: UIImage? = nil
                            
                            switch category {
                            case .character:
                                icon = characterIcons[id]
                                iconFileName = "items_7_64_15.png"
                            case .corporation:
                                icon = corporationIcons[id]
                                iconFileName = "items_7_64_15.png"
                            case .alliance:
                                icon = allianceIcons[id]
                                iconFileName = "items_7_64_15.png"
                            case .inventory_type:
                                iconFileName = itemIcons[id] ?? "items_7_64_15.png"
                            case .solar_system:
                                iconFileName = systemIcons[id] ?? "items_7_64_15.png"
                            case .region:
                                iconFileName = "items_7_64_4.png"
                            }
                            
                            results.append(SearchResult(
                                id: id,
                                name: name,
                                category: category,
                                iconFileName: iconFileName,
                                icon: icon
                            ))
                        }
                    }
                    if !results.isEmpty {
                        finalResults[category] = results
                    }
                }
            }
            
            // 更新 UI
            await MainActor.run {
                self.searchResults = finalResults
            }
            
        } catch {
            Logger.error("搜索失败: \(error)")
        }
    }
} 
