import Foundation

class ESIDataManager {
    static let shared = ESIDataManager()
    private let baseURL = "https://esi.evetech.net/latest"
    private let session: URLSession
    
    private init() {
        self.session = URLSession.shared
    }
    
    // 获取钱包余额
    func getWalletBalance(characterId: Int) async throws -> Double {
        Logger.info("ESIDataManager: 开始获取钱包余额，角色ID: \(characterId)")
        
        // 获取有效的访问令牌
        let token = try await EVELogin.shared.getValidToken()
        Logger.info("ESIDataManager: 成功获取有效访问令牌")
        
        // 构建请求URL
        let urlString = "\(baseURL)/characters/\(characterId)/wallet/?datasource=tranquility"
        Logger.info("ESIDataManager: 准备请求URL: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            Logger.error("ESIDataManager: 无法构建钱包API URL")
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        Logger.info("ESIDataManager: 发送钱包余额请求...")
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            Logger.error("ESIDataManager: 响应不是HTTP响应")
            throw NetworkError.invalidResponse
        }
        
        Logger.info("ESIDataManager: 收到响应，状态码: \(httpResponse.statusCode)")
        if httpResponse.statusCode != 200 {
            if let responseString = String(data: data, encoding: .utf8) {
                Logger.error("ESIDataManager: 响应内容: \(responseString)")
            }
            Logger.error("ESIDataManager: 获取钱包余额失败，状态码: \(httpResponse.statusCode)")
            throw NetworkError.httpError(statusCode: httpResponse.statusCode)
        }
        
        let balance = try JSONDecoder().decode(Double.self, from: data)
        Logger.info("ESIDataManager: 成功获取钱包余额: \(balance) ISK")
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