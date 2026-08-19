import Foundation

/// 装配槽位flag枚举，支持ESI API返回的所有flag字符串
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
    /// T3D模式槽
    case t3dModeSlot0 = "T3DModeSlot0"

    case invalid = "Invalid"
}

/// 在线配置结构体（与ESI返回结构一致）
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

/// 突变属性数据结构
struct MutationData: Codable {
    let mutaplasmid_id: Int // 突变质体ID
    let attribute_id: Int // 突变属性ID
    let value: Double // 突变数值（不带百分号，如15表示15%）
}

/// 装配引用：本地装配用 UUID，线上装配用 ESI 的 Int ID。
/// 全链路（模型/持久化/导航树/详情）统一使用，避免裸 Int 混淆
enum FittingRef: Hashable {
    case local(UUID)
    case online(Int)

    /// 日志与字典展示用
    var debugDescription: String {
        switch self {
        case let .local(id): return "local:\(id.uuidString)"
        case let .online(id): return "online:\(id)"
        }
    }
}

/// 无法正常解析的本地装配（仅保留展示所需元数据，不可打开，仅提醒）
struct UnreadableFitting: Identifiable {
    let fileName: String // 源文件名（稳定身份/日志定位）
    let name: String? // 抢救出的装配名（可能为 nil）
    let shipTypeId: Int? // 抢救出的飞船ID（可能为 nil）

    var id: String {
        fileName
    }

    /// 展示名称（未知时回退为“未命名”）
    var displayName: String {
        guard let name, !name.isEmpty else { return NSLocalizedString("Unnamed", comment: "") }
        return name
    }
}

/// 本地配置结构体
struct LocalFittingItem: Codable {
    let flag: FittingFlag
    let quantity: Int
    let type_id: Int
    let status: Int? // 装备状态（可选）
    let charge_type_id: Int? // 弹药类型ID（可选）
    let charge_quantity: Int? // 弹药数量（可选）
    let muta: [MutationData]? // 突变数据（可选）
    /// 完全预热；缺失或为 `nil` 时视为开启（与旧装配文件兼容）
    let spool_up_full: Bool?

    init(
        flag: FittingFlag,
        quantity: Int,
        type_id: Int,
        status: Int? = nil,
        charge_type_id: Int? = nil,
        charge_quantity: Int? = nil,
        muta: [MutationData]? = nil,
        spool_up_full: Bool? = nil
    ) {
        self.flag = flag
        self.quantity = quantity
        self.type_id = type_id
        self.status = status
        self.charge_type_id = charge_type_id
        self.charge_quantity = charge_quantity
        self.muta = muta
        self.spool_up_full = spool_up_full
    }
}

struct LocalFitting: Codable {
    let description: String
    let fitting_id: UUID
    let items: [LocalFittingItem]
    let name: String
    let ship_type_id: Int
    let drones: [Drone]? // 无人机列表
    let fighters: [FighterSquad]? // 舰载机中队列表
    let cargo: [CargoItem]? // 货舱物品列表
    let implants: [Int]? // 植入体typeId列表
    let environment_type_id: Int? // 环境typeId（可选）

    private enum CodingKeys: String, CodingKey {
        case description, fitting_id, items, name, ship_type_id, drones, fighters, cargo
        case implants, environment_type_id
    }

    init(
        description: String,
        fitting_id: UUID,
        items: [LocalFittingItem],
        name: String,
        ship_type_id: Int,
        drones: [Drone]? = nil,
        fighters: [FighterSquad]? = nil,
        cargo: [CargoItem]? = nil,
        implants: [Int]? = nil,
        environment_type_id: Int? = nil
    ) {
        self.description = description
        self.fitting_id = fitting_id
        self.items = items
        self.name = name
        self.ship_type_id = ship_type_id
        self.drones = drones
        self.fighters = fighters
        self.cargo = cargo
        self.implants = implants
        self.environment_type_id = environment_type_id
    }

    /// 兼容解码：新版 fitting_id 为 UUID 字符串；旧版为时间戳 Int，
    /// 解码时生成新 UUID（持久化层检测到文件名与新 ID 不一致时会重写迁移）
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        description = try container.decode(String.self, forKey: .description)
        if let uuid = try? container.decode(UUID.self, forKey: .fitting_id) {
            fitting_id = uuid
        } else {
            fitting_id = UUID()
        }
        items = try container.decode([LocalFittingItem].self, forKey: .items)
        name = try container.decode(String.self, forKey: .name)
        ship_type_id = try container.decode(Int.self, forKey: .ship_type_id)
        drones = try container.decodeIfPresent([Drone].self, forKey: .drones)
        fighters = try container.decodeIfPresent([FighterSquad].self, forKey: .fighters)
        cargo = try container.decodeIfPresent([CargoItem].self, forKey: .cargo)
        implants = try container.decodeIfPresent([Int].self, forKey: .implants)
        environment_type_id = try container.decodeIfPresent(Int.self, forKey: .environment_type_id)
    }

    /// 重命名（ID 与其余字段不变）
    func renamed(_ newName: String) -> LocalFitting {
        LocalFitting(
            description: description,
            fitting_id: fitting_id,
            items: items,
            name: newName,
            ship_type_id: ship_type_id,
            drones: drones,
            fighters: fighters,
            cargo: cargo,
            implants: implants,
            environment_type_id: environment_type_id
        )
    }

    /// 生成副本：新 ID + 新名称，其余字段不变
    func duplicated(newId: UUID, name newName: String) -> LocalFitting {
        LocalFitting(
            description: description,
            fitting_id: newId,
            items: items,
            name: newName,
            ship_type_id: ship_type_id,
            drones: drones,
            fighters: fighters,
            cargo: cargo,
            implants: implants,
            environment_type_id: environment_type_id
        )
    }
}

/// 无人机结构体
struct Drone: Codable {
    let type_id: Int // 无人机类型ID
    let quantity: Int // 携带数量
    let active_count: Int // 激活数量
    let muta: [MutationData]? // 突变数据（可选）
}

/// 货舱物品结构体
struct CargoItem: Codable {
    let type_id: Int // 物品类型ID
    let quantity: Int // 物品数量
}

/// 舰载机中队结构体
struct FighterSquad: Codable {
    let type_id: Int // 舰载机类型ID
    let quantity: Int // 舰载机数量
    let tubeId: Int // 舰载机发射管ID
}
