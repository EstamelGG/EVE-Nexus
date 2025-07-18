import SwiftUI

// MARK: - 建筑选择器 Sheet

struct StructureSelectorSheet: View {
    let character: EVECharacterInfo
    @Binding var selectedStructure: SearcherView.SearchResult?
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText = ""
    @State private var searchResults: [SearcherView.SearchResult] = []
    @State private var isSearching = false
    @State private var searchError: Error?
    @State private var searchTask: Task<Void, Never>?
    @State private var isSearchActive = false
    @State private var searchingStatus = ""
    
    // 存储建筑ID到类型ID的映射
    @State private var structureTypeIdMap: [Int: Int] = [:]
    
    // 存储能安装市场模块的建筑类型ID
    @State private var marketCapableStructureTypes: Set<Int> = []
    
    private let minSearchLength = 3
    
    var body: some View {
        NavigationView {
            VStack {
                if searchText.count < minSearchLength && searchText.count > 0 {
                    // 搜索提示
                    VStack(spacing: 16) {
                        Spacer()
                        
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text(String(format: NSLocalizedString("Market_Structure_Search_Min_Length", comment: ""), minSearchLength))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Spacer()
                    }
                } else if searchText.count >= minSearchLength && searchResults.isEmpty && !isSearching {
                    // 无搜索结果
                    VStack(spacing: 16) {
                        Spacer()
                        
                        Image(systemName: "building.2")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        
                        Text(NSLocalizedString("Market_Structure_Search_No_Results", comment: ""))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Text(NSLocalizedString("Market_Structure_Search_Try_Different", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                    }
                } else if searchText.isEmpty {
                    // 初始状态
                    VStack(spacing: 16) {
                        Spacer()
                        
                        Image(systemName: "building.2.crop.circle")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        
                        Text(NSLocalizedString("Market_Structure_Search_Hint", comment: ""))
                            .font(.title3)
                            .foregroundColor(.secondary)
                        
                        Text(NSLocalizedString("Market_Structure_Search_Description", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                    }
                } else {
                    // 搜索结果列表
                    List {
                        if isSearching {
                            // 搜索进度指示器
                            VStack(spacing: 12) {
                                ProgressView()
                                    .scaleEffect(1.2)
                                
                                if !searchingStatus.isEmpty {
                                    Text(searchingStatus)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                        .multilineTextAlignment(.center)
                                } else {
                                    Text(NSLocalizedString("Market_Structure_Search_Searching", comment: ""))
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                        } else {
                            ForEach(searchResults) { result in
                                StructureResultRow(
                                    result: result,
                                    isSelected: selectedStructure?.id == result.id,
                                    onTap: {
                                        selectedStructure = result
                                        dismiss()
                                    },
                                    characterId: character.CharacterID
                                )
                            }
                        }
                    }
                }
                
                Spacer()
            }
            .navigationTitle(NSLocalizedString("Market_Structure_Structure_Selector_Title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                isPresented: $isSearchActive,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text(NSLocalizedString("Market_Structure_Search_Placeholder", comment: ""))
            )
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Market_Structure_Sheet_Cancel", comment: "")) {
                        dismiss()
                    }
                }
            }
        }
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty {
                searchingStatus = ""
            }
            handleSearchTextChange(newValue)
        }
        .onDisappear {
            searchTask?.cancel()
        }
    }
    
    private func handleSearchTextChange(_ text: String) {
        // 取消之前的搜索任务
        searchTask?.cancel()
        
        guard text.count >= minSearchLength else {
            searchResults = []
            isSearching = false
            searchingStatus = ""
            structureTypeIdMap = [:]
            return
        }
        
        // 创建新的搜索任务
        searchTask = Task {
            // 等待500ms防抖
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                isSearching = true
            }
            
            await performSearch(text: text)
        }
    }
    
    @MainActor
    private func performSearch(text: String) async {
        do {
            // 首先加载能安装市场模块的建筑类型
            await loadMarketCapableStructureTypes()
            
            // 直接搜索建筑物，不使用通用的StructureSearchView
            try await searchStructuresOnly(text: text)
            
            isSearching = false
            searchingStatus = ""
        } catch {
            Logger.error("建筑搜索失败: \(error)")
            searchError = error
            searchResults = []
            isSearching = false
            searchingStatus = ""
            structureTypeIdMap = [:]
        }
    }
    
    // 加载能安装市场模块的建筑类型ID
    private func loadMarketCapableStructureTypes() async {
        let marketModuleTypeId = 35892 // 市场模块的type_id
        
        do {
            // 1. 获取所有可装配相关的属性ID，参考CanFit.swift中的实现
            let attributeQuery = """
                SELECT attribute_id, name, unitName 
                FROM dogmaAttributes 
                WHERE (name LIKE 'canFitShipType%' OR name LIKE 'canFitShipGroup%') 
                AND unitName IN ('groupID', 'typeID')
            """
            
            var shipGroupAttributes: [Int] = []
            var shipTypeAttributes: [Int] = []
            
            if case let .success(rows) = DatabaseManager.shared.executeQuery(attributeQuery) {
                for row in rows {
                    if let attrId = row["attribute_id"] as? Int,
                        let unitName = row["unitName"] as? String
                    {
                        if unitName == "groupID" {
                            shipGroupAttributes.append(attrId)
                        } else if unitName == "typeID" {
                            shipTypeAttributes.append(attrId)
                        }
                    }
                }
            }
            
            Logger.info("找到 \(shipGroupAttributes.count) 个canFitShipGroup属性和 \(shipTypeAttributes.count) 个canFitShipType属性")
            
            if shipGroupAttributes.isEmpty && shipTypeAttributes.isEmpty {
                Logger.warning("未找到可装配属性ID")
                return
            }
            
            // 2. 查找能装配市场模块的group_id和type_id
            let allCanFitAttributes = shipGroupAttributes + shipTypeAttributes
            let placeholders = allCanFitAttributes.map { _ in "?" }.joined(separator: ",")
            let valueQuery = """
                SELECT DISTINCT value, attribute_id
                FROM typeAttributes 
                WHERE attribute_id IN (\(placeholders)) AND type_id = ?
            """
            
            var parameters = allCanFitAttributes.map { $0 as Any }
            parameters.append(marketModuleTypeId)
            
            var allowedGroupIds: Set<Int> = []
            var allowedTypeIds: Set<Int> = []
            
            if case let .success(rows) = DatabaseManager.shared.executeQuery(valueQuery, parameters: parameters) {
                for row in rows {
                    if let value = row["value"] as? Double,
                       let attributeId = row["attribute_id"] as? Int {
                        let valueInt = Int(value)
                        
                        if shipGroupAttributes.contains(attributeId) {
                            // 这是一个group_id
                            allowedGroupIds.insert(valueInt)
                        } else if shipTypeAttributes.contains(attributeId) {
                            // 这是一个type_id
                            allowedTypeIds.insert(valueInt)
                        }
                    }
                }
            }
            
            Logger.info("市场模块可装配到的group_id: \(Array(allowedGroupIds).sorted())")
            Logger.info("市场模块可装配到的type_id: \(Array(allowedTypeIds).sorted())")
            
            // 3. 根据允许的group_id查找所有对应的type_id
            var allCapableTypeIds: Set<Int> = allowedTypeIds
            
            if !allowedGroupIds.isEmpty {
                let groupPlaceholders = allowedGroupIds.map { _ in "?" }.joined(separator: ",")
                let typeFromGroupQuery = """
                    SELECT DISTINCT type_id 
                    FROM types 
                    WHERE groupID IN (\(groupPlaceholders)) AND published = 1
                """
                
                if case let .success(rows) = DatabaseManager.shared.executeQuery(typeFromGroupQuery, parameters: Array(allowedGroupIds)) {
                    for row in rows {
                        if let typeId = row["type_id"] as? Int {
                            allCapableTypeIds.insert(typeId)
                        }
                    }
                }
            }
            
            await MainActor.run {
                marketCapableStructureTypes = allCapableTypeIds
                Logger.info("找到 \(allCapableTypeIds.count) 种能安装市场模块的建筑类型: \(Array(allCapableTypeIds).sorted())")
            }
            
        }
    }

    // 专门搜索建筑物的方法
    private func searchStructuresOnly(text: String) async throws {
        searchingStatus = NSLocalizedString("Main_Search_Status_Finding_Structures", comment: "")
        
        var structureIds: [Int] = []
        
        // 使用CharacterSearchAPI进行在线搜索，只搜索建筑物
        do {
            let data = try await CharacterSearchAPI.shared.search(
                characterId: character.CharacterID,
                categories: [.structure],  // 只搜索建筑物
                searchText: text
            )
            
            let response = try JSONDecoder().decode(SearcherView.SearchResponse.self, from: data)
            
            if let structures = response.structure {
                structureIds = structures
                Logger.debug("找到 \(structures.count) 个建筑物")
            }
        } catch {
            Logger.error("建筑物搜索失败: \(error)")
            throw error
        }
        
        guard !structureIds.isEmpty else {
            Logger.debug("没有找到任何建筑物")
            searchResults = []
            searchingStatus = ""
            return
        }
        
        var results: [SearcherView.SearchResult] = []
        
        // 处理建筑物结果
        searchingStatus = NSLocalizedString("Main_Search_Status_Loading_Structure_Info", comment: "")
        
        // 计算合适的批次大小
        let batchSize = min(max(structureIds.count / 5, 1), 10)
        
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
                            let info = try await UniverseStructureAPI.shared.fetchStructureInfo(
                                structureId: Int64(structureId),
                                characterId: character.CharacterID,
                                forceRefresh: true,
                                cacheTimeOut: 1
                            )
                            
                            return (structureId, info.name, info.type_id, info.solar_system_id)
                        } catch {
                            Logger.error("获取建筑物信息失败 - ID: \(structureId), 错误: \(error)")
                            return nil
                        }
                    }
                }
                
                // 等待当前批次完成
                for try await result in group {
                    if let (id, name, typeId, systemId) = result {
                        structureInfos.append((id: id, name: name, typeId: typeId, systemId: systemId))
                        allSystemIds.append(systemId)
                        allTypeIds.append(typeId)
                    }
                    processedCount += 1
                    searchingStatus = String(
                        format: NSLocalizedString("Main_Search_Status_Loading_Structure_Progress", comment: ""),
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
            
            guard let locationInfo = locationInfoMap[info.systemId] else {
                Logger.error("未找到建筑物位置信息: \(info.id)")
                continue
            }
            
            guard let iconFilename = iconMap[info.typeId] else {
                Logger.error("未找到建筑物类型图标: \(info.typeId)")
                continue
            }
            
            // 检查建筑是否能安装市场模块
            if !marketCapableStructureTypes.contains(info.typeId) {
                Logger.debug("建筑 \(info.name) (类型ID: \(info.typeId)) 不支持市场模块，跳过")
                continue
            }
            
            // 存储建筑ID到类型ID的映射
            structureTypeIdMap[info.id] = info.typeId
            
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
        
        // 按照指定的类型ID顺序排序
        results.sort { result1, result2 in
            // 定义优先级类型ID顺序
            let priorityTypeIds = [40340, 35834, 35833, 35827, 35832, 35825, 35836, 35826, 35835]
            
            // 从结果中提取类型ID
            let typeId1 = extractTypeIdFromResult(result1)
            let typeId2 = extractTypeIdFromResult(result2)
            
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
        searchingStatus = ""
        
        Logger.debug("建筑物搜索完成，共有 \(results.count) 个结果")
    }
    
    // 从搜索结果中提取类型ID的辅助函数
    private func extractTypeIdFromResult(_ result: SearcherView.SearchResult) -> Int {
        return structureTypeIdMap[result.id] ?? 0
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
}



// MARK: - 建筑结果行

struct StructureResultRow: View {
    let result: SearcherView.SearchResult
    let isSelected: Bool
    let onTap: () -> Void
    let characterId: Int
    
    var body: some View {
        HStack(spacing: 12) {
            // 建筑图标
            if let iconFilename = result.typeInfo {
                IconManager.shared.loadImage(for: iconFilename)
                    .resizable()
                    .frame(width: 40, height: 40)
                    .cornerRadius(8)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "building.2")
                            .foregroundColor(.secondary)
                    )
            }
            
            // 建筑信息
            VStack(alignment: .leading, spacing: 4) {
                Text(result.name)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                if let locationInfo = result.locationInfo {
                    HStack(spacing: 4) {
                        Text(formatSystemSecurity(locationInfo.security))
                            .foregroundColor(getSecurityColor(locationInfo.security))
                            .font(.caption)
                        
                        Text("\(locationInfo.systemName) / \(locationInfo.regionName)")
                            .foregroundColor(.secondary)
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
                    .font(.title3)
            }
        }
        .contextMenu {
            Button {
                UIPasteboard.general.string = result.name
            } label: {
                Label(NSLocalizedString("Misc_Copy_Structure", comment: ""), systemImage: "doc.on.doc")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
}
