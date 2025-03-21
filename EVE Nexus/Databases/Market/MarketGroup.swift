import Foundation

struct MarketGroup: Identifiable {
    let id: Int  // group_id
    let name: String  // 目录名称
    let description: String  // 描述
    let iconName: String  // 图标文件名
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

        if case let .success(rows) = databaseManager.executeQuery(query) {
            for row in rows {
                if let groupID = row["group_id"] as? Int,
                    let name = row["name"] as? String,
                    let description = row["description"] as? String,
                    let iconName = row["icon_name"] as? String
                {
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
    func getRootGroups(_ groups: [MarketGroup], allowedIDs: Set<Int>? = nil) -> [MarketGroup] {
        let rootGroups = groups.filter { $0.parentGroupID == nil }

        // 如果提供了Group ID白名单集合，则进行过滤
        if let allowedIDs = allowedIDs {
            return rootGroups.filter { allowedIDs.contains($0.id) }
        }

        return rootGroups
    }

    // 获取子目录
    func getSubGroups(_ groups: [MarketGroup], for parentID: Int) -> [MarketGroup] {
        return groups.filter { $0.parentGroupID == parentID }
    }

    // 检查是否是最后一级目录
    func isLeafGroup(_ group: MarketGroup, in groups: [MarketGroup]) -> Bool {
        return !groups.contains { $0.parentGroupID == group.id }
    }

    // 根据顶级目录白名单获取所有允许的市场组ID
    func getAllowedGroupIDs(_ groups: [MarketGroup], allowedIDs: Set<Int>) -> [Int] {
        var result: [Int] = []

        // 获取所有允许的顶级目录
        let rootGroups = getRootGroups(groups, allowedIDs: allowedIDs)

        // 递归获取所有子目录ID
        for rootGroup in rootGroups {
            result.append(contentsOf: getAllSubGroupIDs(groups, startingFrom: rootGroup.id))
        }

        return result
    }
}
