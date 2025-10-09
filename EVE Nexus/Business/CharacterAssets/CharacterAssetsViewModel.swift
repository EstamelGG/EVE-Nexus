import Foundation
import SwiftUI

// 搜索结果
struct AssetSearchResult: Identifiable {
    let node: AssetTreeNode // 目标物品节点（用于显示基本信息）
    let itemInfo: ItemInfo // 物品基本信息
    let locationPath: [AssetTreeNode] // 从顶层位置到物品的完整路径
    let containerNode: AssetTreeNode // 直接容器节点
    let totalQuantity: Int // 合并后的总数量

    var id: String {
        // 使用type_id和容器路径组合作为唯一标识
        "\(node.type_id)_\(containerNode.item_id)_\(formattedPath.hashValue)"
    }

    // 格式化的位置路径字符串，只显示到倒数第二级
    var formattedPath: String {
        // 如果路径少于2个节点，直接返回完整路径
        guard locationPath.count >= 2 else {
            return locationPath.map { node in
                HTMLUtils.decodeHTMLEntities(node.name ?? NSLocalizedString("Unknown_System", comment: ""))
            }.joined(separator: " > ")
        }

        // 去掉最后一个节点（当前物品），只显示到倒数第二级
        let pathToShow = locationPath.dropLast()
        return pathToShow.map { node in
            HTMLUtils.decodeHTMLEntities(node.name ?? NSLocalizedString("Unknown_System", comment: ""))
        }.joined(separator: " > ")
    }
}

// 物品信息结构体
struct ItemInfo {
    let name: String
    let zh_name: String
    let en_name: String
    let iconFileName: String
}

@MainActor
class CharacterAssetsViewModel: ObservableObject {
    // MARK: - 发布属性

    @Published var isLoading = false
    @Published var assetLocations: [AssetTreeNode] = []
    @Published var error: Error?
    @Published var loadingProgress: AssetLoadingProgress?
    @Published var searchResults: [AssetSearchResult] = []
    @Published var regionNames: [Int: String] = [:]
    @Published var systemInfoCache: [Int: SolarSystemInfo] = [:]
    @Published var stationNameCache: [Int64: String] = [:]
    @Published var solarSystemNameCache: [Int: String] = [:]

    // MARK: - 私有属性

    private var isCurrentlyLoading = false
    private(set) var itemInfoCache: [Int: ItemInfo] = [:]
    private let characterId: Int
    private let databaseManager: DatabaseManager

    // MARK: - 计算属性

    // 获取置顶的位置
    var pinnedLocations: [AssetTreeNode] {
        let pinnedIDs = UserDefaultsManager.shared.getPinnedAssetLocationIDs(for: characterId)
        return assetLocations.filter { location in
            pinnedIDs.contains(location.location_id)
        }.sorted { $0.location_id < $1.location_id }
    }

    // 获取非置顶的位置（按星域分组）
    var unpinnedLocationsByRegion: [(region: String, locations: [AssetTreeNode])] {
        let pinnedIDs = UserDefaultsManager.shared.getPinnedAssetLocationIDs(for: characterId)
        let unpinnedLocations = assetLocations.filter { location in
            !pinnedIDs.contains(location.location_id)
        }

        // 1. 按区域分组
        let grouped = Dictionary(grouping: unpinnedLocations) { location in
            if let regionId = location.region_id,
               let regionName = regionNames[regionId]
            {
                return regionName
            }
            return NSLocalizedString("Assets_Unknown_Region", comment: "")
        }

        // 2. 转换为排序后的数组
        return grouped.filter { !$0.value.isEmpty }
            .map { (region: $0.key, locations: sortLocations($0.value)) }
            .sorted { pair1, pair2 in
                // 确保Unknown Region始终在最后
                if pair1.region == NSLocalizedString("Assets_Unknown_Region", comment: "") {
                    return false
                }
                if pair2.region == NSLocalizedString("Assets_Unknown_Region", comment: "") {
                    return true
                }
                return pair1.region < pair2.region
            }
    }

    // MARK: - 初始化

    init(characterId: Int, databaseManager: DatabaseManager = DatabaseManager()) {
        self.characterId = characterId
        self.databaseManager = databaseManager
    }

    // MARK: - 置顶功能方法

    // 切换置顶状态
    func togglePinLocation(_ location: AssetTreeNode) {
        let isPinned = UserDefaultsManager.shared.isAssetLocationPinned(
            location.location_id, for: characterId
        )

        if isPinned {
            UserDefaultsManager.shared.removePinnedAssetLocation(
                location.location_id, for: characterId
            )
        } else {
            UserDefaultsManager.shared.addPinnedAssetLocation(
                location.location_id, for: characterId
            )
        }

        // 触发UI更新
        objectWillChange.send()
    }

    // MARK: - 私有辅助方法

    // 清理无效的置顶位置ID
    private func cleanupInvalidPinnedLocations() {
        let currentLocationIds = Set(assetLocations.map { $0.location_id })
        let pinnedLocationIds = UserDefaultsManager.shared.getPinnedAssetLocationIDs(
            for: characterId)

        // 找出不再存在于当前资产列表中的置顶ID
        let invalidPinnedIds = pinnedLocationIds.filter { pinnedId in
            !currentLocationIds.contains(pinnedId)
        }

        // 如果有无效的置顶ID，从缓存中移除它们
        if !invalidPinnedIds.isEmpty {
            Logger.info("清理无效的置顶位置ID: \(invalidPinnedIds)")

            let validPinnedIds = pinnedLocationIds.filter { pinnedId in
                currentLocationIds.contains(pinnedId)
            }

            UserDefaultsManager.shared.setPinnedAssetLocationIDs(validPinnedIds, for: characterId)
        }
    }

    // 对位置进行排序
    private func sortLocations(_ locations: [AssetTreeNode]) -> [AssetTreeNode] {
        locations.sorted { loc1, loc2 in
            // 按照system_id名称排序，如果没有system_id信息则排在后面
            if let system1 = loc1.system_id,
               let system2 = loc2.system_id
            {
                return system1 < system2
            }
            // 如果其中一个没有solar system信息，将其排在后面
            return (loc1.system_id) != nil
        }
    }

    // 收集资产树中所有物品的type_id
    private func collectAllTypeIds() -> Set<Int> {
        var typeIds = Set<Int>()

        // 递归函数收集所有type_id
        func collectTypeIds(from node: AssetTreeNode) {
            typeIds.insert(node.type_id)

            if let items = node.items {
                for item in items {
                    collectTypeIds(from: item)
                }
            }
        }

        // 从所有顶层位置开始收集
        for location in assetLocations {
            collectTypeIds(from: location)
        }

        return typeIds
    }

    // 收集资产数据中所有的空间站ID
    private func collectAllStationIds() -> [Int64] {
        var stationIds = Set<Int64>()

        func collectFromNode(_ node: AssetTreeNode) {
            // 如果节点是空间站类型，收集其ID
            if node.location_type == "station" {
                stationIds.insert(node.location_id)
            }

            // 递归处理子节点
            if let items = node.items {
                for item in items {
                    collectFromNode(item)
                }
            }
        }

        // 从所有顶层位置开始收集
        for location in assetLocations {
            collectFromNode(location)
        }

        return Array(stationIds)
    }

    // 从数据库中获取物品信息的辅助方法
    private func fetchItemInfoFromDatabase(_ typeIds: Set<Int>) {
        if typeIds.isEmpty {
            return
        }

        // 构建查询语句，获取物品名称
        let query = """
            SELECT t.type_id, t.name, t.zh_name, t.en_name
            FROM types t
            WHERE t.type_id IN (\(typeIds.sorted().map { String($0) }.joined(separator: ",")))
        """

        if case let .success(rows) = databaseManager.executeQuery(query) {
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                   let name = row["name"] as? String,
                   let zh_name = row["zh_name"] as? String,
                   let en_name = row["en_name"] as? String
                {
                    // 保存到物品信息缓存
                    itemInfoCache[typeId] = ItemInfo(
                        name: name,
                        zh_name: zh_name,
                        en_name: en_name,
                        iconFileName: DatabaseConfig.defaultItemIcon // 默认图标，实际使用时会从节点获取
                    )
                }
            }
        }
    }

    // 查找物品的递归函数
    private func findItems(
        in node: AssetTreeNode, matchingTypeIds: [Int: ItemInfo],
        currentPath: [AssetTreeNode], results: inout [AssetSearchResult]
    ) {
        var path = currentPath
        path.append(node)

        // 如果当前节点的type_id在搜索结果中
        if let itemInfo = matchingTypeIds[node.type_id] {
            // 使用路径的倒数第二个节点作为容器（如果路径长度大于1）
            let container = path.count > 1 ? path[path.count - 2] : node

            // 创建一个包含正确图标的ItemInfo
            let iconName = node.icon_name ?? itemInfo.iconFileName
            let updatedItemInfo = ItemInfo(
                name: itemInfo.name,
                zh_name: itemInfo.zh_name,
                en_name: itemInfo.en_name,
                iconFileName: iconName
            )

            results.append(
                AssetSearchResult(
                    node: node,
                    itemInfo: updatedItemInfo,
                    locationPath: path,
                    containerNode: container,
                    totalQuantity: 0
                ))
        }

        // 递归检查子节点
        if let items = node.items {
            for item in items {
                findItems(
                    in: item, matchingTypeIds: matchingTypeIds, currentPath: path, results: &results
                )
            }
        }
    }

    // MARK: - 公共方法

    // 加载资产数据
    func loadAssets(forceRefresh: Bool = false) async {
        // 如果已经在加载中，直接返回
        guard !isCurrentlyLoading else {
            return
        }

        if forceRefresh {
            loadingProgress = .loading(page: 1)
        } else if !assetLocations.isEmpty {
            // 如果已有数据且不是强制刷新，直接返回
            return
        } else {
            isLoading = true
            loadingProgress = .loading(page: 1)
        }

        // 设置加载标志
        isCurrentlyLoading = true

        do {
            if let jsonString = try await CharacterAssetsJsonAPI.shared.generateAssetTreeJson(
                characterId: characterId,
                forceRefresh: forceRefresh,
                progressCallback: { [weak self] progress in
                    Task { @MainActor in
                        self?.loadingProgress = progress
                        if case .completed = progress {
                            self?.isLoading = false
                        }
                    }
                }
            ) {
                // 解析JSON
                let decoder = JSONDecoder()
                if let data = jsonString.data(using: .utf8) {
                    let wrapper = try decoder.decode(AssetTreeWrapper.self, from: data)

                    // 更新UI
                    assetLocations = wrapper.assetsTree

                    // 获取所有星系的信息
                    await loadRegionNames()

                    // 预加载所有空间站名称
                    await preloadStationNames()

                    // 从数据库加载物品信息
                    await loadItemInfoFromDatabase()

                    // 在内存中填充节点名称
                    await fillNodeNamesInMemory()

                    // 成功加载数据后，清除错误状态
                    error = nil

                    // 清理无效的置顶位置ID
                    cleanupInvalidPinnedLocations()
                }
            }
        } catch {
            // 检查是否是取消错误
            if let nsError = error as NSError?,
               nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled
            {
                Logger.info("资产加载任务被取消")
            } else if error is CancellationError {
                Logger.info("资产加载任务被取消: \(error)")
            } else {
                Logger.error("加载资产失败: \(error)")
                self.error = error

                // 在非取消错误的情况下，确保UI显示错误状态
                isLoading = false
                loadingProgress = nil
            }
        }

        // 只有在成功完成时才重置加载状态
        isLoading = false
        loadingProgress = nil

        // 重置加载标志
        isCurrentlyLoading = false
    }

    // 加载星域名称
    private func loadRegionNames() async {
        // 收集所有需要查询的星系ID
        let systemIds = Set(assetLocations.compactMap { $0.system_id })

        // 如果没有星系ID，直接返回
        if systemIds.isEmpty {
            return
        }

        // 使用批量查询获取所有星系信息
        let systemInfoMap = await getBatchSolarSystemInfo(
            solarSystemIds: Array(systemIds),
            databaseManager: databaseManager
        )

        // 保存星系信息到缓存
        systemInfoCache = systemInfoMap

        // 从查询结果中提取区域信息和星系名称
        for (systemId, systemInfo) in systemInfoMap {
            regionNames[systemInfo.regionId] = systemInfo.regionName
            solarSystemNameCache[systemId] = systemInfo.systemName
        }

        // 触发UI更新
        objectWillChange.send()
    }

    // 预加载所有空间站名称
    private func preloadStationNames() async {
        let stationIds = collectAllStationIds()

        if stationIds.isEmpty {
            Logger.info("没有需要预载的空间站ID")
            return
        }

        // 构建SQL查询，一次性获取所有空间站名称
        let stationIdStrings = stationIds.map { String($0) }.joined(separator: ",")
        let query = """
            SELECT stationID, stationName 
            FROM stations 
            WHERE stationID IN (\(stationIdStrings))
        """

        if case let .success(rows) = databaseManager.executeQuery(query) {
            for row in rows {
                if let stationId = row["stationID"] as? Int,
                   let name = row["stationName"] as? String
                {
                    stationNameCache[Int64(stationId)] = name
                }
            }
        }
    }

    // 从数据库中加载物品信息
    private func loadItemInfoFromDatabase() async {
        // 收集所有需要的type_id
        let typeIds = collectAllTypeIds()
        // 使用辅助方法从数据库中获取信息
        fetchItemInfoFromDatabase(typeIds)
    }

    // 搜索资产
    func searchAssets(query: String) async {
        guard !query.isEmpty else {
            searchResults = []
            return
        }

        // 使用缓存的物品信息进行搜索，而不是查询数据库
        var matchingTypeIds: [Int: ItemInfo] = [:]
        let lowercasedQuery = query.lowercased()

        // 在缓存中查找匹配搜索条件的物品
        for (typeId, itemInfo) in itemInfoCache {
            // 搜索中英文名称
            if itemInfo.zh_name.lowercased().contains(lowercasedQuery)
                || itemInfo.en_name.lowercased().contains(lowercasedQuery)
            {
                matchingTypeIds[typeId] = itemInfo
            }
        }

        // 在资产数据中查找这些type_id对应的item_id
        var rawResults: [AssetSearchResult] = []
        for location in assetLocations {
            findItems(
                in: location, matchingTypeIds: matchingTypeIds, currentPath: [],
                results: &rawResults
            )
        }

        // 按位置和物品类型合并结果
        var mergedResults: [String: AssetSearchResult] = [:]

        for result in rawResults {
            // 创建合并键：type_id + 容器ID + 位置路径
            let mergeKey =
                "\(result.node.type_id)_\(result.containerNode.item_id)_\(result.formattedPath.hashValue)"

            if let existingResult = mergedResults[mergeKey] {
                // 合并数量
                let newTotalQuantity = existingResult.totalQuantity + result.node.quantity

                let mergedResult = AssetSearchResult(
                    node: existingResult.node, // 保持第一个节点的信息
                    itemInfo: existingResult.itemInfo,
                    locationPath: existingResult.locationPath,
                    containerNode: existingResult.containerNode,
                    totalQuantity: newTotalQuantity
                )
                mergedResults[mergeKey] = mergedResult
            } else {
                // 第一次遇到这个物品在这个位置
                let initialResult = AssetSearchResult(
                    node: result.node,
                    itemInfo: result.itemInfo,
                    locationPath: result.locationPath,
                    containerNode: result.containerNode,
                    totalQuantity: result.node.quantity
                )
                mergedResults[mergeKey] = initialResult
            }
        }

        // 转换为数组并排序
        let finalResults = Array(mergedResults.values).sorted {
            $0.itemInfo.name < $1.itemInfo.name
        }

        // 更新搜索结果
        searchResults = finalResults
    }

    // 在内存中填充节点名称
    private func fillNodeNamesInMemory() async {
        // 递归函数，填充节点及其所有子节点的名称
        func fillNodeName(_ node: inout AssetTreeNode) {
            // 为空间站节点填充名称
            if node.location_type == "station", node.name == nil {
                node.name = stationNameCache[node.location_id]
            }

            // 为星系节点填充名称
            if node.location_type == "solar_system", node.name == nil,
               let systemId = node.system_id
            {
                node.name = solarSystemNameCache[systemId]
            }

            // 递归处理子节点
            if var items = node.items {
                for i in 0 ..< items.count {
                    fillNodeName(&items[i])
                }
                node.items = items
            }
        }

        // 遍历并处理所有顶层位置节点
        for i in 0 ..< assetLocations.count {
            var location = assetLocations[i]
            fillNodeName(&location)
            assetLocations[i] = location
        }
    }
}
