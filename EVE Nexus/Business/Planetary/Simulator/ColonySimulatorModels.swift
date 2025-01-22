import Foundation

/// 设施类型
enum PinType: String {
    case extractor = "EXTRACTOR"
    case processor = "PROCESSOR"
    case storage = "STORAGE"
    case launchpad = "LAUNCHPAD"
    case commandCenter = "COMMAND_CENTER"  // 添加指挥中心类型
    
    /// 获取设施的存储容量（立方米）
    var storageCapacity: Double? {
        switch self {
        case .storage:
            return 12_000.0  // 存储设施 12000m³
        case .launchpad:
            return 10_000.0  // 发射台 10000m³
        case .commandCenter:
            return 500.0     // 指挥中心 500m³
        case .processor, .extractor:
            return nil       // 加工设施和提取设施没有固定存储容量
        }
    }
}

/// 设施内容物
struct PinContents {
    var commodities: [Int64: Int64] // [typeId: quantity]
    var capacity: Int64
    private var commodityVolumes: [Int64: Double] // [typeId: volume]
    
    init(commodities: [Int64: Int64], capacity: Int64) {
        self.commodities = commodities
        self.capacity = capacity
        self.commodityVolumes = [:]
        
        // 从数据库加载商品体积数据
        if !commodities.isEmpty {
            let typeIds = commodities.keys.map { String($0) }.joined(separator: ",")
            let query = "SELECT type_id, volume FROM types WHERE type_id IN (\(typeIds))"
            if case .success(let rows) = DatabaseManager.shared.executeQuery(query) {
                for row in rows {
                    if let typeId = row["type_id"] as? Int64,
                       let volume = row["volume"] as? Double {
                        commodityVolumes[typeId] = volume
                    }
                }
            }
        }
    }
    
    var isEmpty: Bool {
        commodities.isEmpty
    }
    
    /// 计算当前使用的总体积
    var usedVolume: Double {
        commodities.reduce(0.0) { total, item in
            total + (Double(item.value) * (commodityVolumes[item.key] ?? 0.0))
        }
    }
    
    /// 计算剩余可用体积
    var availableVolume: Double {
        Double(capacity) - usedVolume
    }
    
    /// 计算指定数量商品需要的体积
    func volumeFor(typeId: Int64, amount: Int64) -> Double {
        Double(amount) * (commodityVolumes[typeId] ?? 0.0)
    }
    
    /// 检查是否有足够空间存储指定数量的商品
    func hasSpaceFor(typeId: Int64, amount: Int64) -> Bool {
        availableVolume >= volumeFor(typeId: typeId, amount: amount)
    }
}

/// 模拟事件
struct SimulationEvent: Comparable {
    let time: Date
    let pinId: Int64
    
    static func < (lhs: SimulationEvent, rhs: SimulationEvent) -> Bool {
        lhs.time < rhs.time
    }
}

/// 模拟结束条件
enum SimulationEndCondition {
    case untilNow
    case untilWorkEnds
    
    var simEndTime: Date {
        switch self {
        case .untilNow:
            return Date()
        case .untilWorkEnds:
            return Date.distantFuture
        }
    }
} 
