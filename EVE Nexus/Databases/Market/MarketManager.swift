extension MarketManager {
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
    
    // 获取指定父分组下的所有子分组ID
    func getChildGroupIDs(_ allGroups: [MarketGroup], parentGroupID: Int) -> [Int] {
        return allGroups
            .filter { $0.parentGroupID == parentGroupID }
            .map { $0.id }
    }
}
