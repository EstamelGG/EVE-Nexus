import Foundation

class ESIDataManager {
    static let shared = ESIDataManager()
    
    private init() {}
    
    // 获取钱包余额
    func getWalletBalance(characterId: Int) async throws -> Double {
        let data: Data = try await NetworkManager.shared.fetchDataWithToken(
            characterId: characterId,
            endpoint: "/characters/\(characterId)/wallet/"
        )
        
        guard let stringValue = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let balance = Double(stringValue) else {
            throw NetworkError.invalidResponse
        }
        return balance
    }
} 
