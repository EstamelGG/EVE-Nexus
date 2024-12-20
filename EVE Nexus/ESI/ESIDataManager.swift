import Foundation

class ESIDataManager {
    static let shared = ESIDataManager()
    private let baseURL = "https://esi.evetech.net/latest"
    private let session: URLSession
    
    private init() {
        self.session = URLSession.shared
    }
    
    // 获取钱包余额
    func getWalletBalance(characterId: Int, token: String) async throws -> Double {
        let urlString = "\(baseURL)/characters/\(characterId)/wallet/"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw NetworkError.httpError(statusCode: httpResponse.statusCode)
        }
        
        guard let balanceString = String(data: data, encoding: .utf8),
              let balance = Double(balanceString) else {
            throw NetworkError.invalidData
        }
        
        return balance
    }
    
    // 格式化 ISK 金额
    func formatISK(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "0.00"
    }
} 
