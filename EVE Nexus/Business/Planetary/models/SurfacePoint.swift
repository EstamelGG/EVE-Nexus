import Foundation

/// 行星表面点
class SurfacePoint {
    let radius: Float
    let theta: Float
    let phi: Float
    
    let x: Float
    let y: Float
    let z: Float
    
    init(radius: Float, theta: Float, phi: Float) {
        self.radius = radius
        self.theta = theta
        self.phi = phi
        
        let radSinPhi = radius * sin(phi)
        x = radSinPhi * cos(theta)
        z = radSinPhi * sin(theta)
        y = radius * cos(phi)
    }
    
    /// 获取到另一个点的距离
    /// - Parameter other: 另一个点
    /// - Returns: 距离
    func getDistanceTo(other: SurfacePoint) -> Float {
        return radius * getAngleTo(other: other)
    }
    
    /// 获取到另一个点的角度
    /// - Parameter other: 另一个点
    /// - Returns: 角度
    private func getAngleTo(other: SurfacePoint) -> Float {
        var dotProduct = (x * other.x + y * other.y + z * other.z) / radius / other.radius
        if dotProduct > 1.0 {
            dotProduct = 1.0
        }
        return acos(dotProduct)
    }
} 