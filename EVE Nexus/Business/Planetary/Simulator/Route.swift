import Foundation

/// 商品类型
struct CommodityType {
    let id: Int64
    let name: String
    let volume: Double
    
    static func fromTypeId(_ typeId: Int64) -> CommodityType? {
        let query = "SELECT type_id, type_name, volume FROM types WHERE type_id = \(typeId)"
        if case .success(let rows) = DatabaseManager.shared.executeQuery(query),
           let row = rows.first,
           let id = row["type_id"] as? Int64,
           let name = row["type_name"] as? String,
           let volume = row["volume"] as? Double {
            return CommodityType(id: id, name: name, volume: volume)
        }
        return nil
    }
}

/// 路由
struct Route {
    let id: Int64           // 路由ID
    let sourcePinId: Int64  // 源设施ID
    let destinationPinId: Int64  // 目标设施ID
    let commodityType: CommodityType  // 商品类型
    let quantity: Int64    // 数量
    let waypoints: [Int64]? // 路由点（可选）
} 