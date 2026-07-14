import Foundation

/// 强制刷新统一限流器
///
/// 各市场 API 在执行强制刷新前应先询问本限流器；cooldown 窗口内的重复强制刷新会被拒绝，
/// 调用方应降级为使用缓存数据，避免触发 ESI 请求频率限制。
actor ForceRefreshThrottle {
    static let shared = ForceRefreshThrottle()

    private let cooldown: TimeInterval = 5 * 60
    private var lastRefreshTimes: [String: Date] = [:]

    private init() {}

    /// 请求对指定资源执行强制刷新
    /// - Parameter key: 资源标识（如 "orders-34-10000002"）
    /// - Returns: true 表示允许执行强制刷新；false 表示距上次刷新不足 cooldown，应使用缓存
    func request(key: String) -> Bool {
        if let last = lastRefreshTimes[key], Date().timeIntervalSince(last) < cooldown {
            return false
        }
        lastRefreshTimes[key] = Date()
        return true
    }
}
