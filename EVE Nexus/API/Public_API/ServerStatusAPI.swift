import Foundation

// MARK: - 服务器状态数据模型

struct ServerStatus: Codable {
    let players: Int
    let serverVersion: String
    let startTime: String
    let error: String?
    let timeout: Int?

    enum CodingKeys: String, CodingKey {
        case players
        case serverVersion = "server_version"
        case startTime = "start_time"
        case error
        case timeout
    }

    var isOnline: Bool {
        return error == nil
    }
}

// MARK: - 错误类型

enum ServerStatusAPIError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case decodingError(Error)
    case httpError(Int)
    case rateLimitExceeded
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的URL"
        case let .networkError(error):
            return "网络错误: \(error.localizedDescription)"
        case .invalidResponse:
            return "无效的响应"
        case let .decodingError(error):
            return "数据解码错误: \(error.localizedDescription)"
        case let .httpError(code):
            return "HTTP错误: \(code)"
        case .rateLimitExceeded:
            return "超出请求限制"
        case .timeout:
            return "请求超时"
        }
    }
}

// MARK: - 服务器状态API

@globalActor actor ServerStatusAPIActor {
    static let shared = ServerStatusAPIActor()
}

@ServerStatusAPIActor
class ServerStatusAPI {
    static let shared = ServerStatusAPI()

    private var lastStatus: ServerStatus?
    private var lastFetchTime: Date?

    // 缓存时间常量
    private let normalCacheInterval: TimeInterval = 30 * 60  // 30分钟
    private let maintenanceCacheInterval: TimeInterval = 60  // 1分钟

    private init() {}

    // 检查是否在维护时间窗口内
    private func isInMaintenanceWindow(_ date: Date = Date()) -> Bool {
        let calendar = Calendar.current
        let utc = TimeZone(identifier: "UTC")!
        let components = calendar.dateComponents(in: utc, from: date)

        guard let hour = components.hour else { return false }
        return hour >= 11 && hour < 24  // 11AM - 12AM UTC
    }

    // 检查是否需要刷新缓存
    private func shouldRefreshCache() -> Bool {
        guard let lastFetch = lastFetchTime else { return true }

        let currentTime = Date()
        let wasInMaintenanceWindow = isInMaintenanceWindow(lastFetch)
        let isNowInMaintenanceWindow = isInMaintenanceWindow(currentTime)

        // 如果刚进入维护时间窗口，立即刷新
        if !wasInMaintenanceWindow && isNowInMaintenanceWindow {
            return true
        }

        // 根据时间窗口决定缓存间隔
        let cacheInterval =
            isNowInMaintenanceWindow ? maintenanceCacheInterval : normalCacheInterval
        return currentTime.timeIntervalSince(lastFetch) > cacheInterval
    }

    // MARK: - 公共方法

    /// 获取服务器状态（使用智能缓存）
    /// - Parameter forceRefresh: 是否强制刷新，忽略缓存
    /// - Returns: 服务器状态
    func fetchServerStatus(forceRefresh: Bool = false) async throws -> ServerStatus {
        // 检查是否需要刷新缓存
        if !forceRefresh && !shouldRefreshCache(), let cachedStatus = lastStatus {
            return cachedStatus
        }

        let baseURL = "https://esi.evetech.net/status/?datasource=tranquility"
        let components = URLComponents(string: baseURL)
        guard let url = components?.url else {
            throw ServerStatusAPIError.invalidURL
        }

        do {
            // 使用NetworkManager的fetchData方法，设置1,2,5,5,10秒的超时重试
            Logger.info("尝试获取服务器状态...")
            let data = try await NetworkManager.shared.fetchData(
                from: url,
                forceRefresh: forceRefresh,
                timeouts: [1, 2, 5, 5, 10]
            )
            let status = try JSONDecoder().decode(ServerStatus.self, from: data)
            Logger.info("服务器状态: \(status)")
            // 如果响应中包含 error 字段，返回离线状态
            if status.error != nil {
                let offlineStatus = ServerStatus(
                    players: 0,
                    serverVersion: "",
                    startTime: "",
                    error: "Server is offline",
                    timeout: nil
                )
                // 更新缓存
                lastStatus = offlineStatus
                lastFetchTime = Date()
                return offlineStatus
            }

            // 更新缓存
            lastStatus = status
            lastFetchTime = Date()
            return status
        } catch {
            if (error as NSError).code == NSURLErrorTimedOut {
                let timeoutStatus = ServerStatus(
                    players: 0,
                    serverVersion: "",
                    startTime: "",
                    error: "Unknown",
                    timeout: nil
                )
                // 更新缓存
                lastStatus = timeoutStatus
                lastFetchTime = Date()
                return timeoutStatus
            }
            throw error
        }
    }
}
