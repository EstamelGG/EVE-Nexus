import Foundation

// 搜索结果路径节点
struct AssetPathNode {
    let node: AssetTreeNode
    let isTarget: Bool  // 是否为搜索目标物品
}

// 搜索结果
struct AssetSearchResult {
    let path: [AssetPathNode]  // 从根节点到目标物品的完整路径
    let itemName: String       // 物品名称
    let iconFileName: String   // 物品图标文件名
    
    var locationName: String? {
        path.first?.node.name
    }
    
    var containerNode: AssetTreeNode? {
        // 如果路径长度大于1，返回目标物品的直接容器
        // 否则返回顶层位置节点
        path.count > 1 ? path[path.count - 2].node : path.first?.node
    }
}

@MainActor
class CharacterAssetsViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var assetLocations: [AssetTreeNode] = []
    @Published var error: Error?
    @Published var loadingProgress: AssetLoadingProgress?
    @Published var searchResults: [AssetSearchResult] = []  // 添加搜索结果属性
    
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
            location.region_name ?? NSLocalizedString("Assets_Unknown_Region", comment: "")
        }
        
        // 2. 转换为排序后的数组
        return grouped.filter { !$0.value.isEmpty }
            .map { (region: $0.key, locations: sortLocations($0.value)) }
            .sorted { pair1, pair2 in
                // 确保Unknown Region始终在最后
                if pair1.region == NSLocalizedString("Assets_Unknown_Region", comment: "") { return false }
                if pair2.region == NSLocalizedString("Assets_Unknown_Region", comment: "") { return true }
                return pair1.region < pair2.region
            }
    }
    
    // 对位置进行排序
    private func sortLocations(_ locations: [AssetTreeNode]) -> [AssetTreeNode] {
        locations.sorted { loc1, loc2 in
            // 按照solar system名称排序，如果没有solar system信息则排在后面
            if let system1 = loc1.system_name,
               let system2 = loc2.system_name {
                return system1 < system2
            }
            // 如果其中一个没有solar system信息，将其排在后面
            return loc1.system_name != nil
        }
    }
    
    // 加载资产数据
    func loadAssets(forceRefresh: Bool = false) async {
        if forceRefresh {
            loadingProgress = .fetchingPage(1)
        } else if !assetLocations.isEmpty {
            // 如果已有数据且不是强制刷新，直接返回
            return
        } else {
            isLoading = true
        }
        
        do {
            if let jsonString = try await CharacterAssetsJsonAPI.shared.generateAssetTreeJson(
                characterId: characterId,
                forceRefresh: forceRefresh,
                progressCallback: { progress in
                    Task { @MainActor in
                        self.loadingProgress = progress
                    }
                }
            ) {
                // 解析JSON
                let decoder = JSONDecoder()
                let data = jsonString.data(using: .utf8)!
                let locations = try decoder.decode([AssetTreeNode].self, from: data)
                
                // 更新UI
                self.assetLocations = locations
            }
        } catch {
            Logger.error("加载资产失败: \(error)")
            self.error = error
        }
        
        isLoading = false
        loadingProgress = nil
    }
    
    // 获取物品信息
    func getItemInfo(for typeIds: Set<Int>) async -> [Int: ItemInfo] {
        var itemInfoCache: [Int: ItemInfo] = [:]
        let query = """
            SELECT type_id, name, icon_filename
            FROM types
            WHERE type_id IN (\(typeIds.map { String($0) }.joined(separator: ",")))
        """
        
        if case .success(let rows) = databaseManager.executeQuery(query) {
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                   let name = row["name"] as? String {
                    let iconFileName = (row["icon_filename"] as? String) ?? DatabaseConfig.defaultItemIcon
                    itemInfoCache[typeId] = ItemInfo(name: name, iconFileName: iconFileName)
                }
            }
        }
        
        return itemInfoCache
    }
    
    // 搜索资产
    func searchAssets(query: String) async {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        // 获取所有type_id和对应的名称和图标
        let itemQuery = """
            SELECT type_id, name, icon_filename
            FROM types
            WHERE LOWER(name) LIKE LOWER('%\(query)%')
            ORDER BY name
        """
        Logger.debug("Search for \(query)")
        var typeIdToInfo: [Int: (name: String, iconFileName: String)] = [:]
        if case .success(let rows) = databaseManager.executeQuery(itemQuery) {
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                   let name = row["name"] as? String {
                    let iconFileName = (row["icon_filename"] as? String) ?? DatabaseConfig.defaultItemIcon
                    typeIdToInfo[typeId] = (name: name, iconFileName: iconFileName)
                }
            }
        }
        
        var results: [AssetSearchResult] = []
        
        // 递归搜索函数
        func searchNode(_ node: AssetTreeNode, currentPath: [AssetPathNode]) {
            // 检查当前节点是否匹配
            if let items = node.items {
                for item in items {
                    // 如果物品类型匹配搜索条件
                    if let itemInfo = typeIdToInfo[item.type_id] {
                        // 创建新路径，包含当前路径和目标物品
                        var newPath = currentPath
                        newPath.append(AssetPathNode(node: item, isTarget: true))
                        
                        // 创建搜索结果
                        results.append(AssetSearchResult(
                            path: newPath,
                            itemName: itemInfo.name,
                            iconFileName: itemInfo.iconFileName
                        ))
                    }
                    
                    // 如果当前物品是容器，继续搜索其内容
                    if item.items != nil {
                        var newPath = currentPath
                        newPath.append(AssetPathNode(node: item, isTarget: false))
                        searchNode(item, currentPath: newPath)
                    }
                }
            }
        }
        
        // 开始搜索每个顶层位置
        for location in assetLocations {
            let rootPath = [AssetPathNode(node: location, isTarget: false)]
            searchNode(location, currentPath: rootPath)
        }
        
        // 按物品名称排序结果
        results.sort { $0.itemName < $1.itemName }
        
        // 更新搜索结果
        self.searchResults = results
    }
}

// 物品信息结构体
struct ItemInfo {
    let name: String
    let iconFileName: String
} 
