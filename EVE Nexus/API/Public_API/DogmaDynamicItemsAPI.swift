import Foundation

// MARK: - ESI 原始响应模型

struct DogmaAttributeItem: Codable {
    let attribute_id: Int
    let value: Double
}

struct DogmaEffectItem: Codable {
    let effect_id: Int
    let is_default: Bool
}

/// ESI dogma/dynamic/items 接口返回的完整 JSON 结构
struct DogmaDynamicItemsRawResponse: Codable {
    let created_by: Int
    let dogma_attributes: [DogmaAttributeItem]
    let dogma_effects: [DogmaEffectItem]
    let mutator_type_id: Int
    let source_type_id: Int
}

// MARK: - 对外返回模型

/// 解析后对外返回的数据：仅包含 mutator_type_id、source_type_id、created_by、dogma_attributes
struct DogmaDynamicItemsResult {
    let mutator_type_id: Int
    let source_type_id: Int
    let created_by: Int
    let dogma_attributes: [DogmaAttributeItem]
}

// MARK: - 错误类型

enum DogmaDynamicItemsAPIError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case decodingError(Error)
    case httpError(Int)

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
        }
    }
}

// MARK: - Dogma Dynamic Items API

/// 获取 ESI dogma/dynamic/items 数据
/// 接口：https://esi.evetech.net/dogma/dynamic/items/{type_id}/{item_id}
@globalActor actor DogmaDynamicItemsAPIActor {
    static let shared = DogmaDynamicItemsAPIActor()
}

@DogmaDynamicItemsAPIActor
class DogmaDynamicItemsAPI {
    static let shared = DogmaDynamicItemsAPI()

    private let baseURL = "https://esi.evetech.net/dogma/dynamic/items"

    private init() {}

    /// 获取指定 type_id 与 item_id 的 dogma 动态物品数据
    /// - Parameters:
    ///   - typeId: 类型 ID（如 47736）
    ///   - itemId: 物品 ID（如 1052673239313）
    /// - Returns: 包含 mutator_type_id、source_type_id、created_by、dogma_attributes 的结果
    func fetch(typeId: Int, itemId: Int) async throws -> DogmaDynamicItemsResult {
        let urlString = "\(baseURL)/\(typeId)/\(itemId)"
        guard let url = URL(string: urlString) else {
            throw DogmaDynamicItemsAPIError.invalidURL
        }

        let data = try await NetworkManager.shared.fetchData(from: url)
        let raw = try JSONDecoder().decode(DogmaDynamicItemsRawResponse.self, from: data)

        return DogmaDynamicItemsResult(
            mutator_type_id: raw.mutator_type_id,
            source_type_id: raw.source_type_id,
            created_by: raw.created_by,
            dogma_attributes: raw.dogma_attributes
        )
    }
}
