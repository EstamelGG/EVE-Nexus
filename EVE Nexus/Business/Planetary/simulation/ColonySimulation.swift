import Foundation

/// 模拟结束条件
enum SimulationEndCondition {
    case untilNow           // 模拟到当前时间
    case untilWorkEnds      // 模拟到工作结束
    
    var simEndTime: Date {
        switch self {
        case .untilNow:
            return Date()
        case .untilWorkEnds:
            return Date.distantFuture
        }
    }
}

class ColonySimulation {
    private var colony: Colony
    private var eventQueue: [(date: Date, pinId: Int64)] = []
    private var currentSimTime: Date
    private var simEndTime: Date?
    private let currentRealTime: Date
    
    init(_ colony: Colony) {
        self.colony = colony.clone()
        self.currentSimTime = colony.currentSimTime
        self.currentRealTime = Date()
    }
    
    /// 模拟殖民地运行
    /// - Parameter until: 模拟结束条件
    /// - Returns: 模拟后的殖民地状态
    func simulate(until: SimulationEndCondition) -> Colony {
        let currentSimTime = runSimulation(until: until)
        return Colony(
            id: colony.id,
            pins: colony.pins,
            routes: colony.routes,
            currentSimTime: currentSimTime,
            status: ColonyStatus.getStatus(for: colony.pins),
            overview: ColonyOverview.getOverview(routes: colony.routes, pins: colony.pins)
        )
    }
    
    // MARK: - Private Methods
    
    private func runSimulation(until: SimulationEndCondition) -> Date {
        // 如果是模拟到工作结束，且当前已经不在工作，直接返回
        if case .untilWorkEnds = until,
           !ColonyStatus.getStatus(for: colony.pins).isWorking {
            return currentSimTime
        }
        
        initializeSimulation(until: until)
        
        while !eventQueue.isEmpty {
            // 按时间排序并获取最早的事件
            eventQueue.sort { $0.date < $1.date }
            let (simTime, simPinId) = eventQueue.removeFirst()
            
            // 检查是否达到模拟结束条件
            if case .untilNow = until, simTime > currentRealTime {
                return currentRealTime
            }
            if let endTime = simEndTime, simTime > endTime {
                return currentSimTime
            }
            
            currentSimTime = simTime
            guard let simPin = getPin(simPinId),
                  canRun(pin: simPin, until: until.simEndTime) else {
                continue
            }
            
            evaluatePin(simPin)
            
            // 检查是否需要结束模拟
            if case .untilWorkEnds = until, simEndTime == nil {
                let status = ColonyStatus.getStatus(for: colony.pins)
                if !status.isWorking {
                    if status.pins.contains(.storageFull) {
                        return currentSimTime
                    } else {
                        simEndTime = simTime
                    }
                }
            }
        }
        
        return switch until {
        case .untilNow:
            currentRealTime
        case .untilWorkEnds:
            currentSimTime
        }
    }
    
    private func initializeSimulation(until: SimulationEndCondition) {
        eventQueue.removeAll()
        for pin in colony.pins {
            if canRun(pin: pin, until: until.simEndTime) {
                schedulePin(pin)
            }
        }
    }
    
    private func schedulePin(_ pin: Pin) {
        guard let nextRunTime = pin.getNextRunTime() else { return }
        
        // 如果队列中已有该设施的事件，检查是否需要更新
        if let index = eventQueue.firstIndex(where: { $0.pinId == pin.id }) {
            let existingEvent = eventQueue[index]
            if nextRunTime < existingEvent.date {
                eventQueue.remove(at: index)
            } else {
                return
            }
        }
        
        // 添加新事件
        let runTime = nextRunTime < currentSimTime ? currentSimTime : nextRunTime
        eventQueue.append((date: runTime, pinId: pin.id))
    }
    
    private func evaluatePin(_ pin: Pin) {
        // 如果设施不能激活且不处于活跃状态，直接返回
        if !pin.canActivate() && !pin.isActive() {
            return
        }
        
        // 获取设施产出的商品
        let commodities = pin.run(currentTime: currentSimTime)
        
        // 如果是消费者，处理输入
        if pin.isConsumer() {
            routeCommodityInput(pin)
        }
        
        // 如果设施活跃或可以激活，安排下一次运行
        if pin.isActive() || pin.canActivate() {
            schedulePin(pin)
        }
        
        // 如果没有产出，直接返回
        if commodities.isEmpty {
            return
        }
        
        // 处理产出路由
        routeCommodityOutput(pin, commodities)
    }
    
    private func routeCommodityInput(_ destinationPin: Pin) {
        // 获取目标设施的所有输入路由
        let routesToEvaluate = colony.routes.filter { $0.destinationPinId == destinationPin.id }
        
        for route in routesToEvaluate {
            guard let sourcePin = getPin(route.sourcePinId),
                  sourcePin.isStorage() else {
                continue
            }
            
            let storedCommodities = sourcePin.contents
            if storedCommodities.isEmpty { continue }
            
            executeRoute(route, storedCommodities)
        }
    }
    
    private func executeRoute(_ route: Route, _ commodities: [Int: Int64]) {
        transferCommodities(
            sourceId: route.sourcePinId,
            destinationId: route.destinationPinId,
            typeId: route.typeId,
            quantity: route.quantity,
            commodities: commodities
        )
    }
    
    private func transferCommodities(
        sourceId: Int64,
        destinationId: Int64,
        typeId: Int,
        quantity: Int64,
        commodities: [Int: Int64],
        maxAmount: Int64? = nil
    ) -> (typeId: Int?, quantity: Int64) {
        guard let sourcePin = getPin(sourceId),
              let destinationPin = getPin(destinationId),
              let availableQuantity = commodities[typeId] else {
            return (nil, 0)
        }
        
        var amountToMove = min(availableQuantity, quantity)
        if let maxAmount = maxAmount {
            amountToMove = min(maxAmount, amountToMove)
        }
        
        if amountToMove <= 0 {
            return (nil, 0)
        }
        
        let amountMoved = destinationPin.addCommodity(typeId, amountToMove)
        if sourcePin.isStorage() {
            sourcePin.removeCommodity(typeId, amountMoved)
        }
        
        return (typeId, amountMoved)
    }
    
    private func routeCommodityOutput(_ sourcePin: Pin, _ commodities: [Int: Int64]) {
        var remainingCommodities = commodities
        var pinsReceivingCommodities: [Int64: [Int: Int64]] = [:]
        var done = false
        
        // 获取并排序路由
        let routes = getSortedRoutes(for: sourcePin.id, commodities: commodities)
        let (processorRoutes, storageRoutes) = routes
        
        // 先处理加工设施路由，再处理存储设施路由
        for (isStorageRoutes, routes) in [(false, processorRoutes), (true, storageRoutes)] {
            if done { break }
            
            var currentRoutes = routes
            while !currentRoutes.isEmpty {
                let route = currentRoutes.removeFirst()
                
                var maxAmount: Int64?
                if isStorageRoutes {
                    // 平均分配到剩余的存储设施
                    if let commodityQuantity = remainingCommodities[route.typeId] {
                        maxAmount = Int64(ceil(Double(commodityQuantity) / Double(currentRoutes.count + 1)))
                    }
                }
                
                let (type, transferredQuantity) = transferCommodities(
                    sourceId: sourcePin.id,
                    destinationId: route.destinationPinId,
                    typeId: route.typeId,
                    quantity: route.quantity,
                    commodities: remainingCommodities,
                    maxAmount: maxAmount
                )
                
                if let type = type {
                    // 更新剩余商品数量
                    if let currentQuantity = remainingCommodities[type] {
                        let newQuantity = currentQuantity - transferredQuantity
                        if newQuantity <= 0 {
                            remainingCommodities.removeValue(forKey: type)
                        } else {
                            remainingCommodities[type] = newQuantity
                        }
                    }
                    
                    // 记录接收商品的设施
                    if transferredQuantity > 0 {
                        var receivingPin = pinsReceivingCommodities[route.destinationPinId] ?? [:]
                        receivingPin[type] = (receivingPin[type] ?? 0) + transferredQuantity
                        pinsReceivingCommodities[route.destinationPinId] = receivingPin
                    }
                }
                
                if remainingCommodities.isEmpty {
                    done = true
                    break
                }
            }
        }
        
        // 处理接收商品的设施
        for (receivingPinId, commoditiesAdded) in pinsReceivingCommodities {
            guard let receivingPin = getPin(receivingPinId) else { continue }
            
            if receivingPin.isConsumer() {
                schedulePin(receivingPin)
            }
            
            if !sourcePin.isStorage() && receivingPin.isStorage() {
                routeCommodityOutput(receivingPin, commoditiesAdded)
            }
        }
    }
    
    private func getSortedRoutes(
        for pinId: Int64,
        commodities: [Int: Int64]
    ) -> (processors: [Route], storage: [Route]) {
        let routes = colony.routes.filter { $0.sourcePinId == pinId }
        var processorRoutes: [Route] = []
        var storageRoutes: [Route] = []
        
        for route in routes {
            if let destinationPin = getPin(route.destinationPinId) {
                if destinationPin.isProcessor() {
                    processorRoutes.append(route)
                } else if destinationPin.isStorage() {
                    storageRoutes.append(route)
                }
            }
        }
        
        return (processorRoutes, storageRoutes)
    }
    
    private func getPin(_ id: Int64) -> Pin? {
        return colony.pins.first { $0.id == id }
    }
    
    private func canRun(pin: Pin, until: Date) -> Bool {
        // TODO: 实现设施是否可以运行的判断逻辑
        return true
    }
} 