import Foundation

/// 行星殖民地
struct Colony {
    let id: String
    let checkpointSimTime: Date
    var currentSimTime: Date
    let characterId: Int
    let system: SolarSystem
    let upgradeLevel: Int
    let links: [PlanetaryLink]
    let pins: [Pin]
    let routes: [Route]
    var status: ColonyStatus
    var overview: ColonyOverview
    
    /// 克隆殖民地
    func clone() -> Colony {
        return Colony(
            id: id,
            checkpointSimTime: checkpointSimTime,
            currentSimTime: currentSimTime,
            characterId: characterId,
            system: system,
            upgradeLevel: upgradeLevel,
            links: links,
            pins: pins.map { pin in
                if let extractor = pin as? Pin.Extractor {
                    return extractor.clone()
                } else if let factory = pin as? Pin.Factory {
                    return factory.clone()
                } else if let storage = pin as? Pin.Storage {
                    return storage.clone()
                } else if let launchpad = pin as? Pin.Launchpad {
                    return launchpad.clone()
                } else if let commandCenter = pin as? Pin.CommandCenter {
                    return commandCenter.clone()
                } else {
                    return pin.clone()
                }
            },
            routes: routes,
            status: status,
            overview: overview
        )
    }
}

/// 恒星系
struct SolarSystem {
    let id: Int
    let name: String
} 
