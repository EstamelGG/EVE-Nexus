import Foundation

// 军团钱包数据模型
struct CorpWallet: Codable {
    let division: Int
    let balance: Double
    var name: String?
}

// 军团部门数据模型
struct CorpDivisions: Codable {
    let hangar: [DivisionInfo]
    let wallet: [DivisionInfo]
}

struct DivisionInfo: Codable {
    let division: Int
    let name: String?
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
        
        // 2. 获取部门信息
        let divisions = try await fetchCorpDivisions(characterId: characterId, forceRefresh: forceRefresh)
        
        // 3. 检查缓存
        let cacheKey = "corp_wallets_\(corporationId)"
        let cacheTimeKey = "corp_wallets_\(corporationId)_time"
        
        if !forceRefresh,
           let cachedData = UserDefaults.standard.data(forKey: cacheKey),
           let lastUpdateTime = UserDefaults.standard.object(forKey: cacheTimeKey) as? Date,
           Date().timeIntervalSince(lastUpdateTime) < 60 * 60 { // 60 分钟缓存
            do {
                var wallets = try JSONDecoder().decode([CorpWallet].self, from: cachedData)
                // 添加部门名称
                for i in 0..<wallets.count {
                    let division = wallets[i].division
                    if let divisionInfo = divisions.wallet.first(where: { $0.division == division }) {
                        wallets[i].name = getDivisionName(division: division, type: "wallet", customName: divisionInfo.name)
                    }
                }
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
        var wallets = try JSONDecoder().decode([CorpWallet].self, from: data)
        
        // 6. 添加部门名称
        for i in 0..<wallets.count {
            let division = wallets[i].division
            if let divisionInfo = divisions.wallet.first(where: { $0.division == division }) {
                wallets[i].name = getDivisionName(division: division, type: "wallet", customName: divisionInfo.name)
            }
        }
        
        // 7. 更新缓存
        UserDefaults.standard.set(data, forKey: cacheKey)
        UserDefaults.standard.set(Date(), forKey: cacheTimeKey)
        
        Logger.info("成功获取军团钱包数据 - 军团ID: \(corporationId)")
        return wallets
    }
    
    /// 获取军团部门信息
    /// - Parameters:
    ///   - characterId: 角色ID
    ///   - forceRefresh: 是否强制刷新缓存
    /// - Returns: 军团部门信息
    func fetchCorpDivisions(characterId: Int, forceRefresh: Bool = false) async throws -> CorpDivisions {
        // 1. 获取角色的军团ID
        guard let corporationId = try await CharacterDatabaseManager.shared.getCharacterCorporationId(characterId: characterId) else {
            throw NetworkError.authenticationError("无法获取军团ID")
        }
        
        // 2. 检查缓存
        let cacheKey = "corp_divisions_\(corporationId)"
        let cacheTimeKey = "corp_divisions_\(corporationId)_time"
        
        if !forceRefresh,
           let cachedData = UserDefaults.standard.data(forKey: cacheKey),
           let lastUpdateTime = UserDefaults.standard.object(forKey: cacheTimeKey) as? Date,
           Date().timeIntervalSince(lastUpdateTime) < 60 * 60 { // 1小时缓存
            do {
                let divisions = try JSONDecoder().decode(CorpDivisions.self, from: cachedData)
                Logger.info("使用缓存的军团部门数据 - 军团ID: \(corporationId)")
                return divisions
            } catch {
                Logger.error("解析缓存的军团部门数据失败: \(error)")
            }
        }
        
        // 3. 构建请求
        let urlString = "https://esi.evetech.net/latest/corporations/\(corporationId)/divisions/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        
        // 4. 发送请求
        let data = try await NetworkManager.shared.fetchDataWithToken(from: url, characterId: characterId)
        let divisions = try JSONDecoder().decode(CorpDivisions.self, from: data)
        
        // 5. 更新缓存
        UserDefaults.standard.set(data, forKey: cacheKey)
        UserDefaults.standard.set(Date(), forKey: cacheTimeKey)
        
        Logger.info("成功获取军团部门数据 - 军团ID: \(corporationId)")
        return divisions
    }
    
    /// 获取部门名称
    /// - Parameters:
    ///   - division: 部门编号
    ///   - type: 部门类型 ("hangar" 或 "wallet")
    ///   - customName: 自定义名称
    /// - Returns: 本地化的部门名称
    func getDivisionName(division: Int, type: String, customName: String?) -> String {
        if let name = customName {
            return name
        }
        
        // 根据类型返回默认名称
        if type == "hangar" {
            return String(format: NSLocalizedString("Main_Corporation_Hangar_Default", comment: ""), division)
        } else {
            return String(format: NSLocalizedString("Main_Corporation_Wallet_Default", comment: ""), division)
        }
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
