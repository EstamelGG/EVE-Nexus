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
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        case .invalidResponse:
            return "无效的响应"
        case .decodingError(let error):
            return "数据解码错误: \(error.localizedDescription)"
        case .httpError(let code):
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
    
    private init() {}
    
    // MARK: - 公共方法
    
    /// 获取服务器状态（不使用任何缓存）
    /// - Returns: 服务器状态
    func fetchServerStatus() async throws -> ServerStatus {
        let baseURL = "https://esi.evetech.net/latest/status/"
        var components = URLComponents(string: baseURL)
        components?.queryItems = [
            URLQueryItem(name: "datasource", value: "tranquility"),
            // 添加随机参数以避免任何可能的缓存
            URLQueryItem(name: "t", value: "\(Date().timeIntervalSince1970)")
        ]
        
        guard let url = components?.url else {
            throw ServerStatusAPIError.invalidURL
        }
        
        do {
            // 直接从网络获取最新状态，设置3秒超时
            let data = try await NetworkManager.shared.fetchData(from: url, timeout: 3.0)
            let status = try JSONDecoder().decode(ServerStatus.self, from: data)
            
            // 如果响应中包含 error 字段，返回离线状态
            if status.error != nil {
                return ServerStatus(
                    players: 0,
                    serverVersion: "",
                    startTime: "",
                    error: "Server is offline",
                    timeout: nil
                )
            }
            return status
        } catch {
            if (error as NSError).code == NSURLErrorTimedOut {
                return ServerStatus(
                    players: 0,
                    serverVersion: "",
                    startTime: "",
                    error: "Unknown",
                    timeout: nil
                )
            }
            throw error
        }
    }
} 
