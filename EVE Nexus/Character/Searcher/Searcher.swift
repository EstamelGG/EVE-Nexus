import SwiftUI

struct SearcherView: View {
    let character: EVECharacterInfo
    @State private var searchText = ""
    @State private var selectedSearchType = SearchType.character
    @State private var isSearching = false
    
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
                            performSearch()
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
            
            // 过滤条件部分
            List {
                Section(header: Text(NSLocalizedString("Main_Search_Filter_Title", comment: ""))) {
                    filterView
                    
                    Button(action: clearFilters) {
                        Text(NSLocalizedString("Main_Search_Filter_Clear", comment: ""))
                            .foregroundColor(.red)
                    }
                }
            }
            
            if isSearching {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .padding()
            }
        }
        .navigationTitle(NSLocalizedString("Main_Search_Title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
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
    
    private func performSearch() {
        guard !searchText.isEmpty else { return }
        isSearching = true
        
        // TODO: 实现搜索逻辑
        Task {
            do {
                switch selectedSearchType {
                case .character:
                    // 搜索人物
                    break
                case .corporation:
                    // 搜索军团
                    break
                case .alliance:
                    // 搜索联盟
                    break
                case .structure:
                    // 搜索建筑与空间站
                    break
                }
            } catch {
                Logger.error("搜索失败: \(error)")
            }
            
            isSearching = false
        }
    }
}
