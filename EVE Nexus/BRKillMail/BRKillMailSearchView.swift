import SwiftUI

struct BRKillMailSearchView: View {
    let characterId: Int
    @StateObject private var viewModel = BRKillMailSearchViewModel()
    @State private var showSearchSheet = false
    @State private var killMails: [[String: Any]] = []
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var currentPage = 1
    @State private var totalPages = 1
    @State private var shipInfoMap: [Int: (name: String, iconFileName: String)] = [:]
    @State private var allianceIconMap: [Int: UIImage] = [:]
    @State private var corporationIconMap: [Int: UIImage] = [:]
    @State private var selectedFilter: KillMailFilter = .all
    
    var body: some View {
        List {
            // 搜索对象选择区域
            Section {
                if viewModel.selectedResult != nil {
                    HStack {
                        KMSearchResultRow(result: viewModel.selectedResult!)
                        Spacer()
                        Button {
                            viewModel.selectedResult = nil
                            killMails = []
                            currentPage = 1
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
            if viewModel.selectedResult != nil {
                Section {
                    // 只在非星系和星域搜索时显示过滤器
                    if let selectedResult = viewModel.selectedResult,
                       selectedResult.category != .solar_system && selectedResult.category != .region {
                        Picker(NSLocalizedString("KillMail_Filter", comment: ""), selection: $selectedFilter) {
                            Text(NSLocalizedString("KillMail_Filter_All", comment: "")).tag(KillMailFilter.all)
                            Text(NSLocalizedString("KillMail_Filter_Kills", comment: "")).tag(KillMailFilter.kill)
                            Text(NSLocalizedString("KillMail_Filter_Losses", comment: "")).tag(KillMailFilter.loss)
                        }
                        .pickerStyle(.segmented)
                        .padding(.vertical, 8)
                        .onChange(of: selectedFilter) { oldValue, newValue in
                            Task {
                                await loadKillMails()
                            }
                        }
                    }
                    
                    if isLoading && killMails.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    } else if killMails.isEmpty {
                        Text(NSLocalizedString("KillMail_No_Results", comment: ""))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    } else {
                        ForEach(Array(killMails.enumerated()), id: \.offset) { index, killmail in
                            if let shipId = viewModel.kbAPI.getShipInfo(killmail, path: "vict", "ship").id {
                                let victInfo = killmail["vict"] as? [String: Any]
                                let allyInfo = victInfo?["ally"] as? [String: Any]
                                let corpInfo = victInfo?["corp"] as? [String: Any]
                                
                                let allyId = allyInfo?["id"] as? Int
                                let corpId = corpInfo?["id"] as? Int
                                
                                BRKillMailCell(
                                    killmail: killmail,
                                    kbAPI: viewModel.kbAPI,
                                    shipInfo: shipInfoMap[shipId] ?? (name: NSLocalizedString("KillMail_Unknown_Item", comment: ""), iconFileName: DatabaseConfig.defaultItemIcon),
                                    allianceIcon: allianceIconMap[allyId ?? 0],
                                    corporationIcon: corporationIconMap[corpId ?? 0],
                                    characterId: characterId
                                )
                            }
                        }
                        
                        if currentPage < totalPages {
                            HStack {
                                Spacer()
                                if isLoadingMore {
                                    ProgressView()
                                } else {
                                    Button(action: {
                                        Task {
                                            await loadMoreKillMails()
                                        }
                                    }) {
                                        Text(NSLocalizedString("KillMail_Load_More", comment: ""))
                                            .font(.system(size: 14))
                                            .foregroundColor(.blue)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
            } else {
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
        .onChange(of: viewModel.selectedResult) { oldValue, newValue in
            if newValue != nil {
                // 如果是星系或星域搜索，重置过滤器为all
                if newValue?.category == .solar_system || newValue?.category == .region {
                    selectedFilter = .all
                }
                Task {
                    await loadKillMails()
                }
            }
        }
    }
    
    private func loadKillMails() async {
        guard let selectedResult = viewModel.selectedResult else { return }
        
        isLoading = true
        currentPage = 1
        totalPages = 1
        killMails = []
        shipInfoMap = [:]
        allianceIconMap = [:]
        corporationIconMap = [:]
        
        do {
            let response = try await KbEvetoolAPI.shared.fetchKillMailsBySearchResult(selectedResult, page: currentPage, filter: selectedFilter)
            if let data = response["data"] as? [[String: Any]] {
                killMails = data
                await loadShipInfo(for: data)
                await loadOrganizationIcons(for: data)
            }
            if let total = response["totalPages"] as? Int {
                totalPages = total
            }
        } catch {
            Logger.error("加载战斗日志失败: \(error)")
        }
        
        isLoading = false
    }
    
    private func loadMoreKillMails() async {
        guard let selectedResult = viewModel.selectedResult else { return }
        
        isLoadingMore = true
        currentPage += 1
        
        do {
            let response = try await KbEvetoolAPI.shared.fetchKillMailsBySearchResult(selectedResult, page: currentPage, filter: selectedFilter)
            if let data = response["data"] as? [[String: Any]] {
                killMails.append(contentsOf: data)
                await loadShipInfo(for: data)
                await loadOrganizationIcons(for: data)
            }
            if let total = response["totalPages"] as? Int {
                totalPages = total
            }
        } catch {
            Logger.error("加载更多战斗日志失败: \(error)")
            currentPage -= 1
        }
        
        isLoadingMore = false
    }
    
    private func loadShipInfo(for mails: [[String: Any]]) async {
        let shipIds = mails.compactMap { viewModel.kbAPI.getShipInfo($0, path: "vict", "ship").id }
        guard !shipIds.isEmpty else { return }
        
        let placeholders = String(repeating: "?,", count: shipIds.count).dropLast()
        let query = """
            SELECT type_id, name, icon_filename 
            FROM types 
            WHERE type_id IN (\(placeholders))
        """
        
        let result = DatabaseManager.shared.executeQuery(query, parameters: shipIds)
        if case .success(let rows) = result {
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                   let name = row["name"] as? String,
                   let iconFileName = row["icon_filename"] as? String {
                    shipInfoMap[typeId] = (name: name, iconFileName: iconFileName)
                }
            }
        }
    }
    
    private func loadOrganizationIcons(for mails: [[String: Any]]) async {
        for mail in mails {
            if let victInfo = mail["vict"] as? [String: Any] {
                // 优先检查联盟ID
                if let allyInfo = victInfo["ally"] as? [String: Any],
                   let allyId = allyInfo["id"] as? Int,
                   allyId > 0 {
                    // 只有当联盟ID有效且图标未加载时才加载联盟图标
                    if allianceIconMap[allyId] == nil,
                       let icon = await loadOrganizationIcon(type: "alliance", id: allyId) {
                        allianceIconMap[allyId] = icon
                    }
                } else if let corpInfo = victInfo["corp"] as? [String: Any],
                          let corpId = corpInfo["id"] as? Int,
                          corpId > 0 {
                    // 只有在没有有效联盟ID的情况下才加载军团图标
                    if corporationIconMap[corpId] == nil,
                       let icon = await loadOrganizationIcon(type: "corporation", id: corpId) {
                        corporationIconMap[corpId] = icon
                    }
                }
            }
        }
    }
    
    private func loadOrganizationIcon(type: String, id: Int) async -> UIImage? {
        let baseURL = "https://images.evetech.net/\(type)s/\(id)/logo"
        guard let iconURL = URL(string: "\(baseURL)?size=64") else { return nil }
        
        do {
            let data = try await NetworkManager.shared.fetchData(from: iconURL)
            return UIImage(data: data)
        } catch {
            return nil
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
                            .onChange(of: searchText) { oldValue, newValue in
                                if !newValue.isEmpty {
                                    viewModel.debounceSearch(characterId: characterId, searchText: newValue)
                                } else {
                                    viewModel.searchResults = [:]
                                }
                            }
                            .submitLabel(.search)
                            .onSubmit {
                                if !searchText.isEmpty {
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
                        Text(NSLocalizedString("Main_Search_Network_Min_Length", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(uiColor: .systemBackground))
                
                if viewModel.isSearching {
                    Spacer()
                    ProgressView()
                        .padding()
                    Spacer()
                } else if !searchText.isEmpty {
                    if viewModel.searchResults.isEmpty {
                        Spacer()
                        Text(NSLocalizedString("Main_Search_No_Results", comment: ""))
                            .foregroundColor(.secondary)
                        Spacer()
                    } else {
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
                    Spacer()
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
    @State private var loadedIcon: UIImage?
    
    var body: some View {
        HStack {
            if let image = result.icon ?? loadedIcon {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else if result.category == .inventory_type || result.category == .solar_system || result.category == .region {
                // 对于物品、星系和星域类型，直接使用本地图标
                IconManager.shared.loadImage(for: result.iconFileName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                // 显示加载中的占位图，同时开始加载图标
                ProgressView()
                    .frame(width: 32, height: 32)
                    .task {
                        await loadIcon()
                    }
            }
            
            VStack(alignment: .leading) {
                Text(result.name)
                Text(result.category.localizedTitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func loadIcon() async {
        let baseURL: String
        switch result.category {
        case .character:
            baseURL = "https://images.evetech.net/characters/\(result.id)/portrait"
        case .corporation:
            baseURL = "https://images.evetech.net/corporations/\(result.id)/logo"
        case .alliance:
            baseURL = "https://images.evetech.net/alliances/\(result.id)/logo"
        default:
            return
        }
        
        guard let url = URL(string: "\(baseURL)?size=64") else { return }
        
        do {
            let data = try await NetworkManager.shared.fetchData(from: url)
            if let image = UIImage(data: data) {
                await MainActor.run {
                    loadedIcon = image
                }
            }
        } catch {
            Logger.error("加载图标失败: \(error)")
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
struct SearchResult: Identifiable, Equatable {
    let id: Int
    let name: String
    let category: SearchResultCategory
    let iconFileName: String
    var icon: UIImage?
    
    static func == (lhs: SearchResult, rhs: SearchResult) -> Bool {
        return lhs.id == rhs.id && lhs.category == rhs.category
    }
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
    let kbAPI = KbEvetoolAPI.shared
    
    private var searchTask: Task<Void, Never>?
    
    func debounceSearch(characterId: Int, searchText: String) {
        // 取消之前的任务
        searchTask?.cancel()
        
        // 创建新的搜索任务
        searchTask = Task {
            // 等待300毫秒
            try? await Task.sleep(nanoseconds: 300_000_000)
            
            // 如果任务被取消，直接返回
            guard !Task.isCancelled else { return }
            
            // 执行搜索
            await search(characterId: characterId, searchText: searchText)
        }
    }
    
    private func searchLocalTypes(searchText: String) async -> [SearchResult]? {
        let query = """
            SELECT type_id, name, icon_filename
            FROM types
            WHERE name LIKE '%\(searchText)%'
            AND categoryID IN (6, 65, 87)
            LIMIT 50
        """
        
        if case .success(let rows) = DatabaseManager.shared.executeQuery(query) {
            var results: [SearchResult] = []
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                   let name = row["name"] as? String,
                   let iconFileName = row["icon_filename"] as? String {
                    results.append(SearchResult(
                        id: typeId,
                        name: name,
                        category: .inventory_type,
                        iconFileName: iconFileName,
                        icon: nil
                    ))
                }
            }
            return results
        }
        return nil
    }
    
    func search(characterId: Int, searchText: String) async {
        guard !searchText.isEmpty else {
            searchResults = [:]
            return
        }
        
        isSearching = true
        defer { isSearching = false }
        
        // 本地搜索（只需1个字符）
        var localResults: [SearchResultCategory: [SearchResult]] = [:]
        if searchText.count >= 1 {
            if let typeResults = await searchLocalTypes(searchText: searchText) {
                localResults[.inventory_type] = typeResults
            }
        }
        
        // 联网搜索（需要3个字符）
        var networkResults: [SearchResultCategory: [SearchResult]] = [:]
        if searchText.count >= 3 {
            do {
                // 使用searchEveItems进行搜索
                let apiResults = try await KbEvetoolAPI.shared.searchEveItems(
                    characterId: characterId,
                    searchText: searchText
                )
                
                // 收集所有ID
                var allIds: [Int] = []
                for (_, ids) in apiResults {
                    allIds.append(contentsOf: ids)
                }
                
                // 批量获取名称
                let names = try await UniverseAPI.shared.getNamesWithFallback(ids: allIds)
                
                // 处理solar_system的图标
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
                
                // 处理inventory_type的图标信息
                var itemInfo: [Int: String] = [:]
                if let items = apiResults["inventory_type"], !items.isEmpty {
                    let itemIds = items.map(String.init).joined(separator: ",")
                    let query = """
                        SELECT type_id, icon_filename
                        FROM types 
                        WHERE type_id IN (\(itemIds))
                        AND categoryID IN (6, 65, 87)
                    """
                    if case .success(let rows) = DatabaseManager.shared.executeQuery(query) {
                        for row in rows {
                            if let typeId = row["type_id"] as? Int,
                               let iconFileName = row["icon_filename"] as? String {
                                itemInfo[typeId] = iconFileName
                            }
                        }
                    }
                }
                
                // 整理联网搜索结果
                for category in categories {
                    let categoryStr = category.rawValue
                    if let ids = apiResults[categoryStr] {
                        var results: [SearchResult] = []
                        for id in ids {
                            if let name = names[id]?.name {
                                var iconFileName = ""
                                
                                switch category {
                                case .character:
                                    iconFileName = "items_7_64_15.png"
                                case .corporation:
                                    iconFileName = "items_7_64_15.png"
                                case .alliance:
                                    iconFileName = "items_7_64_15.png"
                                case .inventory_type:
                                    if let fileName = itemInfo[id] {
                                        iconFileName = fileName
                                    } else {
                                        continue
                                    }
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
                                    icon: nil
                                ))
                            }
                        }
                        if !results.isEmpty {
                            networkResults[category] = results
                        }
                    }
                }
                
                // 开始异步加载图标
                Task {
                    if let characters = networkResults[.character] {
                        let icons = await loadIcons(for: .character, ids: characters.map { $0.id })
                        for id in icons.keys {
                            if let index = self.searchResults[.character]?.firstIndex(where: { $0.id == id }) {
                                self.searchResults[.character]?[index].icon = icons[id]
                            }
                        }
                    }
                }
                
                Task {
                    if let corporations = networkResults[.corporation] {
                        let icons = await loadIcons(for: .corporation, ids: corporations.map { $0.id })
                        for id in icons.keys {
                            if let index = self.searchResults[.corporation]?.firstIndex(where: { $0.id == id }) {
                                self.searchResults[.corporation]?[index].icon = icons[id]
                            }
                        }
                    }
                }
                
                Task {
                    if let alliances = networkResults[.alliance] {
                        let icons = await loadIcons(for: .alliance, ids: alliances.map { $0.id })
                        for id in icons.keys {
                            if let index = self.searchResults[.alliance]?.firstIndex(where: { $0.id == id }) {
                                self.searchResults[.alliance]?[index].icon = icons[id]
                            }
                        }
                    }
                }
                
            } catch {
                Logger.error("联网搜索失败: \(error)")
            }
        }
        
        // 合并本地和联网搜索结果
        var finalResults = localResults
        for (category, results) in networkResults {
            if category == .inventory_type {
                // 对于inventory_type，合并本地和在线结果，并去重
                var existingIds = Set(finalResults[.inventory_type]?.map { $0.id } ?? [])
                var mergedResults = finalResults[.inventory_type] ?? []
                
                for result in results {
                    if !existingIds.contains(result.id) {
                        mergedResults.append(result)
                        existingIds.insert(result.id)
                    }
                }
                
                if !mergedResults.isEmpty {
                    finalResults[.inventory_type] = mergedResults
                } else {
                    finalResults.removeValue(forKey: .inventory_type)
                }
            } else {
                finalResults[category] = results
            }
        }
        
        // 更新UI
        self.searchResults = finalResults
    }
    
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
} 
