import Foundation

class LocationManager {
    static let shared = LocationManager()
    
    private init() {}
    
    // 获取角色位置信息
    func getCharacterLocation(characterId: Int, token: String) async throws -> CharacterLocation {
        let urlString = "https://esi.evetech.net/latest/characters/\(characterId)/location/"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("tranquility", forHTTPHeaderField: "datasource")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw NetworkError.httpError(statusCode: httpResponse.statusCode)
        }
        
        return try JSONDecoder().decode(CharacterLocation.self, from: data)
    }
}

// 角色位置信息模型
struct CharacterLocation: Codable {
    let solar_system_id: Int
    let structure_id: Int?
} 