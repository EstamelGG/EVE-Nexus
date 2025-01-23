import Foundation

/// 殖民地
class Colony {
    let id: String
    let characterId: Int64
    let checkpointSimTime: Date
    let currentSimTime: Date
    let upgradeLevel: Int
    let pins: [Pin]
    let routes: [Route]
    let status: ColonyStatus
    
    init(
        id: String,
        characterId: Int64,
        checkpointSimTime: Date,
        currentSimTime: Date,
        upgradeLevel: Int = 0,
        pins: [Pin],
        routes: [Route],
        status: ColonyStatus? = nil
    ) {
        self.id = id
        self.characterId = characterId
        self.checkpointSimTime = checkpointSimTime
        self.currentSimTime = currentSimTime
        self.upgradeLevel = upgradeLevel
        self.pins = pins
        self.routes = routes
        self.status = status ?? ColonyStatus(pins: [])  // 如果没有提供状态，创建一个空的状态
        
        // 设置每个Pin的colony引用
        pins.forEach { $0.colony = self }
    }
    
    /// 克隆殖民地
    func clone() -> Colony {
        return Colony(
            id: id,
            characterId: characterId,
            checkpointSimTime: checkpointSimTime,
            currentSimTime: currentSimTime,
            upgradeLevel: upgradeLevel,
            pins: pins.map { $0.clone() },
            routes: routes,
            status: status
        )
    }
    
    /// 复制殖民地并更新状态
    func copy(currentSimTime: Date, status: ColonyStatus) -> Colony {
        return Colony(
            id: id,
            characterId: characterId,
            checkpointSimTime: checkpointSimTime,
            currentSimTime: currentSimTime,
            upgradeLevel: upgradeLevel,
            pins: pins,
            routes: routes,
            status: status
        )
    }
}

// MARK: - 工厂方法
extension Colony {
    /// 从ESI数据创建殖民地实例
    static func fromESIData(
        id: String,
        characterId: Int64,
        upgradeLevel: Int,
        pins: [ESIPlanetaryPin],
        routes: [ESIPlanetaryRoute],
        currentTime: Date = Date()
    ) -> Colony {
        let colonyPins = pins.map { esiPin -> Pin in
            let contents = PinContents(
                commodities: Dictionary(
                    uniqueKeysWithValues: esiPin.contents.map { ($0.typeId, $0.amount) }
                ),
                capacity: Int64(esiPin.type.capacity)
            )
            
            return Pin(
                id: esiPin.pinId,
                type: PinType(rawValue: esiPin.type.name) ?? .storage,
                schematicId: esiPin.schematicId,
                cycleTime: TimeInterval(esiPin.cycleTime),
                lastRunTime: esiPin.lastRunTime,
                contents: contents
            )
        }
        
        let colonyRoutes = routes.map { esiRoute in
            Route(
                id: esiRoute.routeId,
                sourcePinId: esiRoute.sourcePinId,
                destinationPinId: esiRoute.destinationPinId,
                commodityTypeId: esiRoute.commodityTypeId,
                quantity: esiRoute.quantity
            )
        }
        
        // 创建初始状态
        let pinStatusInfos = colonyPins.map { pin in
            ColonyStatus.PinStatusInfo(pinId: pin.id, status: .idle)
        }
        
        return Colony(
            id: id,
            characterId: characterId,
            checkpointSimTime: currentTime,
            currentSimTime: currentTime,
            upgradeLevel: upgradeLevel,
            pins: colonyPins,
            routes: colonyRoutes,
            status: ColonyStatus(pins: pinStatusInfos)
        )
    }
} 