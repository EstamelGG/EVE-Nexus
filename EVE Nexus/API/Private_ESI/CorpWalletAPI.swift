import Foundation

// 军团钱包数据模型
struct CorpWallet: Codable {
    let division: Int
    let balance: Double
}

@globalActor actor CorpWalletAPIActor {
    static let shared = CorpWalletAPIActor()
}

@CorpWalletAPIActor
class CorpWalletAPI {
    static let shared = CorpWalletAPI()
    
    private init() {}
    
    /// 获取军团钱包信息
    /// - Parameters:
    ///   - characterId: 角色ID
    ///   - forceRefresh: 是否强制刷新缓存
    /// - Returns: 军团钱包数组
    func fetchCorpWallets(characterId: Int, forceRefresh: Bool = false) async throws -> [CorpWallet] {
        // 1. 获取角色的军团ID
        guard let corporationId = try await CharacterDatabaseManager.shared.getCharacterCorporationId(characterId: characterId) else {
            throw NetworkError.authenticationError("无法获取军团ID")
        }
        
        // 3. 检查缓存
        let cacheKey = "corp_wallets_\(corporationId)"
        let cacheTimeKey = "corp_wallets_\(corporationId)_time"
        
        if !forceRefresh,
           let cachedData = UserDefaults.standard.data(forKey: cacheKey),
           let lastUpdateTime = UserDefaults.standard.object(forKey: cacheTimeKey) as? Date,
           Date().timeIntervalSince(lastUpdateTime) < 5 * 60 { // 5分钟缓存
            do {
                let wallets = try JSONDecoder().decode([CorpWallet].self, from: cachedData)
                Logger.info("使用缓存的军团钱包数据 - 军团ID: \(corporationId)")
                return wallets
            } catch {
                Logger.error("解析缓存的军团钱包数据失败: \(error)")
            }
        }
        
        // 4. 构建请求
        let urlString = "https://esi.evetech.net/latest/corporations/\(corporationId)/wallets/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        // 5. 发送请求
        let data = try await NetworkManager.shared.fetchDataWithToken(from: url, characterId: characterId)
        let wallets = try JSONDecoder().decode([CorpWallet].self, from: data)
        
        // 6. 更新缓存
        UserDefaults.standard.set(data, forKey: cacheKey)
        UserDefaults.standard.set(Date(), forKey: cacheTimeKey)
        
        Logger.info("成功获取军团钱包数据 - 军团ID: \(corporationId)")
        return wallets
    }
    
    /// 清理缓存
    func clearCache() {
        let defaults = UserDefaults.standard
        let allKeys = defaults.dictionaryRepresentation().keys
        
        // 清理所有军团钱包相关的缓存
        for key in allKeys {
            if key.hasPrefix("corp_wallets_") {
                defaults.removeObject(forKey: key)
            }
        }
        
        Logger.info("已清理军团钱包缓存")
    }
} 
