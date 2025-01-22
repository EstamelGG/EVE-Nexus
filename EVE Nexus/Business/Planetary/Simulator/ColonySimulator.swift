import Foundation

class ColonySimulator {
    private var colony: Colony // 需要实现Colony类
    private var eventQueue: [SimulationEvent]
    private var currentSimTime: Date
    private var simEndTime: Date?
    private let currentRealTime: Date
    
    init(colony: Colony) {
        self.colony = colony.clone()
        self.eventQueue = []
        self.currentSimTime = colony.currentSimTime
        self.currentRealTime = Date()
    }
    
    /// 模拟殖民地运作
    func simulate(until condition: SimulationEndCondition) -> Colony {
        let currentSimTime = runSimulation(until: condition)
        return colony.copy(
            currentSimTime: currentSimTime,
            status: getColonyStatus(at: currentSimTime)
        )
    }
    
    /// 获取殖民地状态
    private func getColonyStatus(at time: Date) -> ColonyStatus {
        colony.pins.forEach { pin in
            pin.status = pin.getStatus(at: time, routes: colony.routes)
        }
        return ColonyStatus(pins: colony.pins.map { 
            .init(pinId: $0.id, status: $0.status)
        })
    }
    
    /// 运行模拟
    private func runSimulation(until condition: SimulationEndCondition) -> Date {
        if condition == .untilWorkEnds && !getColonyStatus(at: currentSimTime).isWorking {
            return currentSimTime // 殖民地已经停止工作
        }
        
        initializeSimulation(until: condition)
        while !eventQueue.isEmpty {
            let event = eventQueue.removeFirst()
            let simTime = event.time
            let simPinId = event.pinId
            
            if condition == .untilNow && simTime > currentRealTime {
                return currentRealTime
            }
            
            if let endTime = simEndTime, simTime > endTime {
                return currentSimTime
            }
            
            currentSimTime = simTime
            guard let simPin = getPin(id: simPinId) else { continue }
            guard simPin.canRun(until: condition.simEndTime) else { continue }
            
            evaluatePin(simPin)
            
            if condition == .untilWorkEnds && simEndTime == nil {
                let status = getColonyStatus(at: currentSimTime)
                if !status.isWorking {
                    if status.pins.contains(where: { $0.status == .storageFull }) {
                        return currentSimTime // 不再模拟其他设施
                    } else {
                        simEndTime = simTime // 继续模拟其他设施直到超过这个时间点
                    }
                }
            }
        }
        
        return switch condition {
            case .untilNow: currentRealTime
            case .untilWorkEnds: currentSimTime
        }
    }
    
    /// 初始化模拟
    private func initializeSimulation(until condition: SimulationEndCondition) {
        eventQueue.removeAll()
        for pin in colony.pins {
            if pin.canRun(until: condition.simEndTime) {
                schedulePin(pin)
            }
        }
        eventQueue.sort()
    }
    
    /// 安排设施的下一次运行
    private func schedulePin(_ pin: Pin) {
        guard let nextRunTime = pin.getNextRunTime() else { return }
        
        if let existingEventIndex = eventQueue.firstIndex(where: { $0.pinId == pin.id }) {
            let existingEvent = eventQueue[existingEventIndex]
            if nextRunTime < existingEvent.time {
                eventQueue.remove(at: existingEventIndex)
            } else {
                return
            }
        }
        
        let runTime = nextRunTime < currentSimTime ? currentSimTime : nextRunTime
        addTimer(pinId: pin.id, runTime: runTime)
    }
    
    /// 添加定时器事件
    private func addTimer(pinId: Int64, runTime: Date) {
        eventQueue.append(SimulationEvent(time: runTime, pinId: pinId))
        eventQueue.sort()
    }
    
    /// 评估设施的运行状态
    private func evaluatePin(_ pin: Pin) {
        if !pin.canActivate() && !pin.isActive() {
            return
        }
        
        let commodities = getCommoditiesProducedByPin(pin)
        
        if pin.isConsumer() {
            routeCommodityInput(pin)
        }
        
        if pin.isActive() || pin.canActivate() {
            schedulePin(pin)
        }
        
        if commodities.isEmpty {
            return
        }
        
        routeCommodityOutput(pin, commodities: commodities)
    }
    
    /// 获取设施生产的商品
    private func getCommoditiesProducedByPin(_ pin: Pin) -> [Int64: Int64] {
        return pin.run(at: currentSimTime)
    }
    
    /// 路由商品输入
    private func routeCommodityInput(_ destinationPin: Pin) {
        let routesToEvaluate = getDestinationRoutesForPin(destinationPin.id)
        for route in routesToEvaluate {
            guard let sourcePin = getPin(id: route.sourcePinId) else { continue }
            guard sourcePin.isStorage() else { continue }
            
            let storedCommodities = sourcePin.contents.commodities
            guard !storedCommodities.isEmpty else { continue }
            
            executeRoute(route, commodities: storedCommodities)
        }
    }
    
    /// 执行路由
    private func executeRoute(_ route: Route, commodities: [Int64: Int64]) {
        transferCommodities(
            sourceId: route.sourcePinId,
            destinationId: route.destinationPinId,
            typeId: route.commodityType.id,
            quantity: route.quantity,
            commodities: commodities
        )
    }
    
    /// 转移商品
    private func transferCommodities(
        sourceId: Int64,
        destinationId: Int64,
        typeId: Int64,
        quantity: Int64,
        commodities: [Int64: Int64],
        maxAmount: Int64? = nil
    ) -> (typeId: Int64?, amount: Int64) {
        guard let sourcePin = getPin(id: sourceId) else { return (nil, 0) }
        guard let amount = commodities[typeId] else { return (nil, 0) }
        
        var amountToMove = min(amount, quantity)
        if let maxAmount = maxAmount {
            amountToMove = min(maxAmount, amountToMove)
        }
        
        guard amountToMove > 0 else { return (nil, 0) }
        guard let destinationPin = getPin(id: destinationId) else { return (nil, 0) }
        
        let amountMoved = destinationPin.addCommodity(typeId: typeId, amount: amountToMove)
        if sourcePin.isStorage() {
            sourcePin.removeCommodity(typeId: typeId, amount: amountMoved)
        }
        
        return (typeId, amountMoved)
    }
    
    /// 路由商品输出
    private func routeCommodityOutput(_ sourcePin: Pin, commodities: [Int64: Int64]) {
        var pinsReceivingCommodities: [Int64: [Int64: Int64]] = [:] // [pinId: [typeId: amount]]
        var remainingCommodities = commodities
        var done = false
        
        let routes = getSortedRoutesForPin(sourcePin.id, commodities: commodities)
        let processorRoutes = routes.processor
        let storageRoutes = routes.storage
        
        for (isStorageRoutes, routes) in [(false, processorRoutes), (true, storageRoutes)] {
            if done { break }
            
            var routesList = routes
            while !routesList.isEmpty {
                let route = routesList.removeFirst()
                var maxAmount: Int64?
                
                if isStorageRoutes {
                    maxAmount = Int64(ceil(
                        Double(remainingCommodities[route.commodityType.id, default: 0]) /
                        Double(routesList.count + 1)
                    ))
                }
                
                let (typeId, transferredQuantity) = transferCommodities(
                    sourceId: sourcePin.id,
                    destinationId: route.destinationPinId,
                    typeId: route.commodityType.id,
                    quantity: route.quantity,
                    commodities: remainingCommodities,
                    maxAmount: maxAmount
                )
                
                if let typeId = typeId {
                    if let currentAmount = remainingCommodities[typeId] {
                        let newAmount = currentAmount - transferredQuantity
                        if newAmount <= 0 {
                            remainingCommodities.removeValue(forKey: typeId)
                        } else {
                            remainingCommodities[typeId] = newAmount
                        }
                    }
                    
                    if transferredQuantity > 0 {
                        var pinCommodities = pinsReceivingCommodities[route.destinationPinId, default: [:]]
                        pinCommodities[typeId] = pinCommodities[typeId, default: 0] + transferredQuantity
                        pinsReceivingCommodities[route.destinationPinId] = pinCommodities
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
            guard let receivingPin = getPin(id: receivingPinId) else { continue }
            
            if receivingPin.isConsumer() {
                schedulePin(receivingPin)
            }
            
            if !sourcePin.isStorage() && receivingPin.isStorage() {
                routeCommodityOutput(receivingPin, commodities: commoditiesAdded)
            }
        }
    }
    
    /// 获取目标设施的输入路由
    private func getDestinationRoutesForPin(_ pinId: Int64) -> [Route] {
        return colony.routes.filter { $0.destinationPinId == pinId }
    }
    
    /// 获取设施的排序后的路由
    private func getSortedRoutesForPin(_ pinId: Int64, commodities: [Int64: Int64]) -> (processor: [Route], storage: [Route]) {
        let routes = colony.routes.filter { $0.sourcePinId == pinId }
        
        let (processorRoutes, storageRoutes) = routes.reduce(into: ([Route](), [Route]())) { result, route in
            if let destinationPin = getPin(id: route.destinationPinId) {
                if destinationPin.isStorage() {
                    result.1.append(route)
                } else {
                    result.0.append(route)
                }
            }
        }
        
        return (processorRoutes, storageRoutes)
    }
    
    /// 获取设施
    private func getPin(id: Int64) -> Pin? {
        colony.pins.first { $0.id == id }
    }
} 