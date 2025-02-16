import Foundation

class ColonySimulation {
    // MARK: - Properties
    
    private let colony: Colony
    private var eventQueue: PriorityQueue<(time: Date, pinId: Int64)>
    private var currentSimTime: Date
    private var simEndTime: Date?
    private let currentRealTime: Date
    private var processedEventCount: Int = 0  // 添加事件计数器
    
    // MARK: - Types
    
    /// 模拟结束条件
    enum SimulationEndCondition {
        case untilNow           // 模拟到当前时间
        case untilWorkEnds      // 模拟到工作结束
        
        var simEndTime: Date {
            switch self {
            case .untilNow:
                return Date()
            case .untilWorkEnds:
                return .distantFuture
            }
        }
    }
    
    /// 模拟结果
    struct SimulationResult {
        /// 时间点
        let time: Date
        /// 殖民地状态
        let colony: Colony
    }
    
    /// 事件
    struct Event: Comparable {
        /// 运行时间
        let time: Date
        /// 设施ID
        let pinId: Int64
        
        static func < (lhs: Event, rhs: Event) -> Bool {
            return lhs.time < rhs.time
        }
        
        static func == (lhs: Event, rhs: Event) -> Bool {
            return lhs.time == rhs.time && lhs.pinId == rhs.pinId
        }
    }
    
    // MARK: - Initialization
    
    init(colony: Colony) {
        self.colony = colony
        self.eventQueue = PriorityQueue<(time: Date, pinId: Int64)> { $0.time < $1.time }
        self.currentSimTime = colony.currentSimTime
        self.currentRealTime = Date()
    }
    
    /// 添加定时器
    /// - Parameters:
    ///   - pinId: 设施ID
    ///   - runTime: 运行时间
    private func addTimer(pinId: Int64, runTime: Date) {
        eventQueue.enqueue((time: runTime, pinId: pinId))
    }
    
    /// 获取设施的目标路由
    /// - Parameter pinId: 设施ID
    /// - Returns: 目标路由列表
    private func getDestinationRoutesForPin(pinId: Int64) -> [Route] {
        return colony.routes.filter { $0.destinationPinId == pinId }
    }
    
    /// 调度设施
    /// - Parameter pin: 设施
    private func schedulePin(_ pin: Pin) {
        let nextRunTime = pin.getNextRunTime()
        if let existingEvent = eventQueue.first(where: { $0.pinId == pin.id }) {
            if nextRunTime == nil || nextRunTime! < existingEvent.time {
                eventQueue.remove(existingEvent) { $0.time == $1.time && $0.pinId == $1.pinId }
            } else {
                return
            }
        }
        
        if nextRunTime == nil || nextRunTime! < currentSimTime {
            addTimer(pinId: pin.id, runTime: currentSimTime)
        } else {
            addTimer(pinId: pin.id, runTime: nextRunTime!)
        }
    }
    
    /// 初始化模拟器
    /// - Parameter until: 模拟结束条件
    private func initializeSimulation(_ until: SimulationEndCondition) {
        // 清空事件队列
        eventQueue.clear()
        
        // 从检查点时间开始模拟
        currentSimTime = colony.checkpointSimTime
        Logger.debug("\n=== 初始化模拟器 ===")
        Logger.debug("模拟开始时间: \(currentSimTime)")
        Logger.debug("模拟结束时间: \(until.simEndTime)")
        Logger.debug("检查点时间: \(colony.checkpointSimTime)")
        
        // 为所有可运行的设施安排调度
        for pin in colony.pins {
            // 如果设施有上次运行时间，从该时间开始调度
            if let lastRunTime = pin.lastRunTime {
                currentSimTime = lastRunTime
                if pin.canRun(until.simEndTime) {
                    schedulePin(pin)
                }
            } else if pin.canRun(until.simEndTime) {
                // 如果没有上次运行时间，从当前时间开始调度
                schedulePin(pin)
            }
        }
        
        // 重置当前模拟时间为检查点时间
        currentSimTime = colony.checkpointSimTime
        
        // 打印初始化后的殖民地状态
        Logger.debug("\n=== 初始化后的殖民地状态 ===")
        Logger.debug("殖民地设施数量: \(colony.pins.count)")
        Logger.debug("设施详情:")
        for pin in colony.pins {
            Logger.debug("\n设施ID: \(pin.id)")
            Logger.debug("设施类型: \(String(describing: type(of: pin)))")
            Logger.debug("库存状态: \(pin.contents)")
            Logger.debug("已用容量: \(pin.capacityUsed)")
            if let lastRunTime = pin.lastRunTime {
                Logger.debug("上次运行时间: \(lastRunTime)")
            }
            Logger.debug("当前状态: \(pin.status)")
        }
        
        Logger.debug("\n路由信息:")
        Logger.debug("路由总数: \(colony.routes.count)")
        for route in colony.routes {
            Logger.debug("路由: \(route.sourcePinId) -> \(route.destinationPinId), 资源类型: \(route.type.id), 数量: \(route.quantity)")
        }
        Logger.debug("=== 初始化完成 ===\n")
    }
    
    /// 获取指定 ID 的设施
    /// - Parameter pinId: 设施 ID
    /// - Returns: 设施实例
    private func getPin(pinId: Int64) -> Pin {
        guard let pin = colony.pins.first(where: { $0.id == pinId }) else {
            fatalError("找不到 ID 为 \(pinId) 的设施.")
        }
        return pin
    }
    
    /// 获取指定 ID 的设施（如果不存在则返回 nil）
    /// - Parameter pinId: 设施 ID
    /// - Returns: 设施实例，如果不存在则返回 nil
    private func getPinOrNull(pinId: Int64) -> Pin? {
        return colony.pins.first(where: { $0.id == pinId })
    }
    
    /// 获取设施生产的资源
    /// - Parameter pin: 设施
    /// - Returns: 生产的资源及其数量
    private func getCommoditiesProducedByPin(_ pin: Pin) -> [CommodityType: Int64] {
        return pin.run(currentSimTime)
    }
    
    /// 在两个设施之间传输资源
    /// - Parameters:
    ///   - sourcePin: 源设施
    ///   - destinationPin: 目标设施
    ///   - type: 资源类型
    ///   - quantity: 数量
    /// - Returns: 实际传输的数量
    private func transferCommodities(from sourcePin: Pin, to destinationPin: Pin, type: CommodityType, quantity: Int64) -> Int64 {
        Logger.debug("\n=== (\(currentSimTime)) 资源传输事件 ===")
//        Logger.debug("时间: \(currentSimTime)")
//        Logger.debug("源设施: \(sourcePin.id) (\(String(describing: sourcePin).split(separator: " ")[0]))")
//        Logger.debug("目标设施: \(destinationPin.id) (\(String(describing: destinationPin).split(separator: " ")[0]))")
        
        // 记录传输前的状态
//        let sourceBeforeTransfer = sourcePin.contents[type] ?? 0
//        let destBeforeTransfer = destinationPin.contents[type] ?? 0
//        let sourceVolumeBeforeTransfer = Float(type.volume) * Float(sourceBeforeTransfer)
//        let destVolumeBeforeTransfer = Float(type.volume) * Float(destBeforeTransfer)
        
//        Logger.debug("传输前状态:")
//        Logger.debug("- 源设施资源 \(type.id): \(sourceBeforeTransfer) 单位 (\(String(format: "%.2f", sourceVolumeBeforeTransfer)) m³)")
//        Logger.debug("- 目标设施资源 \(type.id): \(destBeforeTransfer) 单位 (\(String(format: "%.2f", destVolumeBeforeTransfer)) m³)")
        
        // 执行传输
        var quantityToTransfer = quantity
        
        // 如果源设施是存储类型，需要先移除资源
        if sourcePin is StoragePin || sourcePin is CommandCenterPin || sourcePin is LaunchpadPin {
            quantityToTransfer = sourcePin.removeCommodity(type: type, quantity: quantity)
            if quantityToTransfer == 0 {
                Logger.debug("无法从源设施移除资源")
                Logger.debug("=== 传输结束 ===\n")
                return 0
            }
        }
        
        let quantityAdded = destinationPin.addCommodity(type: type, quantity: quantityToTransfer)
        Logger.debug("\(sourcePin.id) (\(String(describing: sourcePin).split(separator: " ")[0]))) - > \(destinationPin.id) (\(String(describing: destinationPin).split(separator: " ")[0]))) : Type \(type.id) * \(quantityAdded) units")
        // 记录传输后的状态
//        let sourceAfterTransfer = sourcePin.contents[type] ?? 0
//        let destAfterTransfer = destinationPin.contents[type] ?? 0
//        let sourceVolumeAfterTransfer = Float(type.volume) * Float(sourceAfterTransfer)
//        let destVolumeAfterTransfer = Float(type.volume) * Float(destAfterTransfer)
        
//        Logger.debug("\n传输结果:")
//        Logger.debug("- 实际传输: \(quantityAdded) 单位 (\(String(format: "%.2f", Float(type.volume) * Float(quantityAdded))) m³)")
//        Logger.debug("- 源设施资源 \(type.id): \(sourceBeforeTransfer) -> \(sourceAfterTransfer) 单位")
//        Logger.debug("- 源设施体积: \(String(format: "%.2f", sourceVolumeBeforeTransfer)) -> \(String(format: "%.2f", sourceVolumeAfterTransfer)) m³")
//        Logger.debug("- 目标设施资源 \(type.id): \(destBeforeTransfer) -> \(destAfterTransfer) 单位")
//        Logger.debug("- 目标设施体积: \(String(format: "%.2f", destVolumeBeforeTransfer)) -> \(String(format: "%.2f", destVolumeAfterTransfer)) m³")
        
        // 如果有资源需要返还给源设施（仅对存储类型的设施）
        if (sourcePin is StoragePin || sourcePin is CommandCenterPin || sourcePin is LaunchpadPin) && quantityAdded < quantityToTransfer {
            let returnQuantity = quantityToTransfer - quantityAdded
            let quantityReturned = sourcePin.addCommodity(type: type, quantity: returnQuantity)
//            Logger.debug("\n资源返还:")
            Logger.debug("- 返还数量: \(quantityReturned) 单位 (\(String(format: "%.2f", Float(type.volume) * Float(quantityReturned))) m³)")
//            Logger.debug("- 源设施最终资源 \(type.id): \(sourcePin.contents[type] ?? 0) 单位")
        }
        
        Logger.debug("=== 传输结束 ===\n")
        return quantityAdded
    }
    
    /// 执行路由传输
    /// - Parameter route: 路由
    private func executeRoute(_ route: Route) {
        // 获取源设施和目标设施
        guard let sourcePin = getPinOrNull(pinId: route.sourcePinId),
              let destinationPin = getPinOrNull(pinId: route.destinationPinId) else {
            return
        }
        
        // 执行资源传输
        _ = transferCommodities(from: sourcePin, 
                              to: destinationPin, 
                              type: route.type, 
                              quantity: route.quantity)
    }
    
    /// 处理设施的输入路由
    /// - Parameter destinationPin: 目标设施
    private func routeCommodityInput(_ destinationPin: Pin) {
        // 获取目标设施的所有输入路由
        var routesToEvaluate = getDestinationRoutesForPin(pinId: destinationPin.id)
        
        // 遍历每个路由
        while !routesToEvaluate.isEmpty {
            let route = routesToEvaluate.removeFirst()
            
            // 获取源设施
            guard let sourcePin = getPinOrNull(pinId: route.sourcePinId) else { continue }
            
            // 只处理存储类型的源设施
            if !(sourcePin is StoragePin || sourcePin is CommandCenterPin || sourcePin is LaunchpadPin) { continue }
            
            // 检查源设施是否有存储的资源
            let storedCommodities = sourcePin.contents
            if storedCommodities.isEmpty { continue }
            
            // 执行路由传输
            executeRoute(route)
        }
    }
    
    /// 处理设施的输出路由
    /// - Parameters:
    ///   - sourcePin: 源设施
    ///   - commodities: 待分配的资源
    private func routeCommodityOutput(_ sourcePin: Pin, commodities: [CommodityType: Int64]) {
        // 跳过无效的资源
        let validCommodities = commodities.filter { $0.key.id != 0 && $0.value > 0 }
        if validCommodities.isEmpty { return }
        
        Logger.debug("\n=== 开始资源分配 ===")
        Logger.debug("源设施: \(sourcePin.id)")
        Logger.debug("待分配资源: \(validCommodities)")
        
        // 记录剩余待分配的资源
        var remainingCommodities = validCommodities
        
        // 持续分配，直到没有剩余资源或无法继续分配
        var roundCount = 1
        while !remainingCommodities.isEmpty {
            Logger.debug("\n--- 第\(roundCount)轮分配开始 ---")
            Logger.debug("剩余资源: \(remainingCommodities)")
            
            // 按资源类型ID排序，确保固定的分配顺序
            let sortedCommodities = remainingCommodities.sorted { $0.key.id < $1.key.id }
            var commoditiesDistributed = false
            
            // 对每种资源进行分配
            for (commodityType, quantity) in sortedCommodities {
                Logger.debug("\n处理资源: \(commodityType.id)")
                Logger.debug("可分配数量: \(quantity)")
                
                // 获取并排序该资源的所有可能路由
                var (processorRoutes, storageRoutes) = getSortedRoutesForPin(
                    pinId: sourcePin.id,
                    commodities: [commodityType: quantity]
                )
                
                // 先分配给工厂
                while let route = processorRoutes.dequeue() {
                    if let factory = getPinOrNull(pinId: route.destinationId) as? FactoryPin {
                        Logger.debug("\n尝试分配给工厂 \(factory.id):")
                        
                        let maxNeeded = factory.schematic?.inputs[commodityType] ?? 0
                        let currentStock = factory.contents[commodityType] ?? 0
                        let neededQuantity = maxNeeded - currentStock
                        
                        Logger.debug("- 单轮需求量: \(maxNeeded)")
                        Logger.debug("- 当前库存: \(currentStock)")
                        Logger.debug("- 缺货量: \(neededQuantity)")
                        
                        if neededQuantity > 0 {
                            let amountToTransfer = min(quantity, neededQuantity)
                            let transferred = transferCommodities(
                                from: sourcePin,
                                to: factory,
                                type: commodityType,
                                quantity: amountToTransfer
                            )
                            
                            if transferred > 0 {
                                Logger.debug("- 成功转移: \(transferred)")
                                remainingCommodities[commodityType] = quantity - transferred
                                commoditiesDistributed = true

                                let newStock = factory.contents[commodityType] ?? 0
                                if newStock == maxNeeded {
                                    // 缓冲区已满，检查是否完成上一轮加工（假设 isCycleComplete() 方法可用）
                                    if factory.isCycleComplete() {
                                        Logger.debug("- 缓冲区已满且上轮生产已完成，开启下一轮生产并清空缓冲区")
                                        factory.startNextProductionCycle()
                                    } else {
                                        Logger.debug("- 缓冲区已满但上一轮生产未完成")
                                    }
                                }
                                schedulePin(factory)
                            } else {
                                Logger.debug("- 转移失败")
                            }
                        } else {
                            Logger.debug("- 工厂不需要更多该资源")
                        }
                    }
                }
                
                // 如果还有剩余，分配给存储设施
                if let remaining = remainingCommodities[commodityType], remaining > 0 {
                    Logger.debug("\n开始分配剩余资源给存储设施")
                    Logger.debug("剩余数量: \(remaining)")
                    
                    while let route = storageRoutes.dequeue() {
                        if let storage = getPinOrNull(pinId: route.destinationId) {
                            let transferred = transferCommodities(
                                from: sourcePin,
                                to: storage,
                                type: commodityType,
                                quantity: remaining
                            )
                            
                            if transferred > 0 {
                                Logger.debug("存储设施 \(storage.id) 接收: \(transferred)")
                                remainingCommodities[commodityType] = remaining - transferred
                                commoditiesDistributed = true
                                
                                if remainingCommodities[commodityType] == 0 {
                                    remainingCommodities.removeValue(forKey: commodityType)
                                    break
                                }
                            }
                        }
                    }
                }
            }
            
            // 如果这一轮没有分配出任何资源，退出循环
            if !commoditiesDistributed {
                Logger.debug("\n本轮未能分配任何资源，终止分配")
                break
            }
            
            roundCount += 1
            Logger.debug("\n--- 第\(roundCount-1)轮分配结束 ---")
        }
        
        Logger.debug("\n=== 资源分配结束 ===")
        if remainingCommodities.isEmpty {
            Logger.debug("所有资源已分配完成")
        } else {
            Logger.debug("剩余未分配资源: \(remainingCommodities)")
        }
        Logger.debug("共进行了\(roundCount-1)轮分配\n")
    }
    
    /// 获取设施的排序路由
    /// - Parameters:
    ///   - pinId: 设施ID
    ///   - commodities: 资源列表
    /// - Returns: 处理器路由和存储路由
    private func getSortedRoutesForPin(pinId: Int64, commodities: [CommodityType: Int64]) -> (processorRoutes: PriorityQueue<SortedRoute>, storageRoutes: PriorityQueue<SortedRoute>) {
        // 创建两个优先队列，用于存储处理器路由和存储路由
        var processorRoutes = PriorityQueue<SortedRoute> { $0.sortingKey < $1.sortingKey }
        var storageRoutes = PriorityQueue<SortedRoute> { $0.sortingKey < $1.sortingKey }
        
        // 遍历所有以该设施为源的路由
        for route in colony.routes.filter({ $0.sourcePinId == pinId }) {
            // 如果路由的资源类型不在待分配的资源列表中，跳过
            if !commodities.keys.contains(route.type) { continue }
            
            // 获取目标设施
            let destinationPin = getPin(pinId: route.destinationPinId)
            
            // 根据目标设施类型，将路由添加到相应的队列
            if let factory = destinationPin as? FactoryPin {
                if let schematic = factory.schematic,
                   let requiredQuantity = schematic.inputs[route.type] {
                    let currentStock = factory.contents[route.type] ?? 0
                    let needed = max(requiredQuantity - currentStock, 0)
                    // 新的排序逻辑：缺货量越小，优先级越高；缺货量相同时，工厂id越小优先
                    let idPriority = Float(factory.id) / 1_000_0000
                    let sortingKey = Float(needed) + idPriority
                    processorRoutes.enqueue(SortedRoute(
                        sortingKey: sortingKey,
                        destinationId: route.destinationPinId,
                        commodityType: route.type,
                        quantity: route.quantity
                    ))
                }
            } else {
                // 对于存储设施，使用剩余空间作为排序键
                let capacity: Float
                switch destinationPin {
                case is StoragePin:
                    capacity = Float(PinCapacity.storage)
                case is LaunchpadPin:
                    capacity = Float(PinCapacity.launchpad)
                case is CommandCenterPin:
                    capacity = Float(PinCapacity.commandCenter)
                default:
                    capacity = 0
                }
                
                var usedSpace: Float = 0
                for (type, qty) in destinationPin.contents {
                    usedSpace += Float(type.volume) * Float(qty)
                }
                let freeSpace = capacity - usedSpace
                
                // 添加ID作为次要排序条件
                let idPriority = Float(destinationPin.id) / 1_000_000
                let sortingKey = freeSpace + idPriority
                
                storageRoutes.enqueue(SortedRoute(
                    sortingKey: sortingKey,
                    destinationId: route.destinationPinId,
                    commodityType: route.type,
                    quantity: route.quantity
                ))
            }
        }
        
        return (processorRoutes, storageRoutes)
    }
    
    /// 排序路由
    struct SortedRoute {
        /// 排序键
        let sortingKey: Float
        /// 目标设施ID
        let destinationId: Int64
        /// 资源类型
        let commodityType: CommodityType
        /// 数量
        let quantity: Int64
    }
    
    /// 评估设施状态
    /// - Parameter pin: 设施
    private func evaluatePin(_ pin: Pin) {
        Logger.debug("\n=== \(currentSimTime) 设施运行事件 ===")
        Logger.debug("设施: \(pin.id) (\(String(describing: pin).split(separator: " ")[0]))")

        // 如果是消费者，先处理输入路由
        if pin.isConsumer() {
            routeCommodityInput(pin)
        }
        
        // 获取生产的资源
        let commodities = getCommoditiesProducedByPin(pin)
        
        // 如果生产了资源，处理输出路由
        if !commodities.isEmpty {
            routeCommodityOutput(pin, commodities: commodities)
        }
        
        // 如果设施可以运行，重新调度
        if pin.canRun(currentSimTime) {
            Logger.debug("\n重新调度设施")
            schedulePin(pin)
        }
        
        Logger.debug("=== 设施运行结束 ===\n")
    }
    
    /// 处理设施输出
    /// - Parameters:
    ///   - pin: 设施
    ///   - outputs: 输出的资源
    private func handleOutputs(pin: Pin, outputs: [CommodityType: Int64]) {
        // 如果没有输出，直接返回
        if outputs.isEmpty { return }
        
        // 如果是消费者，先处理输入路由
        if pin.isConsumer() {
            routeCommodityInput(pin)
        }
        
        // 处理输出路由
        routeCommodityOutput(pin, commodities: outputs)
        
        // 如果设施可以运行，重新调度
        if pin.canRun(currentSimTime) {
            schedulePin(pin)
        }
    }
    
    /// 运行模拟
    /// - Parameter until: 模拟结束时间
    /// - Returns: 模拟后的殖民地状态列表
    func runSimulation(until: Date) -> [SimulationResult] {
        Logger.debug("初始化模拟器")
        initializeSimulation(.untilNow)
        simEndTime = until
        processedEventCount = 0
        
        var results: [SimulationResult] = []
        
        Logger.debug("开始模拟，结束时间: \(until)")
        while let event = eventQueue.dequeue() {
            if event.time > until {
                Logger.debug("事件时间 \(event.time) 超过结束时间，停止模拟. 模拟了 \(processedEventCount) 个事件")
                break
            }
            
            processedEventCount += 1
            currentSimTime = event.time
            
            if let pin = colony.pins.first(where: { $0.id == event.pinId }) {
                let outputs = pin.run(currentSimTime)
                schedulePin(pin)
                handleOutputs(pin: pin, outputs: outputs)
                
                // 创建新的殖民地实例并记录状态
                let updatedColony = colony.clone()
                updatedColony.pins.forEach { pin in
                    pin.status = pin.getStatus(now: event.time, routes: updatedColony.routes)
                }
                results.append(SimulationResult(time: event.time, colony: updatedColony))
            }
        }
        
        // 检查最终结果中的发射台状态
        if let lastResult = results.last,
           let launchpad = lastResult.colony.pins.first(where: { $0 is LaunchpadPin }) {
            Logger.debug("\n=== 最终模拟结果检查 ===")
            Logger.debug("发射台ID: \(launchpad.id)")
            Logger.debug("发射台库存: \(launchpad.contents)")
            Logger.debug("发射台已用容量: \(launchpad.capacityUsed)")
            Logger.debug("发射台状态: \(launchpad.status)")
            Logger.debug("=== 检查结束 ===\n")
        }
        
        return results
    }
    
    /// 执行模拟
    /// - Parameter endCondition: 结束条件，默认模拟到当前时间
    /// - Returns: 更新后的殖民地状态列表
    func simulate(endCondition: SimulationEndCondition = .untilNow) -> [SimulationResult] {
        Logger.debug("开始模拟，结束条件: \(endCondition)")
        
        // 执行模拟
        let results = runSimulation(until: endCondition.simEndTime)
        
        // 如果是模拟到当前时间，只返回最后一个状态
        if case .untilNow = endCondition {
            return [results.last].compactMap { $0 }
        }
        
        return results
    }
}

// 以下扩展为 FactoryPin 添加生产周期相关的默认实现，以支持缓存机制
extension FactoryPin {
    func isCycleComplete() -> Bool {
        // 检查缓冲区是否已达到生产所需的物资数量
        // 这里假设 FactoryPin 有一个 schematic 属性，其中定义了每种物资的需求量
        guard let schematic = self.schematic else { return true }
        for (commodity, requiredQuantity) in schematic.inputs {
            let current = self.contents[commodity] ?? 0
            if current < requiredQuantity {
                return false
            }
        }
        return true
    }

    func startNextProductionCycle() {
        // 打开下一轮生产：清空缓冲区（即清空当前缓存的物资），并重置其他必要状态
        self.contents.removeAll()
        // 如有需要，可在此添加其他状态重置逻辑
    }
} 
