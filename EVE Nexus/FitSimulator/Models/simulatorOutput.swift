import Foundation

// MARK: - 模拟输出数据模型
/// 用于存储属性模拟的计算结果，包含飞船、装备、无人机、植入体、环境效果和技能等的计算后属性
struct SimulationOutput {
    // 元数据 (与输入保持一致)
    var fittingId: Int                 // 本地配置ID
    var name: String                   // 配置名称  
    var description: String            // 配置描述
    
    // 模拟核心数据 (使用计算后的属性)
    var ship: SimShipOutput           // 当前模拟的飞船
    var modules: [SimModuleOutput]    // 所有已安装装备（含激活状态、弹药）
    var drones: [SimDroneOutput]      // 所有携带的无人机
    var cargo: SimCargoOutput         // 货舱（容量与物品明细）
    var implants: [SimImplantOutput]  // 所有已装备的植入体
    var environmentEffects: [SimEnvironmentEffectOutput] // 当前生效的环境效果
    var characterSkills: [Int: Int]   // 角色技能（技能ID: 等级）
    var fighters: [FighterSquadOutput]? // 舰载机中队（如有）
    
    // 技能计算结果
    var characterSkillCalculatedAttributes: [Int: [Int: Double]] = [:]  // 技能ID: [属性ID: 计算后的值]
    
    // 原始输入数据的引用
    var originalInput: SimulationInput
    
    /// 从SimulationInput创建SimulationOutput
    /// - Parameter input: 模拟输入数据
    init(from input: SimulationInput) {
        self.fittingId = input.fittingId
        self.name = input.name
        self.description = input.description
        self.originalInput = input
        
        // 初始化计算后的飞船数据
        self.ship = SimShipOutput(from: input.ship)
        
        // 初始化计算后的模块数据
        self.modules = input.modules.map { SimModuleOutput(from: $0) }
        
        // 初始化计算后的无人机数据
        self.drones = input.drones.map { SimDroneOutput(from: $0) }
        
        // 初始化计算后的货舱数据
        self.cargo = SimCargoOutput(from: input.cargo)
        
        // 初始化计算后的植入体数据
        self.implants = input.implants.map { SimImplantOutput(from: $0) }
        
        // 初始化计算后的环境效果数据
        self.environmentEffects = input.environmentEffects.map { SimEnvironmentEffectOutput(from: $0) }
        
        // 复制技能数据
        self.characterSkills = input.characterSkills
        
        // 初始化计算后的舰载机数据
        if let fighters = input.fighters {
            self.fighters = fighters.map { FighterSquadOutput(from: $0) }
        } else {
            self.fighters = nil
        }
        
        // 复制技能计算属性
        self.characterSkillCalculatedAttributes = input.characterSkillCalculatedAttributes
    }
}

// MARK: - 输出数据模型

/// 飞船输出数据（基础属性、效果、分组，计算后的属性）
struct SimShipOutput {
    let typeId: Int                    // 飞船类型ID
    var attributes: [Int: Double]      // 计算后的属性值
    var attributesByName: [String: Double] // 计算后的属性值（名称索引）
    let effects: [Int]                 // 飞船自带效果ID列表
    let groupID: Int                   // 飞船分组ID
    let name: String                   // 飞船名称
    let iconFileName: String?          // 飞船图标文件名
    let requiredSkills: [Int]          // 所需技能ID列表
    
    // 添加角色属性字段
    var characterAttributes: [Int: Double] = [:]      // 角色计算后的属性值
    var characterAttributesByName: [String: Double] = [:] // 角色计算后的属性值（名称索引）
    
    /// 从SimShip创建SimShipOutput
    init(from ship: SimShip) {
        self.typeId = ship.typeId
        self.attributes = ship.baseAttributes
        self.attributesByName = ship.baseAttributesByName
        self.effects = ship.effects
        self.groupID = ship.groupID
        self.name = ship.name
        self.iconFileName = ship.iconFileName
        self.requiredSkills = ship.requiredSkills
        // 角色属性初始化为空字典，将在计算后填充
        self.characterAttributes = [:]
        self.characterAttributesByName = [:]
    }
}

/// 装备/模块输出数据（含属性、效果、激活状态、弹药）
struct SimModuleOutput {
    let instanceId: UUID               // 实例唯一标识符
    let typeId: Int                    // 装备类型ID
    var attributes: [Int: Double]      // 计算后的属性值
    var attributesByName: [String: Double] // 计算后的属性值（名称索引）
    let effects: [Int]                 // 装备效果ID列表
    let groupID: Int                   // 装备分组ID
    let status: Int                    // 激活状态（如0未激活，1激活等）
    var charge: SimChargeOutput?       // 当前装填的弹药（如有）
    let flag: FittingFlag?             // 装备的槽位标识
    let quantity: Int                  // 装备数量
    let name: String                   // 装备名称
    let iconFileName: String?          // 装备图标文件名
    let requiredSkills: [Int]          // 所需技能ID列表
    
    /// 从SimModule创建SimModuleOutput
    init(from module: SimModule) {
        self.instanceId = module.instanceId
        self.typeId = module.typeId
        self.attributes = module.attributes
        self.attributesByName = module.attributesByName
        self.effects = module.effects
        self.groupID = module.groupID
        self.status = module.status
        if let charge = module.charge {
            self.charge = SimChargeOutput(from: charge)
        } else {
            self.charge = nil
        }
        self.flag = module.flag
        self.quantity = module.quantity
        self.name = module.name
        self.iconFileName = module.iconFileName
        self.requiredSkills = module.requiredSkills
    }
}

/// 弹药输出数据（属性、效果、分组）
struct SimChargeOutput {
    let instanceId: UUID               // 实例唯一标识符
    let typeId: Int                    // 弹药类型ID
    var attributes: [Int: Double]      // 计算后的属性值
    var attributesByName: [String: Double] // 计算后的属性值（名称索引）
    let effects: [Int]                 // 弹药效果ID列表
    let groupID: Int                   // 弹药分组ID
    let chargeQuantity: Int?           // 弹药数量（可选）
    let name: String                   // 弹药名称
    let iconFileName: String?          // 弹药图标文件名
    let requiredSkills: [Int]          // 所需技能ID列表
    
    /// 从SimCharge创建SimChargeOutput
    init(from charge: SimCharge) {
        self.instanceId = charge.instanceId
        self.typeId = charge.typeId
        self.attributes = charge.attributes
        self.attributesByName = charge.attributesByName
        self.effects = charge.effects
        self.groupID = charge.groupID
        self.chargeQuantity = charge.chargeQuantity
        self.name = charge.name
        self.iconFileName = charge.iconFileName
        self.requiredSkills = charge.requiredSkills
    }
}

/// 无人机输出数据（属性、效果、数量、激活数）
struct SimDroneOutput {
    let instanceId: UUID               // 实例唯一标识符
    let typeId: Int                    // 无人机类型ID
    var attributes: [Int: Double]      // 计算后的属性值
    var attributesByName: [String: Double] // 计算后的属性值（名称索引）
    let effects: [Int]                 // 无人机效果ID列表
    let quantity: Int                  // 携带数量
    let activeCount: Int               // 激活数量
    let groupID: Int                   // 无人机分组ID
    let name: String                   // 无人机名称
    let iconFileName: String?          // 无人机图标文件名
    let requiredSkills: [Int]          // 所需技能ID列表
    
    /// 从SimDrone创建SimDroneOutput
    init(from drone: SimDrone) {
        self.instanceId = drone.instanceId
        self.typeId = drone.typeId
        self.attributes = drone.attributes
        self.attributesByName = drone.attributesByName
        self.effects = drone.effects
        self.quantity = drone.quantity
        self.activeCount = drone.activeCount
        self.groupID = drone.groupID
        self.name = drone.name
        self.iconFileName = drone.iconFileName
        self.requiredSkills = drone.requiredSkills
    }
}

/// 货舱输出数据（物品明细）
struct SimCargoOutput {
    let items: [SimCargoItemOutput]    // 货舱内所有物品及数量
    
    /// 从SimCargo创建SimCargoOutput
    init(from cargo: SimCargo) {
        self.items = cargo.items.map { SimCargoItemOutput(from: $0) }
    }
}

/// 货舱内单个物品输出数据
struct SimCargoItemOutput {
    let typeId: Int                    // 物品类型ID
    let quantity: Int                  // 物品数量
    let volume: Double                 // 物品体积
    let name: String                   // 物品名称
    let iconFileName: String?          // 物品图标文件名
    
    /// 从SimCargoItem创建SimCargoItemOutput
    init(from item: SimCargoItem) {
        self.typeId = item.typeId
        self.quantity = item.quantity
        self.volume = item.volume
        self.name = item.name
        self.iconFileName = item.iconFileName
    }
}

/// 植入体输出数据（属性、效果）
struct SimImplantOutput {
    let instanceId: UUID               // 实例唯一标识符
    let typeId: Int                    // 植入体类型ID
    var attributes: [Int: Double]      // 计算后的属性值
    var attributesByName: [String: Double] // 计算后的属性值（名称索引）
    let effects: [Int]                 // 植入体效果ID列表
    let name: String                   // 植入体名称
    let iconFileName: String?          // 植入体图标文件名
    let requiredSkills: [Int]          // 所需技能ID列表
    
    /// 从SimImplant创建SimImplantOutput
    init(from implant: SimImplant) {
        self.instanceId = implant.instanceId
        self.typeId = implant.typeId
        self.attributes = implant.attributes
        self.attributesByName = implant.attributesByName
        self.effects = implant.effects
        self.name = implant.name
        self.iconFileName = implant.iconFileName
        self.requiredSkills = implant.requiredSkills
    }
}

/// 环境效果输出数据（如空间站、星系、信号场等带来的加成）
struct SimEnvironmentEffectOutput {
    let typeId: Int                    // 环境效果类型ID
    let name: String                   // 环境效果名称
    var attributes: [Int: Double]      // 计算后的属性值
    var attributesByName: [String: Double] // 计算后的属性值（名称索引）
    let effects: [Int]                 // 效果ID列表
    let iconFileName: String?          // 环境效果图标文件名
    
    /// 从SimEnvironmentEffect创建SimEnvironmentEffectOutput
    init(from effect: SimEnvironmentEffect) {
        self.typeId = effect.typeId
        self.name = effect.name
        self.attributes = effect.attributes
        self.attributesByName = effect.attributesByName
        self.effects = effect.effects
        self.iconFileName = effect.iconFileName
    }
}

/// 舰载机中队输出数据
struct FighterSquadOutput {
    var typeId: Int                    // 舰载机类型ID
    var quantity: Int                   // 数量
    var tubeId: Int                     // 舰载机发射管ID
    var attributes: [Int: Double]       // 计算后的属性值
    var attributesByName: [String: Double] // 计算后的属性值（名称索引）
    var effects: [Int]                  // 舰载机效果ID列表
    var groupID: Int                    // 舰载机分组ID
    var instanceId: UUID                // 实例唯一标识符
    var name: String                    // 舰载机名称
    var iconFileName: String?           // 舰载机图标文件名
    var requiredSkills: [Int]           // 所需技能ID列表
    
    /// 从SimFighterSquad创建FighterSquadOutput
    init(from fighter: SimFighterSquad) {
        self.typeId = fighter.typeId
        self.quantity = fighter.quantity
        self.tubeId = fighter.tubeId
        self.attributes = fighter.attributes
        self.attributesByName = fighter.attributesByName
        self.effects = fighter.effects
        self.groupID = fighter.groupID
        self.instanceId = fighter.instanceId
        self.name = fighter.name
        self.iconFileName = fighter.iconFileName
        self.requiredSkills = fighter.requiredSkills
    }
}
