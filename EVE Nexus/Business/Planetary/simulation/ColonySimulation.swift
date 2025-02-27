import Foundation

/// 行星殖民地模拟
class ColonySimulation {
    
    // MARK: - 类型别名
    
    /// 物品类型别名，对应Kotlin版本中的Type
    typealias ItemType = Type
    
    // MARK: - 模拟结束条件
    
    /// 模拟结束条件
    enum SimulationEndCondition {
        /// 模拟到当前时间
        case untilNow
        /// 模拟到工作结束
        case untilWorkEnds
        
        /// 获取模拟结束时间
        /// - Returns: 模拟结束时间
        func getSimEndTime() -> Date {
            switch self {
            case .untilNow:
                return Date()
            case .untilWorkEnds:
                // 使用一个很远的未来时间
                return Date(timeIntervalSince1970: Double.greatestFiniteMagnitude)
            }
        }
    }
    
    // MARK: - 属性
    
    /// 事件队列 - 存储(时间, 设施ID)的元组
    private static var eventQueue: [(date: Date, pinId: Int64)] = []
    /// 模拟结束时间
    private static var simEndTime: Date? = nil
    /// 当前正在模拟的殖民地引用，用于日志记录
    private static var colony: Colony? = nil
    
    // MARK: - 公共方法
    
    /// 模拟殖民地
    /// - Parameters:
    ///   - colony: 殖民地
    ///   - targetTime: 目标时间
    /// - Returns: 模拟后的殖民地
    static func simulate(colony: Colony, targetTime: Date) -> Colony {
        // 克隆殖民地以避免修改原始数据
        var simulatedColony = colony.clone()
        
        // 如果目标时间早于当前模拟时间，直接返回
        if targetTime <= simulatedColony.currentSimTime {
            return simulatedColony
        }
        
        // 格式化时间
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let startTimeString = dateFormatter.string(from: simulatedColony.currentSimTime)
        let endTimeString = dateFormatter.string(from: targetTime)
        
        Logger.info("开始模拟殖民地: 从 \(startTimeString) 到 \(endTimeString)")
        
        // 检查并处理已经在生产周期中的工厂
        for pin in simulatedColony.pins {
            if let factory = pin as? Pin.Factory, 
               let lastCycleStartTime = factory.lastCycleStartTime, 
               let schematic = factory.schematic,
               factory.isActive {
                
                let cycleEndTime = lastCycleStartTime.addingTimeInterval(schematic.cycleTime)
                
                // 如果生产周期在模拟开始前已经结束，但产品尚未被收集
                if cycleEndTime <= simulatedColony.currentSimTime {
                    Logger.info("模拟开始前发现已完成生产周期的工厂(\(factory.id))，处理其产出")
                    
                    // 添加产出
                    let outputType = schematic.outputType
                    let outputQuantity = schematic.outputQuantity
                    let currentOutputQuantity = factory.contents[outputType] ?? 0
                    factory.contents[outputType] = currentOutputQuantity + outputQuantity
                    
                    // 更新容量使用情况
                    factory.capacityUsed += outputType.volume * Double(outputQuantity)
                    
                    // 清除上一个周期的开始时间，表示已经完成了这个周期
                    factory.lastCycleStartTime = nil
                    
                    // 处理产出的路由
                    let products = [outputType: outputQuantity]
                    routeCommodityOutput(colony: simulatedColony, sourcePin: factory, commodities: products, currentTime: simulatedColony.currentSimTime)
                }
                // 如果工厂正在生产中，但尚未完成，确保它在事件队列中被正确处理
                else if cycleEndTime > simulatedColony.currentSimTime {
                    Logger.info("模拟开始前发现正在生产中的工厂(\(factory.id))，周期结束时间: \(dateFormatter.string(from: cycleEndTime))")
                    // 不需要特殊处理，因为initializeSimulation会将其添加到事件队列中
                }
            }
        }
        
        // 初始化事件队列
        initializeSimulation(colony: simulatedColony, endCondition: .untilNow)
        simEndTime = nil
        
        // 运行事件驱动的模拟
        runEventDrivenSimulation(colony: &simulatedColony, targetTime: targetTime)
        
        // 更新设施状态
        updatePinStatuses(colony: simulatedColony)
        
        // 更新殖民地状态
        simulatedColony.status = getColonyStatus(pins: simulatedColony.pins)
        
        // 更新殖民地概览
        simulatedColony.overview = getColonyOverview(routes: simulatedColony.routes, pins: simulatedColony.pins)
        
        Logger.info("殖民地模拟完成: 状态: \(simulatedColony.status), 最终产品数量: \(simulatedColony.overview.finalProducts.count)")
        
        // 打印殖民地模拟详细信息
        printColonySimulationDetails(colony: simulatedColony)
        
        return simulatedColony
    }
    
    /// 模拟殖民地到未来时间
    /// - Parameters:
    ///   - colony: 殖民地
    ///   - hours: 小时数
    /// - Returns: 模拟后的殖民地
    static func simulateColonyForward(colony: Colony, hours: Int) -> Colony {
        let targetTime = colony.currentSimTime.addingTimeInterval(TimeInterval(hours * 3600))
        return simulate(colony: colony, targetTime: targetTime)
    }
    
    /// 模拟殖民地直到工作结束
    /// - Parameter colony: 殖民地
    /// - Returns: 模拟后的殖民地
    static func simulateColonyUntilWorkEnds(colony: Colony) -> Colony {
        // 克隆殖民地以避免修改原始数据
        var simulatedColony = colony.clone()
        
        // 如果殖民地已经不处于工作状态，直接返回
        if !isColonyWorking(pins: simulatedColony.pins) {
            return simulatedColony
        }
        
        Logger.info("开始模拟殖民地直到工作结束: 从 \(simulatedColony.currentSimTime)")
        
        // 格式化时间
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        // 检查并处理已经在生产周期中的工厂
        for pin in simulatedColony.pins {
            if let factory = pin as? Pin.Factory, 
               let lastCycleStartTime = factory.lastCycleStartTime, 
               let schematic = factory.schematic,
               factory.isActive {
                
                let cycleEndTime = lastCycleStartTime.addingTimeInterval(schematic.cycleTime)
                
                // 如果生产周期在模拟开始前已经结束，但产品尚未被收集
                if cycleEndTime <= simulatedColony.currentSimTime {
                    Logger.info("模拟开始前发现已完成生产周期的工厂(\(factory.id))，处理其产出")
                    
                    // 添加产出
                    let outputType = schematic.outputType
                    let outputQuantity = schematic.outputQuantity
                    let currentOutputQuantity = factory.contents[outputType] ?? 0
                    factory.contents[outputType] = currentOutputQuantity + outputQuantity
                    
                    // 更新容量使用情况
                    factory.capacityUsed += outputType.volume * Double(outputQuantity)
                    
                    // 清除上一个周期的开始时间，表示已经完成了这个周期
                    factory.lastCycleStartTime = nil
                    
                    // 处理产出的路由
                    let products = [outputType: outputQuantity]
                    routeCommodityOutput(colony: simulatedColony, sourcePin: factory, commodities: products, currentTime: simulatedColony.currentSimTime)
                }
                // 如果工厂正在生产中，但尚未完成，确保它在事件队列中被正确处理
                else if cycleEndTime > simulatedColony.currentSimTime {
                    Logger.info("模拟开始前发现正在生产中的工厂(\(factory.id))，周期结束时间: \(dateFormatter.string(from: cycleEndTime))")
                    // 不需要特殊处理，因为initializeSimulation会将其添加到事件队列中
                }
            }
        }
        
        // 初始化事件队列和模拟结束时间
        initializeSimulation(colony: simulatedColony, endCondition: .untilWorkEnds)
        simEndTime = nil
        
        // 运行事件驱动的模拟
        let targetTime = SimulationEndCondition.untilWorkEnds.getSimEndTime()
        runEventDrivenSimulation(colony: &simulatedColony, targetTime: targetTime)
        
        // 更新设施状态
        updatePinStatuses(colony: simulatedColony)
        
        // 更新殖民地状态
        simulatedColony.status = getColonyStatus(pins: simulatedColony.pins)
        
        // 更新殖民地概览
        simulatedColony.overview = getColonyOverview(routes: simulatedColony.routes, pins: simulatedColony.pins)
        
        Logger.info("殖民地模拟完成，状态: \(simulatedColony.status)")
        
        // 打印殖民地模拟详细信息
        printColonySimulationDetails(colony: simulatedColony)
        
        return simulatedColony
    }
    
    /// 获取殖民地的下一个关键时间点
    /// - Parameter colony: 殖民地
    /// - Returns: 下一个关键时间点
    static func getNextKeyTime(colony: Colony) -> Date? {
        var nextTime: Date? = nil
        
        // 检查提取器过期时间
        for pin in colony.pins {
            if let extractor = pin as? Pin.Extractor, extractor.isActive {
                if let expiryTime = extractor.expiryTime, expiryTime > colony.currentSimTime {
                    if nextTime == nil || expiryTime < nextTime! {
                        nextTime = expiryTime
                    }
                }
            }
        }
        
        // 检查下一个运行时间
        for pin in colony.pins {
            let nextRunTime = getNextRunTime(pin: pin)
            if let nextRun = nextRunTime, nextRun > colony.currentSimTime {
                if nextTime == nil || nextRun < nextTime! {
                    nextTime = nextRun
                }
            }
        }
        
        return nextTime
    }
    
    /// 模拟殖民地到下一个关键时间点
    /// - Parameter colony: 殖民地
    /// - Returns: 模拟后的殖民地和是否有更多关键时间点
    static func simulateColonyToNextKeyTime(colony: Colony) -> (Colony, Bool) {
        guard let nextTime = getNextKeyTime(colony: colony) else {
            return (colony, false)
        }
        
        let simulatedColony = simulate(colony: colony, targetTime: nextTime)
        let hasMoreKeyTimes = getNextKeyTime(colony: simulatedColony) != nil
        
        return (simulatedColony, hasMoreKeyTimes)
    }
    
    // MARK: - 私有方法
    
    /// 检查殖民地是否处于工作状态
    /// - Parameter pins: 设施列表
    /// - Returns: 是否处于工作状态
    private static func isColonyWorking(pins: [Pin]) -> Bool {
        // 检查是否有任何设施处于工作状态
        for pin in pins {
            if isActive(pin: pin) {
                return true
            }
        }
        
        // 检查是否有任何设施可以激活
        for pin in pins {
            if canActivate(pin: pin) {
                return true
            }
        }
        
        return false
    }
    
    /// 获取设施的下一个运行时间
    /// - Parameter pin: 设施
    /// - Returns: 下一个运行时间
    private static func getNextRunTime(pin: Pin) -> Date? {
        if let extractor = pin as? Pin.Extractor {
            if extractor.isActive, let lastRunTime = extractor.lastRunTime, let cycleTime = extractor.cycleTime {
                return lastRunTime.addingTimeInterval(cycleTime)
            }
        } else if let factory = pin as? Pin.Factory {
            // 如果工厂正在生产中（有lastCycleStartTime），则返回周期结束时间
            if let lastCycleStartTime = factory.lastCycleStartTime, let schematic = factory.schematic {
                return lastCycleStartTime.addingTimeInterval(schematic.cycleTime)
            }
            // 否则，如果有lastRunTime，返回下一个可以开始生产的时间
            else if let lastRunTime = factory.lastRunTime, let schematic = factory.schematic {
                return lastRunTime.addingTimeInterval(schematic.cycleTime)
            }
        }
        
        return nil
    }
    
    /// 初始化模拟事件队列
    /// - Parameters:
    ///   - colony: 殖民地
    ///   - endCondition: 模拟结束条件
    private static func initializeSimulation(colony: Colony, endCondition: SimulationEndCondition) {
        // 清空事件队列
        eventQueue.removeAll()
        
        // 格式化时间
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        // 为每个可运行的设施安排事件
        for pin in colony.pins {
            // 特别处理正在生产中的工厂
            if let factory = pin as? Pin.Factory, 
               let lastCycleStartTime = factory.lastCycleStartTime, 
               let schematic = factory.schematic,
               factory.isActive {
                
                let cycleEndTime = lastCycleStartTime.addingTimeInterval(schematic.cycleTime)
                
                // 如果生产周期尚未结束，直接将其添加到事件队列
                if cycleEndTime > colony.currentSimTime {
                    Logger.info("将正在生产中的工厂(\(factory.id))添加到事件队列，周期结束时间: \(dateFormatter.string(from: cycleEndTime))")
                    eventQueue.append((cycleEndTime, factory.id))
                    continue
                }
            }
            
            // 处理其他可运行的设施
            if canRun(pin: pin, time: endCondition.getSimEndTime()) {
                schedulePin(pin: pin, currentTime: colony.currentSimTime)
            }
        }
        
        // 按时间排序事件队列
        eventQueue.sort { event1, event2 in
            if event1.date == event2.date {
                return event1.pinId < event2.pinId
            }
            return event1.date < event2.date
        }
        
        // 记录事件队列信息
        if !eventQueue.isEmpty {
            Logger.info("初始化事件队列完成，共 \(eventQueue.count) 个事件:")
            for (index, event) in eventQueue.prefix(5).enumerated() {
                let pinId = event.pinId
                let eventTime = event.date
                let pinType = colony.pins.first(where: { $0.id == pinId }).map { getPinTypeName(pin: $0) } ?? "未知"
                Logger.info("  \(index + 1). \(pinType)(\(pinId)) 将在 \(dateFormatter.string(from: eventTime)) 运行")
            }
            if eventQueue.count > 5 {
                Logger.info("  ... 以及 \(eventQueue.count - 5) 个其他事件")
            }
        }
    }
    
    /// 运行事件驱动的模拟
    /// - Parameters:
    ///   - colony: 殖民地引用
    ///   - targetTime: 目标时间
    private static func runEventDrivenSimulation(colony: inout Colony, targetTime: Date) {
        // 保存当前模拟时间
        var currentSimTime = colony.currentSimTime
        let realTimeNow = Date()
        
        // 设置当前模拟的殖民地引用，用于日志记录
        self.colony = colony
        
        // 格式化时间
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        Logger.info("开始事件驱动模拟，从 \(dateFormatter.string(from: currentSimTime)) 到 \(dateFormatter.string(from: targetTime))")
        
        // 循环处理事件队列
        while !eventQueue.isEmpty {
            // 获取并移除队列中的第一个事件
            let event = eventQueue.removeFirst()
            let eventTime = event.date
            let pinId = event.pinId
            
            // 检查模拟结束条件
            // 1. 如果已设置模拟结束时间且事件时间超过结束时间，结束模拟
            if let endTime = simEndTime, eventTime > endTime {
                Logger.info("事件时间 \(dateFormatter.string(from: eventTime)) 超过模拟结束时间 \(dateFormatter.string(from: endTime))，结束模拟")
                break
            }
            
            // 2. 如果事件时间超过目标时间，结束模拟
            if eventTime > targetTime {
                Logger.info("事件时间 \(dateFormatter.string(from: eventTime)) 超过目标时间 \(dateFormatter.string(from: targetTime))，结束模拟")
                break
            }
            
            // 3. 如果模拟到当前时间且事件时间超过当前实际时间，结束模拟
            if eventTime > realTimeNow && targetTime > realTimeNow {
                Logger.info("事件时间 \(dateFormatter.string(from: eventTime)) 超过当前实际时间 \(dateFormatter.string(from: realTimeNow))，结束模拟")
                colony.currentSimTime = realTimeNow
                break
            }
            
            // 更新当前模拟时间
            currentSimTime = eventTime
            colony.currentSimTime = currentSimTime
            
            // 获取要处理的设施
            guard let pin = colony.pins.first(where: { $0.id == pinId }) else {
                Logger.warning("找不到ID为 \(pinId) 的设施，跳过该事件")
                continue
            }
            
            // 记录事件处理信息
            let pinType = getPinTypeName(pin: pin)
            Logger.info("\(dateFormatter.string(from: currentSimTime)): 处理 \(pinType)(\(pin.id)) 的事件")
            
            // 检查工厂是否正在生产中
            if let factory = pin as? Pin.Factory, 
               let lastCycleStartTime = factory.lastCycleStartTime, 
               let schematic = factory.schematic,
               factory.isActive {
                
                let cycleEndTime = lastCycleStartTime.addingTimeInterval(schematic.cycleTime)
                
                // 如果当前时间已经达到或超过了周期结束时间，记录详细信息
                if currentSimTime >= cycleEndTime {
                    Logger.info("\(dateFormatter.string(from: currentSimTime)): 工厂(\(factory.id))的生产周期已完成，开始于 \(dateFormatter.string(from: lastCycleStartTime))，周期时间 \(Int(schematic.cycleTime)) 秒")
                }
            }
            
            // 如果设施可以运行，处理该设施
            if canRun(pin: pin, time: targetTime) {
                // 修改处理顺序，与Kotlin版本保持一致
                
                // 1. 如果设施是消费者，先处理输入路由
                if isConsumer(pin: pin) {
                    routeCommodityInput(colony: colony, destinationPin: pin, currentTime: currentSimTime)
                }
                
                // 2. 运行设施并获取产出的资源
                let commodities = run(pin: pin, time: currentSimTime)
                
                // 3. 重新安排该设施的下一次运行
                if isActive(pin: pin) || canActivate(pin: pin) {
                    schedulePin(pin: pin, currentTime: currentSimTime)
                }
                
                // 4. 如果设施产出了资源，处理输出路由
                if !commodities.isEmpty {
                    routeCommodityOutput(colony: colony, sourcePin: pin, commodities: commodities, currentTime: currentSimTime)
                }
            }
            
            // 检查是否需要更新模拟结束时间（针对"直到工作结束"的模拟）
            if targetTime == SimulationEndCondition.untilWorkEnds.getSimEndTime() && simEndTime == nil {
                // 获取殖民地当前状态
                updatePinStatuses(colony: colony)
                let isWorking = isColonyWorking(pins: colony.pins)
                
                // 如果已经不在工作，设置模拟结束时间
                if !isWorking {
                    // 检查是否有设施的存储已满
                    let hasStorageFull = colony.pins.contains { pin in 
                        return pin.status == .storageFull
                    }
                    
                    if hasStorageFull {
                        // 如果因为存储已满而停止，立即结束模拟
                        break
                    } else {
                        // 否则，继续模拟到当前时间点
                        simEndTime = currentSimTime
                    }
                }
            }
        }
        
        // 更新殖民地的当前模拟时间
        colony.currentSimTime = simEndTime ?? targetTime
        if colony.currentSimTime > targetTime {
            colony.currentSimTime = targetTime
        }
        
        // 清除当前模拟的殖民地引用
        self.colony = nil
    }
    
    /// 运行设施
    /// - Parameters:
    ///   - pin: 设施
    ///   - time: 当前时间
    /// - Returns: 产出的资源
    private static func run(pin: Pin, time: Date) -> [ItemType: Int64] {
        var products: [ItemType: Int64] = [:]
        
        if let extractor = pin as? Pin.Extractor {
            runExtractor(extractor: extractor, time: time)
            
            // 收集提取器产出的资源
            if let productType = extractor.productType, extractor.isActive {
                let output = extractor.contents[productType] ?? 0
                if output > 0 {
                    products[productType] = output
                    
                    // 清空提取器的存储，因为产出的资源会被路由
                    extractor.contents.removeValue(forKey: productType)
                    extractor.capacityUsed = 0
                }
            }
        } else if let factory = pin as? Pin.Factory {
            // 运行工厂并获取生产状态
            let productionStatus = runFactory(factory: factory, time: time)
            
            // 只有当工厂完成了一个生产周期时，才收集产出
            if productionStatus == .completedCycle, let schematic = factory.schematic {
                // 移除对factory.isActive的检查，确保产出能被收集
                products[schematic.outputType] = schematic.outputQuantity
                
                // 清空工厂的产出存储，因为产出的资源会被路由
                factory.contents.removeValue(forKey: schematic.outputType)
                factory.capacityUsed -= schematic.outputType.volume * Double(schematic.outputQuantity)
            }
        }
        
        return products
    }
    
    /// 运行提取器
    /// - Parameters:
    ///   - extractor: 提取器
    ///   - time: 当前时间
    private static func runExtractor(extractor: Pin.Extractor, time: Date) {
        guard let productType = extractor.productType,
              let baseValue = extractor.baseValue,
              let installTime = extractor.installTime,
              let cycleTime = extractor.cycleTime else {
            Logger.warning("提取器缺少必要信息，无法运行: \(extractor.designator)")
            return
        }
        
        // 计算产量
        let output = ExtractionSimulation.getProgramOutput(
            baseValue: baseValue,
            startTime: installTime,
            currentTime: time,
            cycleTime: cycleTime
        )
        
        // 格式化时间
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timeString = dateFormatter.string(from: time)
        
        Logger.info("\(timeString): 提取器(\(extractor.id)) 生产 [\(productType.name)x\(output)]")
        
        // 将产出的资源添加到存储中
        let currentQuantity = extractor.contents[productType] ?? 0
        extractor.contents[productType] = currentQuantity + output
        
        // 更新容量使用情况
        extractor.capacityUsed += productType.volume * Double(output)
        
        // 更新运行时间
        extractor.lastRunTime = time
        
        // 检查是否过期
        if let expiryTime = extractor.expiryTime, expiryTime <= time {
            extractor.isActive = false
            Logger.info("\(timeString): 提取器(\(extractor.id)) 已过期")
        }
    }
    
    /// 工厂生产状态
    enum FactoryProductionStatus {
        /// 未生产（缺少材料或配方）
        case notProduced
        /// 开始新的生产周期
        case startedCycle
        /// 完成生产周期
        case completedCycle
    }
    
    /// 运行工厂
    /// - Parameters:
    ///   - factory: 工厂
    ///   - time: 当前时间
    /// - Returns: 工厂生产状态
    private static func runFactory(factory: Pin.Factory, time: Date) -> FactoryProductionStatus {
        // 格式化时间
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timeString = dateFormatter.string(from: time)
        
        // 首先检查是否有配方
        guard let schematic = factory.schematic else {
            Logger.warning("工厂 \(factory.designator) 没有配置配方，无法运行")
            return .notProduced
        }
        
        // 检查是否有上一个生产周期的产品需要输出
        if let lastCycleStartTime = factory.lastCycleStartTime, factory.isActive {
            let cycleEndTime = lastCycleStartTime.addingTimeInterval(schematic.cycleTime)
            
            // 如果当前时间已经达到或超过了周期结束时间，则完成生产周期
            if time >= cycleEndTime {
                // 添加产出
                let outputType = schematic.outputType
                let outputQuantity = schematic.outputQuantity
                let currentOutputQuantity = factory.contents[outputType] ?? 0
                factory.contents[outputType] = currentOutputQuantity + outputQuantity
                
                // 更新容量使用情况
                factory.capacityUsed += outputType.volume * Double(outputQuantity)
                
                Logger.info("\(timeString): 工厂(\(factory.id)) 完成生产周期，生产 [\(outputType.name)x\(outputQuantity)]")
                
                // 清除上一个周期的开始时间，表示已经完成了这个周期
                factory.lastCycleStartTime = nil
                
                // 与Kotlin版本保持一致，在生产周期结束后设置isActive为false
                factory.isActive = false
                
                // 工厂开始生产后，尝试从仓储设施重新填充其缓冲区
                refillFactoryBuffer(factory: factory, time: time)
                
                return .completedCycle
            }
            
            // 当前时间还未到达周期结束时间，继续等待
            Logger.debug("工厂(\(factory.id)) 正在生产中，等待周期结束")
            return .startedCycle
        }
        
        // 检查是否在生产周期内
        if let lastRunTime = factory.lastRunTime {
            let nextRunTime = lastRunTime.addingTimeInterval(schematic.cycleTime)
            if time < nextRunTime {
                Logger.debug("工厂(\(factory.id)) 尚未到达下一个生产周期")
                return .notProduced
            }
        }
        
        // 记录工厂缓冲区状态
        var bufferStatus = ""
        for (inputType, requiredQuantity) in schematic.inputs {
            let availableQuantity = factory.contents[inputType] ?? 0
            let ratio = Double(availableQuantity) / Double(requiredQuantity)
            bufferStatus += "\(inputType.name): \(availableQuantity)/\(requiredQuantity) (\(Int(ratio * 100))%), "
        }
        
        // 移除最后的逗号和空格
        if !bufferStatus.isEmpty {
            bufferStatus.removeLast(2)
        }
        
        Logger.info("\(timeString): 工厂(\(factory.id)) 运行前缓冲区状态: [\(bufferStatus)]")
        
        // 检查是否有足够的输入材料
        var canConsume = true
        for (inputType, requiredQuantity) in schematic.inputs {
            let availableQuantity = factory.contents[inputType] ?? 0
            if availableQuantity < requiredQuantity {
                canConsume = false
                break
            }
        }
        
        if canConsume {
            // 记录输入材料消耗
            var inputsLog = ""
            for (inputType, requiredQuantity) in schematic.inputs {
                if !inputsLog.isEmpty {
                    inputsLog += ", "
                }
                inputsLog += "\(inputType.name)x\(requiredQuantity)"
                
                // 消耗输入材料
                let currentQuantity = factory.contents[inputType] ?? 0
                factory.contents[inputType] = currentQuantity - requiredQuantity
                
                // 更新容量使用情况
                factory.capacityUsed -= inputType.volume * Double(requiredQuantity)
            }
            
            Logger.info("\(timeString): 工厂(\(factory.id)) 消耗 [\(inputsLog)]")
            Logger.info("\(timeString): 工厂(\(factory.id)) 开始生产 [\(schematic.outputType.name)x\(schematic.outputQuantity)]，需要 \(Int(schematic.cycleTime)) 秒")
            
            // 更新状态
            factory.isActive = true
            factory.lastCycleStartTime = time
            
            // 记录工厂运行后的缓冲区状态
            bufferStatus = ""
            for (inputType, requiredQuantity) in schematic.inputs {
                let availableQuantity = factory.contents[inputType] ?? 0
                let ratio = Double(availableQuantity) / Double(requiredQuantity)
                bufferStatus += "\(inputType.name): \(availableQuantity)/\(requiredQuantity) (\(Int(ratio * 100))%), "
            }
            
            // 移除最后的逗号和空格
            if !bufferStatus.isEmpty {
                bufferStatus.removeLast(2)
            }
            
            Logger.info("\(timeString): 工厂(\(factory.id)) 运行后缓冲区状态: [\(bufferStatus)]")
            
            // 更新运行时间和输入状态
            factory.lastRunTime = time
            factory.receivedInputsLastCycle = factory.hasReceivedInputs
            factory.hasReceivedInputs = false
            
            // 工厂开始生产后，尝试从仓储设施重新填充其缓冲区
            refillFactoryBuffer(factory: factory, time: time)
            
            return .startedCycle // 开始新的生产周期
        } else {
            // 与Kotlin版本保持一致，如果不能消耗材料，设置isActive为false
            factory.isActive = false
            factory.lastRunTime = time
            factory.receivedInputsLastCycle = factory.hasReceivedInputs
            factory.hasReceivedInputs = false
            
            Logger.info("\(timeString): 工厂(\(factory.id)) 缺少材料，无法开始生产")
            return .notProduced
        }
    }
    
    /// 安排设施的下一次运行
    /// - Parameters:
    ///   - pin: 设施
    ///   - currentTime: 当前时间
    private static func schedulePin(pin: Pin, currentTime: Date) {
        // 获取下一次运行时间
        guard let nextRunTime = getNextRunTime(pin: pin) else {
            return
        }
        
        // 如果下一次运行时间早于当前时间，则使用当前时间
        let scheduleTime = nextRunTime > currentTime ? nextRunTime : currentTime
        
        // 检查是否已经在队列中
        if let index = eventQueue.firstIndex(where: { $0.pinId == pin.id }) {
            // 如果新的运行时间更早，则更新事件
            if scheduleTime < eventQueue[index].date {
                eventQueue.remove(at: index)
                eventQueue.append((scheduleTime, pin.id))
                // 重新排序队列
                eventQueue.sort { event1, event2 in
                    if event1.date == event2.date {
                        return event1.pinId < event2.pinId
                    }
                    return event1.date < event2.date
                }
            }
        } else {
            // 添加新事件到队列
            eventQueue.append((scheduleTime, pin.id))
            // 重新排序队列
            eventQueue.sort { event1, event2 in
                if event1.date == event2.date {
                    return event1.pinId < event2.pinId
                }
                return event1.date < event2.date
            }
        }
    }
    
    /// 运行所有设施
    /// - Parameters:
    ///   - colony: 殖民地
    ///   - targetTime: 目标时间
    private static func runPins(colony: Colony, targetTime: Date) {
        // 按照优先级排序设施
        let sortedPins = sortPinsByPriority(pins: colony.pins)
        
        Logger.info("开始运行设施，共 \(sortedPins.count) 个设施")
        
        // 运行每个设施
        for pin in sortedPins {
            if canRun(pin: pin, time: targetTime) {
                Logger.info("运行设施: \(pin.designator) (\(pin.name)), ID: \(pin.id)")
                
                // 1. 如果设施是消费者，先处理输入路由
                if isConsumer(pin: pin) {
                    routeCommodityInput(colony: colony, destinationPin: pin, currentTime: targetTime)
                }
                
                // 2. 运行设施并获取产出的资源
                let commodities = run(pin: pin, time: targetTime)
                
                // 3. 如果设施产出了资源，处理输出路由
                if !commodities.isEmpty {
                    routeCommodityOutput(colony: colony, sourcePin: pin, commodities: commodities, currentTime: targetTime)
                }
            } else {
                Logger.debug("设施无法运行: \(pin.designator) (\(pin.name)), ID: \(pin.id)")
            }
        }
    }
    
    /// 按优先级排序设施
    /// - Parameter pins: 设施列表
    /// - Returns: 排序后的设施列表
    private static func sortPinsByPriority(pins: [Pin]) -> [Pin] {
        return pins.sorted { pin1, pin2 in
            let priority1 = getPinPriority(pin: pin1)
            let priority2 = getPinPriority(pin: pin2)
            return priority1 > priority2
        }
    }
    
    /// 获取设施优先级
    /// - Parameter pin: 设施
    /// - Returns: 优先级
    private static func getPinPriority(pin: Pin) -> Int {
        switch pin {
        case is Pin.Extractor:
            return 3
        case is Pin.Factory:
            return 2
        case is Pin.Storage, is Pin.Launchpad, is Pin.CommandCenter:
            return 1
        default:
            return 0
        }
    }
    
    /// 检查设施是否可以运行
    /// - Parameters:
    ///   - pin: 设施
    ///   - time: 当前时间
    /// - Returns: 是否可以运行
    private static func canRun(pin: Pin, time: Date) -> Bool {
        // 首先检查设施是否可以激活或已经激活
        if !canActivate(pin: pin) && !isActive(pin: pin) {
            return false
        }
        
        // 获取下一次运行时间
        let nextRunTime = getNextRunTime(pin: pin)
        
        // 如果没有下一次运行时间或者下一次运行时间小于等于当前时间，则可以运行
        return nextRunTime == nil || nextRunTime! <= time
    }
    
    /// 检查设施是否可以激活
    /// - Parameter pin: 设施
    /// - Returns: 是否可以激活
    private static func canActivate(pin: Pin) -> Bool {
        if let extractor = pin as? Pin.Extractor {
            // 提取器需要是激活状态并且有产品类型
            if !extractor.isActive {
                return false
            }
            return extractor.productType != nil
        } else if let factory = pin as? Pin.Factory {
            // 工厂需要有配方
            if factory.schematic == nil {
                return false
            }
            
            // 如果已经激活，直接返回true
            if isActive(pin: factory) {
                return true
            }
            
            // 如果当前周期或上一周期收到了输入，可以激活
            if factory.hasReceivedInputs || factory.receivedInputsLastCycle {
                return true
            }
            
            // 与Kotlin版本保持一致，如果有足够的输入材料，返回false
            if hasEnoughInputs(factory: factory) {
                return false
            }
        }
        
        // 存储类设施不需要激活
        return false
    }
    
    /// 检查设施是否处于激活状态
    /// - Parameter pin: 设施
    /// - Returns: 是否处于激活状态
    private static func isActive(pin: Pin) -> Bool {
        if let extractor = pin as? Pin.Extractor {
            return extractor.productType != nil && extractor.isActive
        } else if let factory = pin as? Pin.Factory {
            return factory.isActive
        } else {
            // 存储类设施默认是激活的
            return pin.isActive
        }
    }
    
    /// 检查设施是否为消费者
    /// - Parameter pin: 设施
    /// - Returns: 是否为消费者
    private static func isConsumer(pin: Pin) -> Bool {
        return pin is Pin.Factory
    }
    
    /// 检查设施是否为存储设施
    /// - Parameter pin: 设施
    /// - Returns: 是否为存储设施
    private static func isStorage(pin: Pin) -> Bool {
        return pin is Pin.Storage || pin is Pin.Launchpad || pin is Pin.CommandCenter
    }
    
    /// 获取设施的剩余容量
    /// - Parameter pin: 设施
    /// - Returns: 剩余容量
    private static func getCapacityRemaining(pin: Pin) -> Double {
        var totalCapacity: Double = 0
        
        if let capacity = getCapacity(for: pin) {
            totalCapacity = Double(capacity)
        }
        
        return max(0, totalCapacity - pin.capacityUsed)
    }
    
    /// 获取工厂的输入缓冲区状态
    /// - Parameter factory: 工厂
    /// - Returns: 输入缓冲区状态（0-1之间的浮点数，0表示满，1表示空）
    private static func getInputBufferState(factory: Pin.Factory) -> Double {
        guard let schematic = factory.schematic else {
            return 1.0
        }
        
        var productsRatio: Double = 0.0
        for (inputType, requiredQuantity) in schematic.inputs {
            let availableQuantity = factory.contents[inputType] ?? 0
            productsRatio += Double(availableQuantity) / Double(requiredQuantity)
        }
        
        // 如果没有输入材料，返回1.0（完全空）
        if schematic.inputs.isEmpty {
            return 1.0
        }
        
        // 返回空闲比例（1 - 填充比例）
        return (1.0 - productsRatio / Double(schematic.inputs.count))
    }
    
    /// 检查工厂是否有足够的输入材料
    /// - Parameter factory: 工厂
    /// - Returns: 是否有足够的输入材料
    private static func hasEnoughInputs(factory: Pin.Factory) -> Bool {
        guard let schematic = factory.schematic else {
            return false
        }
        
        // 检查每种输入材料是否足够
        for (inputType, requiredQuantity) in schematic.inputs {
            let availableQuantity = factory.contents[inputType] ?? 0
            if availableQuantity < requiredQuantity {
                return false
            }
        }
        
        return true
    }
    
    /// 处理设施的输入资源路由
    /// - Parameters:
    ///   - colony: 殖民地
    ///   - destinationPin: 目标设施
    ///   - currentTime: 当前模拟时间
    private static func routeCommodityInput(colony: Colony, destinationPin: Pin, currentTime: Date) {
        // 获取以该设施为目标的所有路由
        let routesToEvaluate = colony.routes.filter { $0.destinationPinId == destinationPin.id }
        
        // 记录接收资源的设施和数量
        var pinsReceivingCommodities: [Int64: [ItemType: Int64]] = [:]
        
        for route in routesToEvaluate {
            // 获取源设施
            guard let sourcePin = colony.pins.first(where: { $0.id == route.sourcePinId }) else {
                continue
            }
            
            // 仅处理存储设施作为源的路由
            if !isStorage(pin: sourcePin) {
                continue
            }
            
            // 获取存储的资源
            let storedCommodities = sourcePin.contents
            if storedCommodities.isEmpty {
                continue
            }
            
            // 执行路由
            let (type, transferredQuantity) = transferCommodities(
                sourcePin: sourcePin,
                destinationPin: destinationPin,
                type: route.type,
                quantity: route.quantity,
                commodities: storedCommodities,
                currentTime: currentTime
            )
            
            // 如果转移了资源，记录日志和更新接收记录
            if let type = type, transferredQuantity > 0 {
                // 获取设施类型名称
                let sourcePinType = getPinTypeName(pin: sourcePin)
                let destinationPinType = getPinTypeName(pin: destinationPin)
                
                // 格式化时间
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                let timeString = dateFormatter.string(from: currentTime)
                
                Logger.info("\(timeString): \(sourcePinType)(\(sourcePin.id)) 输出 [\(type.name)x\(transferredQuantity)] 到 \(destinationPinType)(\(destinationPin.id))")
                Logger.info("\(timeString): \(destinationPinType)(\(destinationPin.id)) 接收 [\(type.name)x\(transferredQuantity)] 从 \(sourcePinType)(\(sourcePin.id))")
                
                // 更新接收记录
                if !pinsReceivingCommodities.keys.contains(destinationPin.id) {
                    pinsReceivingCommodities[destinationPin.id] = [:]
                }
                
                pinsReceivingCommodities[destinationPin.id]![type] = (pinsReceivingCommodities[destinationPin.id]![type] ?? 0) + transferredQuantity
            }
        }
        
        // 处理接收到资源的设施
        for (receivingPinId, _) in pinsReceivingCommodities {
            guard let receivingPin = colony.pins.first(where: { $0.id == receivingPinId }) else {
                continue
            }
            
            // 如果接收者是消费者，安排其运行
            if isConsumer(pin: receivingPin) {
                schedulePin(pin: receivingPin, currentTime: currentTime)
            }
        }
    }
    
    /// 处理设施的输出资源路由
    /// - Parameters:
    ///   - colony: 殖民地
    ///   - sourcePin: 源设施
    ///   - commodities: 要路由的资源
    ///   - currentTime: 当前模拟时间
    private static func routeCommodityOutput(colony: Colony, sourcePin: Pin, commodities: [ItemType: Int64], currentTime: Date) {
        // 记录接收资源的设施和数量
        var pinsReceivingCommodities: [Int64: [ItemType: Int64]] = [:]
        
        // 创建可变的资源副本
        var remainingCommodities = commodities
        
        // 获取并排序路由
        var (processorRoutes, storageRoutes) = getSortedRoutesForPin(colony: colony, pinId: sourcePin.id, commodities: commodities)
        
        // 记录路由排序信息
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timeString = dateFormatter.string(from: currentTime)
        
        if !processorRoutes.isEmpty {
            var routeInfo = ""
            for route in processorRoutes {
                if let destinationPin = colony.pins.first(where: { $0.id == route.destinationId }) {
                    let pinType = getPinTypeName(pin: destinationPin)
                    routeInfo += "\(pinType)(\(destinationPin.id)): 缓冲区状态 \(Int(route.sortingKey * 100))%, "
                }
            }
            if !routeInfo.isEmpty {
                routeInfo.removeLast(2)
                Logger.info("\(timeString): 处理器路由排序: [\(routeInfo)]")
            }
        }
        
        // 优先处理处理器路由（工厂优先）
        var done = false
        
        // 首先处理处理器路由
        while !processorRoutes.isEmpty && !done {
            let route = processorRoutes.removeFirst()
            
            guard let destinationPin = colony.pins.first(where: { $0.id == route.destinationId }) else {
                continue
            }
            
            let (type, transferredQuantity) = transferCommodities(
                sourcePin: sourcePin,
                destinationPin: destinationPin,
                type: route.commodityType,
                quantity: route.quantity,
                commodities: remainingCommodities,
                currentTime: currentTime
            )
            
            // 更新剩余资源和接收记录
            updateCommoditiesAfterTransfer(
                type: type,
                transferredQuantity: transferredQuantity,
                remainingCommodities: &remainingCommodities,
                pinsReceivingCommodities: &pinsReceivingCommodities,
                destinationId: route.destinationId
            )
            
            // 如果所有资源都已路由，结束处理
            if remainingCommodities.isEmpty {
                done = true
                break
            }
        }
        
        // 然后处理存储路由
        while !storageRoutes.isEmpty && !done {
            let route = storageRoutes.removeFirst()
            
            guard let destinationPin = colony.pins.first(where: { $0.id == route.destinationId }) else {
                continue
            }
            
            // 为存储路由计算最大转移量（平均分配）
            var maxAmount: Int64 = 0
            if remainingCommodities.count > 0 {
                let commodity = route.commodityType
                let remaining = remainingCommodities[commodity] ?? 0
                maxAmount = Int64(ceil(Double(remaining) / Double(storageRoutes.count + 1)))
            }
            
            let (type, transferredQuantity) = transferCommodities(
                sourcePin: sourcePin,
                destinationPin: destinationPin,
                type: route.commodityType,
                quantity: route.quantity,
                commodities: remainingCommodities,
                maxAmount: maxAmount,
                currentTime: currentTime
            )
            
            // 更新剩余资源和接收记录
            updateCommoditiesAfterTransfer(
                type: type,
                transferredQuantity: transferredQuantity,
                remainingCommodities: &remainingCommodities,
                pinsReceivingCommodities: &pinsReceivingCommodities,
                destinationId: route.destinationId
            )
            
            // 如果所有资源都已路由，结束处理
            if remainingCommodities.isEmpty {
                done = true
                break
            }
        }
        
        // 处理接收到资源的设施
        for (receivingPinId, commoditiesAdded) in pinsReceivingCommodities {
            guard let receivingPin = colony.pins.first(where: { $0.id == receivingPinId }) else {
                continue
            }
            
            // 如果接收者是消费者，安排其运行
            if isConsumer(pin: receivingPin) {
                schedulePin(pin: receivingPin, currentTime: currentTime)
            }
            
            // 如果源不是存储设施但接收者是存储设施，继续路由输出
            if !isStorage(pin: sourcePin) && isStorage(pin: receivingPin) && !commoditiesAdded.isEmpty {
                routeCommodityOutput(colony: colony, sourcePin: receivingPin, commodities: commoditiesAdded, currentTime: currentTime)
            }
        }
    }
    
    /// 更新资源转移后的状态
    /// - Parameters:
    ///   - type: 资源类型
    ///   - transferredQuantity: 转移数量
    ///   - remainingCommodities: 剩余资源
    ///   - pinsReceivingCommodities: 接收记录
    ///   - destinationId: 目标设施ID
    private static func updateCommoditiesAfterTransfer(
        type: ItemType?,
        transferredQuantity: Int64,
        remainingCommodities: inout [ItemType: Int64],
        pinsReceivingCommodities: inout [Int64: [ItemType: Int64]],
        destinationId: Int64
    ) {
        guard let type = type, transferredQuantity > 0 else {
            return
        }
        
        // 更新剩余资源
        if let remaining = remainingCommodities[type] {
            let newRemaining = remaining - transferredQuantity
            if newRemaining <= 0 {
                remainingCommodities.removeValue(forKey: type)
            } else {
                remainingCommodities[type] = newRemaining
            }
        }
        
        // 更新接收记录
        if !pinsReceivingCommodities.keys.contains(destinationId) {
            pinsReceivingCommodities[destinationId] = [:]
        }
        
        pinsReceivingCommodities[destinationId]![type] = (pinsReceivingCommodities[destinationId]![type] ?? 0) + transferredQuantity
    }
    
    /// 获取排序后的路由
    /// - Parameters:
    ///   - colony: 殖民地
    ///   - pinId: 设施ID
    ///   - commodities: 资源
    /// - Returns: 处理器路由和存储路由的元组
    private static func getSortedRoutesForPin(colony: Colony, pinId: Int64, commodities: [ItemType: Int64]) -> ([(sortingKey: Double, destinationId: Int64, commodityType: ItemType, quantity: Int64)], [(sortingKey: Double, destinationId: Int64, commodityType: ItemType, quantity: Int64)]) {
        // 存储路由和处理器路由
        var processorRoutes: [(sortingKey: Double, destinationId: Int64, commodityType: ItemType, quantity: Int64)] = []
        var storageRoutes: [(sortingKey: Double, destinationId: Int64, commodityType: ItemType, quantity: Int64)] = []
        
        // 筛选和排序路由
        for route in colony.routes.filter({ $0.sourcePinId == pinId }) {
            // 如果路由的资源类型不在待处理资源中，跳过
            if !commodities.keys.contains(route.type) {
                continue
            }
            
            // 获取目标设施
            guard let destinationPin = colony.pins.first(where: { $0.id == route.destinationPinId }) else {
                continue
            }
            
            // 根据目标设施类型分类路由
            if let factory = destinationPin as? Pin.Factory {
                // 处理器路由，使用输入缓冲区状态作为排序键
                let inputBufferState = getInputBufferState(factory: factory)
                processorRoutes.append((sortingKey: inputBufferState, destinationId: route.destinationPinId, commodityType: route.type, quantity: route.quantity))
            } else if isStorage(pin: destinationPin) {
                // 存储路由，使用剩余空间作为排序键
                let freeSpace = getCapacityRemaining(pin: destinationPin)
                storageRoutes.append((sortingKey: freeSpace, destinationId: route.destinationPinId, commodityType: route.type, quantity: route.quantity))
            }
        }
        
        // 排序路由（按排序键升序，当排序键相同时按设施ID升序）
        processorRoutes.sort { route1, route2 in
            if route1.sortingKey == route2.sortingKey {
                return route1.destinationId < route2.destinationId
            }
            return route1.sortingKey < route2.sortingKey
        }
        
        storageRoutes.sort { route1, route2 in
            if route1.sortingKey == route2.sortingKey {
                return route1.destinationId < route2.destinationId
            }
            return route1.sortingKey < route2.sortingKey
        }
        
        return (processorRoutes, storageRoutes)
    }
    
    /// 转移资源
    /// - Parameters:
    ///   - sourcePin: 源设施
    ///   - destinationPin: 目标设施
    ///   - type: 资源类型
    ///   - quantity: 请求数量
    ///   - commodities: 可用资源
    ///   - maxAmount: 最大转移量
    ///   - currentTime: 当前模拟时间
    /// - Returns: 资源类型和转移数量的元组
    private static func transferCommodities(
        sourcePin: Pin,
        destinationPin: Pin,
        type: ItemType,
        quantity: Int64,
        commodities: [ItemType: Int64],
        maxAmount: Int64? = nil,
        currentTime: Date
    ) -> (ItemType?, Int64) {
        // 检查资源是否存在
        if !commodities.keys.contains(type) {
            return (nil, 0)
        }
        
        // 计算要转移的数量
        var amountToMove = min(commodities[type]!, quantity)
        if let maxAmount = maxAmount {
            amountToMove = min(maxAmount, amountToMove)
        }
        
        if amountToMove <= 0 {
            return (nil, 0)
        }
        
        // 计算目标设施可接受的数量
        let amountAccepted = canAccept(pin: destinationPin, type: type, quantity: amountToMove)
        if amountAccepted <= 0 {
            return (nil, 0)
        }
        
        // 从源设施移除资源
        if isStorage(pin: sourcePin) {
            let currentQuantity = sourcePin.contents[type] ?? 0
            sourcePin.contents[type] = currentQuantity - amountAccepted
            sourcePin.capacityUsed -= type.volume * Double(amountAccepted)
            
            // 如果数量为0，移除该键
            if sourcePin.contents[type] == 0 {
                sourcePin.contents.removeValue(forKey: type)
            }
        }
        
        // 向目标设施添加资源
        let destinationQuantity = destinationPin.contents[type] ?? 0
        destinationPin.contents[type] = destinationQuantity + amountAccepted
        destinationPin.capacityUsed += type.volume * Double(amountAccepted)
        
        // 如果目标是工厂，标记为已接收输入并记录缓冲区状态
        if let factory = destinationPin as? Pin.Factory {
            factory.hasReceivedInputs = true
            
            // 计算并记录缓冲区状态
            if let schematic = factory.schematic {
                var bufferStatus = ""
                var totalRatio: Double = 0.0
                var itemCount = 0
                
                for (inputType, requiredQuantity) in schematic.inputs {
                    let availableQuantity = factory.contents[inputType] ?? 0
                    let ratio = Double(availableQuantity) / Double(requiredQuantity)
                    totalRatio += ratio
                    itemCount += 1
                    
                    bufferStatus += "\(inputType.name): \(availableQuantity)/\(requiredQuantity) (\(Int(ratio * 100))%), "
                }
                
                // 移除最后的逗号和空格
                if !bufferStatus.isEmpty {
                    bufferStatus.removeLast(2)
                }
                
                // 计算总体缓冲区状态
                let overallBufferState = itemCount > 0 ? totalRatio / Double(itemCount) : 0.0
                
                // 格式化时间
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                let timeString = dateFormatter.string(from: currentTime)
                
                Logger.info("\(timeString): 工厂(\(factory.id)) 缓冲区状态: [\(bufferStatus)] 总体完成度: \(Int(overallBufferState * 100))%")
            }
        }
        
        return (type, amountAccepted)
    }
    
    /// 计算设施可接受的资源数量
    /// - Parameters:
    ///   - pin: 设施
    ///   - type: 资源类型
    ///   - quantity: 请求数量
    /// - Returns: 可接受的数量
    private static func canAccept(pin: Pin, type: ItemType, quantity: Int64) -> Int64 {
        if let factory = pin as? Pin.Factory {
            // 工厂只接受配方中需要的输入材料
            guard let schematic = factory.schematic else {
                return 0
            }
            
            // 检查资源是否在配方需求中
            guard let demandQuantity = schematic.inputs[type] else {
                return 0
            }
            
            // 计算还需要的数量
            let currentQuantity = factory.contents[type] ?? 0
            let remainingSpace = demandQuantity - currentQuantity
            
            if remainingSpace <= 0 {
                return 0
            }
            
            return min(quantity, remainingSpace)
        } else if isStorage(pin: pin) {
            // 存储设施根据容量接受资源
            let volume = type.volume
            let newVolume = volume * Double(quantity)
            let capacityRemaining = getCapacityRemaining(pin: pin)
            
            if newVolume > capacityRemaining {
                return Int64(capacityRemaining / volume)
            } else {
                return quantity
            }
        }
        
        // 提取器不接受资源
        return 0
    }
    
    /// 更新设施状态
    /// - Parameter colony: 殖民地
    private static func updatePinStatuses(colony: Colony) {
        for pin in colony.pins {
            pin.status = getPinStatus(pin: pin, now: colony.currentSimTime, routes: colony.routes)
        }
    }
    
    // MARK: - 辅助方法
    
    /// 获取设施容量
    /// - Parameter pin: 设施
    /// - Returns: 容量
    private static func getCapacity(for pin: Pin) -> Int? {
        switch pin {
        case is Pin.Extractor:
            return nil
        case is Pin.Factory:
            return nil
        case is Pin.Storage:
            return 12_000
        case is Pin.CommandCenter:
            return 500
        case is Pin.Launchpad:
            return 10_000
        default:
            return nil
        }
    }
    
    /// 打印殖民地模拟详细信息
    /// - Parameter colony: 模拟后的殖民地
    static func printColonySimulationDetails(colony: Colony) {
        Logger.info("========== 殖民地模拟概览 ==========")
        Logger.info("殖民地ID: \(colony.id)")
        
        // 格式化时间
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timeString = dateFormatter.string(from: colony.currentSimTime)
        
        Logger.info("当前模拟时间: \(timeString)")
        Logger.info("殖民地状态: \(colony.status)")
        
        // 记录最终产品详情
        if !colony.overview.finalProducts.isEmpty {
            Logger.info("最终产品:")
            for product in colony.overview.finalProducts {
                Logger.info("- \(product.name) (ID: \(product.id))")
            }
        }
        
        // 记录仓储内容
        Logger.info("========== 仓储内容 ==========")
        for pin in colony.pins {
            if pin is Pin.Storage || pin is Pin.CommandCenter || pin is Pin.Launchpad {
                Logger.info("\(getPinTypeName(pin: pin))(\(pin.id)) 内容:")
                if pin.contents.isEmpty {
                    Logger.info("- 空")
                } else {
                    for (type, quantity) in pin.contents {
                        Logger.info("- \(type.name)x\(quantity) (体积: \(type.volume * Double(quantity)))")
                    }
                }
                
                // 显示容量使用情况
                if let capacity = getCapacity(for: pin) {
                    let usedPercentage = Int((pin.capacityUsed / Double(capacity)) * 100)
                    Logger.info("容量使用: \(Int(pin.capacityUsed))/\(capacity) (\(usedPercentage)%)")
                }
                Logger.info("----------------------------")
            }
        }
        
        // 记录工厂缓冲区状态
        Logger.info("========== 工厂缓冲区状态 ==========")
        for pin in colony.pins {
            if let factory = pin as? Pin.Factory {
                Logger.info("工厂(\(factory.id)) 缓冲区状态:")
                
                if let schematic = factory.schematic {
                    Logger.info("配方: \(schematic.id) (输出: \(schematic.outputType.name)x\(schematic.outputQuantity))")
                    
                    // 显示输入缓冲区状态
                    if schematic.inputs.isEmpty {
                        Logger.info("- 无需输入材料")
                    } else {
                        for (inputType, requiredQuantity) in schematic.inputs {
                            let availableQuantity = factory.contents[inputType] ?? 0
                            let ratio = Double(availableQuantity) / Double(requiredQuantity)
                            Logger.info("- \(inputType.name): \(availableQuantity)/\(requiredQuantity) (\(Int(ratio * 100))%)")
                        }
                    }
                    
                    // 显示生产状态
                    if let lastCycleStartTime = factory.lastCycleStartTime {
                        // 如果有lastCycleStartTime，说明工厂正在生产周期中
                        let cycleEndTime = lastCycleStartTime.addingTimeInterval(schematic.cycleTime)
                        let remainingTime = cycleEndTime.timeIntervalSince(colony.currentSimTime)
                        if remainingTime > 0 {
                            Logger.info("生产状态: 正在生产，剩余时间 \(Int(remainingTime)) 秒")
                        } else {
                            Logger.info("生产状态: 已完成生产周期")
                        }
                    } else if factory.isActive {
                        // 没有lastCycleStartTime但isActive为true，表示工厂有足够材料但尚未开始生产
                        Logger.info("生产状态: 活跃但未开始生产")
                    } else {
                        // 既没有lastCycleStartTime，isActive也为false，表示工厂缺少材料
                        Logger.info("生产状态: 等待材料")
                    }
                } else {
                    Logger.info("- 未配置配方")
                }
                Logger.info("----------------------------")
            }
        }
        
        Logger.info("========== 模拟概览结束 ==========")
    }
    
    /// 获取设施类型名称
    /// - Parameter pin: 设施
    /// - Returns: 设施类型名称
    private static func getPinTypeName(pin: Pin) -> String {
        switch pin {
        case is Pin.Extractor:
            return "提取器"
        case is Pin.Factory:
            return "工厂"
        case is Pin.Storage:
            return "存储设施"
        case is Pin.CommandCenter:
            return "指挥中心"
        case is Pin.Launchpad:
            return "发射台"
        default:
            return "未知设施"
        }
    }
    
    /// 从仓储设施重新填充工厂缓冲区
    /// - Parameters:
    ///   - factory: 工厂
    ///   - time: 当前时间
    private static func refillFactoryBuffer(factory: Pin.Factory, time: Date) {
        guard let colony = self.colony, let schematic = factory.schematic else {
            return
        }
        
        // 格式化时间
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timeString = dateFormatter.string(from: time)
        
        Logger.info("\(timeString): 尝试为工厂(\(factory.id))重新填充缓冲区")
        
        // 获取所有指向该工厂的路由
        let incomingRoutes = colony.routes.filter { $0.destinationPinId == factory.id }
        if incomingRoutes.isEmpty {
            Logger.info("\(timeString): 工厂(\(factory.id))没有输入路由，无法填充缓冲区")
            return
        }
        
        // 检查每个输入材料是否需要补充
        for (inputType, requiredQuantity) in schematic.inputs {
            let currentQuantity = factory.contents[inputType] ?? 0
            let neededQuantity = requiredQuantity - currentQuantity
            
            if neededQuantity <= 0 {
                continue // 该材料已经足够
            }
            
            // 查找可以提供该材料的仓储设施和路由
            let relevantRoutes = incomingRoutes.filter { $0.type.id == inputType.id }
            for route in relevantRoutes {
                // 查找源设施
                guard let sourcePin = colony.pins.first(where: { $0.id == route.sourcePinId }),
                      isStorage(pin: sourcePin) else {
                    continue
                }
                
                // 检查源设施是否有该材料
                let availableQuantity = sourcePin.contents[inputType] ?? 0
                if availableQuantity <= 0 {
                    continue
                }
                
                // 计算可以转移的数量
                let transferQuantity = min(neededQuantity, availableQuantity, route.quantity)
                if transferQuantity <= 0 {
                    continue
                }
                
                // 执行转移
                let (_, transferredQuantity) = transferCommodities(
                    sourcePin: sourcePin,
                    destinationPin: factory,
                    type: inputType,
                    quantity: transferQuantity,
                    commodities: sourcePin.contents,
                    currentTime: time
                )
                
                if transferredQuantity > 0 {
                    Logger.info("\(timeString): 从\(getPinTypeName(pin: sourcePin))(\(sourcePin.id))转移 [\(inputType.name)x\(transferredQuantity)] 到工厂(\(factory.id))")
                    
                    // 更新工厂的输入状态
                    factory.hasReceivedInputs = true
                    
                    // 如果已经满足需求，跳出循环
                    if transferredQuantity >= neededQuantity {
                        break
                    }
                }
            }
        }
        
        // 记录填充后的缓冲区状态
        var bufferStatus = ""
        for (inputType, requiredQuantity) in schematic.inputs {
            let availableQuantity = factory.contents[inputType] ?? 0
            let ratio = Double(availableQuantity) / Double(requiredQuantity)
            bufferStatus += "\(inputType.name): \(availableQuantity)/\(requiredQuantity) (\(Int(ratio * 100))%), "
        }
        
        // 移除最后的逗号和空格
        if !bufferStatus.isEmpty {
            bufferStatus.removeLast(2)
            Logger.info("\(timeString): 工厂(\(factory.id)) 填充后缓冲区状态: [\(bufferStatus)]")
        }
        
        // 如果工厂已经有足够的材料可以开始下一个周期，重新安排它
        if hasEnoughInputs(factory: factory) {
            Logger.info("\(timeString): 工厂(\(factory.id)) 已有足够材料，安排下一次运行")
            schedulePin(pin: factory, currentTime: time)
        }
    }
}

// MARK: - 模拟缓存管理

/// 行星模拟管理器
class ColonySimulationManager {
    /// 单例实例
    static let shared = ColonySimulationManager()
    
    /// 模拟缓存
    private var simulationCache: [String: Colony] = [:]
    
    /// 私有初始化方法
    private init() {}
    
    /// 模拟殖民地
    /// - Parameters:
    ///   - colony: 殖民地
    ///   - targetTime: 目标时间
    /// - Returns: 模拟后的殖民地
    func simulateColony(colony: Colony, targetTime: Date) -> Colony {
        let cacheKey = "\(colony.id)_\(targetTime.timeIntervalSince1970)"
        
        // 检查缓存
        if let cachedColony = simulationCache[cacheKey] {
            return cachedColony
        }
        
        // 执行模拟
        let simulatedColony = ColonySimulation.simulate(colony: colony, targetTime: targetTime)
        
        // 缓存结果
        simulationCache[cacheKey] = simulatedColony
        
        return simulatedColony
    }
    
    /// 模拟殖民地到未来时间
    /// - Parameters:
    ///   - colony: 殖民地
    ///   - hours: 小时数
    /// - Returns: 模拟后的殖民地
    func simulateColonyForward(colony: Colony, hours: Int) -> Colony {
        let targetTime = colony.currentSimTime.addingTimeInterval(TimeInterval(hours * 3600))
        return simulateColony(colony: colony, targetTime: targetTime)
    }
    
    /// 清除缓存
    func clearCache() {
        simulationCache.removeAll()
    }
    
    /// 清除特定殖民地的缓存
    /// - Parameter colonyId: 殖民地ID
    func clearCache(colonyId: String) {
        let keysToRemove = simulationCache.keys.filter { $0.starts(with: "\(colonyId)_") }
        for key in keysToRemove {
            simulationCache.removeValue(forKey: key)
        }
    }
    
    /// 获取殖民地的下一个关键时间点
    /// - Parameter colony: 殖民地
    /// - Returns: 下一个关键时间点
    func getNextKeyTime(colony: Colony) -> Date? {
        return ColonySimulation.getNextKeyTime(colony: colony)
    }
    
    /// 模拟殖民地到下一个关键时间点
    /// - Parameter colony: 殖民地
    /// - Returns: 模拟后的殖民地和是否有更多关键时间点
    func simulateColonyToNextKeyTime(colony: Colony) -> (Colony, Bool) {
        return ColonySimulation.simulateColonyToNextKeyTime(colony: colony)
    }
} 
