import Foundation

struct CharacterAffiliation: Codable {
    let character_id: Int
    let corporation_id: Int
    let alliance_id: Int?
    let faction_id: Int?
}

class CharacterAffiliationAPI {
    static let shared = CharacterAffiliationAPI()
    private init() {}

    func fetchAffiliations(characterIds: [Int]) async throws -> [CharacterAffiliation] {
        let urlString =
            "https://esi.evetech.net/characters/affiliation/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        // 准备请求数据
        let jsonData = try JSONEncoder().encode(characterIds)

        // 发送POST请求
        let data = try await NetworkManager.shared.fetchData(
            from: url,
            method: "POST",
            body: jsonData
        )

        // 解析响应数据
        return try JSONDecoder().decode([CharacterAffiliation].self, from: data)
    }

    /// 批量获取角色关联信息，自动处理大量请求
    func fetchAffiliationsInBatches(characterIds: [Int], batchSize: Int = 1000) async throws
        -> [CharacterAffiliation]
    {
        var results: [CharacterAffiliation] = []

        // 将角色ID分批处理
        for batch in stride(from: 0, to: characterIds.count, by: batchSize) {
            let endIndex = min(batch + batchSize, characterIds.count)
            let batchIds = Array(characterIds[batch..<endIndex])

            let batchResults = try await fetchAffiliations(characterIds: batchIds)
            results.append(contentsOf: batchResults)
        }

        return results
    }
}
