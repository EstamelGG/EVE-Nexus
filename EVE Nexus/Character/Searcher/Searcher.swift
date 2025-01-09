import SwiftUI

struct SearcherView: View {
    let character: EVECharacterInfo
    @StateObject private var viewModel = SearcherViewModel()
    @State private var searchText = ""
    @State private var selectedSearchType = SearchType.character
    @State private var isLoadingContacts = true
    @State private var loadingError: Error?
    @State private var hasLoadedContacts = false
    
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
        var allianceId: Int?
        var corporationId: Int?
        var structureType: StructureType?
        var locationInfo: (security: Double, systemName: String, regionName: String)?
        var typeInfo: String? // 图标文件名
        var additionalInfo: String?
        
        init(id: Int, name: String, type: SearchType, structureType: StructureType? = nil,
             locationInfo: (security: Double, systemName: String, regionName: String)? = nil,
             typeInfo: String? = nil,
             additionalInfo: String? = nil,
             allianceId: Int? = nil,
             corporationId: Int? = nil) {
            self.id = id
            self.name = name
            self.type = type
            self.structureType = structureType
            self.locationInfo = locationInfo
            self.typeInfo = typeInfo
            self.additionalInfo = additionalInfo
            self.allianceId = allianceId
            self.corporationId = corporationId
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
                        if !viewModel.searchingStatus.isEmpty {
                            HStack {
                                Spacer()
                                VStack(spacing: 8) {
                                    Text(viewModel.searchingStatus)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
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
                                NavigationLink(destination: {
                                    if result.type == .character {
                                        CharacterDetailView(characterId: result.id)
                                    } else {
                                        SearchResultRow(result: result, character: character)
                                    }
                                }) {
                                    SearchResultRow(result: result, character: character)
                                }
                                .buttonStyle(.plain)
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                        }
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Main_Search_Title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isLoadingContacts {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.8)
                } else if loadingError != nil {
                    Button(action: {
                        Task {
                            isLoadingContacts = true
                            hasLoadedContacts = false
                            await loadContactsData()
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .onAppear {
            if !hasLoadedContacts {
                Task {
                    await loadContactsData()
                }
            }
        }
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty || newValue.count <= 2 {
                viewModel.searchResults = []
                if !newValue.isEmpty {
                    viewModel.error = nil
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
    
    private func loadContactsData() async {
        guard !hasLoadedContacts else { return }
        
        do {
            // 并行加载所有联系人数据
            async let characterContacts = GetCharContacts.shared.fetchContacts(characterId: character.CharacterID)
            async let corporationContacts = GetCorpContacts.shared.fetchContacts(characterId: character.CharacterID, corporationId: character.corporationId ?? 0)
            
            // 如果角色有联盟，也加载联盟联系人
            if let allianceId = character.allianceId {
                async let allianceContacts = GetAllianceContacts.shared.fetchContacts(characterId: character.CharacterID, allianceId: allianceId)
                _ = try await [characterContacts, corporationContacts, allianceContacts]
            } else {
                _ = try await [characterContacts, corporationContacts]
            }
            
            await MainActor.run {
                isLoadingContacts = false
                loadingError = nil
                hasLoadedContacts = true
            }
        } catch {
            await MainActor.run {
                isLoadingContacts = false
                loadingError = error
                Logger.error("加载联系人数据失败: \(error)")
            }
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
    @State private var allianceName: String?
    @State private var isLoadingAlliance = false
    @State private var allianceId: Int?
    @State private var isLoadingCorpInfo = false
    @State private var hasAttemptedCorpInfoLoad = false
    @State private var hasAttemptedAllianceLoad = false
    @State private var loadTask: Task<Void, Never>?
    @State private var standingIcon: String = "ColorTag-Neutral"
    
    private func determineStandingIcon() async {
        // 1. 检查是否同军团
        if let corpId = character.corporationId,
           let resultCorpId = (result.type == .character ? result.corporationId : (result.type == .corporation ? result.id : nil)),
           corpId == resultCorpId {
            standingIcon = "ColorTag-StarGreen9"
            return
        }
        
        // 2. 检查是否同联盟
        if let allianceId = character.allianceId,
           let resultAllianceId = (result.type == .character ? result.allianceId : (result.type == .alliance ? result.id : nil)),
           allianceId == resultAllianceId {
            standingIcon = "ColorTag-StarBlue9"
            return
        }
        
        // 3. 检查联盟声望
        if let allianceId = character.allianceId {
            if let contacts = try? await GetAllianceContacts.shared.fetchContacts(characterId: character.CharacterID, allianceId: allianceId),
               let contact = contacts.first(where: { $0.contact_id == result.id }) {
                standingIcon = getStandingIcon(standing: contact.standing)
                return
            }
        }
        
        // 4. 检查军团声望
        if let corpId = character.corporationId {
            if let contacts = try? await GetCorpContacts.shared.fetchContacts(characterId: character.CharacterID, corporationId: corpId),
               let contact = contacts.first(where: { $0.contact_id == result.id }) {
                standingIcon = getStandingIcon(standing: contact.standing)
                return
            }
        }
        
        // 5. 检查个人声望
        if let contacts = try? await GetCharContacts.shared.fetchContacts(characterId: character.CharacterID),
           let contact = contacts.first(where: { $0.contact_id == result.id }) {
            standingIcon = getStandingIcon(standing: contact.standing)
            return
        }
        
        // 默认图标
        standingIcon = "ColorTag-Neutral"
    }
    
    private func getStandingIcon(standing: Double) -> String {
        let standingValues = [-10.0, -5.0, 0.0, 5.0, 10.0]
        let icons = ["ColorTag-MinusRed9", "ColorTag-MinusOrange9", "ColorTag-Neutral", "ColorTag-PlusLightBlue9", "ColorTag-PlusDarkBlue9"]
        
        // 找到最接近的声望值
        var closestIndex = 0
        var minDiff = abs(standing - standingValues[0])
        
        for (index, value) in standingValues.enumerated() {
            let diff = abs(standing - value)
            if diff < minDiff {
                minDiff = diff
                closestIndex = index
            }
        }
        
        return icons[closestIndex]
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // 头像/图标
            if let iconFilename = result.typeInfo {
                IconManager.shared.loadImage(for: iconFilename)
                    .resizable()
                    .frame(width: 38, height: 38)
                    .cornerRadius(6)
            } else {
                UniversePortrait(id: result.id, type: result.type.recipientType, size: 32)
                    .frame(width: 38, height: 38)
                    .cornerRadius(6)
            }
            
            // 信息
            VStack(alignment: .leading, spacing: 2) {
                // 第一行：名称
                Text(result.name)
                    .font(.body)
                
                // 第二行：军团和联盟信息
                if result.type == .character {
                    if let corpName = result.corporationName {
                        Text(corpName)
                            .foregroundColor(.secondary)
                            .font(.caption)
                    } else {
                        Text("[No Corp]")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    if let allianceName = result.allianceName {
                        Text("\(allianceName)")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    } else {
                        Text("[No Alliance]")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                } else if result.type == .corporation {
                    // 军团搜索时显示联盟信息
                    if let allianceName = allianceName {
                        Text("[\(allianceName)]")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
                
                // 第三行：位置信息（仅建筑搜索时显示）
                if let locationInfo = result.locationInfo {
                    HStack(spacing: 4) {
                        // 安全等级
                        Text(formatSystemSecurity(locationInfo.security))
                            .foregroundColor(getSecurityColor(locationInfo.security))
                        
                        // 星系名
                        Text("\(locationInfo.systemName) / \(locationInfo.regionName)")
                            .foregroundColor(.secondary)
                    }
                    .font(.caption)
                }
            }
            
            Spacer()
            
            // 声望图标
            ZStack {
                // 前景图标
                Image(standingIcon)
                    .resizable()
                    .frame(width: 12, height: 12)
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            scheduleLoad()
            // 加载声望图标
            Task {
                await determineStandingIcon()
            }
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }
    
    private func scheduleLoad() {
        loadTask?.cancel()
        loadTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms delay
            if !Task.isCancelled {
                // 只有当结果类型是军团时才加载军团信息
                if result.type == .corporation && !hasAttemptedCorpInfoLoad {
                    await loadCorporationInfo()
                }
                // 只有当有联盟ID且结果类型不是建筑时才加载联盟信息
                if allianceId != nil && result.type != .structure && !hasAttemptedAllianceLoad {
                    await loadAllianceName()
                }
            }
        }
    }
    
    private func loadCorporationInfo() async {
        guard !isLoadingCorpInfo && !hasAttemptedCorpInfoLoad else { return }
        
        isLoadingCorpInfo = true
        hasAttemptedCorpInfoLoad = true
        do {
            if let corpInfo = try? await CorporationAPI.shared.fetchCorporationInfo(corporationId: result.id) {
                if !Task.isCancelled {
                    await MainActor.run {
                        self.allianceId = corpInfo.alliance_id
                    }
                }
            }
        } catch {
            Logger.error("加载军团信息失败: \(error)")
        }
        isLoadingCorpInfo = false
    }
    
    private func loadAllianceName() async {
        guard let allianceId = allianceId, !isLoadingAlliance && !hasAttemptedAllianceLoad else { return }
        
        isLoadingAlliance = true
        hasAttemptedAllianceLoad = true
        do {
            let allianceNamesWithCategories = try await UniverseAPI.shared.getNamesWithFallback(ids: [allianceId])
            if let allianceName = allianceNamesWithCategories[allianceId]?.name {
                if !Task.isCancelled {
                    await MainActor.run {
                        self.allianceName = allianceName
                    }
                }
            }
        } catch {
            Logger.error("加载联盟名称失败: \(error)")
        }
        isLoadingAlliance = false
    }
}

// 视图模型
@MainActor
class SearcherViewModel: ObservableObject {
    @Published var searchResults: [SearcherView.SearchResult] = []
    @Published var filteredResults: [SearcherView.SearchResult] = []
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
        
        searchingStatus = NSLocalizedString("Main_Search_Status_Searching", comment: "")
        
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
        
        // 根据建筑类型过滤结果
        if structureType == .all {
            filteredResults = searchResults
        } else {
            filteredResults = searchResults.filter { result in
                result.structureType == structureType
            }
        }
    }
}



