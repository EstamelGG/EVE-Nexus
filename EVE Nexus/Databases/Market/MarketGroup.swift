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

    // 获取默认的展示的顶级目录
    func getRootGroups(_ groups: [MarketGroup], allowedIDs: Set<Int>? = nil) -> [MarketGroup] {
        let rootGroups = groups.filter { $0.parentGroupID == nil }

        // 如果提供了Group ID白名单集合，则进行过滤
        if let allowedIDs = allowedIDs {
            return rootGroups.filter { allowedIDs.contains($0.id) }
        }

        return rootGroups
    }

    // 将指定的ID设为展示的顶级目录
    func setRootGroups(_ groups: [MarketGroup], allowedIDs: Set<Int>? = nil) -> [MarketGroup] {
        guard let allowedIDs = allowedIDs, !allowedIDs.isEmpty else {
            return groups.filter { $0.parentGroupID == nil }
        }

        return groups.filter { allowedIDs.contains($0.id) }
    }

    // 获取子目录
    func getSubGroups(_ groups: [MarketGroup], for parentID: Int) -> [MarketGroup] {
        return groups.filter { $0.parentGroupID == parentID }
    }

    // 检查是否是最后一级目录
    func isLeafGroup(_ group: MarketGroup, in groups: [MarketGroup]) -> Bool {
        return !groups.contains { $0.parentGroupID == group.id }
    }

    // 根据顶级目录白名单获取所有子目录的GroupID
    func getAllSubGroupIDsFromIDs(_ groups: [MarketGroup], allowedIDs: Set<Int>) -> [Int] {
        // 传入的allowedIDs可以是非顶级目录
        var result: [Int] = []
        for rootGroupId in allowedIDs {
            result.append(contentsOf: getAllSubGroupIDsFromID(groups, startingFrom: rootGroupId))
        }
        return result
    }

    // 获取指定父组ID的直接子组ID（不包括子组的子组）
    func getChildGroupIDs(_ groups: [MarketGroup], parentGroupID: Int) -> [Int] {
        return getSubGroups(groups, for: parentGroupID).map { $0.id }
    }

    // 递归获取所有子组ID（包括当前组ID）
    func getAllSubGroupIDsFromID(_ allGroups: [MarketGroup], startingFrom groupID: Int) -> [Int] {
        var result = [groupID]

        // 获取直接子组
        let subGroups = getSubGroups(allGroups, for: groupID)

        // 递归获取每个子组的子组
        for subGroup in subGroups {
            result.append(contentsOf: getAllSubGroupIDsFromID(allGroups, startingFrom: subGroup.id))
        }

        return result
    }
}
