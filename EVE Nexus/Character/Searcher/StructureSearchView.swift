import SwiftUI

// 数组分块扩展
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

@MainActor
struct StructureSearchView: View {
    let characterId: Int
    let searchText: String
    @Binding var searchResults: [SearcherView.SearchResult]
    @Binding var filteredResults: [SearcherView.SearchResult]
    @Binding var searchingStatus: String
    @Binding var error: Error?
    let structureType: SearcherView.StructureType

    init(
        characterId: Int,
        searchText: String,
        searchResults: Binding<[SearcherView.SearchResult]>,
        filteredResults: Binding<[SearcherView.SearchResult]>,
        searchingStatus: Binding<String>,
        error: Binding<Error?>,
        structureType: SearcherView.StructureType
    ) {
        self.characterId = characterId
        self.searchText = searchText
        _searchResults = searchResults
        _filteredResults = filteredResults
        _searchingStatus = searchingStatus
        _error = error
        self.structureType = structureType
    }

    var body: some View {
        EmptyView()  // 这个视图不需要UI，只是用于处理搜索逻辑
            .task {
                do {
                    try await search()
                } catch is CancellationError {
                    Logger.debug("搜索任务被取消")
                } catch {
                    Logger.error("搜索失败: \(error)")
                    self.error = error
                }
                searchingStatus = ""
            }
    }

    // 加载位置信息
    private func loadLocationInfo(systemId: Int) async throws -> (
        security: Double, systemName: String, regionName: String
    ) {
        guard
            let solarSystemInfo = await getSolarSystemInfo(
                solarSystemId: systemId, databaseManager: DatabaseManager.shared
            )
        else {
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

        guard
            case let .success(rows) = DatabaseManager.shared.executeQuery(sql, parameters: [typeId]),
            let row = rows.first
        else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "未找到类型图标"])
        }

        return row["icon_filename"] as! String
    }

    // 从数据库批量加载空间站信息
    private func loadStationsInfo(stationIds: [Int]) throws -> [(
        id: Int, name: String, typeId: Int, systemId: Int
    )] {
        let placeholders = String(repeating: "?,", count: stationIds.count).dropLast()
        let sql = """
                SELECT 
                    stationID,
                    stationName,
                    stationTypeID,
                    solarSystemID
                FROM stations
                WHERE stationID IN (\(placeholders))
            """

        guard
            case let .success(rows) = DatabaseManager.shared.executeQuery(
                sql, parameters: stationIds
            )
        else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "未找到空间站信息"])
        }

        return rows.map { row in
            (
                id: row["stationID"] as! Int,
                name: row["stationName"] as! String,
                typeId: row["stationTypeID"] as! Int,
                systemId: row["solarSystemID"] as! Int
            )
        }
    }

    func search() async throws {
        // 检查是否被取消
        try Task.checkCancellation()

        guard !searchText.isEmpty else {
            searchingStatus = ""
            return
        }

        // 设置搜索状态
        Logger.debug("开始搜索建筑，关键词: \(searchText)")
        searchingStatus = NSLocalizedString("Main_Search_Status_Finding_Structures", comment: "")

        // 使用CharacterSearchAPI进行搜索
        let data = try await CharacterSearchAPI.shared.search(
            characterId: characterId,
            categories: [.station, .structure],
            searchText: searchText
        )

        // 检查是否被取消
        try Task.checkCancellation()

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

        guard !stationIds.isEmpty || !structureIds.isEmpty else {
            Logger.debug("没有找到任何建筑")
            searchResults = []
            filteredResults = []
            searchingStatus = ""
            return
        }

        var results: [SearcherView.SearchResult] = []

        // 处理空间站结果
        if !stationIds.isEmpty {
            searchingStatus = NSLocalizedString(
                "Main_Search_Status_Loading_Station_Info", comment: ""
            )
            do {
                try Task.checkCancellation()

                // 批量获取空间站信息
                let stationsInfo = try loadStationsInfo(stationIds: stationIds)

                // 计算合适的批次大小：最小1，最大10，默认为总数的1/5
                let batchSize = min(max(stationsInfo.count / 5, 1), 10)

                // 使用 TaskGroup 并发处理空间站信息
                try await withThrowingTaskGroup(of: SearcherView.SearchResult?.self) { group in
                    var processedCount = 0

                    for batch in stationsInfo.chunked(into: batchSize) {
                        for info in batch {
                            group.addTask {
                                try Task.checkCancellation()

                                do {
                                    // 获取位置信息
                                    let locationInfo = try await loadLocationInfo(
                                        systemId: info.systemId)

                                    try Task.checkCancellation()

                                    // 获取建筑类型图标
                                    let iconFilename = try await loadTypeIcon(typeId: info.typeId)

                                    return SearcherView.SearchResult(
                                        id: info.id,
                                        name: info.name,
                                        type: .structure,
                                        structureType: .station,
                                        locationInfo: locationInfo,
                                        typeInfo: iconFilename
                                    )
                                } catch {
                                    if error is CancellationError { throw error }
                                    Logger.error("获取空间站附加信息失败: \(error)")
                                    return nil
                                }
                            }
                        }

                        // 等待当前批次完成
                        for try await result in group {
                            if let result = result {
                                results.append(result)
                            }
                            processedCount += 1
                            searchingStatus = String(
                                format: NSLocalizedString(
                                    "Main_Search_Status_Loading_Station_Progress", comment: ""
                                ),
                                processedCount,
                                stationsInfo.count
                            )
                        }
                    }
                }
            } catch {
                if error is CancellationError { throw error }
                Logger.error("批量获取空间站信息失败: \(error)")
            }
        }

        // 处理建筑物结果
        if !structureIds.isEmpty {
            searchingStatus = NSLocalizedString(
                "Main_Search_Status_Loading_Structure_Info", comment: ""
            )

            // 计算合适的批次大小：最小1，最大10，默认为总数的1/5
            let batchSize = min(max(structureIds.count / 5, 1), 10)

            // 使用 TaskGroup 并发处理建筑物信息
            try await withThrowingTaskGroup(of: SearcherView.SearchResult?.self) { group in
                var processedCount = 0

                for batch in structureIds.chunked(into: batchSize) {
                    for structureId in batch {
                        group.addTask {
                            try Task.checkCancellation()

                            do {
                                // 获取建筑物信息
                                let info = try await UniverseStructureAPI.shared.fetchStructureInfo(
                                    structureId: Int64(structureId),
                                    characterId: characterId
                                )

                                try Task.checkCancellation()

                                // 获取位置信息
                                let locationInfo = try await loadLocationInfo(
                                    systemId: info.solar_system_id)

                                try Task.checkCancellation()

                                // 获取建筑类型图标
                                let iconFilename = try await loadTypeIcon(typeId: info.type_id)

                                return SearcherView.SearchResult(
                                    id: structureId,
                                    name: info.name,
                                    type: .structure,
                                    structureType: .structure,
                                    locationInfo: locationInfo,
                                    typeInfo: iconFilename
                                )
                            } catch {
                                if error is CancellationError { throw error }
                                Logger.error("获取建筑物信息失败 - ID: \(structureId), 错误: \(error)")
                                return nil
                            }
                        }
                    }

                    // 等待当前批次完成
                    for try await result in group {
                        if let result = result {
                            results.append(result)
                        }
                        processedCount += 1
                        searchingStatus = String(
                            format: NSLocalizedString(
                                "Main_Search_Status_Loading_Structure_Progress", comment: ""
                            ),
                            processedCount,
                            structureIds.count
                        )
                    }
                }
            }
        }

        // 最后一次检查是否被取消
        try Task.checkCancellation()

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

        // 根据当前的过滤条件设置过滤后的结果
        if structureType == .all {
            filteredResults = results
        } else {
            filteredResults = results.filter { result in
                result.structureType == structureType
            }
        }

        Logger.debug("建筑搜索完成，共有 \(results.count) 个结果，过滤后显示 \(filteredResults.count) 个结果")

        // 打印前5个结果的详细信息
        if !filteredResults.isEmpty {
            Logger.debug("前 \(min(5, filteredResults.count)) 个过滤后的结果:")
            for (index, result) in filteredResults.prefix(5).enumerated() {
                Logger.debug(
                    "\(index + 1). ID: \(result.id), 名称: \(result.name), 类型: \(result.structureType?.rawValue ?? "unknown")"
                )
            }
        }

        // 清除搜索状态
        searchingStatus = ""
    }
}
