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
                        .padding(.vertical, 2)
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
                        Text(NSLocalizedString("KillMail_No_Records", comment: ""))
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
                                    characterId: characterId,
                                    searchResult: viewModel.selectedResult
                                )
                            }
                        }
                        
                        if totalPages > 1 && currentPage < totalPages {
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
                    Text(NSLocalizedString("Main_Search_Results_Placeholder", comment: ""))
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
            let response = try await KbEvetoolAPI.shared.fetchKillMailsBySearchResult(result: selectedResult, page: currentPage, filter: selectedFilter)
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
        guard let selectedResult = viewModel.selectedResult,
              !isLoadingMore,
              currentPage < totalPages else { return }
        
        isLoadingMore = true
        currentPage += 1
        
        do {
            let response = try await KbEvetoolAPI.shared.fetchKillMailsBySearchResult(result: selectedResult, page: currentPage, filter: selectedFilter)
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
        // 替换图标尺寸
        Logger.debug("Load img from result: \(result.imageURL)")
        let urlString = result.imageURL.replacingOccurrences(of: "size=32", with: "size=64")
        guard let url = URL(string: urlString) else { return }
        
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
    let imageURL: String
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
    
    func search(characterId: Int, searchText: String) async {
        guard !searchText.isEmpty else {
            searchResults = [:]
            return
        }
        
        isSearching = true
        defer { isSearching = false }
        
        // 联网搜索
        var networkResults: [SearchResultCategory: [SearchResult]] = [:]
        do {
            // 使用searchEveItems进行搜索
            let apiResults = try await KbEvetoolAPI.shared.searchEveItems(
                characterId: characterId,
                searchText: searchText
            )
            
            // 处理搜索结果
            for (categoryStr, items) in apiResults {
                guard let category = SearchResultCategory(rawValue: categoryStr) else { continue }
                
                var results: [SearchResult] = []
                for item in items {
                    results.append(SearchResult(
                        id: item.id,
                        name: item.name,
                        category: category,
                        imageURL: item.image,
                        icon: nil
                    ))
                }
                
                if !results.isEmpty {
                    networkResults[category] = results
                }
            }
            
            // 开始异步加载图标
            Task {
                for category in categories {
                    if let results = networkResults[category] {
                        for result in results {
                            if let url = URL(string: result.imageURL.replacingOccurrences(of: "size=32", with: "size=64")),
                               let data = try? await NetworkManager.shared.fetchData(from: url),
                               let image = UIImage(data: data) {
                                if let index = self.searchResults[category]?.firstIndex(where: { $0.id == result.id }) {
                                    self.searchResults[category]?[index].icon = image
                                }
                            }
                        }
                    }
                }
            }
            
        } catch {
            Logger.error("联网搜索失败: \(error)")
        }
        
        // 更新UI
        self.searchResults = networkResults
    }
} 
