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
    let securityLevel: SearcherView.SecurityLevel
    let structureType: SearcherView.StructureType
    
    func search() async throws {
        guard !searchText.isEmpty else { return }
        
        Logger.debug("开始搜索建筑，关键词: \(searchText)")
        searchingStatus = NSLocalizedString("Main_Search_Status_Finding_Characters", comment: "")
        
        // 使用CharacterSearchAPI进行搜索
        let data = try await CharacterSearchAPI.shared.search(
            characterId: characterId,
            categories: [.station, .structure],
            searchText: searchText
        )
        
        // 打印响应结果
        if let responseString = String(data: data, encoding: .utf8) {
            Logger.debug("搜索响应结果: \(responseString)")
        }
        
        let response = try JSONDecoder().decode(SearcherView.SearchResponse.self, from: data)
        
        // 获取建筑ID列表
        var allIds: [Int] = []
        var idToType: [Int: SearcherView.StructureType] = [:]
        
        // 处理空间站
        if let stationIds = response.station {
            allIds.append(contentsOf: stationIds)
            for id in stationIds {
                idToType[id] = .station
            }
            Logger.debug("找到 \(stationIds.count) 个空间站")
            Logger.debug("空间站ID列表: \(stationIds.map { String($0) }.joined(separator: ", "))")
        }
        
        // 处理建筑物
        if let structureIds = response.structure {
            allIds.append(contentsOf: structureIds)
            for id in structureIds {
                idToType[id] = .structure
            }
            Logger.debug("找到 \(structureIds.count) 个建筑物")
            Logger.debug("建筑物ID列表: \(structureIds.map { String($0) }.joined(separator: ", "))")
        }
        
        guard !allIds.isEmpty else {
            Logger.debug("未找到任何建筑")
            searchResults = []
            filteredResults = []
            return
        }
        
        // 获取建筑名称
        searchingStatus = NSLocalizedString("Main_Search_Status_Loading_Names", comment: "")
        let namesResponse = try await UniverseAPI.shared.getNamesWithFallback(ids: allIds)
        Logger.debug("成功获取 \(namesResponse.count) 个建筑的名称")
        
        // 创建搜索结果
        var results = allIds.compactMap { id -> SearcherView.SearchResult? in
            guard let nameInfo = namesResponse[id],
                  let type = idToType[id] else { return nil }
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
        Logger.debug("- 安全等级: \(securityLevel)")
        Logger.debug("- 建筑类型: \(structureType)")
        
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
