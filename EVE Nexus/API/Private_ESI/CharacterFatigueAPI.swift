import Foundation

public struct CharacterFatigue: Codable {
    public let jump_fatigue_expire_date: String?
    public let last_jump_date: String?
    public let last_update_date: String?
}

public class CharacterFatigueAPI {
    public static let shared = CharacterFatigueAPI()

    private init() {}

    public func fetchCharacterFatigue(characterId: Int) async throws -> CharacterFatigue? {
        let urlString =
            "https://esi.evetech.net/characters/\(characterId)/fatigue/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId
        )

        return try? JSONDecoder().decode(CharacterFatigue.self, from: data)
    }
}
