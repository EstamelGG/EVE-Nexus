import Foundation

/// 行星设施状态
enum PinStatus: String {
    case idle = "idle"               // 空闲
    case active = "active"           // 活跃
    case storageFull = "storageFull" // 存储已满
    case noInput = "noInput"         // 无输入
    case noRoute = "noRoute"         // 无路由
    case noStorage = "noStorage"     // 无存储
    
    var isWorking: Bool {
        switch self {
        case .active:
            return true
        default:
            return false
        }
    }
}

/// 殖民地状态
struct ColonyStatus {
    let isWorking: Bool
    let pins: [PinStatus]
    
    static func getStatus(for pins: [Pin]) -> ColonyStatus {
        let pinStatuses = pins.map { $0.status }
        let isWorking = pinStatuses.contains { $0.isWorking }
        return ColonyStatus(isWorking: isWorking, pins: pinStatuses)
    }
}

/// 殖民地概览
struct ColonyOverview {
    let routeCount: Int
    let pinCount: Int
    let extractorCount: Int
    let processorCount: Int
    let storageCount: Int
    
    static func getOverview(routes: [Route], pins: [Pin]) -> ColonyOverview {
        return ColonyOverview(
            routeCount: routes.count,
            pinCount: pins.count,
            extractorCount: pins.filter { $0.isExtractor() }.count,
            processorCount: pins.filter { $0.isProcessor() }.count,
            storageCount: pins.filter { $0.isStorage() }.count
        )
    }
}

/// 行星设施
class Pin {
    // MARK: - Type Constants
    
    private struct GroupID {
        static let extractor: Int = 1026  // 采集器
        static let commandCenter: Int = 1027  // 指挥中心
        static let processor: Int = 1028  // 处理设施
        static let storage: Int = 1029  // 储藏设施
    }
    
    let id: Int64
    let typeId: Int
    let groupId: Int
    var status: PinStatus = .idle
    var contents: [Int: Int64] = [:] // [typeId: quantity]
    private let capacity: Int64
    
    init(id: Int64, typeId: Int, groupId: Int, capacity: Int64) {
        self.id = id
        self.typeId = typeId
        self.groupId = groupId
        self.capacity = capacity
    }
    
    func isExtractor() -> Bool {
        return groupId == GroupID.extractor
    }
    
    func isProcessor() -> Bool {
        return groupId == GroupID.processor
    }
    
    func isStorage() -> Bool {
        return groupId == GroupID.storage
    }
    
    func isCommandCenter() -> Bool {
        return groupId == GroupID.commandCenter
    }
    
    func isConsumer() -> Bool {
        return isProcessor()
    }
    
    func canActivate() -> Bool {
        // TODO: 判断是否可以激活
        return false
    }
    
    func isActive() -> Bool {
        return status == .active
    }
    
    func getNextRunTime() -> Date? {
        // TODO: 计算下一次运行时间
        return nil
    }
    
    func run(currentTime: Date) -> [Int: Int64] {
        // TODO: 运行设施并返回产出
        return [:]
    }
    
    func addCommodity(_ typeId: Int, _ quantity: Int64) -> Int64 {
        let currentQuantity = contents[typeId] ?? 0
        let availableSpace = capacity - contents.values.reduce(0, +)
        let amountToAdd = min(quantity, availableSpace)
        if amountToAdd > 0 {
            contents[typeId] = currentQuantity + amountToAdd
        }
        return amountToAdd
    }
    
    func removeCommodity(_ typeId: Int, _ quantity: Int64) {
        if let currentQuantity = contents[typeId] {
            let newQuantity = currentQuantity - quantity
            if newQuantity <= 0 {
                contents.removeValue(forKey: typeId)
            } else {
                contents[typeId] = newQuantity
            }
        }
    }
}

/// 资源路由
struct Route {
    let id: Int64
    let sourcePinId: Int64
    let destinationPinId: Int64
    let typeId: Int
    let quantity: Int64
}

/// 殖民地
struct Colony {
    let id: Int64
    let pins: [Pin]
    let routes: [Route]
    var currentSimTime: Date
    var status: ColonyStatus
    var overview: ColonyOverview
    
    func clone() -> Colony {
        // 创建深拷贝
        let clonedPins = pins.map { pin in
            let clonedPin = Pin(id: pin.id, typeId: pin.typeId, groupId: pin.groupId, capacity: 0)
            clonedPin.status = pin.status
            clonedPin.contents = pin.contents
            return clonedPin
        }
        
        return Colony(
            id: id,
            pins: clonedPins,
            routes: routes,
            currentSimTime: currentSimTime,
            status: status,
            overview: overview
        )
    }
} 