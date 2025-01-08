import SwiftUI

struct SearcherView: View {
    let character: EVECharacterInfo
    @StateObject private var viewModel = SearcherViewModel()
    @State private var searchText = ""
    @State private var selectedSearchType = SearchType.character
    
    // 过滤条件
    @State private var corporationFilter = ""
    @State private var allianceFilter = ""
    @State private var tickerFilter = ""
    @State private var selectedSecurityLevel = SecurityLevel.all
    @State private var selectedStructureType = StructureType.all
    
    enum SearchType: String, CaseIterable {
        case character = "Main_Search_Type_Character"
        case corporation = "Main_Search_Type_Corporation"
        case alliance = "Main_Search_Type_Alliance"
        case structure = "Main_Search_Type_Structure"
        
        var localizedName: String {
            NSLocalizedString(self.rawValue, comment: "")
        }
        
        // 转换为MailRecipient.RecipientType
        var recipientType: MailRecipient.RecipientType {
            switch self {
            case .character:
                return .character
            case .corporation:
                return .corporation
            case .alliance:
                return .alliance
            case .structure:
                return .character // 建筑物没有对应的类型，暂时使用character
            }
        }
    }
    
    enum SecurityLevel: String, CaseIterable {
        case all = "Main_Search_Filter_All"
        case highSec = "Main_Search_Filter_High_Sec"
        case lowSec = "Main_Search_Filter_Low_Sec"
        case nullSec = "Main_Search_Filter_Null_Sec"
        
        var localizedName: String {
            NSLocalizedString(self.rawValue, comment: "")
        }
    }
    
    enum StructureType: String, CaseIterable {
        case all = "Main_Search_Filter_All"
        case station = "Main_Search_Filter_Station"
        case structure = "Main_Search_Filter_Structure"
        
        var localizedName: String {
            NSLocalizedString(self.rawValue, comment: "")
        }
    }
    
    // 搜索结果数据模型
    struct SearchResult: Identifiable {
        let id: Int
        let name: String
        let type: SearchType
        var corporationName: String?
        var allianceName: String?
    }
    
    // 搜索响应数据结构
    struct SearchResponse: Codable {
        let character: [Int]?
        let corporation: [Int]?
        let alliance: [Int]?
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 搜索类型选择器
            Picker("", selection: $selectedSearchType) {
                ForEach(SearchType.allCases, id: \.self) { type in
                    Text(type.localizedName).tag(type)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            .padding(.top)
            
            // 搜索框
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField(NSLocalizedString("Main_Search_Placeholder", comment: ""), text: $searchText)
                        .submitLabel(.search)
                        .onSubmit {
                            if !searchText.isEmpty && searchText.count > 2 {
                                viewModel.debounceSearch(characterId: character.CharacterID, searchText: searchText, type: selectedSearchType)
                            }
                        }
                    
                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            List {
                // 过滤条件部分
                Section(header: Text(NSLocalizedString("Main_Search_Filter_Title", comment: ""))) {
                    filterView
                    
                    Button(action: clearFilters) {
                        Text(NSLocalizedString("Main_Search_Filter_Clear", comment: ""))
                            .foregroundColor(.red)
                    }
                    
                    if viewModel.hasMoreResults {
                        Button(action: {
                            Task {
                                await viewModel.loadMoreResults()
                            }
                        }) {
                            if viewModel.isSearching {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text(NSLocalizedString("Main_Search_Load_More_Status", comment: ""))
                                }
                            } else {
                                Text(NSLocalizedString("Main_Search_Load_More", comment: ""))
                            }
                        }
                        .disabled(viewModel.isSearching)
                    }
                }
                
                // 搜索结果部分
                if !searchText.isEmpty {
                    Section(header: Text(NSLocalizedString("Main_Search_Results", comment: ""))) {
                        if viewModel.isSearching {
                            HStack {
                                Spacer()
                                VStack(spacing: 8) {
                                    ProgressView()
                                    if !viewModel.searchingStatus.isEmpty {
                                        Text(viewModel.searchingStatus)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.vertical, 8)
                        } else if viewModel.error != nil {
                            HStack {
                                Spacer()
                                VStack {
                                    Image(systemName: "exclamationmark.triangle")
                                        .font(.largeTitle)
                                        .foregroundColor(.red)
                                    Text(NSLocalizedString("Main_Search_Failed", comment: ""))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                        } else if searchText.count <= 2 {
                            Text(NSLocalizedString("Main_Search_Min_Length", comment: ""))
                                .foregroundColor(.secondary)
                        } else if viewModel.filteredResults.isEmpty {
                            if viewModel.searchResults.isEmpty {
                                Text(NSLocalizedString("Main_Search_No_Results", comment: ""))
                                    .foregroundColor(.secondary)
                            } else {
                                Text(NSLocalizedString("Main_Search_No_Filtered_Results", comment: ""))
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            ForEach(viewModel.filteredResults) { result in
                                SearchResultRow(result: result)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Main_Search_Title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty || newValue.count <= 2 {
                viewModel.searchResults = []
                if !newValue.isEmpty {
                    viewModel.error = nil
                    viewModel.isSearching = false
                }
            } else {
                viewModel.debounceSearch(characterId: character.CharacterID, searchText: newValue, type: selectedSearchType)
            }
        }
        .onChange(of: corporationFilter) { _, _ in
            viewModel.filterResults(corporationFilter: corporationFilter, allianceFilter: allianceFilter)
        }
        .onChange(of: allianceFilter) { _, _ in
            viewModel.filterResults(corporationFilter: corporationFilter, allianceFilter: allianceFilter)
        }
    }
    
    @ViewBuilder
    private var filterView: some View {
        switch selectedSearchType {
        case .character:
            TextField(NSLocalizedString("Main_Search_Filter_Corporation", comment: ""), text: $corporationFilter)
            TextField(NSLocalizedString("Main_Search_Filter_Alliance", comment: ""), text: $allianceFilter)
        case .corporation:
            TextField(NSLocalizedString("Main_Search_Filter_Alliance", comment: ""), text: $allianceFilter)
            TextField(NSLocalizedString("Main_Search_Filter_Ticker", comment: ""), text: $tickerFilter)
        case .alliance:
            TextField(NSLocalizedString("Main_Search_Filter_Ticker", comment: ""), text: $tickerFilter)
        case .structure:
            Picker(NSLocalizedString("Main_Search_Filter_Security", comment: ""), selection: $selectedSecurityLevel) {
                ForEach(SecurityLevel.allCases, id: \.self) { level in
                    Text(level.localizedName).tag(level)
                }
            }
            
            Picker(NSLocalizedString("Main_Search_Filter_Structure_Type", comment: ""), selection: $selectedStructureType) {
                ForEach(StructureType.allCases, id: \.self) { type in
                    Text(type.localizedName).tag(type)
                }
            }
        }
    }
    
    private func clearFilters() {
        corporationFilter = ""
        allianceFilter = ""
        tickerFilter = ""
        selectedSecurityLevel = .all
        selectedStructureType = .all
        // 清除过滤器时重置过滤结果
        viewModel.filterResults(corporationFilter: "", allianceFilter: "")
    }
}

// 搜索结果行视图
struct SearchResultRow: View {
    let result: SearcherView.SearchResult
    
    var body: some View {
        HStack {
            UniversePortrait(id: result.id, type: result.type.recipientType, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.name)
                if let corpName = result.corporationName {
                    HStack(spacing: 4) {
                        Text(corpName)
                        if let allianceName = result.allianceName {
                            Text("•")
                                .foregroundColor(.secondary)
                            Text(allianceName)
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
        }
    }
}

// 视图模型
@MainActor
class SearcherViewModel: ObservableObject {
    @Published var searchResults: [SearcherView.SearchResult] = []
    @Published var filteredResults: [SearcherView.SearchResult] = []
    @Published var isSearching = false
    @Published var searchingStatus = ""
    @Published var error: Error?
    @Published var hasMoreResults = false
    
    private var searchTask: Task<Void, Never>?
    private var allCharacterIds: [Int] = [] // 存储所有搜索到的角色ID
    private var currentOffset = 0 // 当前加载的偏移量
    private let batchSize = 100 // 每批加载的数量
    private var characterNames: [Int: String] = [:] // 缓存所有角色名称
    
    // 添加属性来保存当前的过滤条件
    private var currentCorpFilter = ""
    private var currentAllianceFilter = ""
    
    // 直接从ESI获取名称的方法
    private func fetchNamesFromESI(ids: [Int]) async throws -> [Int: String] {
        let urlString = "https://esi.evetech.net/latest/universe/names/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        
        // 准备请求数据
        let jsonData = try JSONEncoder().encode(ids)
        
        // 发送POST请求
        let data = try await NetworkManager.shared.fetchData(
            from: url,
            method: "POST",
            body: jsonData
        )
        
        // 解析响应数据
        let responses = try JSONDecoder().decode([UniverseNameResponse].self, from: data)
        
        // 转换为字典
        var namesMap: [Int: String] = [:]
        for response in responses {
            namesMap[response.id] = response.name
        }
        
        return namesMap
    }
    
    // 直接从ESI获取角色公开信息的方法
    private func fetchCharacterInfoFromESI(characterId: Int) async throws -> CharacterPublicInfo {
        let urlString = "https://esi.evetech.net/latest/characters/\(characterId)/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        
        let data = try await NetworkManager.shared.fetchData(from: url)
        return try JSONDecoder().decode(CharacterPublicInfo.self, from: data)
    }
    
    func search(characterId: Int, searchText: String, type: SearcherView.SearchType) async {
        guard !searchText.isEmpty else {
            searchResults = []
            return
        }
        
        guard !isSearching else { return }
        
        isSearching = true
        searchingStatus = NSLocalizedString("Main_Search_Status_Searching", comment: "")
        defer { isSearching = false }
        
        do {
            error = nil
            currentOffset = 0 // 重置偏移量
            searchResults = [] // 清空当前结果
            
            switch type {
            case .character:
                searchingStatus = NSLocalizedString("Main_Search_Status_Finding_Characters", comment: "")
                let data = try await CharacterSearchAPI.shared.search(
                    characterId: characterId,
                    categories: [.character],
                    searchText: searchText
                )
                
                if Task.isCancelled { return }
                
                // 解析搜索结果
                let searchResponse = try JSONDecoder().decode(SearcherView.SearchResponse.self, from: data)
                
                if let characters = searchResponse.character {
                    allCharacterIds = characters // 保存所有角色ID
                    hasMoreResults = characters.count > batchSize
                    
                    // 一次性获取所有角色名称
                    searchingStatus = NSLocalizedString("Main_Search_Status_Loading_Names", comment: "")
                    characterNames = try await fetchNamesFromESI(ids: characters)
                    
                    // 获取前100个角色的详细信息
                    let initialBatch = Array(characters.prefix(batchSize))
                    
                    // 创建基本的搜索结果（使用已缓存的名称）
                    let basicResults = initialBatch.compactMap { id -> SearcherView.SearchResult? in
                        guard let name = characterNames[id] else { return nil }
                        return SearcherView.SearchResult(
                            id: id,
                            name: name,
                            type: .character
                        )
                    }.sorted { $0.name < $1.name }
                    
                    // 获取角色详细信息
                    searchingStatus = NSLocalizedString("Main_Search_Status_Loading_Details", comment: "")
                    let publicInfos = try await withThrowingTaskGroup(of: (Int, CharacterPublicInfo).self) { group in
                        for result in basicResults {
                            group.addTask {
                                let info = try await self.fetchCharacterInfoFromESI(characterId: result.id)
                                return (result.id, info)
                            }
                        }
                        
                        var infos: [Int: CharacterPublicInfo] = [:]
                        for try await (id, info) in group {
                            infos[id] = info
                        }
                        return infos
                    }
                    
                    if Task.isCancelled { return }
                    
                    // 收集军团和联盟ID
                    var corporationIds: Set<Int> = []
                    var allianceIds: Set<Int> = []
                    
                    for info in publicInfos.values {
                        corporationIds.insert(info.corporation_id)
                        if let allianceId = info.alliance_id {
                            allianceIds.insert(allianceId)
                        }
                    }
                    
                    // 获取军团和联盟名称
                    searchingStatus = NSLocalizedString("Main_Search_Status_Loading_Corps", comment: "")
                    let corpNames = try await fetchNamesFromESI(ids: Array(corporationIds))
                    
                    var initialResults: [SearcherView.SearchResult] = []
                    
                    if !allianceIds.isEmpty {
                        searchingStatus = NSLocalizedString("Main_Search_Status_Loading_Alliances", comment: "")
                        let allianceNames = try await fetchNamesFromESI(ids: Array(allianceIds))
                        
                        // 组装结果
                        for var result in basicResults {
                            if let publicInfo = publicInfos[result.id] {
                                result.corporationName = corpNames[publicInfo.corporation_id]
                                if let allianceId = publicInfo.alliance_id {
                                    result.allianceName = allianceNames[allianceId]
                                }
                                initialResults.append(result)
                            }
                        }
                    } else {
                        // 如果没有联盟，直接组装结果
                        for var result in basicResults {
                            if let publicInfo = publicInfos[result.id] {
                                result.corporationName = corpNames[publicInfo.corporation_id]
                                initialResults.append(result)
                            }
                        }
                    }
                    
                    if Task.isCancelled { return }
                    
                    // 更新结果
                    searchResults = initialResults
                    currentOffset = initialBatch.count
                    
                    // 应用当前的过滤条件
                    filterResults(corporationFilter: currentCorpFilter, allianceFilter: currentAllianceFilter)
                    
                    Logger.info("初始搜索完成，已加载 \(searchResults.count)/\(allCharacterIds.count) 个结果，过滤后显示 \(filteredResults.count) 个结果")
                    
                } else {
                    allCharacterIds = []
                    characterNames = [:]
                    searchResults = []
                    filteredResults = []
                    hasMoreResults = false
                }
                
            default:
                break
            }
            
        } catch {
            if error is CancellationError {
                Logger.debug("搜索任务被取消")
                return
            }
            Logger.error("搜索失败: \(error)")
            self.error = error
        }
        searchingStatus = ""
    }
    
    func loadMoreResults() async {
        guard !isSearching && hasMoreResults else { return }
        
        isSearching = true
        searchingStatus = NSLocalizedString("Main_Search_Load_More_Status", comment: "")
        defer { isSearching = false }
        
        do {
            // 获取下一批角色ID
            let endIndex = min(currentOffset + batchSize, allCharacterIds.count)
            let nextBatch = Array(allCharacterIds[currentOffset..<endIndex])
            
            // 创建基本的搜索结果（使用已缓存的名称）
            let basicResults = nextBatch.compactMap { id -> SearcherView.SearchResult? in
                guard let name = characterNames[id] else { return nil }
                return SearcherView.SearchResult(
                    id: id,
                    name: name,
                    type: .character
                )
            }.sorted { $0.name < $1.name }
            
            // 获取角色详细信息
            searchingStatus = NSLocalizedString("Main_Search_Status_Loading_Details", comment: "")
            let publicInfos = try await withThrowingTaskGroup(of: (Int, CharacterPublicInfo).self) { group in
                for result in basicResults {
                    group.addTask {
                        let info = try await self.fetchCharacterInfoFromESI(characterId: result.id)
                        return (result.id, info)
                    }
                }
                
                var infos: [Int: CharacterPublicInfo] = [:]
                for try await (id, info) in group {
                    infos[id] = info
                }
                return infos
            }
            
            if Task.isCancelled { return }
            
            // 收集军团和联盟ID
            var corporationIds: Set<Int> = []
            var allianceIds: Set<Int> = []
            
            for info in publicInfos.values {
                corporationIds.insert(info.corporation_id)
                if let allianceId = info.alliance_id {
                    allianceIds.insert(allianceId)
                }
            }
            
            // 获取军团和联盟名称
            searchingStatus = NSLocalizedString("Main_Search_Status_Loading_Corps", comment: "")
            let corpNames = try await fetchNamesFromESI(ids: Array(corporationIds))
            
            var newResults: [SearcherView.SearchResult] = []
            
            if !allianceIds.isEmpty {
                searchingStatus = NSLocalizedString("Main_Search_Status_Loading_Alliances", comment: "")
                let allianceNames = try await fetchNamesFromESI(ids: Array(allianceIds))
                
                // 组装结果
                for var result in basicResults {
                    if let publicInfo = publicInfos[result.id] {
                        result.corporationName = corpNames[publicInfo.corporation_id]
                        if let allianceId = publicInfo.alliance_id {
                            result.allianceName = allianceNames[allianceId]
                        }
                        newResults.append(result)
                    }
                }
            } else {
                // 如果没有联盟，直接组装结果
                for var result in basicResults {
                    if let publicInfo = publicInfos[result.id] {
                        result.corporationName = corpNames[publicInfo.corporation_id]
                        newResults.append(result)
                    }
                }
            }
            
            if Task.isCancelled { return }
            
            // 更新结果
            searchResults.append(contentsOf: newResults)
            currentOffset = endIndex
            hasMoreResults = currentOffset < allCharacterIds.count
            
            // 应用当前的过滤条件
            filterResults(corporationFilter: currentCorpFilter, allianceFilter: currentAllianceFilter)
            
            Logger.info("加载更多完成，当前已加载 \(searchResults.count)/\(allCharacterIds.count) 个结果，过滤后显示 \(filteredResults.count) 个结果")
            
        } catch {
            if error is CancellationError {
                Logger.debug("加载更多任务被取消")
                return
            }
            Logger.error("加载更多失败: \(error)")
            self.error = error
        }
        searchingStatus = ""
    }
    
    // 添加过滤方法
    func filterResults(corporationFilter: String, allianceFilter: String) {
        // 保存当前的过滤条件
        currentCorpFilter = corporationFilter
        currentAllianceFilter = allianceFilter
        
        let corpFilter = corporationFilter.lowercased()
        let allianceFilter = allianceFilter.lowercased()
        
        if corpFilter.isEmpty && allianceFilter.isEmpty {
            // 如果没有过滤条件，显示所有结果
            filteredResults = searchResults
        } else {
            // 根据过滤条件筛选结果
            filteredResults = searchResults.filter { result in
                let matchCorp = corpFilter.isEmpty || 
                    (result.corporationName?.lowercased().contains(corpFilter) ?? false)
                let matchAlliance = allianceFilter.isEmpty || 
                    (result.allianceName?.lowercased().contains(allianceFilter) ?? false)
                return matchCorp && matchAlliance
            }
        }
        
        Logger.debug("过滤结果：原有 \(searchResults.count) 个结果，过滤后剩余 \(filteredResults.count) 个结果")
    }
    
    func debounceSearch(characterId: Int, searchText: String, type: SearcherView.SearchType) {
        searchTask?.cancel()
        
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            if Task.isCancelled { return }
            await search(characterId: characterId, searchText: searchText, type: type)
        }
    }
}
