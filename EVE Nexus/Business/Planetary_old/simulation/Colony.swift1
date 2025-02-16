import Foundation

/// 殖民地
struct Colony {
    /// 殖民地ID
    let id: String
    
    /// 检查点时间
    let checkpointSimTime: Date
    
    /// 当前模拟时间
    let currentSimTime: Date
    
    /// 角色ID
    let characterId: Int
    
    /// 设施间连接
    let links: [PlanetaryFacilityLink]
    
    /// 设施列表
    let pins: [Pin]
    
    /// 资源传输路线
    let routes: [Route]
    
    /// 殖民地状态
    let status: ColonyStatus
    
    /// 克隆殖民地
    func clone() -> Colony {
        // 克隆设施
        let clonedPins = pins.map { pin -> Pin in
            switch pin {
            case let extractor as ExtractorPin:
                return ExtractorPin(
                    id: extractor.id,
                    type: extractor.type,
                    designator: extractor.designator,
                    lastRunTime: extractor.lastRunTime,
                    contents: extractor.contents,
                    capacityUsed: extractor.capacityUsed,
                    isActive: extractor.isActive,  // 确保复制激活状态
                    latitude: extractor.latitude,
                    longitude: extractor.longitude,
                    status: extractor.status,
                    expiryTime: extractor.expiryTime,
                    installTime: extractor.installTime,
                    cycleTime: extractor.cycleTime,
                    productType: extractor.productType,
                    baseValue: extractor.baseValue
                )
                
            case let factory as FactoryPin:
                return FactoryPin(
                    id: factory.id,
                    type: factory.type,
                    designator: factory.designator,
                    lastRunTime: factory.lastRunTime,
                    contents: factory.contents,
                    capacityUsed: factory.capacityUsed,
                    isActive: factory.isActive,  // 确保复制激活状态
                    latitude: factory.latitude,
                    longitude: factory.longitude,
                    status: factory.isActive ? .producing : .factoryIdle,  // 根据激活状态设置正确的状态
                    schematic: factory.schematic,
                    hasReceivedInputs: factory.hasReceivedInputs,
                    receivedInputsLastCycle: factory.receivedInputsLastCycle,
                    lastCycleStartTime: factory.lastCycleStartTime
                )
                
            case let storage as StoragePin:
                return StoragePin(
                    id: storage.id,
                    type: storage.type,
                    designator: storage.designator,
                    lastRunTime: storage.lastRunTime,
                    contents: storage.contents,
                    capacityUsed: storage.capacityUsed,
                    isActive: storage.isActive,  // 确保复制激活状态
                    latitude: storage.latitude,
                    longitude: storage.longitude,
                    status: storage.status
                )
                
            case let launchpad as LaunchpadPin:
                return LaunchpadPin(
                    id: launchpad.id,
                    type: launchpad.type,
                    designator: launchpad.designator,
                    lastRunTime: launchpad.lastRunTime,
                    contents: launchpad.contents,
                    capacityUsed: launchpad.capacityUsed,
                    isActive: launchpad.isActive,  // 确保复制激活状态
                    latitude: launchpad.latitude,
                    longitude: launchpad.longitude,
                    status: launchpad.status
                )
                
            case let commandCenter as CommandCenterPin:
                return CommandCenterPin(
                    id: commandCenter.id,
                    type: commandCenter.type,
                    designator: commandCenter.designator,
                    lastRunTime: commandCenter.lastRunTime,
                    contents: commandCenter.contents,
                    capacityUsed: commandCenter.capacityUsed,
                    isActive: commandCenter.isActive,  // 确保复制激活状态
                    latitude: commandCenter.latitude,
                    longitude: commandCenter.longitude,
                    status: commandCenter.status,
                    level: commandCenter.level
                )
                
            default:
                fatalError("Unknown pin type")
            }
        }
        
        return Colony(
            id: id,
            checkpointSimTime: checkpointSimTime,
            currentSimTime: currentSimTime,
            characterId: characterId,
            links: links,
            pins: clonedPins,
            routes: routes,
            status: status
        )
    }
}

/// 行星
struct Planet {
    /// 行星ID
    let id: Int64
    
    /// 行星名称
    let name: String
    
    /// 行星类型ID
    let typeId: Int64
}

/// 行星类型
enum PlanetType: Int {
    case barren = 2016      // 贫瘠
    case gas = 2014         // 气体
    case ice = 2017         // 冰体
    case lava = 2015        // 熔岩
    case oceanic = 2018     // 海洋
    case plasma = 11        // 等离子体
    case storm = 13         // 风暴
    case temperate = 2019   // 温和
}

/// 星系
struct SolarSystem {
    /// 星系ID
    let id: Int64
    
    /// 星系名称
    let name: String
    
    /// 安全等级
    let security: Float
}

/// 资源使用情况
struct Usage {
    /// CPU使用量
    let cpuUsage: Int
    
    /// CPU供应量
    let cpuSupply: Int
    
    /// 能量使用量
    let powerUsage: Int
    
    /// 能量供应量
    let powerSupply: Int
}

/// 行星设施连接
struct PlanetaryFacilityLink {
    /// 源设施ID
    let sourcePinId: Int64
    
    /// 目标设施ID
    let destinationPinId: Int64
    
    /// 等级
    let level: Int
} 