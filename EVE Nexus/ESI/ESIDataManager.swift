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
        
        let data: Data = try await NetworkManager.shared.fetchDataWithToken(
            characterId: characterId,
            endpoint: "/characters/\(characterId)/wallet/"
        )
        
        guard let stringValue = String(data: data, encoding: .utf8),
              let balance = Double(stringValue) else {
            throw NetworkError.invalidResponse
        }
        return balance
    }
} 
