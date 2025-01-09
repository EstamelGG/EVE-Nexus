import SwiftUI

@MainActor
struct StructureSearchView {
    let characterId: Int
    let searchText: String
    @Binding var searchResults: [SearcherView.SearchResult]
    @Binding var filteredResults: [SearcherView.SearchResult]
    @Binding var searchingStatus: String
    @Binding var isSearching: Bool
    @Binding var error: Error?
    let locationFilter: String
    let securityLevel: SearcherView.SecurityLevel
    let structureType: SearcherView.StructureType
    
    func search() async throws {
        guard !searchText.isEmpty else { return }
        
        Logger.debug("开始搜索建筑，关键词: \(searchText)")
        searchingStatus = NSLocalizedString("Main_Search_Status_Finding_Characters", comment: "")
        
        // 构建搜索URL
        let encodedSearch = searchText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://esi.evetech.net/latest/search/?categories=structure&search=\(encodedSearch)&strict=false"
        
        guard let url = URL(string: urlString) else {
            Logger.error("无效的URL: \(urlString)")
            throw NetworkError.invalidURL
        }
        
        // 发送搜索请求
        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId
        )
        let response = try JSONDecoder().decode(SearcherView.SearchResponse.self, from: data)
        
        // 获取建筑ID列表
        guard let structureIds = response.structure else {
            Logger.debug("未找到任何建筑")
            searchResults = []
            filteredResults = []
            return
        }
        
        Logger.debug("找到 \(structureIds.count) 个建筑")
        
        // 获取建筑名称
        searchingStatus = NSLocalizedString("Main_Search_Status_Loading_Names", comment: "")
        let namesResponse = try await UniverseAPI.shared.getNamesWithFallback(ids: structureIds)
        Logger.debug("成功获取 \(namesResponse.count) 个建筑的名称")
        
        // 创建搜索结果
        var results = structureIds.compactMap { id -> SearcherView.SearchResult? in
            guard let nameInfo = namesResponse[id] else { return nil }
            return SearcherView.SearchResult(id: id, name: nameInfo.name, type: .structure)
        }
        
        Logger.debug("成功创建 \(results.count) 个搜索结果")
        
        // 按名称排序，优先显示以搜索文本开头的结果
        results.sort { result1, result2 in
            let name1 = result1.name.lowercased()
            let name2 = result2.name.lowercased()
            let searchTextLower = searchText.lowercased()
            
            let starts1 = name1.starts(with: searchTextLower)
            let starts2 = name2.starts(with: searchTextLower)
            
            if starts1 != starts2 {
                return starts1
            }
            return name1 < name2
        }
        
        // 应用过滤器
        searchResults = results
        applyFilters()
        
        Logger.debug("建筑搜索完成，过滤前: \(results.count) 个结果，过滤后: \(filteredResults.count) 个结果")
        
        // 打印前5个结果的详细信息
        if !results.isEmpty {
            Logger.debug("前 \(min(5, results.count)) 个搜索结果:")
            for (index, result) in results.prefix(5).enumerated() {
                Logger.debug("\(index + 1). ID: \(result.id), 名称: \(result.name)")
            }
        }
    }
    
    private func applyFilters() {
        var filtered = searchResults
        
        Logger.debug("开始应用过滤器:")
        Logger.debug("- 地点过滤: \(locationFilter.isEmpty ? "无" : locationFilter)")
        Logger.debug("- 安全等级: \(securityLevel)")
        Logger.debug("- 建筑类型: \(structureType)")
        
        // 应用地点过滤
        if !locationFilter.isEmpty {
            filtered = filtered.filter { result in
                // TODO: 实现地点过滤逻辑
                // 需要获取建筑的位置信息并与过滤条件匹配
                return true
            }
            Logger.debug("应用地点过滤后剩余: \(filtered.count) 个结果")
        }
        
        // 应用安全等级过滤
        if securityLevel != .all {
            filtered = filtered.filter { result in
                // TODO: 实现安全等级过滤逻辑
                // 需要获取建筑所在星系的安全等级并与过滤条件匹配
                return true
            }
            Logger.debug("应用安全等级过滤后剩余: \(filtered.count) 个结果")
        }
        
        // 应用建筑类型过滤
        if structureType != .all {
            filtered = filtered.filter { result in
                // TODO: 实现建筑类型过滤逻辑
                // 需要获取建筑类型信息并与过滤条件匹配
                return true
            }
            Logger.debug("应用建筑类型过滤后剩余: \(filtered.count) 个结果")
        }
        
        filteredResults = filtered
    }
} 
