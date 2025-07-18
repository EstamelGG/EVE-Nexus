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
struct StructureSearchView {
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

    // 从本地数据库搜索空间站
    private func searchLocalStations(searchText: String) throws -> [Int] {
        let sql = """
                SELECT stationID 
                FROM stations 
                WHERE stationName LIKE ?
                LIMIT 500
            """

        guard
            case let .success(rows) = DatabaseManager.shared.executeQuery(
                sql, parameters: ["%\(searchText)%"]
            )
        else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "本地数据库搜索失败"])
        }

        return rows.compactMap { $0["stationID"] as? Int }
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

        // 收集所有找到的空间站ID
        var allStationIds = Set<Int>()
        var structureIds: [Int] = []

        // 1. 从本地数据库搜索
        do {
            let localStationIds = try searchLocalStations(searchText: searchText)
            allStationIds.formUnion(localStationIds)
            Logger.debug("本地数据库找到 \(localStationIds.count) 个空间站")
        } catch {
            Logger.error("本地数据库搜索失败: \(error)")
        }

        // 2. 使用CharacterSearchAPI进行在线搜索
        do {
            let data = try await CharacterSearchAPI.shared.search(
                characterId: characterId,
                categories: [.station, .structure],
                searchText: searchText
            )

            // 检查是否被取消
            try Task.checkCancellation()

            let response = try JSONDecoder().decode(SearcherView.SearchResponse.self, from: data)

            // 处理在线搜索结果
            if let stations = response.station {
                allStationIds.formUnion(stations)
                Logger.debug("在线搜索找到 \(stations.count) 个空间站")
            }

            // 处理建筑物
            if let structures = response.structure {
                structureIds = structures
                Logger.debug("找到 \(structures.count) 个建筑物")
            }
        } catch {
            Logger.error("在线搜索失败: \(error)")
            // 在线搜索失败时，继续使用本地搜索结果
        }

        // 合并所有结果并继续处理
        guard !allStationIds.isEmpty || !structureIds.isEmpty else {
            Logger.debug("没有找到任何建筑")
            searchResults = []
            filteredResults = []
            searchingStatus = ""
            return
        }

        var results: [SearcherView.SearchResult] = []
        var typeIdMap: [Int: Int] = [:]  // 建筑ID到类型ID的映射

        // 处理空间站结果
        if !allStationIds.isEmpty {
            searchingStatus = NSLocalizedString(
                "Main_Search_Status_Loading_Station_Info", comment: ""
            )
            do {
                try Task.checkCancellation()

                // 批量获取空间站信息
                let stationsInfo = try loadStationsInfo(stationIds: Array(allStationIds))

                // 收集所有空间站的星系ID和类型ID
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

                    // 存储类型ID映射
                    typeIdMap[info.id] = info.typeId
                    
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
            // 收集所有建筑物的星系ID和类型ID
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
                                    characterId: characterId,
                                    forceRefresh: true,  // 建筑搜索功能总是联网搜索
                                    cacheTimeOut: 1  // 缓存超时时间改为 1 小时
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

                // 存储类型ID映射
                typeIdMap[info.id] = info.typeId
                
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

        // 按照指定的类型ID顺序排序
        results.sort { result1, result2 in
            // 定义优先级类型ID顺序
            let priorityTypeIds = [40340, 35834, 35833, 35827, 35832, 35825, 35836, 35826, 35835]
            
            // 从映射中获取类型ID
            let typeId1 = typeIdMap[result1.id] ?? 0
            let typeId2 = typeIdMap[result2.id] ?? 0
            
            // 获取优先级索引
            let priority1 = priorityTypeIds.firstIndex(of: typeId1) ?? Int.max
            let priority2 = priorityTypeIds.firstIndex(of: typeId2) ?? Int.max
            
            // 如果两个都在优先级列表中
            if priority1 != Int.max && priority2 != Int.max {
                if priority1 != priority2 {
                    return priority1 < priority2
                }
                // 同类型按建筑ID排序
                return result1.id < result2.id
            }
            
            // 如果只有一个在优先级列表中
            if priority1 != Int.max {
                return true
            }
            if priority2 != Int.max {
                return false
            }
            
            // 两个都不在优先级列表中，按建筑ID排序
            return result1.id < result2.id
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
