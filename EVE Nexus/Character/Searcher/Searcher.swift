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
        var structureType: StructureType?
        var locationInfo: (security: Double, systemName: String, regionName: String)?
        var typeInfo: String? // 图标文件名
        
        init(id: Int, name: String, type: SearchType, structureType: StructureType? = nil, 
             locationInfo: (security: Double, systemName: String, regionName: String)? = nil, 
             typeInfo: String? = nil) {
            self.id = id
            self.name = name
            self.type = type
            self.structureType = structureType
            self.locationInfo = locationInfo
            self.typeInfo = typeInfo
        }
    }
    
    // 搜索响应数据结构
    struct SearchResponse: Codable {
        let character: [Int]?
        let corporation: [Int]?
        let alliance: [Int]?
        let station: [Int]?
        let structure: [Int]?
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
            .onChange(of: selectedSearchType) { _, _ in
                // 清空搜索结果和状态
                viewModel.searchResults = []
                viewModel.filteredResults = []
                viewModel.error = nil
                viewModel.isSearching = false
                viewModel.searchingStatus = ""
                
                // 如果有搜索文本，则重新搜索
                if !searchText.isEmpty && searchText.count > 2 {
                    viewModel.debounceSearch(characterId: character.CharacterID, searchText: searchText, type: selectedSearchType)
                }
            }
            
            // 搜索框
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField(NSLocalizedString("Main_Search_Placeholder", comment: ""), text: $searchText)
                        .submitLabel(.search)
                    
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
                // 过滤条件部分，只在角色搜索和建筑搜索时显示
                if selectedSearchType == .character || selectedSearchType == .structure {
                    Section(header: Text(NSLocalizedString("Main_Search_Filter_Title", comment: ""))) {
                        filterView
                        
                        if selectedSearchType == .character {
                            Button(action: clearFilters) {
                                Text(NSLocalizedString("Main_Search_Filter_Clear", comment: ""))
                                    .foregroundColor(.red)
                            }
                        }
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
                                SearchResultRow(result: result, character: character)
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
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
        .onChange(of: selectedStructureType) { _, _ in
            viewModel.updateStructureFilters(
                structureType: selectedStructureType
            )
        }
    }
    
    @ViewBuilder
    private var filterView: some View {
        switch selectedSearchType {
        case .character:
            TextField(NSLocalizedString("Main_Search_Filter_Corporation", comment: ""), text: $corporationFilter)
            TextField(NSLocalizedString("Main_Search_Filter_Alliance", comment: ""), text: $allianceFilter)
        case .corporation:
            EmptyView()
        case .alliance:
            EmptyView()
        case .structure:
            Picker(NSLocalizedString("Main_Search_Filter_Structure_Type", comment: ""), selection: $selectedStructureType) {
                ForEach(StructureType.allCases, id: \.self) { type in
                    Text(type.localizedName).tag(type)
                }
            }
            
            Button(action: clearFilters) {
                Text(NSLocalizedString("Main_Search_Filter_Clear", comment: ""))
                    .foregroundColor(.red)
            }
        }
    }
    
    private func clearFilters() {
        corporationFilter = ""
        allianceFilter = ""
        tickerFilter = ""
        selectedStructureType = .all
        // 清除过滤器时重置过滤结果
        viewModel.filterResults(corporationFilter: "", allianceFilter: "")
    }
}

// 搜索结果行视图
struct SearchResultRow: View {
    let result: SearcherView.SearchResult
    let character: EVECharacterInfo
    
    var body: some View {
        HStack(spacing: 12) {
            // 建筑图标
            if let iconFilename = result.typeInfo {
                IconManager.shared.loadImage(for: iconFilename)
                    .resizable()
                    .frame(width: 36, height: 36)
                    .cornerRadius(6)
            } else {
                UniversePortrait(id: result.id, type: result.type.recipientType, size: 32)
            }
            
            // 建筑信息
            VStack(alignment: .leading, spacing: 4) {
                // 第一行：建筑名称
                Text(result.name)
                    .font(.body)
                
                // 第二行：位置信息
                if let locationInfo = result.locationInfo {
                    HStack(spacing: 4) {
                        // 安全等级
                        Text(formatSystemSecurity(locationInfo.security))
                            .foregroundColor(getSecurityColor(locationInfo.security))
                        
                        // 星系名
                        Text(locationInfo.systemName)
                            .foregroundColor(.secondary)
                        
                        Text("•")
                            .foregroundColor(.secondary)
                        
                        // 星域名
                        Text(locationInfo.regionName)
                            .foregroundColor(.secondary)
                    }
                    .font(.caption)
                }
            }
        }
        .padding(.vertical, 4)
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
    
    private var searchTask: Task<Void, Never>?
    private var currentCorpFilter = ""
    private var currentAllianceFilter = ""
    private var currentStructureType: SearcherView.StructureType = SearcherView.StructureType.all
    private var corporationNames: [Int: String] = [:]
    private var allianceNames: [Int: String] = [:]
    
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
            searchResults = [] // 清空当前结果
            
            switch type {
            case .character:
                let characterSearch = CharacterSearchView(
                    characterId: characterId,
                    searchText: searchText,
                    searchResults: Binding(
                        get: { self.searchResults },
                        set: { self.searchResults = $0 }
                    ),
                    filteredResults: Binding(
                        get: { self.filteredResults },
                        set: { self.filteredResults = $0 }
                    ),
                    searchingStatus: Binding(
                        get: { self.searchingStatus },
                        set: { self.searchingStatus = $0 }
                    ),
                    isSearching: Binding(
                        get: { self.isSearching },
                        set: { self.isSearching = $0 }
                    ),
                    error: Binding(
                        get: { self.error },
                        set: { self.error = $0 }
                    ),
                    corporationFilter: currentCorpFilter,
                    allianceFilter: currentAllianceFilter
                )
                try await characterSearch.search()
                
            case .corporation:
                let corporationSearch = CorporationSearchView(
                    characterId: characterId,
                    searchText: searchText,
                    searchResults: Binding(
                        get: { self.searchResults },
                        set: { self.searchResults = $0 }
                    ),
                    filteredResults: Binding(
                        get: { self.filteredResults },
                        set: { self.filteredResults = $0 }
                    ),
                    searchingStatus: Binding(
                        get: { self.searchingStatus },
                        set: { self.searchingStatus = $0 }
                    ),
                    isSearching: Binding(
                        get: { self.isSearching },
                        set: { self.isSearching = $0 }
                    ),
                    error: Binding(
                        get: { self.error },
                        set: { self.error = $0 }
                    )
                )
                try await corporationSearch.search()
                
            case .alliance:
                let allianceSearch = AllianceSearchView(
                    characterId: characterId,
                    searchText: searchText,
                    searchResults: Binding(
                        get: { self.searchResults },
                        set: { self.searchResults = $0 }
                    ),
                    filteredResults: Binding(
                        get: { self.filteredResults },
                        set: { self.filteredResults = $0 }
                    ),
                    searchingStatus: Binding(
                        get: { self.searchingStatus },
                        set: { self.searchingStatus = $0 }
                    ),
                    isSearching: Binding(
                        get: { self.isSearching },
                        set: { self.isSearching = $0 }
                    ),
                    error: Binding(
                        get: { self.error },
                        set: { self.error = $0 }
                    )
                )
                try await allianceSearch.search()
                
            case .structure:
                let structureSearch = StructureSearchView(
                    characterId: characterId,
                    searchText: searchText,
                    searchResults: Binding(
                        get: { self.searchResults },
                        set: { self.searchResults = $0 }
                    ),
                    filteredResults: Binding(
                        get: { self.filteredResults },
                        set: { self.filteredResults = $0 }
                    ),
                    searchingStatus: Binding(
                        get: { self.searchingStatus },
                        set: { self.searchingStatus = $0 }
                    ),
                    isSearching: Binding(
                        get: { self.isSearching },
                        set: { self.isSearching = $0 }
                    ),
                    error: Binding(
                        get: { self.error },
                        set: { self.error = $0 }
                    ),
                    structureType: currentStructureType
                )
                try await structureSearch.search()
                
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
    
    func updateStructureFilters(structureType: SearcherView.StructureType) {
        currentStructureType = structureType
    }
}



