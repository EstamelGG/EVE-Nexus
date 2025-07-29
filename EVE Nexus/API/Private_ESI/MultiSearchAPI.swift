import Foundation

enum SearchCategory: String {
    case agent
    case alliance
    case character
    case constellation
    case corporation
    case faction
    case inventoryType = "inventory_type"
    case region
    case solarSystem = "solar_system"
    case station
    case structure
}

class CharacterSearchAPI {
    static let shared = CharacterSearchAPI()
    private init() {}

    /// 搜索指定类别的内容
    /// - Parameters:
    ///   - characterId: 角色ID
    ///   - categories: 搜索类别数组
    ///   - searchText: 搜索文本
    ///   - strict: 是否精确匹配，默认为false
    /// - Returns: 搜索结果数据
    func search(
        characterId: Int,
        categories: [SearchCategory],
        searchText: String,
        strict: Bool = false
    ) async throws -> Data {
        // 构建URL
        var components = URLComponents(
            string: "https://esi.evetech.net/characters/\(characterId)/search/")

        // 将categories转换为字符串数组并用逗号连接
        let categoriesString = categories.map { $0.rawValue }.joined(separator: ",")

        // 添加查询参数
        components?.queryItems = [
            URLQueryItem(name: "categories", value: categoriesString),
            URLQueryItem(name: "search", value: searchText),
            URLQueryItem(name: "strict", value: strict ? "true" : "false"),
            URLQueryItem(name: "language", value: "en"),
        ]

        guard let url = components?.url else {
            throw NetworkError.invalidURL
        }

        // 发起请求
        return try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId
        )
    }
}
