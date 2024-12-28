import Foundation

// 搜索结果路径节点
struct AssetPathNode {
    let node: AssetTreeNode
    let isTarget: Bool  // 是否为搜索目标物品
}

// 搜索结果
struct AssetSearchResult: Identifiable {
    let node: AssetTreeNode          // 目标物品节点
    let itemInfo: ItemInfo           // 物品基本信息
    let locationName: String         // 位置名称
    let containerNode: AssetTreeNode // 容器节点
    
    var id: Int64 { node.item_id }
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
            loadingProgress = .loading
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
                progressCallback: { [weak self] progress in
                    Task { @MainActor in
                        if case .completed = progress {
                            self?.loadingProgress = nil
                        } else {
                            self?.loadingProgress = .loading
                        }
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
        
        // 1. 先从数据库获取匹配名称的物品类型ID
        let itemQuery = """
            SELECT type_id, name, icon_filename
            FROM types 
            WHERE LOWER(name) LIKE LOWER('%\(query)%')
        """
        
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
        
        // 2. 在资产数据中查找这些type_id对应的item_id
        var results: [AssetSearchResult] = []
        for location in assetLocations {
            findItems(in: location, typeIdToInfo: typeIdToInfo, parentNode: nil, results: &results)
        }
        
        // 按物品名称排序结果
        results.sort { $0.itemInfo.name < $1.itemInfo.name }
        
        // 更新搜索结果
        self.searchResults = results
    }
    
    private func findItems(in node: AssetTreeNode, typeIdToInfo: [Int: (name: String, iconFileName: String)], parentNode: AssetTreeNode?, results: inout [AssetSearchResult]) {
        // 如果当前节点的type_id在搜索结果中
        if let itemInfo = typeIdToInfo[node.type_id] {
            // 如果有父节点，使用父节点作为容器；否则使用当前节点
            let container = parentNode ?? node
            results.append(AssetSearchResult(
                node: node,
                itemInfo: ItemInfo(name: itemInfo.name, iconFileName: itemInfo.iconFileName),
                locationName: container.name ?? container.system_name ?? NSLocalizedString("Unknown_System", comment: ""),
                containerNode: container
            ))
        }
        
        // 递归检查子节点
        if let items = node.items {
            for item in items {
                findItems(in: item, typeIdToInfo: typeIdToInfo, parentNode: node, results: &results)
            }
        }
    }
}

// 物品信息结构体
struct ItemInfo {
    let name: String
    let iconFileName: String
} 
