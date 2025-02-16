import Foundation

public struct LoyaltyPoint: Codable {
    public let corporation_id: Int
    public let loyalty_points: Int
}

public class CharacterLoyaltyPointsAPI {
    public static let shared = CharacterLoyaltyPointsAPI()
    
    private init() {}
    
    public func fetchLoyaltyPoints(characterId: Int, forceRefresh: Bool = false) async throws -> [LoyaltyPoint] {
        // 如果不是强制刷新，先检查缓存
        if !forceRefresh {
            if let cachedData = try checkCache(characterId: characterId) {
                return cachedData
            }
        }
        
        let urlString = "https://esi.evetech.net/latest/characters/\(characterId)/loyalty/points/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        
        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId
        )
        
        let points = try JSONDecoder().decode([LoyaltyPoint].self, from: data)
        
        // 保存到数据库
        try await saveToDatabase(characterId: characterId, data: data)
        
        return points
    }
    
    private func checkCache(characterId: Int) throws -> [LoyaltyPoint]? {
        let query = """
            SELECT points_data, last_updated 
            FROM loyalty_points 
            WHERE character_id = ? 
            AND datetime(last_updated) > datetime('now', '-12 hours')
        """
        
        guard case .success(let rows) = CharacterDatabaseManager.shared.executeQuery(query, parameters: [characterId]),
              let row = rows.first,
              let pointsData = row["points_data"] as? String,
              let data = pointsData.data(using: .utf8) else {
            return nil
        }
        
        return try JSONDecoder().decode([LoyaltyPoint].self, from: data)
    }
    
    private func saveToDatabase(characterId: Int, data: Data) async throws {
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw NetworkError.invalidData
        }
        
        let query = """
            INSERT OR REPLACE INTO loyalty_points (character_id, points_data, last_updated)
            VALUES (?, ?, CURRENT_TIMESTAMP)
        """
        
        guard case .success = CharacterDatabaseManager.shared.executeQuery(query, parameters: [characterId, jsonString]) else {
            throw NetworkError.invalidResponse
        }
    }
} 
