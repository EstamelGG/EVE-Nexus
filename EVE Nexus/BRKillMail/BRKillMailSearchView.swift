import SwiftUI

struct BRKillMailSearchView: View {
    let characterId: Int
    @StateObject private var viewModel = BRKillMailSearchViewModel()
    @State private var showSearchSheet = false
    
    var body: some View {
        List {
            // 搜索对象选择区域
            Section {
                if let selectedResult = viewModel.selectedResult {
                    HStack {
                        KMSearchResultRow(result: selectedResult)
                        Spacer()
                        Button {
                            viewModel.selectedResult = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(.plain)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showSearchSheet = true
                    }
                } else {
                    Button {
                        showSearchSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "magnifyingglass")
                            Text(NSLocalizedString("KillMail_Search_Prompt", comment: ""))
                            Spacer()
                        }
                    }
                }
            }
            
            // 搜索结果展示区域
            if let selectedResult = viewModel.selectedResult {
                Section {
                    Text("搜索结果将在这里展示")
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle(NSLocalizedString("KillMail_Search_Title", comment: ""))
        .sheet(isPresented: $showSearchSheet) {
            SearchSelectorSheet(characterId: characterId, viewModel: viewModel)
        }
    }
}

// 搜索选择器sheet
struct SearchSelectorSheet: View {
    let characterId: Int
    @ObservedObject var viewModel: BRKillMailSearchViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 搜索框区域
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                        TextField(NSLocalizedString("KillMail_Search_Input_Prompt", comment: ""), text: $searchText)
                            .textFieldStyle(.plain)
                            .focused($isSearchFocused)
                            .onChange(of: searchText) { newValue in
                                if newValue.count >= 3 {
                                    Task {
                                        await viewModel.search(characterId: characterId, searchText: newValue)
                                    }
                                } else {
                                    viewModel.searchResults = [:]
                                }
                            }
                            .submitLabel(.search)
                            .onSubmit {
                                if searchText.count >= 3 {
                                    Task {
                                        await viewModel.search(characterId: characterId, searchText: searchText)
                                    }
                                }
                            }
                        
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                                viewModel.searchResults = [:]
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .padding(8)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .cornerRadius(8)
                    
                    if searchText.count < 3 {
                        Text(NSLocalizedString("Main_Search_Min_Length", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(uiColor: .systemBackground))
                
                if viewModel.isSearching {
                    ProgressView()
                        .padding()
                } else if searchText.count >= 3 {
                    if viewModel.searchResults.isEmpty {
                        VStack {
                            Spacer()
                            Text(NSLocalizedString("Main_Search_No_Results", comment: ""))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    } else {
                        // 搜索结果列表
                        List {
                            ForEach(viewModel.categories, id: \.self) { category in
                                if let results = viewModel.searchResults[category], !results.isEmpty {
                                    Section(header: Text(category.localizedTitle)) {
                                        ForEach(results) { result in
                                            Button {
                                                viewModel.selectedResult = result
                                                dismiss()
                                            } label: {
                                                KMSearchResultRow(result: result)
                                                    .foregroundColor(.primary)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .listStyle(.insetGrouped)
                    }
                } else {
                    // 空状态提示
                    VStack {
                        Spacer()
                        Text(NSLocalizedString("KillMail_Search_Input_Prompt", comment: ""))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            }
            .navigationTitle(NSLocalizedString("KillMail_Search", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("KillMail_Cancel", comment: "")) {
                        dismiss()
                    }
                }
            }
            .onAppear {
                isSearchFocused = true
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
                Text(result.category.localizedTitle)
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
    @Published var selectedResult: SearchResult?
    
    let categories: [SearchResultCategory] = [
        .character, .corporation, .alliance,
        .inventory_type, .solar_system, .region
    ]
    
    private func loadIcons(for category: SearchResultCategory, ids: [Int]) async -> [Int: UIImage] {
        var icons: [Int: UIImage] = [:]
        
        await withTaskGroup(of: (Int, UIImage?).self) { group in
            for id in ids {
                group.addTask {
                    let urlString: String
                    switch category {
                    case .character:
                        urlString = "https://images.evetech.net/characters/\(id)/portrait?size=64"
                    case .corporation:
                        urlString = "https://images.evetech.net/corporations/\(id)/logo?size=64"
                    case .alliance:
                        urlString = "https://images.evetech.net/alliances/\(id)/logo?size=64"
                    default:
                        return (id, nil)
                    }
                    
                    guard let url = URL(string: urlString),
                          let data = try? await NetworkManager.shared.fetchData(from: url),
                          let image = UIImage(data: data) else {
                        return (id, nil)
                    }
                    return (id, image)
                }
            }
            
            for await (id, image) in group {
                if let image = image {
                    icons[id] = image
                }
            }
        }
        
        return icons
    }
    
    func search(characterId: Int, searchText: String) async {
        guard !searchText.isEmpty else {
            searchResults = [:]
            return
        }
        
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
            
            // 4. 并发加载所有图标
            async let characterIcons = loadIcons(for: .character, ids: apiResults["character"] ?? [])
            async let corporationIcons = loadIcons(for: .corporation, ids: apiResults["corporation"] ?? [])
            async let allianceIcons = loadIcons(for: .alliance, ids: apiResults["alliance"] ?? [])
            
            // 5. 处理solar_system的图标
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
            
            // 6. 获取inventory_type的图标
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
            
            // 7. 等待所有图标加载完成
            let (characterIconsResult, corporationIconsResult, allianceIconsResult) = await (characterIcons, corporationIcons, allianceIcons)
            
            // 8. 整理最终结果
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
                                icon = characterIconsResult[id]
                                iconFileName = "items_7_64_15.png"
                            case .corporation:
                                icon = corporationIconsResult[id]
                                iconFileName = "items_7_64_15.png"
                            case .alliance:
                                icon = allianceIconsResult[id]
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
            self.searchResults = finalResults
            
        } catch {
            Logger.error("搜索失败: \(error)")
        }
    }
} 
