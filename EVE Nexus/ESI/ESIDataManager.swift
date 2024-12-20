import Foundation

class ESIDataManager {
    static let shared = ESIDataManager()
    
    private init() {}
    
    // 获取钱包余额
    func getWalletBalance(characterId: Int, token: String) async throws -> Double {
        let urlString = "https://esi.evetech.net/latest/characters/\(characterId)/wallet/"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("tranquility", forHTTPHeaderField: "datasource")
        
        let data = try await NetworkManager.shared.fetchData(from: url, request: request)
        return try JSONDecoder().decode(Double.self, from: data)
    }
} 
