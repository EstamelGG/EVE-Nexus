import Foundation

// 装配槽位flag枚举，支持ESI API返回的所有flag字符串
enum FittingFlag: String, Codable, CaseIterable {
    case cargo = "Cargo"
    case droneBay = "DroneBay"
    case fighterBay = "FighterBay"
    // 高槽
    case hiSlot0 = "HiSlot0"
    case hiSlot1 = "HiSlot1"
    case hiSlot2 = "HiSlot2"
    case hiSlot3 = "HiSlot3"
    case hiSlot4 = "HiSlot4"
    case hiSlot5 = "HiSlot5"
    case hiSlot6 = "HiSlot6"
    case hiSlot7 = "HiSlot7"
    // 低槽
    case loSlot0 = "LoSlot0"
    case loSlot1 = "LoSlot1"
    case loSlot2 = "LoSlot2"
    case loSlot3 = "LoSlot3"
    case loSlot4 = "LoSlot4"
    case loSlot5 = "LoSlot5"
    case loSlot6 = "LoSlot6"
    case loSlot7 = "LoSlot7"
    // 中槽
    case medSlot0 = "MedSlot0"
    case medSlot1 = "MedSlot1"
    case medSlot2 = "MedSlot2"
    case medSlot3 = "MedSlot3"
    case medSlot4 = "MedSlot4"
    case medSlot5 = "MedSlot5"
    case medSlot6 = "MedSlot6"
    case medSlot7 = "MedSlot7"
    // 改装槽
    case rigSlot0 = "RigSlot0"
    case rigSlot1 = "RigSlot1"
    case rigSlot2 = "RigSlot2"
    // 服务槽
    case serviceSlot0 = "ServiceSlot0"
    case serviceSlot1 = "ServiceSlot1"
    case serviceSlot2 = "ServiceSlot2"
    case serviceSlot3 = "ServiceSlot3"
    case serviceSlot4 = "ServiceSlot4"
    case serviceSlot5 = "ServiceSlot5"
    case serviceSlot6 = "ServiceSlot6"
    case serviceSlot7 = "ServiceSlot7"
    // 子系统槽
    case subSystemSlot0 = "SubSystemSlot0"
    case subSystemSlot1 = "SubSystemSlot1"
    case subSystemSlot2 = "SubSystemSlot2"
    case subSystemSlot3 = "SubSystemSlot3"
    // T3D模式槽
    case t3dModeSlot0 = "T3DModeSlot0"

    case invalid = "Invalid"
}

// 在线配置结构体（与ESI返回结构一致）
struct FittingItem: Codable {
    let flag: FittingFlag
    let quantity: Int
    let type_id: Int
}

struct OnlineFitting: Codable {
    let description: String
    let fitting_id: Int
    let items: [FittingItem]
    let name: String
    let ship_type_id: Int
}

// 本地配置结构体
struct LocalFittingItem: Codable {
    let flag: FittingFlag
    let quantity: Int
    let type_id: Int
    let status: Int?           // 装备状态（可选）
    let charge_type_id: Int?   // 弹药类型ID（可选）
    let charge_quantity: Int?  // 弹药数量（可选）
}

struct LocalFitting: Codable {
    let description: String
    let fitting_id: Int
    let items: [LocalFittingItem]
    let name: String
    let ship_type_id: Int
    let drones: [Drone]?           // 无人机列表
    let fighters: [FighterSquad]?  // 舰载机中队列表
    let cargo: [CargoItem]?        // 货舱物品列表
    let implants: [Int]?           // 植入体typeId列表
    let environment_type_id: Int?  // 环境typeId（可选）
}

// 无人机结构体
struct Drone: Codable {
    let type_id: Int           // 无人机类型ID
    let quantity: Int         // 携带数量
    let active_count: Int      // 激活数量
}

// 货舱物品结构体
struct CargoItem: Codable {
    let type_id: Int           // 物品类型ID
    let quantity: Int         // 物品数量
}

// 舰载机中队结构体
struct FighterSquad: Codable {
    let type_id: Int           // 舰载机类型ID
    let quantity: Int          // 舰载机数量
    let tubeId: Int            // 舰载机发射管ID
}
