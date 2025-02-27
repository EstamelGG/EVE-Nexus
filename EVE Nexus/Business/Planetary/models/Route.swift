import Foundation

/// 行星路由
struct Route {
    let type: Type
    let sourcePinId: Int64
    let destinationPinId: Int64
    let quantity: Int64
    let routeId: Int64
    let waypoints: [Int64]?
} 