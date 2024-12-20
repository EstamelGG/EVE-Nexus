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
        
        // 保存到本地文件
        let fileURL = StaticResourceManager.shared.getStaticDataSetPath()
            .appendingPathComponent("Characters")
            .appendingPathComponent("\(characterId)")
            .appendingPathComponent("wallet.json")
        
        let walletData = ["balance": balance, "timestamp": Date().timeIntervalSince1970]
        let encodedData = try JSONEncoder().encode(walletData)
        
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), 
                                               withIntermediateDirectories: true)
        try encodedData.write(to: fileURL)
        
        return balance
    }
    
    // 从本地文件加载钱包余额
    func loadWalletBalance(characterId: Int) -> Double? {
        let fileURL = StaticResourceManager.shared.getStaticDataSetPath()
            .appendingPathComponent("Characters")
            .appendingPathComponent("\(characterId)")
            .appendingPathComponent("wallet.json")
            
        guard let data = try? Data(contentsOf: fileURL),
              let walletData = try? JSONDecoder().decode([String: Double].self, from: data) else {
            return nil
        }
        
        return walletData["balance"]
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
