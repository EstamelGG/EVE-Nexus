import Foundation

class ESIDataManager {
    static let shared = ESIDataManager()
    
    private init() {}
    
    // 获取钱包余额
    func getWalletBalance(characterId: Int) async throws -> Double {
        let urlString = "https://esi.evetech.net/latest/characters/\(characterId)/wallet/"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        
        // 从EVELogin获取角色的token
        guard let character = EVELogin.shared.getCharacterByID(characterId) else {
            throw NetworkError.unauthed
        }
        
        var request = URLRequest(url: url)
        request.addValue("Bearer \(character.token.access_token)", forHTTPHeaderField: "Authorization")
        request.addValue("tranquility", forHTTPHeaderField: "datasource")
        
        let data = try await NetworkManager.shared.fetchData(from: url, request: request)
        
        guard let stringValue = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let balance = Double(stringValue) else {
            throw NetworkError.invalidResponse
        }
        return balance
    }
} 
