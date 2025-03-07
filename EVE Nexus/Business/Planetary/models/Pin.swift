import Foundation

/// 设施状态
enum PinStatus {
    case extracting
    case producing
    case notSetup
    case inputNotRouted
    case outputNotRouted
    case extractorExpired
    case extractorInactive
    case storageFull
    case factoryIdle
    case `static`
}

/// 路由状态
enum RoutedState {
    case routed
    case inputNotRouted
    case outputNotRouted
}

/// 基础设施类
class Pin {
    let id: Int64
    let type: Type
    let name: String
    let designator: String
    var lastRunTime: Date?
    var contents: [Type: Int64]
    var capacityUsed: Double
    var isActive: Bool
    let latitude: Double
    let longitude: Double
    var status: PinStatus

    init(
        id: Int64, type: Type, name: String, designator: String, lastRunTime: Date?,
        contents: [Type: Int64], capacityUsed: Double, isActive: Bool, latitude: Double,
        longitude: Double, status: PinStatus
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.designator = designator
        self.lastRunTime = lastRunTime
        self.contents = contents
        self.capacityUsed = capacityUsed
        self.isActive = isActive
        self.latitude = latitude
        self.longitude = longitude
        self.status = status
    }

    /// 克隆设施
    func clone() -> Pin {
        let contentsCopy = contents
        return Pin(
            id: id, type: type, name: name, designator: designator, lastRunTime: lastRunTime,
            contents: contentsCopy, capacityUsed: capacityUsed, isActive: isActive,
            latitude: latitude, longitude: longitude, status: status
        )
    }

    /// 提取器
    class Extractor: Pin {
        let expiryTime: Date?
        let installTime: Date?
        let cycleTime: TimeInterval?
        let headRadius: Double?
        let heads: [PlanetaryExtractorHead]?
        let productType: Type?
        let baseValue: Int?

        init(
            id: Int64, type: Type, name: String, designator: String, lastRunTime: Date?,
            contents: [Type: Int64], capacityUsed: Double, isActive: Bool, latitude: Double,
            longitude: Double, status: PinStatus, expiryTime: Date?, installTime: Date?,
            cycleTime: TimeInterval?, headRadius: Double?, heads: [PlanetaryExtractorHead]?,
            productType: Type?, baseValue: Int?
        ) {
            self.expiryTime = expiryTime
            self.installTime = installTime
            self.cycleTime = cycleTime
            self.headRadius = headRadius
            self.heads = heads
            self.productType = productType
            self.baseValue = baseValue
            super.init(
                id: id, type: type, name: name, designator: designator, lastRunTime: lastRunTime,
                contents: contents, capacityUsed: capacityUsed, isActive: isActive,
                latitude: latitude, longitude: longitude, status: status
            )
        }

        override func clone() -> Pin {
            let contentsCopy = contents
            return Extractor(
                id: id, type: type, name: name, designator: designator, lastRunTime: lastRunTime,
                contents: contentsCopy, capacityUsed: capacityUsed, isActive: isActive,
                latitude: latitude, longitude: longitude, status: status, expiryTime: expiryTime,
                installTime: installTime, cycleTime: cycleTime, headRadius: headRadius,
                heads: heads, productType: productType, baseValue: baseValue
            )
        }
    }

    /// 工厂
    class Factory: Pin {
        let schematic: Schematic?
        var hasReceivedInputs: Bool
        var receivedInputsLastCycle: Bool
        var lastCycleStartTime: Date?

        init(
            id: Int64, type: Type, name: String, designator: String, lastRunTime: Date?,
            contents: [Type: Int64], capacityUsed: Double, isActive: Bool, latitude: Double,
            longitude: Double, status: PinStatus, schematic: Schematic?, hasReceivedInputs: Bool,
            receivedInputsLastCycle: Bool, lastCycleStartTime: Date?
        ) {
            self.schematic = schematic
            self.hasReceivedInputs = hasReceivedInputs
            self.receivedInputsLastCycle = receivedInputsLastCycle
            self.lastCycleStartTime = lastCycleStartTime
            super.init(
                id: id, type: type, name: name, designator: designator, lastRunTime: lastRunTime,
                contents: contents, capacityUsed: capacityUsed, isActive: isActive,
                latitude: latitude, longitude: longitude, status: status
            )
        }

        /// 获取输入缓冲区状态
        func getInputBufferState() -> Double {
            guard let schematic = schematic, !schematic.inputs.isEmpty else {
                return 0.0
            }

            var productsRatio = 0.0
            for (inputType, requiredQuantity) in schematic.inputs {
                let availableQuantity = contents[inputType] ?? 0
                productsRatio += Double(availableQuantity) / Double(requiredQuantity)
            }

            return 1.0 - productsRatio / Double(schematic.inputs.count)
        }

        /// 检查是否有足够的输入材料
        func hasEnoughInputs() -> Bool {
            guard let schematic = schematic else { return false }

            for (inputType, requiredQuantity) in schematic.inputs {
                let availableQuantity = contents[inputType] ?? 0
                if availableQuantity < requiredQuantity {
                    return false
                }
            }

            return true
        }

        override func clone() -> Pin {
            let contentsCopy = contents
            return Factory(
                id: id, type: type, name: name, designator: designator, lastRunTime: lastRunTime,
                contents: contentsCopy, capacityUsed: capacityUsed, isActive: isActive,
                latitude: latitude, longitude: longitude, status: status, schematic: schematic,
                hasReceivedInputs: hasReceivedInputs,
                receivedInputsLastCycle: receivedInputsLastCycle,
                lastCycleStartTime: lastCycleStartTime
            )
        }
    }

    /// 存储设施
    class Storage: Pin {
        override init(
            id: Int64, type: Type, name: String, designator: String, lastRunTime: Date?,
            contents: [Type: Int64], capacityUsed: Double, isActive: Bool, latitude: Double,
            longitude: Double, status: PinStatus
        ) {
            super.init(
                id: id, type: type, name: name, designator: designator, lastRunTime: lastRunTime,
                contents: contents, capacityUsed: capacityUsed, isActive: isActive,
                latitude: latitude, longitude: longitude, status: status
            )
        }

        override func clone() -> Pin {
            let contentsCopy = contents
            return Storage(
                id: id, type: type, name: name, designator: designator, lastRunTime: lastRunTime,
                contents: contentsCopy, capacityUsed: capacityUsed, isActive: isActive,
                latitude: latitude, longitude: longitude, status: status
            )
        }
    }

    /// 发射台
    class Launchpad: Pin {
        override init(
            id: Int64, type: Type, name: String, designator: String, lastRunTime: Date?,
            contents: [Type: Int64], capacityUsed: Double, isActive: Bool, latitude: Double,
            longitude: Double, status: PinStatus
        ) {
            super.init(
                id: id, type: type, name: name, designator: designator, lastRunTime: lastRunTime,
                contents: contents, capacityUsed: capacityUsed, isActive: isActive,
                latitude: latitude, longitude: longitude, status: status
            )
        }

        override func clone() -> Pin {
            let contentsCopy = contents
            return Launchpad(
                id: id, type: type, name: name, designator: designator, lastRunTime: lastRunTime,
                contents: contentsCopy, capacityUsed: capacityUsed, isActive: isActive,
                latitude: latitude, longitude: longitude, status: status
            )
        }
    }

    /// 指挥中心
    class CommandCenter: Pin {
        let level: Int

        init(
            id: Int64, type: Type, name: String, designator: String, lastRunTime: Date?,
            contents: [Type: Int64], capacityUsed: Double, isActive: Bool, latitude: Double,
            longitude: Double, status: PinStatus, level: Int
        ) {
            self.level = level
            super.init(
                id: id, type: type, name: name, designator: designator, lastRunTime: lastRunTime,
                contents: contents, capacityUsed: capacityUsed, isActive: isActive,
                latitude: latitude, longitude: longitude, status: status
            )
        }

        override func clone() -> Pin {
            let contentsCopy = contents
            return CommandCenter(
                id: id, type: type, name: name, designator: designator, lastRunTime: lastRunTime,
                contents: contentsCopy, capacityUsed: capacityUsed, isActive: isActive,
                latitude: latitude, longitude: longitude, status: status, level: level
            )
        }
    }
}

/// 采集头
struct PlanetaryExtractorHead {
    let latitude: Double
    let longitude: Double
}

/// 资源类型
struct Type: Hashable {
    let id: Int
    let name: String
    let volume: Double

    // 实现Hashable协议
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // 实现Equatable协议（Hashable继承自Equatable）
    static func == (lhs: Type, rhs: Type) -> Bool {
        return lhs.id == rhs.id
    }
}

/// 配方
struct Schematic {
    let id: Int
    let cycleTime: TimeInterval
    let outputType: Type
    let outputQuantity: Int64
    let inputs: [Type: Int64]
}
