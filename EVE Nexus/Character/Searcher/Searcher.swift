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
                }
                
                // 搜索结果部分
                if !searchText.isEmpty {
                    Section(header: Text(NSLocalizedString("Main_Search_Results", comment: ""))) {
                        if viewModel.isSearching {
                            HStack {
                                Spacer()
                                ProgressView()
                                Text(NSLocalizedString("Main_Search_Searching", comment: ""))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
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
                        } else if viewModel.searchResults.isEmpty {
                            Text(NSLocalizedString("Main_Search_No_Results", comment: ""))
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(viewModel.searchResults) { result in
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
    }
}

// 搜索结果行视图
struct SearchResultRow: View {
    let result: SearcherView.SearchResult
    
    var body: some View {
        HStack {
            UniversePortrait(id: result.id, type: result.type.recipientType, size: 32)
            VStack(alignment: .leading) {
                Text(result.name)
                Text(result.type.localizedName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// 视图模型
@MainActor
class SearcherViewModel: ObservableObject {
    @Published var searchResults: [SearcherView.SearchResult] = []
    @Published var isSearching = false
    @Published var error: Error?
    
    private var searchTask: Task<Void, Never>?
    
    func debounceSearch(characterId: Int, searchText: String, type: SearcherView.SearchType) {
        searchTask?.cancel()
        
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            if Task.isCancelled { return }
            await search(characterId: characterId, searchText: searchText, type: type)
        }
    }
    
    func search(characterId: Int, searchText: String, type: SearcherView.SearchType) async {
        guard !searchText.isEmpty else {
            searchResults = []
            return
        }
        
        guard !isSearching else { return }
        
        isSearching = true
        defer { isSearching = false }
        
        do {
            error = nil
            
            switch type {
            case .character:
                let data = try await CharacterSearchAPI.shared.search(
                    characterId: characterId,
                    categories: [.character],
                    searchText: searchText
                )
                
                if Task.isCancelled { return }
                
                // 解析搜索结果
                let searchResponse = try JSONDecoder().decode(SearcherView.SearchResponse.self, from: data)
                var results: [SearcherView.SearchResult] = []
                
                if let characters = searchResponse.character {
                    let characterNames = try await UniverseAPI.shared.getNamesWithFallback(ids: characters)
                    results.append(contentsOf: characters.compactMap { id in
                        guard let info = characterNames[id] else { return nil }
                        return SearcherView.SearchResult(id: id, name: info.name, type: .character)
                    })
                }
                
                if Task.isCancelled { return }
                
                results.sort { $0.name < $1.name }
                searchResults = results
                Logger.info("搜索完成，找到 \(results.count) 个结果")
            default:
                break // 其他类型的搜索暂未实现
            }
            
        } catch {
            if error is CancellationError {
                Logger.debug("搜索任务被取消")
                return
            }
            Logger.error("搜索失败: \(error)")
            self.error = error
        }
    }
}
