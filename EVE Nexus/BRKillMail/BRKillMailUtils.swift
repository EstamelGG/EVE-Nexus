import Foundation

class BRKillMailUtils {
    static let shared = BRKillMailUtils()
    private let databaseManager = DatabaseManager.shared
    
    private init() {}
    
    func convertImplantsToFitting(victInfo: [String: Any], items: [[Int]]) -> [[Int]] {
        // 检查是否为太空舱
        guard let shipId = victInfo["ship"] as? Int,
              (shipId == 670 || shipId == 33328) else {
            return items
        }
        
        // 获取所有植入体
        let implantItems = items.filter { $0[0] == 89 && $0.count >= 4 }
        if implantItems.isEmpty {
            return items
        }
        
        // 获取所有植入体的type_id
        let implantTypeIds = implantItems.map { $0[1] }
        
        // 查询植入体的槽位信息
        let placeholders = String(repeating: "?,", count: implantTypeIds.count).dropLast()
        let query = """
            SELECT type_id, value 
            FROM typeAttributes 
            WHERE type_id IN (\(placeholders)) 
            AND attribute_id = 331 
            AND value <= 10
        """
        
        var implantSlots: [Int: Int] = [:] // type_id -> slot
        if case let .success(rows) = databaseManager.executeQuery(query, parameters: implantTypeIds) {
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                   let slot = row["value"] as? Double {
                    implantSlots[typeId] = Int(slot)
                }
            }
        }
        
        // 创建新的items数组，包含原始的非植入体物品
        var newItems = items.filter { $0[0] != 89 }
        
        // 将植入体转换为对应的槽位物品
        for item in implantItems {
            let typeId = item[1]
            guard let slot = implantSlots[typeId] else { continue }
            
            // 转换为对应的槽位
            var newSlot: Int
            if slot <= 5 {
                // 高槽1-5 (27-31)
                newSlot = 26 + slot
            } else if slot <= 10 {
                // 中槽1-5 (19-23)
                newSlot = 18 + (slot - 5)
            } else {
                continue
            }
            
            // 创建新的物品数组，保持原始的数量信息
            let newItem = [newSlot, typeId, item[2], item[3]]
            newItems.append(newItem)
        }
        
        return newItems
    }
} 