import Foundation

/// ESI行星设施数据模型
struct ESIPlanetaryPin {
    let pinId: Int64
    let typeId: Int64
    let schematicId: Int64?
    let cycleTime: Int64
    let lastRunTime: Date?
    let contents: [ESIPlanetaryContent]
    let type: ESIPlanetaryPinType
    let lastCycleStart: String?
    let extractorDetails: ESIExtractorDetails?
    let expiryTime: String?
    let installTime: String?
}

/// ESI行星设施内容物
struct ESIPlanetaryContent {
    let typeId: Int64
    let amount: Int64
}

/// ESI行星设施类型
struct ESIPlanetaryPinType {
    let name: String
    let capacity: Int64
}

/// ESI提取器详情
struct ESIExtractorDetails {
    let productTypeId: Int64
    let headRadius: Double
    let heads: [ESIExtractorHead]
}

/// ESI提取器头部
struct ESIExtractorHead {
    let headId: Int64
    let latitude: Double
    let longitude: Double
}

/// ESI行星路由
struct ESIPlanetaryRoute {
    let routeId: Int64
    let sourcePinId: Int64
    let destinationPinId: Int64
    let commodityTypeId: Int64
    let quantity: Int64
    let waypoints: [Int64]  // 路由点数组
} 