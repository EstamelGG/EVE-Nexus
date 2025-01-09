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
    
    // 加载位置信息
    private func loadLocationInfo(systemId: Int) async throws -> (security: Double, systemName: String, regionName: String) {
        guard let solarSystemInfo = await getSolarSystemInfo(solarSystemId: systemId, databaseManager: DatabaseManager.shared) else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "未找到位置信息"])
        }
        
        return (
            security: solarSystemInfo.security,
            systemName: solarSystemInfo.systemName,
            regionName: solarSystemInfo.regionName
        )
    }
    
    // 加载类型图标
    private func loadTypeIcon(typeId: Int) throws -> String {
        let sql = """
            SELECT 
                icon_filename
            FROM types
            WHERE type_id = ?
        """
        
        guard case .success(let rows) = DatabaseManager.shared.executeQuery(sql, parameters: [typeId]),
              let row = rows.first else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "未找到类型图标"])
        }
        
        return row["icon_filename"] as! String
    }
    
    // 从数据库加载空间站信息
    private func loadStationInfo(stationId: Int) throws -> (name: String, typeId: Int, systemId: Int) {
        let sql = """
            SELECT 
                stationName,
                stationTypeID,
                solarSystemID
            FROM stations
            WHERE stationID = ?
        """
        
        guard case .success(let rows) = DatabaseManager.shared.executeQuery(sql, parameters: [stationId]),
              let row = rows.first else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "未找到空间站信息"])
        }
        
        return (
            name: row["stationName"] as! String,
            typeId: row["stationTypeID"] as! Int,
            systemId: row["solarSystemID"] as! Int
        )
    }
    
    func search() async throws {
        guard !searchText.isEmpty else { return }
        
        Logger.debug("开始搜索建筑，关键词: \(searchText)")
        searchingStatus = NSLocalizedString("Main_Search_Status_Finding_Structures", comment: "")
        
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
        
        var results: [SearcherView.SearchResult] = []
        
        // 处理空间站结果
        if typeToProcess == .all || typeToProcess == .station {
            searchingStatus = NSLocalizedString("Main_Search_Status_Loading_Station_Info", comment: "")
            for stationId in stationIds {
                do {
                    // 从数据库获取空间站信息
                    let info = try loadStationInfo(stationId: stationId)
                    
                    // 获取位置信息
                    let locationInfo = try await loadLocationInfo(systemId: info.systemId)
                    
                    // 获取建筑类型图标
                    let iconFilename = try loadTypeIcon(typeId: info.typeId)
                    
                    let result = SearcherView.SearchResult(
                        id: stationId,
                        name: info.name,
                        type: .structure,
                        structureType: .station,
                        locationInfo: locationInfo,
                        typeInfo: iconFilename
                    )
                    results.append(result)
                } catch {
                    Logger.error("获取空间站信息失败: \(error)")
                    continue
                }
            }
        }
        
        // 处理建筑物结果
        if typeToProcess == .all || typeToProcess == .structure {
            searchingStatus = NSLocalizedString("Main_Search_Status_Loading_Structure_Info", comment: "")
            for structureId in structureIds {
                do {
                    let info = try await StructureInfoAPI.shared.fetchStructureInfo(structureId: structureId, characterId: characterId)
                    
                    // 获取位置信息
                    let locationInfo = try await loadLocationInfo(systemId: info.solar_system_id)
                    
                    // 获取建筑类型图标
                    let iconFilename = try loadTypeIcon(typeId: info.type_id)
                    
                    let result = SearcherView.SearchResult(
                        id: structureId,
                        name: info.name,
                        type: .structure,
                        structureType: .structure,
                        locationInfo: locationInfo,
                        typeInfo: iconFilename
                    )
                    results.append(result)
                } catch {
                    Logger.error("获取建筑信息失败: \(error)")
                    continue
                }
            }
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
