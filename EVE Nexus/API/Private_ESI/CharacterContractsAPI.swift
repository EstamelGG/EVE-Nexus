import Foundation

class CharacterContractsAPI {
    static let shared = CharacterContractsAPI()
    
    private let cacheDirectory: URL = {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("ContractsCache")
    }()
    
    private let cacheValidityDuration: TimeInterval = 8 * 3600 // 8小时的缓存有效期
    private let maxConcurrentPages = 3 // 最大并发页数
    
    private init() {
        // 创建缓存目录
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    private func getCacheFilePath(for characterId: Int) -> URL {
        return cacheDirectory.appendingPathComponent("contracts_\(characterId).json")
    }
    
    private func loadFromCache(characterId: Int) -> [ContractInfo]? {
        let cacheFile = getCacheFilePath(for: characterId)
        
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: cacheFile.path),
              let modificationDate = attributes[.modificationDate] as? Date else {
            return nil
        }
        
        // 检查缓存是否过期
        if Date().timeIntervalSince(modificationDate) > cacheValidityDuration {
            Logger.debug("合同缓存已过期 - 角色ID: \(characterId)")
            return nil
        }
        
        do {
            let data = try Data(contentsOf: cacheFile)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let contracts = try decoder.decode([ContractInfo].self, from: data)
            Logger.debug("从缓存加载合同数据成功 - 角色ID: \(characterId), 合同数量: \(contracts.count)")
            return contracts
        } catch {
            Logger.error("读取合同缓存失败 - 角色ID: \(characterId), 错误: \(error)")
            return nil
        }
    }
    
    private func saveToCache(contracts: [ContractInfo], characterId: Int) {
        let cacheFile = getCacheFilePath(for: characterId)
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(contracts)
            try data.write(to: cacheFile)
            Logger.debug("保存合同数据到缓存成功 - 角色ID: \(characterId), 合同数量: \(contracts.count)")
        } catch {
            Logger.error("保存合同缓存失败 - 角色ID: \(characterId), 错误: \(error)")
        }
    }
    
    private func fetchContractsPage(characterId: Int, page: Int) async throws -> [ContractInfo] {
        let url = URL(string: "https://esi.evetech.net/latest/characters/\(characterId)/contracts/?datasource=tranquility&page=\(page)")!
        
        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId,
            noRetryKeywords: ["Requested page does not exist"]
        )
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        return try decoder.decode([ContractInfo].self, from: data)
    }
    
    func fetchContracts(characterId: Int, forceRefresh: Bool = false) async throws -> [ContractInfo] {
        // 如果不是强制刷新，尝试从缓存加载
        if !forceRefresh {
            if let cachedContracts = loadFromCache(characterId: characterId) {
                return cachedContracts
            }
        }
        
        var allContracts: [ContractInfo] = []
        var currentPage = 1
        
        while true {
            do {
                // 创建并发任务组
                var tasks: [Task<[ContractInfo], Error>] = []
                
                // 创建最多maxConcurrentPages个并发任务
                for page in currentPage...(currentPage + maxConcurrentPages - 1) {
                    let task = Task {
                        try await fetchContractsPage(characterId: characterId, page: page)
                    }
                    tasks.append(task)
                }
                
                // 等待所有任务完成或出错
                var shouldBreak = false
                for task in tasks {
                    do {
                        let contracts = try await task.value
                        allContracts.append(contentsOf: contracts)
                    } catch {
                        // 如果是页面不存在错误，标记退出循环
                        if let networkError = error as? NetworkError,
                           case .httpError(_, let message) = networkError,
                           message?.contains("Requested page does not exist") == true {
                            shouldBreak = true
                            break
                        }
                        // 其他错误则抛出
                        throw error
                    }
                }
                
                if shouldBreak {
                    break
                }
                
                currentPage += maxConcurrentPages
                
            } catch {
                // 如果是页面不存在错误，结束循环
                if let networkError = error as? NetworkError,
                   case .httpError(_, let message) = networkError,
                   message?.contains("Requested page does not exist") == true {
                    break
                }
                throw error
            }
        }
        
        // 按合同ID排序，确保顺序一致
        allContracts.sort { $0.contract_id > $1.contract_id }
        
        // 保存到缓存
        saveToCache(contracts: allContracts, characterId: characterId)
        
        return allContracts
    }
    
    // 清除指定角色的缓存
    func clearCache(for characterId: Int) {
        let cacheFile = getCacheFilePath(for: characterId)
        try? FileManager.default.removeItem(at: cacheFile)
        Logger.debug("清除合同缓存 - 角色ID: \(characterId)")
    }
    
    // 清除所有缓存
    func clearAllCache() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        Logger.debug("清除所有合同缓存")
    }
}

// 合同信息模型
struct ContractInfo: Codable, Identifiable {
    let acceptor_id: Int?
    let assignee_id: Int?
    let availability: String
    let collateral: Double
    let contract_id: Int
    let date_accepted: Date?
    let date_completed: Date?
    let date_expired: Date
    let date_issued: Date
    let days_to_complete: Int
    let end_location_id: Int64
    let for_corporation: Bool
    let issuer_corporation_id: Int
    let issuer_id: Int
    let price: Double
    let reward: Double
    let start_location_id: Int64
    let status: String
    let title: String
    let type: String
    let volume: Double
    
    var id: Int { contract_id }
} 