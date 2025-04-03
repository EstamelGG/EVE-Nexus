import Foundation
import SwiftUI

// 搜索结果路径节点
struct AssetPathNode {
    let node: AssetTreeNode
    let isTarget: Bool  // 是否为搜索目标物品
}

// 搜索结果
struct AssetSearchResult: Identifiable {
    let node: AssetTreeNode  // 目标物品节点
    let itemInfo: ItemInfo  // 物品基本信息
    let locationPath: [AssetTreeNode]  // 从顶层位置到物品的完整路径
    let containerNode: AssetTreeNode  // 直接容器节点

    var id: Int64 { node.item_id }

    // 格式化的位置路径字符串，只显示到倒数第二级
    var formattedPath: String {
        // 如果路径少于2个节点，直接返回完整路径
        guard locationPath.count >= 2 else {
            return locationPath.map { node in
                node.name ?? NSLocalizedString("Unknown_System", comment: "")
            }.joined(separator: " > ")
        }

        // 去掉最后一个节点（当前物品），只显示到倒数第二级
        let pathToShow = locationPath.dropLast()
        return pathToShow.map { node in
            node.name ?? NSLocalizedString("Unknown_System", comment: "")
        }.joined(separator: " > ")
    }
}

@MainActor
class CharacterAssetsViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var assetLocations: [AssetTreeNode] = []
    @Published var error: Error?
    @Published var loadingProgress: AssetLoadingProgress?
    @Published var searchResults: [AssetSearchResult] = []  // 添加搜索结果属性
    @Published var regionNames: [Int: String] = [:]  // (本地化名称, 英文名称)
    @Published var systemInfoCache: [Int: SolarSystemInfo] = [:]  // 添加星系信息缓存
    @AppStorage("useEnglishSystemNames") private var useEnglishSystemNames = false

    // 添加一个标志来跟踪是否正在加载
    private var isCurrentlyLoading = false

    // 添加一个缓存来存储所有物品信息
    private(set) var itemInfoCache: [Int: ItemInfo] = [:]

    private let characterId: Int
    private let databaseManager: DatabaseManager

    init(characterId: Int, databaseManager: DatabaseManager = DatabaseManager()) {
        self.characterId = characterId
        self.databaseManager = databaseManager
    }

    // 按星域分组的位置
    var locationsByRegion: [(region: String, locations: [AssetTreeNode])] {
        // 1. 按区域分组
        let grouped = Dictionary(grouping: assetLocations) { location in
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

                    // 从数据库加载物品信息
                    await loadItemInfoFromDatabase()

                    // 成功加载数据后，清除错误状态
                    self.error = nil
                }
            }
        } catch {
            // 检查是否是取消错误
            if let nsError = error as NSError?,
                nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
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

        // 从查询结果中提取区域信息
        for (_, systemInfo) in systemInfoMap {
            regionNames[systemInfo.regionId] = systemInfo.regionName
        }

        // 触发UI更新
        objectWillChange.send()
    }

    // 搜索资产
    func searchAssets(query: String) async {
        guard !query.isEmpty else {
            searchResults = []
            return
        }

        // 使用缓存的物品信息进行搜索，而不是查询数据库
        var matchingTypeIds: [Int: ItemInfo] = [:]

        // 在缓存中查找匹配搜索条件的物品
        for (typeId, itemInfo) in itemInfoCache {
            if itemInfo.name.lowercased().contains(query.lowercased()) {
                matchingTypeIds[typeId] = itemInfo
            }
        }

        // 在资产数据中查找这些type_id对应的item_id
        var results: [AssetSearchResult] = []
        for location in assetLocations {
            findItems(
                in: location, matchingTypeIds: matchingTypeIds, currentPath: [], results: &results)
        }

        // 按物品名称排序结果
        results.sort { $0.itemInfo.name < $1.itemInfo.name }

        // 更新搜索结果
        searchResults = results
    }

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
            let updatedItemInfo = ItemInfo(name: itemInfo.name, iconFileName: iconName)

            results.append(
                AssetSearchResult(
                    node: node,
                    itemInfo: updatedItemInfo,
                    locationPath: path,
                    containerNode: container
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

    // 新增方法：收集资产树中所有物品的type_id
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

    // 新增方法：从数据库中加载物品信息
    private func loadItemInfoFromDatabase() async {
        // 收集所有需要的type_id
        let typeIds = collectAllTypeIds()

        if typeIds.isEmpty {
            return
        }

        // 构建查询语句，获取物品名称
        let query = """
                SELECT type_id, name
                FROM types
                WHERE type_id IN (\(typeIds.sorted().map { String($0) }.joined(separator: ",")))
            """

        if case let .success(rows) = databaseManager.executeQuery(query) {
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                    let name = row["name"] as? String
                {
                    // 保存到物品信息缓存
                    itemInfoCache[typeId] = ItemInfo(
                        name: name,
                        iconFileName: DatabaseConfig.defaultItemIcon  // 默认图标，实际使用时会从节点获取
                    )
                }
            }
        }
    }
}

// 物品信息结构体
struct ItemInfo {
    let name: String
    let iconFileName: String
}
