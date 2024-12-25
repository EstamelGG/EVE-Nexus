import Foundation

@MainActor
class CharacterAssetsViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var assetLocations: [AssetTreeNode] = []
    @Published var error: Error?
    
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
            location.region_name ?? "Unknown Region"
        }
        
        // 2. 转换为排序后的数组
        return grouped.filter { !$0.value.isEmpty }
            .map { (region: $0.key, locations: sortLocations($0.value)) }
            .sorted { pair1, pair2 in
                // 确保Unknown Region始终在最后
                if pair1.region == "Unknown Region" { return false }
                if pair2.region == "Unknown Region" { return true }
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
        guard !isLoading else { return }
        
        isLoading = true
        error = nil
        
        do {
            // 获取JSON数据（现在支持缓存）
            if let jsonString = try await CharacterAssetsJsonAPI.shared.generateAssetTreeJson(
                characterId: characterId,
                forceRefresh: forceRefresh
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
}

// 物品信息结构体
struct ItemInfo {
    let name: String
    let iconFileName: String
} 
