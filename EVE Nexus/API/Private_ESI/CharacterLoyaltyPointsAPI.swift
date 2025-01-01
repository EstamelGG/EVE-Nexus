import Foundation

public struct LoyaltyPoint: Codable {
    public let corporation_id: Int
    public let loyalty_points: Int
}

public class CharacterLoyaltyPointsAPI {
    public static let shared = CharacterLoyaltyPointsAPI()
    
    private init() {}
    
    public func fetchLoyaltyPoints(characterId: Int) async throws -> [LoyaltyPoint] {
        let urlString = "https://esi.evetech.net/latest/characters/\(characterId)/loyalty/points/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        
        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId
        )
        
        return try JSONDecoder().decode([LoyaltyPoint].self, from: data)
    }
} 