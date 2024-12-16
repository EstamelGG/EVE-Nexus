extension MarketManager {
    // 递归获取所有子组ID（包括当前组ID）
    func getAllSubGroupIDs(_ allGroups: [MarketGroup], startingFrom groupID: Int) -> [Int] {
        var result = [groupID]
        
        // 获取直接子组
        let subGroups = getSubGroups(allGroups, for: groupID)
        
        // 递归获取每个子组的子组
        for subGroup in subGroups {
            result.append(contentsOf: getAllSubGroupIDs(allGroups, startingFrom: subGroup.id))
        }
        
        return result
    }
} 