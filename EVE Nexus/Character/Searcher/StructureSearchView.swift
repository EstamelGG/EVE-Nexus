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
        
        // 分别存储空间站和建筑物ID
        var stationIds: [Int] = []
        var structureIds: [Int] = []
        
        // 处理空间站
        if let stations = response.station {
            stationIds = stations
            Logger.debug("找到 \(stations.count) 个空间站")
            Logger.debug("空间站ID列表: \(stations.map { String($0) }.joined(separator: ", "))")
        }
        
        // 处理建筑物
        if let structures = response.structure {
            structureIds = structures
            Logger.debug("找到 \(structures.count) 个建筑物")
            Logger.debug("建筑物ID列表: \(structures.map { String($0) }.joined(separator: ", "))")
        }
        
        // 根据过滤条件选择要处理的ID
        var idsToProcess: [Int] = []
        var typeToProcess: SearcherView.StructureType = .all
        
        switch structureType {
        case .all:
            idsToProcess = stationIds + structureIds
            typeToProcess = .all
        case .station:
            idsToProcess = stationIds
            typeToProcess = .station
        case .structure:
            idsToProcess = structureIds
            typeToProcess = .structure
        }
        
        guard !idsToProcess.isEmpty else {
            Logger.debug("根据过滤条件，没有需要处理的建筑")
            searchResults = []
            filteredResults = []
            return
        }
        
        // 获取建筑名称
        searchingStatus = NSLocalizedString("Main_Search_Status_Loading_Names", comment: "")
        let namesResponse = try await UniverseAPI.shared.getNamesWithFallback(ids: idsToProcess)
        Logger.debug("成功获取 \(namesResponse.count) 个建筑的名称")
        
        // 创建搜索结果
        var results: [SearcherView.SearchResult] = []
        
        // 处理空间站结果
        if typeToProcess == .all || typeToProcess == .station {
            let stationResults = stationIds.compactMap { id -> SearcherView.SearchResult? in
                guard let nameInfo = namesResponse[id] else { return nil }
                return SearcherView.SearchResult(
                    id: id,
                    name: nameInfo.name,
                    type: .structure,
                    structureType: .station
                )
            }
            results.append(contentsOf: stationResults)
        }
        
        // 处理建筑物结果
        if typeToProcess == .all || typeToProcess == .structure {
            let structureResults = structureIds.compactMap { id -> SearcherView.SearchResult? in
                guard let nameInfo = namesResponse[id] else { return nil }
                return SearcherView.SearchResult(
                    id: id,
                    name: nameInfo.name,
                    type: .structure,
                    structureType: .structure
                )
            }
            results.append(contentsOf: structureResults)
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
        
        searchResults = results
        filteredResults = results
        
        Logger.debug("建筑搜索完成，共有 \(results.count) 个结果")
        
        // 打印前5个结果的详细信息
        if !results.isEmpty {
            Logger.debug("前 \(min(5, results.count)) 个搜索结果:")
            for (index, result) in results.prefix(5).enumerated() {
                Logger.debug("\(index + 1). ID: \(result.id), 名称: \(result.name), 类型: \(result.structureType?.rawValue ?? "unknown")")
            }
        }
    }
} 
