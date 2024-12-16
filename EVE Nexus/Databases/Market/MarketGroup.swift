import Foundation

struct MarketGroup: Identifiable {
    let id: Int              // group_id
    let name: String         // 目录名称
    let description: String  // 描述
    let iconName: String     // 图标文件名
    let parentGroupID: Int?  // 父目录ID
}

class MarketManager {
    static let shared = MarketManager()
    private init() {}
    
    // 加载市场组数据
    func loadMarketGroups(databaseManager: DatabaseManager) -> [MarketGroup] {
        let query = """
            SELECT group_id, name, description, icon_name, parentgroup_id
            FROM marketGroups
            ORDER BY group_id
        """
        
        var groups: [MarketGroup] = []
        
        if case .success(let rows) = databaseManager.executeQuery(query) {
            for row in rows {
                if let groupID = row["group_id"] as? Int,
                   let name = row["name"] as? String,
                   let description = row["description"] as? String,
                   let iconName = row["icon_name"] as? String {
                    let parentGroupID = row["parentgroup_id"] as? Int
                    
                    let group = MarketGroup(
                        id: groupID,
                        name: name,
                        description: description,
                        iconName: iconName,
                        parentGroupID: parentGroupID
                    )
                    groups.append(group)
                }
            }
        }
        
        return groups
    }
    
    // 获取顶级目录
    func getRootGroups(_ groups: [MarketGroup]) -> [MarketGroup] {
        return groups.filter { $0.parentGroupID == nil }
    }
    
    // 获取子目录
    func getSubGroups(_ groups: [MarketGroup], for parentID: Int) -> [MarketGroup] {
        return groups.filter { $0.parentGroupID == parentID }
    }
    
    // 检查是否是最后一级目录
    func isLeafGroup(_ group: MarketGroup, in groups: [MarketGroup]) -> Bool {
        return !groups.contains { $0.parentGroupID == group.id }
    }
} 