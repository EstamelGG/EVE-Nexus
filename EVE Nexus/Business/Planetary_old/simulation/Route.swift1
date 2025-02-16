import Foundation

/// 路由
struct Route {
    /// 资源类型
    let type: CommodityType
    
    /// 源设施ID
    let sourcePinId: Int64
    
    /// 目标设施ID
    let destinationPinId: Int64
    
    /// 传输数量
    let quantity: Int64
    
    /// 路由ID
    let routeId: Int64
    
    /// 路径点
    let waypoints: [Int64]?
}

/// 路由状态
enum RoutedState {
    /// 已路由
    case routed
    /// 输入未路由
    case inputNotRouted
    /// 输出未路由
    case outputNotRouted
} 