import Foundation

class CharacterContractsAPI {
    static let shared = CharacterContractsAPI()
    
    private let cacheDirectory: URL = {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("ContractsCache")
    }()
    
    private let cacheValidityDuration: TimeInterval = 8 * 3600 // 8 小时的缓存有效期
    private let maxConcurrentPages = 2 // 最大并发页数
    
    private init() {
        // 创建缓存目录
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    private func getCacheFilePath(for characterId: Int) -> URL {
        return cacheDirectory.appendingPathComponent("contracts_\(characterId).json")
    }
    
    private func loadFromCache(characterId: Int) -> [ContractInfo]? {
        let cacheFile = getCacheFilePath(for: characterId)
        
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
        var shouldRefreshInBackground = false
        
        // 尝试从缓存加载
        if let cachedContracts = loadFromCache(characterId: characterId) {
            // 检查缓存是否过期
            if let attributes = try? FileManager.default.attributesOfItem(atPath: getCacheFilePath(for: characterId).path),
               let modificationDate = attributes[.modificationDate] as? Date {
                if Date().timeIntervalSince(modificationDate) > cacheValidityDuration {
                    shouldRefreshInBackground = true
                }
            }
            
            if !forceRefresh {
                // 如果缓存过期，启动后台刷新
                if shouldRefreshInBackground {
                    Task {
                        do {
                            let newContracts = try await fetchContractsFromServer(characterId: characterId)
                            // 合并新旧合同并去重
                            var mergedContracts = Set(cachedContracts).union(newContracts)
                            let finalContracts = Array(mergedContracts).sorted { $0.contract_id > $1.contract_id }
                            // 更新缓存
                            saveToCache(contracts: finalContracts, characterId: characterId)
                            // 发送通知以刷新UI
                            NotificationCenter.default.post(name: NSNotification.Name("ContractsUpdated"), object: nil, userInfo: ["characterId": characterId])
                        } catch {
                            Logger.error("后台更新合同数据失败 - 角色ID: \(characterId), 错误: \(error)")
                        }
                    }
                }
                return cachedContracts
            }
        }
        
        // 如果没有缓存或强制刷新，直接从服务器获取
        return try await fetchContractsFromServer(characterId: characterId)
    }
    
    private func fetchContractsFromServer(characterId: Int) async throws -> [ContractInfo] {
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
    
    // 合同物品信息模型
    struct ContractItemInfo: Codable, Identifiable {
        let is_included: Bool
        let is_singleton: Bool
        let quantity: Int
        let record_id: Int64
        let type_id: Int
        let raw_quantity: Int?
        
        var id: Int64 { record_id }
    }
    
    // 获取合同物品的缓存文件路径
    private func getItemsCacheFilePath(characterId: Int, contractId: Int) -> URL {
        return cacheDirectory.appendingPathComponent("contracts_\(characterId)_\(contractId)_items.json")
    }
    
    // 从缓存加载合同物品
    private func loadItemsFromCache(characterId: Int, contractId: Int) -> [ContractItemInfo]? {
        let cacheFile = getItemsCacheFilePath(characterId: characterId, contractId: contractId)
        
        do {
            let data = try Data(contentsOf: cacheFile)
            let decoder = JSONDecoder()
            let items = try decoder.decode([ContractItemInfo].self, from: data)
            Logger.debug("从缓存加载合同物品成功 - 角色ID: \(characterId), 合同ID: \(contractId), 物品数量: \(items.count)")
            return items
        } catch {
            Logger.error("读取合同物品缓存失败 - 角色ID: \(characterId), 合同ID: \(contractId), 错误: \(error)")
            return nil
        }
    }
    
    // 保存合同物品到缓存
    private func saveItemsToCache(items: [ContractItemInfo], characterId: Int, contractId: Int) {
        let cacheFile = getItemsCacheFilePath(characterId: characterId, contractId: contractId)
        
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(items)
            try data.write(to: cacheFile)
            Logger.debug("保存合同物品到缓存成功 - 角色ID: \(characterId), 合同ID: \(contractId), 物品数量: \(items.count)")
        } catch {
            Logger.error("保存合同物品缓存失败 - 角色ID: \(characterId), 合同ID: \(contractId), 错误: \(error)")
        }
    }
    
    // 获取合同物品列表
    func fetchContractItems(characterId: Int, contractId: Int, forceRefresh: Bool = false) async throws -> [ContractItemInfo] {
        // 如果不是强制刷新，尝试从缓存加载
        if !forceRefresh {
            if let cachedItems = loadItemsFromCache(characterId: characterId, contractId: contractId) {
                return cachedItems
            }
        }
        
        let url = URL(string: "https://esi.evetech.net/latest/characters/\(characterId)/contracts/\(contractId)/items/?datasource=tranquility")!
        
        let data = try await NetworkManager.shared.fetchDataWithToken(from: url, characterId: characterId)
        
        let decoder = JSONDecoder()
        let items = try decoder.decode([ContractItemInfo].self, from: data)
        
        // 保存到缓存
        saveItemsToCache(items: items, characterId: characterId, contractId: contractId)
        
        return items
    }
    
    // 清除指定合同的物品缓存
    func clearItemsCache(for characterId: Int, contractId: Int) {
        let cacheFile = getItemsCacheFilePath(characterId: characterId, contractId: contractId)
        try? FileManager.default.removeItem(at: cacheFile)
        Logger.debug("清除合同物品缓存 - 角色ID: \(characterId), 合同ID: \(contractId)")
    }
}

// 合同信息模型
struct ContractInfo: Codable, Identifiable, Hashable {
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
    
    // 实现 Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(contract_id)
    }
    
    static func == (lhs: ContractInfo, rhs: ContractInfo) -> Bool {
        return lhs.contract_id == rhs.contract_id
    }
} 
