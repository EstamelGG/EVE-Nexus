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

    /// 能安装市场模块的建筑类型ID（跨实例共享，仅查一次数据库）
    private static var marketCapableStructureTypes: Set<Int>? = nil

    /// 建筑排序优先级（按 typeId 升序，越小越靠前）
    private static let priorityTypeIds: [Int] = [40340, 35834, 35833, 35827, 35832, 35825, 35836, 35826, 35835]

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
                        Text(
                            String(
                                format: NSLocalizedString(
                                    "Market_Structure_Search_Min_Length", comment: ""
                                ),
                                minSearchLength
                            )
                        )
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                        Spacer()
                    }
                } else if searchText.count >= minSearchLength && searchResults.isEmpty
                    && !isSearching
                {
                    // 无搜索结果
                    VStack(spacing: 16) {
                        Spacer()

                        Image(systemName: "building.2")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)

                        Text(NSLocalizedString("Market_Structure_Search_No_Results", comment: ""))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Text(
                            NSLocalizedString("Market_Structure_Search_Try_Different", comment: "")
                        )
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
                                    Text(
                                        NSLocalizedString(
                                            "Market_Structure_Search_Searching", comment: ""
                                        )
                                    )
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
            .navigationTitle(
                NSLocalizedString("Market_Structure_Structure_Selector_Title", comment: "")
            )
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                isPresented: $isSearchActive,
                // placement: .navigationBarDrawer(displayMode: .always),
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
        searchTask?.cancel()

        guard text.count >= minSearchLength else {
            searchResults = []
            isSearching = false
            searchingStatus = ""
            return
        }

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }

            await MainActor.run { isSearching = true }
            await performSearch(text: text)
        }
    }

    @MainActor
    private func performSearch(text: String) async {
        do {
            // 首先加载能安装市场模块的建筑类型（带缓存）
            await loadMarketCapableStructureTypes()

            try await searchStructuresOnly(text: text)

            isSearching = false
            searchingStatus = ""
        } catch {
            Logger.error("建筑搜索失败: \(error)")
            searchError = error
            searchResults = []
            isSearching = false
            searchingStatus = ""
        }
    }

    /// 加载能安装市场模块的建筑类型ID（仅首次查询数据库，后续使用缓存）
    private func loadMarketCapableStructureTypes() async {
        // 命中缓存直接返回
        if Self.marketCapableStructureTypes != nil {
            return
        }

        let marketModuleTypeId = 35892

        do {
            let attributeQuery = """
                SELECT attribute_id, name, unitID
                FROM dogmaAttributes
                WHERE (name LIKE 'canFitShipType%' OR name LIKE 'canFitShipGroup%')
                AND unitID IN (115, 116)
            """

            var shipGroupAttributes: [Int] = []
            var shipTypeAttributes: [Int] = []

            if case let .success(rows) = DatabaseManager.shared.executeQuery(attributeQuery) {
                for row in rows {
                    if let attrId = row["attribute_id"] as? Int,
                       let unitID = row["unitID"] as? Int
                    {
                        if unitID == 115 {
                            shipGroupAttributes.append(attrId)
                        } else if unitID == 116 {
                            shipTypeAttributes.append(attrId)
                        }
                    }
                }
            }

            guard !(shipGroupAttributes.isEmpty && shipTypeAttributes.isEmpty) else {
                await MainActor.run { Self.marketCapableStructureTypes = [] }
                return
            }

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

            if case let .success(rows) = DatabaseManager.shared.executeQuery(
                valueQuery, parameters: parameters
            ) {
                for row in rows {
                    if let value = row["value"] as? Double,
                       let attributeId = row["attribute_id"] as? Int
                    {
                        let valueInt = Int(value)
                        if shipGroupAttributes.contains(attributeId) {
                            allowedGroupIds.insert(valueInt)
                        } else if shipTypeAttributes.contains(attributeId) {
                            allowedTypeIds.insert(valueInt)
                        }
                    }
                }
            }

            var allCapableTypeIds: Set<Int> = allowedTypeIds

            if !allowedGroupIds.isEmpty {
                let groupPlaceholders = allowedGroupIds.map { _ in "?" }.joined(separator: ",")
                let typeFromGroupQuery = """
                    SELECT DISTINCT type_id
                    FROM types
                    WHERE groupID IN (\(groupPlaceholders)) AND published = 1
                """

                if case let .success(rows) = DatabaseManager.shared.executeQuery(
                    typeFromGroupQuery, parameters: Array(allowedGroupIds)
                ) {
                    for row in rows {
                        if let typeId = row["type_id"] as? Int {
                            allCapableTypeIds.insert(typeId)
                        }
                    }
                }
            }

            await MainActor.run {
                Self.marketCapableStructureTypes = allCapableTypeIds
                Logger.info("找到 \(allCapableTypeIds.count) 种能安装市场模块的建筑类型")
            }
        }
    }

    /// 专门搜索建筑物的方法
    private func searchStructuresOnly(text: String) async throws {
        searchingStatus = NSLocalizedString("Main_Search_Status_Finding_Structures", comment: "")

        var structureIds: [Int] = []

        do {
            let data = try await CharacterSearchAPI.shared.search(
                characterId: character.CharacterID,
                categories: [.structure],
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
            searchResults = []
            searchingStatus = ""
            return
        }

        var results: [SearcherView.SearchResult] = []

        searchingStatus = NSLocalizedString("Main_Search_Status_Loading_Structure_Info", comment: "")
        let batchSize = min(max(structureIds.count / 5, 1), 10)

        var allSystemIds: [Int] = []
        var structureInfos: [(id: Int, name: String, typeId: Int, systemId: Int)] = []

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

                for try await result in group {
                    if let (id, name, typeId, systemId) = result {
                        structureInfos.append((id: id, name: name, typeId: typeId, systemId: systemId))
                        allSystemIds.append(systemId)
                    }
                    processedCount += 1
                    searchingStatus = String(
                        format: NSLocalizedString("Main_Search_Status_Loading_Structure_Progress", comment: ""),
                        processedCount, structureIds.count
                    )
                }
            }
        }

        let locationInfoMap = try await loadBatchLocationInfo(systemIds: allSystemIds)

        for info in structureInfos {
            try Task.checkCancellation()

            guard let locationInfo = locationInfoMap[info.systemId] else {
                Logger.error("未找到建筑物位置信息: \(info.id)")
                continue
            }

            let capableTypes = await MainActor.run { Self.marketCapableStructureTypes ?? [] }
            if !capableTypes.contains(info.typeId) {
                Logger.debug("建筑 \(info.name) (类型ID: \(info.typeId)) 不支持市场模块，跳过")
                continue
            }

            results.append(SearcherView.SearchResult(
                id: info.id, name: info.name, type: .structure,
                structureType: .structure, locationInfo: locationInfo, typeId: info.typeId
            ))
        }

        results.sort { result1, result2 in
            let typeId1 = result1.typeId ?? 0
            let typeId2 = result2.typeId ?? 0
            let priority1 = Self.priorityTypeIds.firstIndex(of: typeId1) ?? Int.max
            let priority2 = Self.priorityTypeIds.firstIndex(of: typeId2) ?? Int.max
            if priority1 != priority2 {
                return priority1 < priority2
            }
            return result1.id < result2.id
        }

        searchResults = results
        searchingStatus = ""
        Logger.debug("建筑物搜索完成，共有 \(results.count) 个结果")
    }

    /// 批量加载位置信息
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
}

// MARK: - 建筑结果行

struct StructureResultRow: View {
    let result: SearcherView.SearchResult
    let isSelected: Bool
    let onTap: () -> Void
    let characterId: Int

    private var structureIconName: String {
        guard let typeId = result.typeId else { return IconManager.defaultItemIcon }
        return DatabaseManager.shared.getItemIconFileName(for: typeId)
            ?? IconManager.defaultItemIcon
    }

    var body: some View {
        HStack(spacing: 12) {
            // 建筑图标（按 typeId 查询）
            IconManager.shared.loadImage(for: structureIconName)
                .resizable()
                .frame(width: 40, height: 40)
                .cornerRadius(8)

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
                Label(
                    NSLocalizedString("Misc_Copy_Structure", comment: ""), systemImage: "doc.on.doc"
                )
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
}
