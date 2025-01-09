import SwiftUI

struct CorporationSearchView: View {
    let characterId: Int
    let searchText: String
    @Binding var searchResults: [SearcherView.SearchResult]
    @Binding var filteredResults: [SearcherView.SearchResult]
    @Binding var searchingStatus: String
    @Binding var error: Error?
    
    var body: some View {
        EmptyView() // 这里不需要UI，因为UI在主搜索视图中
    }
    
    func search() async {
        do {
            searchingStatus = NSLocalizedString("Main_Search_Status_Finding_Corporations", comment: "")
            let data = try await CharacterSearchAPI.shared.search(
                characterId: characterId,
                categories: [.corporation],
                searchText: searchText
            )
            
            if Task.isCancelled { return }
            
            // 解析搜索结果
            let searchResponse = try JSONDecoder().decode(SearcherView.SearchResponse.self, from: data)
            
            if let corporations = searchResponse.corporation {
                // 获取军团名称
                searchingStatus = NSLocalizedString("Main_Search_Status_Loading_Names", comment: "")
                
                // 获取军团基本信息
                let corporationNamesWithCategories = try await UniverseAPI.shared.getNamesWithFallback(ids: corporations)
                
                // 创建搜索结果
                let results = corporations.compactMap { corpId -> SearcherView.SearchResult? in
                    guard let info = corporationNamesWithCategories[corpId] else { return nil }
                    return SearcherView.SearchResult(
                        id: corpId,
                        name: info.name,
                        type: .corporation
                    )
                }.sorted { result1, result2 in
                    // 检查是否以搜索文本开头
                    let searchTextLower = searchText.lowercased()
                    let name1Lower = result1.name.lowercased()
                    let name2Lower = result2.name.lowercased()
                    
                    let starts1 = name1Lower.hasPrefix(searchTextLower)
                    let starts2 = name2Lower.hasPrefix(searchTextLower)
                    
                    if starts1 != starts2 {
                        return starts1 // 以搜索文本开头的排在前面
                    }
                    return result1.name < result2.name // 其次按字母顺序排序
                }
                
                searchResults = results
                filteredResults = searchResults // 对于军团搜索，不进行二次过滤
            } else {
                searchResults = []
                filteredResults = []
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
} 