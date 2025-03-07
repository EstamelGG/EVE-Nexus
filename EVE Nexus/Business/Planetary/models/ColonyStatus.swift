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
        case .notSetup, .needsAttention, .idle: return false
        case .producing, .extracting: return true
        }
    }

    /// 相关的设施
    var pins: [Pin] {
        switch self {
        case let .notSetup(pins), let .needsAttention(pins), let .idle(pins), let .producing(pins),
            let .extracting(pins):
            return pins
        }
    }
}

/// 获取殖民地状态
/// - Parameter pins: 设施列表
/// - Returns: 殖民地状态
func getColonyStatus(pins: [Pin]) -> ColonyStatus {
    let notSetupPins = pins.filter { pin in
        pin.status == .notSetup || pin.status == .inputNotRouted || pin.status == .outputNotRouted
    }
    if !notSetupPins.isEmpty {
        return .notSetup(pins: notSetupPins)
    }

    let needsAttentionPins = pins.filter { pin in
        pin.status == .extractorExpired || pin.status == .extractorInactive
            || pin.status == .storageFull
    }
    if !needsAttentionPins.isEmpty {
        return .needsAttention(pins: needsAttentionPins)
    }

    let extractingPins = pins.filter { pin in
        pin.status == .extracting
    }
    if !extractingPins.isEmpty {
        return .extracting(pins: extractingPins)
    }

    let producingPins = pins.filter { pin in
        pin.status == .producing
    }
    if !producingPins.isEmpty {
        return .producing(pins: producingPins)
    }

    return .idle(pins: [])
}

/// 获取设施状态
/// - Parameters:
///   - pin: 设施
///   - now: 当前时间
///   - routes: 路由列表
/// - Returns: 设施状态
func getPinStatus(pin: Pin, now: Date, routes: [Route]) -> PinStatus {
    if let extractor = pin as? Pin.Extractor {
        let isSetup =
            extractor.installTime != nil && extractor.expiryTime != nil
            && extractor.cycleTime != nil && extractor.baseValue != nil
            && extractor.productType != nil
        if !isSetup {
            return .notSetup
        }

        if let expiryTime = extractor.expiryTime, expiryTime <= now {
            return .extractorExpired
        }

        switch isRouted(pin: pin, routes: routes) {
        case .routed: break
        case .inputNotRouted: return .inputNotRouted
        case .outputNotRouted: return .outputNotRouted
        }

        if extractor.isActive {
            return .extracting
        }

        return .extractorInactive
    } else if let factory = pin as? Pin.Factory {
        if factory.schematic == nil {
            return .notSetup
        }

        switch isRouted(pin: pin, routes: routes) {
        case .routed: break
        case .inputNotRouted: return .inputNotRouted
        case .outputNotRouted: return .outputNotRouted
        }

        // 使用与Kotlin版本相似的逻辑判断工厂是否处于活跃状态
        if let lastCycleStartTime = factory.lastCycleStartTime,
            let schematic = factory.schematic
        {
            let cycleTime = schematic.cycleTime
            let lastCycleAgo = now.timeIntervalSince(lastCycleStartTime)

            // 如果上次周期开始时间到现在的时间小于一个完整周期，则工厂处于活跃状态
            if lastCycleAgo < cycleTime {
                return .producing
            }
        }

        // 检查是否有足够的输入材料
        if factory.hasEnoughInputs() {
            return .factoryIdle  // 有足够材料但未生产
        } else {
            return .inputNotRouted  // 材料不足
        }
    } else if pin is Pin.CommandCenter || pin is Pin.Launchpad || pin is Pin.Storage {
        let incomingRoutes = routes.filter { $0.destinationPinId == pin.id }
        if !incomingRoutes.isEmpty {
            let capacityRemaining = max(Double(getCapacity(for: pin) ?? 0) - pin.capacityUsed, 0)
            if incomingRoutes.contains(where: { route in
                route.type.volume * Double(route.quantity) > capacityRemaining
            }) {
                return .storageFull
            }
        }

        return .static
    }

    return .static
}

/// 检查设施的路由状态
/// - Parameters:
///   - pin: 设施
///   - routes: 路由列表
/// - Returns: 路由状态
func isRouted(pin: Pin, routes: [Route]) -> RoutedState {
    let isInputRouted: Bool
    if let factory = pin as? Pin.Factory {
        if let schematic = factory.schematic {
            let inputTypes = schematic.inputs.map { $0.key.id }
            let inputTypesReceived = Set(
                routes.filter { $0.destinationPinId == pin.id }.map { $0.type.id })
            isInputRouted = inputTypes.allSatisfy { inputTypesReceived.contains($0) }
        } else {
            isInputRouted = true
        }
    } else {
        isInputRouted = true
    }

    let isOutputRouted: Bool
    if pin is Pin.Factory || pin is Pin.Extractor {
        isOutputRouted = routes.contains { $0.sourcePinId == pin.id }
    } else {
        isOutputRouted = true
    }

    if !isInputRouted {
        return .inputNotRouted
    }
    if !isOutputRouted {
        return .outputNotRouted
    }
    return .routed
}

/// 获取设施容量
/// - Parameter pin: 设施
/// - Returns: 容量
func getCapacity(for pin: Pin) -> Int? {
    switch pin {
    case is Pin.Extractor:
        return nil
    case is Pin.Factory:
        return nil
    case is Pin.Storage:
        return 12000
    case is Pin.CommandCenter:
        return 500
    case is Pin.Launchpad:
        return 10000
    default:
        return nil
    }
}
