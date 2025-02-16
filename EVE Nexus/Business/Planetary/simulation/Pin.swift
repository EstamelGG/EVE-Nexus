import Foundation

/// 设施
class Pin {
    // MARK: - Properties
    
    /// 设施ID
    let id: Int64
    
    /// 设施类型
    let type: CommodityType
    
    /// 设施标识符
    let designator: String
    
    /// 上次运行时间
    var lastRunTime: Date?
    
    /// 存储的资源
    var contents: [CommodityType: Int64]
    
    /// 已使用容量
    var capacityUsed: Float
    
    /// 是否激活
    var isActive: Bool
    
    /// 纬度
    let latitude: Float
    
    /// 经度
    let longitude: Float
    
    /// 状态
    var status: PinStatus
    
    // MARK: - Initialization
    
    init(id: Int64, type: CommodityType, designator: String, lastRunTime: Date? = nil, contents: [CommodityType: Int64] = [:], capacityUsed: Float = 0, isActive: Bool = false, latitude: Float, longitude: Float, status: PinStatus) {
        self.id = id
        self.type = type
        self.designator = designator
        self.lastRunTime = lastRunTime
        self.contents = contents
        self.capacityUsed = capacityUsed
        self.isActive = isActive
        self.latitude = latitude
        self.longitude = longitude
        self.status = status
    }
    
    /// 检查设施的路由状态
    /// - Parameter routes: 路由列表
    /// - Returns: 路由状态
    func checkRoutedState(routes: [Route]) -> RoutedState {
        let incomingRoutes = routes.filter { $0.destinationPinId == id }
        let outgoingRoutes = routes.filter { $0.sourcePinId == id }
        
        // 检查输入路由
        let isInputRouted: Bool
        if let factory = self as? FactoryPin {
            if let schematic = factory.schematic {
                let inputTypes = schematic.inputs.map { $0.key.id }
                let inputTypesReceived = Set(incomingRoutes.map { $0.type.id })
                isInputRouted = inputTypes.allSatisfy { inputTypesReceived.contains($0) }
            } else {
                isInputRouted = true
            }
        } else {
            isInputRouted = true
        }
        
        // 检查输出路由
        let isOutputRouted: Bool
        if self is FactoryPin || self is ExtractorPin {
            isOutputRouted = !outgoingRoutes.isEmpty
        } else {
            isOutputRouted = true
        }
        
        if !isInputRouted { return .inputNotRouted }
        if !isOutputRouted { return .outputNotRouted }
        return .routed
    }
    
    /// 获取下一次运行时间
    /// - Returns: 下一次运行时间，如果返回 nil 表示应该立即运行
    func getNextRunTime() -> Date? {
        // 对于工厂，如果未激活但有足够的输入材料，应该立即运行
        if let factory = self as? FactoryPin {
            if !factory.isActive && factory.hasEnoughInputs() {
                return nil
            }
        }
        
        // 其他情况，返回 lastRunTime + cycleTime
        guard let lastRunTime = lastRunTime else { return nil }
        return lastRunTime.addingTimeInterval(getCycleTime())
    }
    
    /// 获取循环时间
    /// - Returns: 循环时间（秒）
    private func getCycleTime() -> TimeInterval {
        switch self {
        case let extractor as ExtractorPin:
            return extractor.cycleTime ?? 0
            
        case let factory as FactoryPin:
            return factory.schematic?.cycleTime ?? 0
            
        case is StoragePin, is CommandCenterPin, is LaunchpadPin:
            return 0
            
        default:
            return 0  // 其他未知类型的设施也返回 0
        }
    }
    
    /// 检查设施是否可以运行
    /// - Parameter runTime: 运行时间
    /// - Returns: 是否可以运行
    func canRun(_ runTime: Date) -> Bool {
        switch self {
        case let extractor as ExtractorPin:
            // 检查是否过期
            if let expiryTime = extractor.expiryTime,
               expiryTime <= runTime {
                return false
            }
            // 采集器需要可以激活且下一次运行时间不晚于指定时间
            if !canActivate() { return false }
            let nextRunTime = getNextRunTime()
            return nextRunTime == nil || nextRunTime! <= runTime
            
        case _ as FactoryPin:
            // 如果工厂没有配方，则不能运行
            if let factory = self as? FactoryPin, factory.schematic == nil {
                return false
            }
            // 工厂需要处于激活状态或可以激活，且下一次运行时间不晚于指定时间
            if !isActive && !canActivate() { return false }
            let nextRunTime = getNextRunTime()
            return nextRunTime == nil || nextRunTime! <= runTime
            
        case is StoragePin, is CommandCenterPin, is LaunchpadPin:
            // 存储设施、指挥中心和发射台不需要运行
            return false
            
        default:
            return false
        }
    }
    
    /// 检查设施是否可以激活
    /// - Returns: 是否可以激活
    func canActivate() -> Bool {
        switch self {
        case let extractor as ExtractorPin:
            // 提取器需要有产品类型
            return extractor.productType != nil
            
        case let factory as FactoryPin:
            // 工厂需要有配方
            if factory.schematic == nil { return false }
            
            // 如果当前正在生产周期中，保持激活状态
            if let lastRunTime = factory.lastRunTime,
               let cycleTime = factory.schematic?.cycleTime {
                let nextRunTime = lastRunTime.addingTimeInterval(cycleTime)
                if Date() < nextRunTime {
                    return true  // 在生产周期内保持激活状态
                }
            }
            
            // 生产周期结束后，只有在缓冲区满时才激活
            return factory.hasEnoughInputs()  // 检查是否所有需要的材料都达到配方要求量
            
        case is StoragePin, is CommandCenterPin, is LaunchpadPin:
            // 存储设施、指挥中心和发射台总是处于激活状态
            return true
            
        default:
            return false
        }
    }
    
    /// 检查设施是否处于激活状态
    /// - Returns: 是否处于激活状态
    func isActivated() -> Bool {
        switch self {
        case let extractor as ExtractorPin:
            // 提取器需要有产品类型且处于激活状态
            return extractor.productType != nil && isActive
            
        case _ as FactoryPin:
            // 工厂直接返回激活状态
            return isActive
            
        case is StoragePin, is CommandCenterPin, is LaunchpadPin:
            // 其他类型的设施直接返回激活状态
            return isActive
            
        default:
            return isActive
        }
    }
    
    /// 检查设施是否是消费者
    /// - Returns: 是否是消费者
    func isConsumer() -> Bool {
        // 只有设置了配方的工厂才是消费者
        if let factory = self as? FactoryPin {
            return factory.schematic != nil
        }
        return false
    }
    
    /// 运行设施并获取生产的资源
    /// - Parameter runTime: 运行时间
    /// - Returns: 生产的资源及其数量
    func run(_ runTime: Date) -> [CommodityType: Int64] {
        switch self {
        case let extractor as ExtractorPin:
            // 更新运行时间
            lastRunTime = runTime
            
            // 检查是否有产品类型
            guard let productType = extractor.productType else {
                return [:]
            }
            
            var products: [CommodityType: Int64] = [:]
            
            // 如果处于激活状态，计算产量
            if isActive {
                if let baseValue = extractor.baseValue,
                   let installTime = extractor.installTime,
                   let cycleTime = extractor.cycleTime {
                    // 计算产量
                    let output = ExtractionSimulation.getProgramOutput(baseValue: baseValue,
                                                                     startTime: installTime,
                                                                     currentTime: runTime,
                                                                     cycleTime: cycleTime)
                    products[productType] = output
                    
                    // 将产出的资源添加到存储中
                    let currentQuantity = contents[productType] ?? 0
                    contents[productType] = currentQuantity + output
                    capacityUsed += Float(productType.volume) * Float(output)
                }
                
                // 检查是否过期
                if let expiryTime = extractor.expiryTime,
                   expiryTime <= runTime {
                    isActive = false
                }
            }
            
            return products
            
        case let factory as FactoryPin:
            // 如果没有配方，设置为非激活状态并返回空字典
            if factory.schematic == nil {
                isActive = false
                lastRunTime = runTime
                return [:]
            }
            
            var products: [CommodityType: Int64] = [:]
            
            // 检查是否可以激活
            Logger.debug("工厂 \(id) 运行检查:")
            Logger.debug("- 当前激活状态: \(isActive)")
            Logger.debug("- 是否有配方: \(factory.schematic != nil)")
            
            // 检查是否在生产周期内
            if let lastRunTime = factory.lastRunTime,
               let schematic = factory.schematic {
                let nextRunTime = lastRunTime.addingTimeInterval(schematic.cycleTime)
                
                // 如果当前时间小于下一次运行时间，说明还在生产周期内
                if runTime < nextRunTime {
                    Logger.debug("- 正在生产周期内，继续生产")
                    return [:]  // 返回空字典，因为还在生产中
                }
            }
            
            // 到这里说明已经不在生产周期内了
            if let schematic = factory.schematic {
                // 检查缓冲区是否满足生产需求
                var hasEnoughInputs = true
                for (demandType, demandQuantity) in schematic.inputs {
                    if let availableQuantity = contents[demandType] {
                        if availableQuantity < demandQuantity {
                            hasEnoughInputs = false
                            break
                        }
                    } else {
                        hasEnoughInputs = false
                        break
                    }
                }
                
                if hasEnoughInputs {
                    Logger.debug("- 缓冲区满足生产需求，开始新的生产周期")
                    // 消耗输入材料
                    for (demandType, demandQuantity) in schematic.inputs {
                        let _ = removeCommodity(type: demandType, quantity: demandQuantity)
                    }
                    
                    // 添加产出
                    products[schematic.outputType] = schematic.outputQuantity
                    
                    // 将产出的资源添加到工厂存储中
                    let currentQuantity = contents[schematic.outputType] ?? 0
                    contents[schematic.outputType] = currentQuantity + schematic.outputQuantity
                    capacityUsed += Float(schematic.outputType.volume) * Float(schematic.outputQuantity)
                    
                    // 更新状态
                    isActive = true
                    factory.lastCycleStartTime = runTime
                } else {
                    Logger.debug("- 缓冲区材料不足，等待材料")
                    isActive = false
                }
            }
            
            // 更新运行时间和输入状态
            lastRunTime = runTime
            factory.receivedInputsLastCycle = factory.hasReceivedInputs
            factory.hasReceivedInputs = false
            
            return products
            
        case is StoragePin, is CommandCenterPin, is LaunchpadPin:
            // 存储设施不生产资源
            lastRunTime = runTime
            if isActive {
                isActive = false
            }
            return [:]
            
        default:
            return [:]
        }
    }
    
    /// 重新计算已使用的容量
    private func recalculateCapacityUsed() {
        capacityUsed = 0
        for (type, quantity) in contents {
            capacityUsed += Float(type.volume) * Float(quantity)
        }
    }
    
    /// 添加资源
    /// - Parameters:
    ///   - type: 资源类型
    ///   - quantity: 数量
    /// - Returns: 实际添加的数量
    func addCommodity(type: CommodityType, quantity: Int64) -> Int64 {
//        Logger.debug("\n--- 添加资源开始 ---")
//        Logger.debug("设施类型: \(String(describing: self).split(separator: " ")[0])")
//        Logger.debug("设施ID: \(id)")
//        Logger.debug("资源类型: \(type.id)")
//        Logger.debug("请求数量: \(quantity)")
//        Logger.debug("当前库存: \(contents)")
//        Logger.debug("当前已用容量: \(capacityUsed)")
        
        // 重新计算当前容量
        recalculateCapacityUsed()
//        Logger.debug("重新计算后的当前容量: \(capacityUsed)")
        
        switch self {
        case is ExtractorPin:
//            Logger.debug("采集器不能接受资源")
//            Logger.debug("--- 添加资源结束 ---\n")
            return 0
            
        case let factory as FactoryPin:
            Logger.debug("工厂检查:")
            // 工厂只能接受配方中需要的资源，且不超过需求量
            guard let schematic = factory.schematic else {
//                Logger.debug("- 工厂未设置配方")
//                Logger.debug("--- 添加资源结束 ---\n")
                return 0
            }
            guard let demandQuantity = schematic.inputs[type] else {
//                Logger.debug("- 工厂不需要该类型资源")
//                Logger.debug("- 需要的资源类型:")
                for (inputType, _) in schematic.inputs {
                    Logger.debug("  - \(inputType.id)")
                }
//                Logger.debug("--- 添加资源结束 ---\n")
                return 0
            }
            
            // 计算还需要多少资源
            let currentQuantity = contents[type] ?? 0
            let remainingSpace = demandQuantity - currentQuantity
//            Logger.debug("- 配方需求量: \(demandQuantity)")
//            Logger.debug("- 当前存储量: \(currentQuantity)")
//            Logger.debug("- 剩余可接收: \(remainingSpace)")
            
            if remainingSpace <= 0 {
//                Logger.debug("- 工厂已有足够的该类型资源")
//                Logger.debug("--- 添加资源结束 ---\n")
                return 0
            }
            
            // 添加资源
            let quantityToAdd = min(quantity, remainingSpace)
            contents[type] = currentQuantity + quantityToAdd
            capacityUsed += Float(type.volume) * Float(quantityToAdd)
            
            // 标记已收到输入
            factory.hasReceivedInputs = true
            
//            Logger.debug("- 实际添加: \(quantityToAdd)")
//            Logger.debug("- 更新后存储量: \(contents[type] ?? 0)")
//            Logger.debug("- 更新后已用容量: \(capacityUsed)")
//            Logger.debug("--- 添加资源结束 ---\n")
            return quantityToAdd
            
        case is StoragePin, is CommandCenterPin, is LaunchpadPin:
            // 存储设施可以接受任何资源，但受容量限制
            let volume = Float(type.volume)
            let newVolume = volume * Float(quantity)
            
            // 计算剩余容量
            let capacity: Float
            switch self {
            case is StoragePin:
                capacity = Float(PinCapacity.storage)
            case is LaunchpadPin:
                capacity = Float(PinCapacity.launchpad)
            case is CommandCenterPin:
                capacity = Float(PinCapacity.commandCenter)
            default:
                capacity = 0
            }
            let capacityRemaining = capacity - capacityUsed
            
//            Logger.debug("- 容量检查:")
//            Logger.debug("  - 总容量: \(capacity)")
//            Logger.debug("  - 已用容量: \(capacityUsed)")
//            Logger.debug("  - 剩余容量: \(capacityRemaining)")
//            Logger.debug("  - 需要容量: \(newVolume)")
            
            // 计算可以添加的数量
            let quantityToAdd: Int64
            if newVolume > capacityRemaining {
                quantityToAdd = Int64(capacityRemaining / volume)
            } else {
                quantityToAdd = quantity
            }
            
            if quantityToAdd <= 0 {
//                Logger.debug("- 无法添加资源：空间不足")
//                Logger.debug("--- 添加资源结束 ---\n")
                return 0
            }
            
            // 添加资源
            let currentQuantity = contents[type] ?? 0
            contents[type] = currentQuantity + quantityToAdd
            capacityUsed += volume * Float(quantityToAdd)
            
            // 重新计算以确保准确性
            recalculateCapacityUsed()
            
//            Logger.debug("- 实际添加: \(quantityToAdd)")
//            Logger.debug("- 更新后存储量: \(contents[type] ?? 0)")
//            Logger.debug("- 更新后已用容量: \(capacityUsed)")
//            Logger.debug("- 更新后总库存: \(contents)")
//            Logger.debug("--- 添加资源结束 ---\n")
            return quantityToAdd
            
        default:
            return 0
        }
    }
    
    /// 移除资源
    /// - Parameters:
    ///   - type: 资源类型
    ///   - quantity: 数量
    /// - Returns: 实际移除的数量
    func removeCommodity(type: CommodityType, quantity: Int64) -> Int64 {
        // 检查是否有该类型的资源
        guard let availableQuantity = contents[type] else {
            return 0
        }
        
        let quantityRemoved: Int64
        if availableQuantity <= quantity {
            // 如果现有数量小于等于要移除的数量，移除全部
            quantityRemoved = availableQuantity
            contents.removeValue(forKey: type)
        } else {
            // 否则移除指定数量
            quantityRemoved = quantity
            contents[type] = availableQuantity - quantityRemoved
        }
        
        // 更新已使用容量
        recalculateCapacityUsed()
        
        return quantityRemoved
    }
}

/// 采集器
class ExtractorPin: Pin {
    /// 过期时间
    let expiryTime: Date?
    
    /// 安装时间
    let installTime: Date?
    
    /// 周期时间
    let cycleTime: TimeInterval?
    
    /// 产品类型
    let productType: CommodityType?
    
    /// 基础产量
    let baseValue: Int?
    
    init(id: Int64, type: CommodityType, designator: String, lastRunTime: Date? = nil, contents: [CommodityType: Int64] = [:], capacityUsed: Float = 0, isActive: Bool = false, latitude: Float, longitude: Float, status: PinStatus, expiryTime: Date? = nil, installTime: Date? = nil, cycleTime: TimeInterval? = nil, productType: CommodityType? = nil, baseValue: Int? = nil) {
        self.expiryTime = expiryTime
        self.installTime = installTime
        self.cycleTime = cycleTime
        self.productType = productType
        self.baseValue = baseValue
        super.init(id: id, type: type, designator: designator, lastRunTime: lastRunTime, contents: contents, capacityUsed: capacityUsed, isActive: isActive, latitude: latitude, longitude: longitude, status: status)
    }
}

/// 工厂
class FactoryPin: Pin {
    /// 配方
    var schematic: Schematic?
    
    /// 是否收到输入
    var hasReceivedInputs: Bool
    
    /// 上个周期是否收到输入
    var receivedInputsLastCycle: Bool
    
    /// 上次生产周期开始时间
    var lastCycleStartTime: Date?
    
    init(id: Int64, type: CommodityType, designator: String, lastRunTime: Date? = nil, contents: [CommodityType: Int64] = [:], capacityUsed: Float = 0, isActive: Bool = false, latitude: Float, longitude: Float, status: PinStatus, schematic: Schematic? = nil, hasReceivedInputs: Bool = false, receivedInputsLastCycle: Bool = false, lastCycleStartTime: Date? = nil) {
        self.schematic = schematic
        self.hasReceivedInputs = hasReceivedInputs
        self.receivedInputsLastCycle = receivedInputsLastCycle
        self.lastCycleStartTime = lastCycleStartTime
        super.init(id: id, type: type, designator: designator, lastRunTime: lastRunTime, contents: contents, capacityUsed: capacityUsed, isActive: isActive, latitude: latitude, longitude: longitude, status: status)
    }
    
    /// 检查是否有足够的输入材料
    /// - Returns: 是否有足够的输入材料
    func hasEnoughInputs() -> Bool {
        guard let schematic = schematic else { return false }
        
        // 检查每种输入材料是否足够
        for (inputType, requiredQuantity) in schematic.inputs {
            guard let availableQuantity = contents[inputType] else {
                return false
            }
            if availableQuantity < requiredQuantity {
                return false
            }
        }
        
        return true
    }
}

/// 存储设施
class StoragePin: Pin {
    // 删除 capacity 属性
}

/// 发射台
class LaunchpadPin: Pin {
    // 删除 capacity 属性
}

/// 指挥中心
class CommandCenterPin: Pin {
    /// 等级
    let level: Int
    
    init(id: Int64, type: CommodityType, designator: String, lastRunTime: Date? = nil, contents: [CommodityType: Int64] = [:], capacityUsed: Float = 0, isActive: Bool = false, latitude: Float, longitude: Float, status: PinStatus, level: Int) {
        self.level = level
        super.init(id: id, type: type, designator: designator, lastRunTime: lastRunTime, contents: contents, capacityUsed: capacityUsed, isActive: isActive, latitude: latitude, longitude: longitude, status: status)
    }
    // 删除 capacity 属性
}

/// 采集头
struct ExtractorHead {
    /// 纬度
    let latitude: Float
    
    /// 经度
    let longitude: Float
}

/// 设施类型
enum PinType {
    /// 采集器
    case extractor(ExtractorInfo)
    /// 工厂
    case factory(FactoryInfo)
    /// 存储设施
    case storage
    /// 指挥中心
    case commandCenter
    /// 发射台
    case launchpad
}

/// 采集器信息
struct ExtractorInfo {
    /// 产品类型
    var productType: CommodityType?
    /// 周期时间
    var cycleTime: TimeInterval?
    /// 过期时间
    var expiryTime: Date?
    /// 安装时间
    var installTime: Date?
    /// 基础产量
    var baseValue: Float?
    /// 是否激活
    var isActive: Bool
}

/// 工厂信息
class FactoryInfo {
    /// 配方
    var schematic: Schematic?
    /// 需求资源
    var demands: [CommodityType: Int64]
    /// 上次生产周期开始时间
    var lastCycleStartTime: Date?
    /// 是否收到输入
    var hasReceivedInputs: Bool
    /// 上个周期是否收到输入
    var receivedInputsLastCycle: Bool
    
    init() {
        self.demands = [:]
        self.hasReceivedInputs = false
        self.receivedInputsLastCycle = false
    }
}

/// 配方
struct Schematic {
    /// 配方ID
    let id: Int64
    /// 输出类型
    let outputType: CommodityType
    /// 输出数量
    let outputQuantity: Int64
    /// 周期时间
    let cycleTime: TimeInterval
    /// 输入资源
    let inputs: [CommodityType: Int64]
}

/// 设施容量常量（立方米）
enum PinCapacity {
    /// 存储设施容量：12,000 m³
    static let storage = 12_000
    /// 发射台容量：10,000 m³
    static let launchpad = 10_000
    /// 指挥中心容量：500 m³
    static let commandCenter = 500
}
