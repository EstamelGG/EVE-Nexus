import Foundation

class Colony {
    let pins: [Pin]
    let routes: [Route]
    let currentSimTime: Date
    let status: ColonyStatus?
    
    init(pins: [Pin], routes: [Route], currentSimTime: Date, status: ColonyStatus? = nil) {
        self.pins = pins
        self.routes = routes
        self.currentSimTime = currentSimTime
        self.status = status
        
        // 设置每个Pin的colony引用
        pins.forEach { $0.colony = self }
    }
    
    /// 克隆殖民地
    func clone() -> Colony {
        return Colony(
            pins: pins.map { $0.clone() },
            routes: routes,
            currentSimTime: currentSimTime,
            status: status
        )
    }
    
    /// 复制殖民地并更新状态
    func copy(currentSimTime: Date, status: ColonyStatus) -> Colony {
        return Colony(
            pins: pins,
            routes: routes,
            currentSimTime: currentSimTime,
            status: status
        )
    }
}

// MARK: - 工厂方法
extension Colony {
    /// 从ESI数据创建殖民地实例
    static func fromESIData(
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
        
        return Colony(
            pins: colonyPins,
            routes: colonyRoutes,
            currentSimTime: currentTime
        )
    }
} 