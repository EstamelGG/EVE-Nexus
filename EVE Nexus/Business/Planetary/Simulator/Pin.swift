import Foundation

class Pin {
    let id: Int64
    let type: PinType
    let schematicId: Int64?
    let cycleTime: TimeInterval
    let lastRunTime: Date?
    var contents: PinContents
    var status: PinStatus = .idle
    
    // 添加提取器特有的属性
    var extractorHeadCount: Int = 0
    
    init(
        id: Int64,
        type: PinType,
        schematicId: Int64? = nil,
        cycleTime: TimeInterval,
        lastRunTime: Date? = nil,
        contents: PinContents,
        extractorHeadCount: Int = 0
    ) {
        self.id = id
        self.type = type
        self.schematicId = schematicId
        self.cycleTime = cycleTime
        self.lastRunTime = lastRunTime
        self.contents = contents
        self.extractorHeadCount = extractorHeadCount
    }
    
    /// 克隆设施
    func clone() -> Pin {
        return Pin(
            id: id,
            type: type,
            schematicId: schematicId,
            cycleTime: cycleTime,
            lastRunTime: lastRunTime,
            contents: PinContents(
                commodities: contents.commodities,
                capacity: contents.capacity
            ),
            extractorHeadCount: extractorHeadCount
        )
    }
    
    /// 判断设施是否为存储设施
    func isStorage() -> Bool {
        return type == .storage || type == .launchpad
    }
    
    /// 判断设施是否为消费者
    func isConsumer() -> Bool {
        return type == .processor
    }
    
    /// 判断设施是否处于活动状态
    func isActive() -> Bool {
        return status == .active
    }
    
    /// 判断设施是否可以激活
    func canActivate() -> Bool {
        return type == .extractor || type == .processor
    }
    
    /// 判断设施是否可以运行
    func canRun(until endTime: Date) -> Bool {
        guard let nextRunTime = getNextRunTime() else { return false }
        return nextRunTime <= endTime
    }
    
    /// 获取下一次运行时间
    func getNextRunTime() -> Date? {
        guard let lastRun = lastRunTime else { return Date() }
        return lastRun.addingTimeInterval(cycleTime)
    }
    
    /// 获取设施状态
    func getStatus(at time: Date, routes: [Route]) -> PinStatus {
        switch type {
        case .extractor:
            return .active
            
        case .processor:
            // 检查输入是否充足
            let inputRoutes = routes.filter { $0.destinationPinId == id }
            let hasInput = inputRoutes.contains { route in
                guard let sourcePin = colony?.pins.first(where: { $0.id == route.sourcePinId }) else { return false }
                return sourcePin.contents.commodities[route.commodityType.id, default: 0] >= route.quantity
            }
            if !hasInput {
                return .inputMissing
            }
            
            // 检查输出存储是否已满
            let outputRoutes = routes.filter { $0.sourcePinId == id }
            let hasOutputSpace = outputRoutes.contains { route in
                guard let destinationPin = colony?.pins.first(where: { $0.id == route.destinationPinId }) else { return false }
                return destinationPin.contents.hasSpaceFor(typeId: route.commodityType.id, amount: route.quantity)
            }
            if !hasOutputSpace {
                return .outputFull
            }
            
            return .active
            
        case .storage, .launchpad, .commandCenter:
            return contents.availableVolume > 0 ? .idle : .storageFull
        }
    }
    
    /// 运行设施
    func run(at time: Date) -> [Int64: Int64] {
        switch type {
        case .extractor:
            // 使用ExtractionSimulator计算产出
            guard let baseValue = schematicId else { return [:] }
            let output = ExtractionSimulator.getProgramOutput(
                baseValue: Int(baseValue),
                startTime: lastRunTime ?? time,
                currentTime: time,
                cycleTime: cycleTime
            )
            return [baseValue: output]
            
        case .processor:
            // 获取图纸信息
            guard let schematicId = schematicId,
                  let schematic = PlanetarySchematic.fetch(schematicId: schematicId) else {
                return [:]
            }
            
            // 检查是否有足够的输入材料
            for input in schematic.inputs {
                let available = contents.commodities[input.typeId, default: 0]
                if available < input.value {
                    return [:]  // 输入材料不足
                }
            }
            
            // 检查是否有足够的存储空间
            if !contents.hasSpaceFor(typeId: schematic.outputTypeId, amount: Int64(schematic.outputValue)) {
                return [:]  // 存储空间不足
            }
            
            // 消耗输入材料
            for input in schematic.inputs {
                _ = removeCommodity(typeId: input.typeId, amount: input.value)
            }
            
            // 返回产出
            return [schematic.outputTypeId: Int64(schematic.outputValue)]
            
        case .storage, .launchpad, .commandCenter:
            return [:]
        }
    }
    
    /// 添加商品
    @discardableResult
    func addCommodity(typeId: Int64, amount: Int64) -> Int64 {
        // 检查是否有足够的存储空间
        guard contents.hasSpaceFor(typeId: typeId, amount: amount) else {
            return 0
        }
        
        contents.commodities[typeId] = contents.commodities[typeId, default: 0] + amount
        return amount
    }
    
    /// 移除商品
    @discardableResult
    func removeCommodity(typeId: Int64, amount: Int64) -> Int64 {
        let currentAmount = contents.commodities[typeId, default: 0]
        let amountToRemove = min(amount, currentAmount)
        
        if amountToRemove <= 0 {
            return 0
        }
        
        let remainingAmount = currentAmount - amountToRemove
        if remainingAmount <= 0 {
            contents.commodities.removeValue(forKey: typeId)
        } else {
            contents.commodities[typeId] = remainingAmount
        }
        
        return amountToRemove
    }
    
    // 用于在Pin类中访问Colony实例的弱引用
    weak var colony: Colony?
} 