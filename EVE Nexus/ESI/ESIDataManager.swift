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
        request.timeoutInterval = 30 // 设置30秒超时
        request.cachePolicy = .reloadIgnoringLocalCacheData // 忽略缓存，直接从服务器获取数据
        
        let data = try await NetworkManager.shared.fetchData(from: url, request: request)
        guard let stringValue = String(data: data, encoding: .utf8),
              let balance = Double(stringValue) else {
            throw NetworkError.invalidResponse
        }
        return balance
    }
} 
