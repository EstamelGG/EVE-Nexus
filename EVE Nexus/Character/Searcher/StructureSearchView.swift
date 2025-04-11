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

    // 批量加载位置信息
    private func loadBatchLocationInfo(systemIds: [Int]) async throws -> [Int: (
        security: Double, systemName: String, regionName: String
    )] {
        let solarSystemInfoMap = await getBatchSolarSystemInfo(
            solarSystemIds: systemIds, databaseManager: DatabaseManager.shared
        )

        var result: [Int: (security: Double, systemName: String, regionName: String)] = [:]

        for (systemId, info) in solarSystemInfoMap {
            result[systemId] = (
                security: info.security,
                systemName: info.systemName,
                regionName: info.regionName
            )
        }

        return result
    }

    // 批量加载类型图标
    private func loadBatchTypeIcons(typeIds: [Int]) throws -> [Int: String] {
        let placeholders = String(repeating: "?,", count: typeIds.count).dropLast()
        let sql = """
                SELECT 
                    type_id,
                    icon_filename
                FROM types
                WHERE type_id IN (\(placeholders))
            """

        guard
            case let .success(rows) = DatabaseManager.shared.executeQuery(
                sql, parameters: typeIds.map { $0 as Any }
            )
        else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "未找到类型图标"])
        }

        var result: [Int: String] = [:]
        for row in rows {
            if let typeId = row["type_id"] as? Int,
                let iconFilename = row["icon_filename"] as? String
            {
                result[typeId] = iconFilename
            }
        }

        return result
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

                // 收集所有空间站的系统ID和类型ID
                let systemIds = stationsInfo.map { $0.systemId }
                let typeIds = Array(Set(stationsInfo.map { $0.typeId }))

                // 批量获取位置信息
                let locationInfoMap = try await loadBatchLocationInfo(systemIds: systemIds)

                // 批量获取类型图标
                let iconMap = try loadBatchTypeIcons(typeIds: typeIds)

                // 处理每个空间站
                for info in stationsInfo {
                    try Task.checkCancellation()

                    // 获取位置信息
                    guard let locationInfo = locationInfoMap[info.systemId] else {
                        Logger.error("未找到空间站位置信息: \(info.id)")
                        continue
                    }

                    // 获取图标
                    guard let iconFilename = iconMap[info.typeId] else {
                        Logger.error("未找到空间站类型图标: \(info.typeId)")
                        continue
                    }

                    let result = SearcherView.SearchResult(
                        id: info.id,
                        name: info.name,
                        type: .structure,
                        structureType: .station,
                        locationInfo: locationInfo,
                        typeInfo: iconFilename
                    )

                    results.append(result)
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
            Logger.info("batchSize: \(batchSize)")
            // 收集所有建筑物的系统ID和类型ID
            var allSystemIds: [Int] = []
            var allTypeIds: [Int] = []
            var structureInfos: [(id: Int, name: String, typeId: Int, systemId: Int)] = []

            // 使用 TaskGroup 并发获取建筑物基本信息
            try await withThrowingTaskGroup(of: (Int, String, Int, Int)?.self) { group in
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

                                return (structureId, info.name, info.type_id, info.solar_system_id)
                            } catch {
                                if error is CancellationError { throw error }
                                Logger.error("获取建筑物信息失败 - ID: \(structureId), 错误: \(error)")
                                return nil
                            }
                        }
                    }

                    // 等待当前批次完成
                    for try await result in group {
                        if let (id, name, typeId, systemId) = result {
                            structureInfos.append(
                                (id: id, name: name, typeId: typeId, systemId: systemId))
                            allSystemIds.append(systemId)
                            allTypeIds.append(typeId)
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

            // 批量获取位置信息
            let locationInfoMap = try await loadBatchLocationInfo(systemIds: allSystemIds)

            // 批量获取类型图标
            let iconMap = try loadBatchTypeIcons(typeIds: Array(Set(allTypeIds)))

            // 处理每个建筑物
            for info in structureInfos {
                try Task.checkCancellation()

                // 获取位置信息
                guard let locationInfo = locationInfoMap[info.systemId] else {
                    Logger.error("未找到建筑物位置信息: \(info.id)")
                    continue
                }

                // 获取图标
                guard let iconFilename = iconMap[info.typeId] else {
                    Logger.error("未找到建筑物类型图标: \(info.typeId)")
                    continue
                }

                let result = SearcherView.SearchResult(
                    id: info.id,
                    name: info.name,
                    type: .structure,
                    structureType: .structure,
                    locationInfo: locationInfo,
                    typeInfo: iconFilename
                )

                results.append(result)
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
