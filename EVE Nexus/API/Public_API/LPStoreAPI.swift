import Foundation

struct LPStoreOffer: Codable {
    let akCost: Int
    let iskCost: Int
    let lpCost: Int
    let offerId: Int
    let quantity: Int
    let requiredItems: [RequiredItem]
    let typeId: Int

    enum CodingKeys: String, CodingKey {
        case akCost = "ak_cost"
        case iskCost = "isk_cost"
        case lpCost = "lp_cost"
        case offerId = "offer_id"
        case quantity
        case requiredItems = "required_items"
        case typeId = "type_id"
    }
}

struct RequiredItem: Codable {
    let quantity: Int
    let typeId: Int

    enum CodingKeys: String, CodingKey {
        case quantity
        case typeId = "type_id"
    }
}

// MARK: - 错误类型

enum LPStoreAPIError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case decodingError(Error)
    case httpError(Int)
    case rateLimitExceeded

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
        }
    }
}

// MARK: - LP商店API

@globalActor actor LPStoreAPIActor {
    static let shared = LPStoreAPIActor()
}

@LPStoreAPIActor
class LPStoreAPI {
    static let shared = LPStoreAPI()
    private let cacheDuration: TimeInterval = 3600  // 1小时缓存

    private init() {}

    // MARK: - 公共方法

    func fetchLPStoreOffers(corporationId: Int, forceRefresh: Bool = false) async throws
        -> [LPStoreOffer]
    {
        // 如果不是强制刷新，尝试从数据库获取
        if !forceRefresh {
            if let cached = try? loadFromDatabase(corporationId: corporationId) {
                return cached
            }
        }

        // 构建URL
        let baseURL = "https://esi.evetech.net/latest/loyalty/stores/\(corporationId)/offers/"
        var components = URLComponents(string: baseURL)
        components?.queryItems = [
            URLQueryItem(name: "datasource", value: "tranquility")
        ]

        guard let url = components?.url else {
            throw LPStoreAPIError.invalidURL
        }

        // 执行请求
        let data = try await NetworkManager.shared.fetchData(from: url)
        let offers = try JSONDecoder().decode([LPStoreOffer].self, from: data)

        // 保存到数据库
        saveLPStoreOffers(corporationId: corporationId, offersData: data)

        return offers
    }

    // MARK: - 私有方法

    private func loadFromDatabase(corporationId: Int) throws -> [LPStoreOffer]? {
        let query = """
                SELECT offers_data, last_updated 
                FROM LPStore 
                WHERE corporation_id = ?
            """

        if case let .success(rows) = CharacterDatabaseManager.shared.executeQuery(
            query, parameters: [corporationId]
        ),
            let row = rows.first,
            let offersData = row["offers_data"] as? String,
            let lastUpdated = row["last_updated"] as? String
        {
            // 检查是否过期
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            if let updateDate = dateFormatter.date(from: lastUpdated),
                Date().timeIntervalSince(updateDate) < cacheDuration
            {
                // 解析数据
                if let data = offersData.data(using: .utf8),
                    let offers = try? JSONDecoder().decode([LPStoreOffer].self, from: data)
                {
                    Logger.info("使用缓存的LP商店数据 - 军团ID: \(corporationId)")
                    return offers
                }
            }
        }
        return nil
    }

    private func saveLPStoreOffers(corporationId: Int, offersData: Data) {
        guard let offersString = String(data: offersData, encoding: .utf8) else {
            Logger.error("无法将响应数据转换为字符串")
            return
        }

        let query = """
                INSERT OR REPLACE INTO LPStore (
                    corporation_id, offers_data, last_updated
                ) VALUES (?, ?, CURRENT_TIMESTAMP)
            """

        _ = CharacterDatabaseManager.shared.executeQuery(
            query,
            parameters: [
                corporationId,
                offersString,
            ]
        )

        Logger.info("保存LP商店数据到数据库 - 军团ID: \(corporationId)")
    }
}
