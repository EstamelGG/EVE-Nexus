import Foundation

/// 殖民地状态
enum ColonyStatus {
    /// 未设置
    case notSetup(pins: [Pin])
    /// 需要注意
    case needsAttention(pins: [Pin])
    /// 空闲
    case idle(pins: [Pin])
    /// 生产中
    case producing(pins: [Pin])
    /// 采集中
    case extracting(pins: [Pin])
    
    /// 排序顺序
    var order: Int {
        switch self {
        case .notSetup: return 1
        case .needsAttention: return 2
        case .idle: return 3
        case .producing: return 4
        case .extracting: return 5
        }
    }
    
    /// 是否正在工作
    var isWorking: Bool {
        switch self {
        case .notSetup, .needsAttention, .idle:
            return false
        case .producing, .extracting:
            return true
        }
    }
    
    /// 相关设施
    var pins: [Pin] {
        switch self {
        case .notSetup(let pins),
             .needsAttention(let pins),
             .idle(let pins),
             .producing(let pins),
             .extracting(let pins):
            return pins
        }
    }
    
    init(pins: [Pin]) {
        let notSetupPins = pins.filter { pin in
            switch pin.status {
            case .notSetup, .inputNotRouted, .outputNotRouted:
                return true
            default:
                return false
            }
        }
        if !notSetupPins.isEmpty {
            self = .notSetup(pins: notSetupPins)
            return
        }
        
        let needsAttentionPins = pins.filter { pin in
            switch pin.status {
            case .extractorExpired, .extractorInactive, .storageFull:
                return true
            default:
                return false
            }
        }
        if !needsAttentionPins.isEmpty {
            self = .needsAttention(pins: needsAttentionPins)
            return
        }
        
        let extractingPins = pins.filter { pin in
            if case .extracting = pin.status {
                return true
            }
            return false
        }
        if !extractingPins.isEmpty {
            self = .extracting(pins: extractingPins)
            return
        }
        
        let producingPins = pins.filter { pin in
            if case .producing = pin.status {
                return true
            }
            return false
        }
        if !producingPins.isEmpty {
            self = .producing(pins: producingPins)
            return
        }
        
        self = .idle(pins: [])
    }
}

/// 设施状态
enum PinStatus {
    /// 被动状态（指挥中心、发射台、存储设施的正常工作状态）
    case Static
    /// 采集中
    case extracting
    /// 生产中
    case producing
    /// 未设置
    case notSetup
    /// 输入未路由
    case inputNotRouted
    /// 输出未路由
    case outputNotRouted
    /// 采集器过期
    case extractorExpired
    /// 采集器未激活
    case extractorInactive
    /// 存储已满
    case storageFull
    /// 工厂空闲
    case factoryIdle
}

extension Pin {
    /// 获取设施状态
    func getStatus(now: Date, routes: [Route]) -> PinStatus {
        switch self {
        case let pin as ExtractorPin:
            // 检查是否设置
            let isSetup = pin.installTime != nil && pin.expiryTime != nil && pin.cycleTime != nil && pin.baseValue != nil && pin.productType != nil
            if !isSetup { return .notSetup }
            
            // 检查是否过期
            if let expiryTime = pin.expiryTime, expiryTime <= now {
                return .extractorExpired
            }
            
            // 检查路由状态
            switch checkRoutedState(routes: routes) {
            case .routed: break
            case .inputNotRouted: return .inputNotRouted
            case .outputNotRouted: return .outputNotRouted
            }
            
            // 检查激活状态
            return pin.isActive ? .extracting : .extractorInactive
            
        case let pin as FactoryPin:
            // 检查是否设置
            if pin.schematic == nil { return .notSetup }
            
            // 检查路由状态
            switch checkRoutedState(routes: routes) {
            case .routed: break
            case .inputNotRouted: return .inputNotRouted
            case .outputNotRouted: return .outputNotRouted
            }
            
            // 检查激活状态
            return pin.isActive ? .producing : .factoryIdle
            
        case is CommandCenterPin, is LaunchpadPin, is StoragePin:
            // 检查存储容量
            if let capacity = getCapacity(), capacity > 0 {
                let freeSpace = max(Float(capacity) - capacityUsed, 0)
                if freeSpace == 0 {
                    let hasIncomingRoutes = routes.contains { $0.destinationPinId == id }
                    if hasIncomingRoutes { return .storageFull }
                }
            }
            return .Static
            
        default:
            return .Static
        }
    }
    
    /// 获取路由状态
    func getRoutedState(routes: [Route]) -> RoutedState {
        let incomingRoutes = routes.filter { $0.destinationPinId == id }
        let outgoingRoutes = routes.filter { $0.sourcePinId == id }
        
        switch self {
        case is ExtractorPin:
            return outgoingRoutes.isEmpty ? .outputNotRouted : .routed
            
        case let pin as FactoryPin:
            if let schematic = pin.schematic {
                let hasAllInputs = schematic.inputs.allSatisfy { inputType, _ in
                    incomingRoutes.contains { $0.type.id == inputType.id }
                }
                if !hasAllInputs { return .inputNotRouted }
                
                let hasOutput = outgoingRoutes.contains { $0.type.id == schematic.outputType.id }
                if !hasOutput { return .outputNotRouted }
            }
            return .routed
            
        default:
            return .routed
        }
    }
    
    /// 获取容量
    func getCapacity() -> Int? {
        let sql = "SELECT groupID, volume, capacity FROM types WHERE type_id = ?"
        if case .success(let rows) = DatabaseManager.shared.executeQuery(sql, parameters: [type.id]),
            let row = rows.first,
            let capacity = row["capacity"] as? Int {
                return capacity
        }
        return 0
    }
}

/// 获取殖民地状态
func getColonyStatus(pins: [Pin]) -> ColonyStatus {
    // 检查未设置的设施
    let notSetupPins = pins.filter { pin in
        switch pin.status {
        case .notSetup, .inputNotRouted, .outputNotRouted:
            return true
        default:
            return false
        }
    }
    if !notSetupPins.isEmpty {
        return .notSetup(pins: notSetupPins)
    }
    
    // 检查需要注意的设施
    let needsAttentionPins = pins.filter { pin in
        switch pin.status {
        case .extractorExpired, .extractorInactive, .storageFull:
            return true
        default:
            return false
        }
    }
    if !needsAttentionPins.isEmpty {
        return .needsAttention(pins: needsAttentionPins)
    }
    
    // 检查采集中的设施
    let extractingPins = pins.filter { $0.status == .extracting }
    if !extractingPins.isEmpty {
        return .extracting(pins: extractingPins)
    }
    
    // 检查生产中的设施
    let producingPins = pins.filter { $0.status == .producing }
    if !producingPins.isEmpty {
        return .producing(pins: producingPins)
    }
    
    // 默认为空闲状态
    return .idle(pins: [])
}
