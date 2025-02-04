import Foundation

class CorporationContractsAPI {
    static let shared = CorporationContractsAPI()
    
    // 通知名称常量
    static let contractsUpdatedNotification = "CorporationContractsUpdatedNotification"
    static let contractsUpdatedCorporationIdKey = "CorporationId"
    
    private let cacheDirectory: URL = {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("CorporationContractsCache")
    }()
    
    private let maxConcurrentPages = 2 // 最大并发页数
    private let cacheTimeout: TimeInterval = 8 * 3600 // 8小时缓存有效期
    
    private let lastContractsQueryKey = "LastCorporationContractsQuery_"
    private let lastContractItemsQueryKey = "LastCorporationContractItemsQuery_"
    
    private init() {
        // 创建缓存目录
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    private func getCacheFilePath(for corporationId: Int) -> URL {
        return cacheDirectory.appendingPathComponent("contracts_\(corporationId).json")
    }
    
    private func loadFromCache(corporationId: Int) -> [ContractInfo]? {
        let cacheFile = getCacheFilePath(for: corporationId)
        
        do {
            let data = try Data(contentsOf: cacheFile)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let contracts = try decoder.decode([ContractInfo].self, from: data)
            Logger.debug("从缓存加载军团合同数据成功 - 军团ID: \(corporationId), 合同数量: \(contracts.count)")
            return contracts
        } catch {
            Logger.error("读取军团合同缓存失败 - 军团ID: \(corporationId), 错误: \(error)")
            return nil
        }
    }
    
    private func saveToCache(contracts: [ContractInfo], corporationId: Int) {
        let cacheFile = getCacheFilePath(for: corporationId)
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(contracts)
            try data.write(to: cacheFile)
            Logger.debug("保存军团合同数据到缓存成功 - 军团ID: \(corporationId), 合同数量: \(contracts.count)")
        } catch {
            Logger.error("保存军团合同缓存失败 - 军团ID: \(corporationId), 错误: \(error)")
        }
    }
    
    private func fetchContractsPage(corporationId: Int, characterId: Int, page: Int) async throws -> [ContractInfo] {
        let url = URL(string: "https://esi.evetech.net/latest/corporations/\(corporationId)/contracts/?datasource=tranquility&page=\(page)")!
        
        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId,  // 使用角色ID获取token
            noRetryKeywords: ["Requested page does not exist"]
        )
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        return try decoder.decode([ContractInfo].self, from: data)
    }
    
    private func fetchContractItemsFromServer(corporationId: Int, contractId: Int, characterId: Int) async throws -> [ContractItemInfo] {
        let url = URL(string: "https://esi.evetech.net/latest/corporations/\(corporationId)/contracts/\(contractId)/items/?datasource=tranquility")!
        
        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId  // 使用角色ID获取token
        )
        
        let decoder = JSONDecoder()
        return try decoder.decode([ContractItemInfo].self, from: data)
    }
    
    // 获取最后查询时间
    private func getLastQueryTime(corporationId: Int, isItems: Bool = false) -> Date? {
        let key = isItems ? lastContractItemsQueryKey + String(corporationId) : lastContractsQueryKey + String(corporationId)
        return UserDefaults.standard.object(forKey: key) as? Date
    }
    
    // 更新最后查询时间
    private func updateLastQueryTime(corporationId: Int, isItems: Bool = false) {
        let key = isItems ? lastContractItemsQueryKey + String(corporationId) : lastContractsQueryKey + String(corporationId)
        UserDefaults.standard.set(Date(), forKey: key)
    }
    
    // 检查是否需要刷新数据
    private func shouldRefreshData(corporationId: Int, isItems: Bool = false) -> Bool {
        guard let lastQueryTime = getLastQueryTime(corporationId: corporationId, isItems: isItems) else {
            return true
        }
        
        let timeSinceLastQuery = Date().timeIntervalSince(lastQueryTime)
        return timeSinceLastQuery >= cacheTimeout
    }
    
    // 从服务器获取合同列表
    private func fetchContractsFromServer(corporationId: Int, characterId: Int) async throws -> [ContractInfo] {
        var allContracts: [ContractInfo] = []
        var currentPage = 1
        var shouldContinue = true
        
        while shouldContinue {
            do {
                let pageContracts = try await fetchContractsPage(corporationId: corporationId, characterId: characterId, page: currentPage)
                if pageContracts.isEmpty {
                    shouldContinue = false
                } else {
                    allContracts.append(contentsOf: pageContracts)
                    currentPage += 1
                }
                if currentPage >= 1000 { // 最多取1000页
                    shouldContinue = false
                    break
                }
            } catch let error as NetworkError {
                if case .httpError(_, let message) = error,
                   message?.contains("Requested page does not exist") == true {
                    shouldContinue = false
                } else {
                    throw error
                }
            }
        }
        
        // 更新最后查询时间
        updateLastQueryTime(corporationId: corporationId)
        
        // 保存到缓存
        saveToCache(contracts: allContracts, corporationId: corporationId)
        
        // 发送数据更新通知
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Notification.Name(CorporationContractsAPI.contractsUpdatedNotification),
                object: nil,
                userInfo: [CorporationContractsAPI.contractsUpdatedCorporationIdKey: corporationId]
            )
        }
        
        Logger.debug("成功从服务器获取军团合同数据 - 军团ID: \(corporationId), 合同数量: \(allContracts.count)")
        
        return allContracts
    }
    
    // 获取合同列表（公开方法）
    public func fetchContracts(characterId: Int, forceRefresh: Bool = false) async throws -> [ContractInfo] {
        // 1. 获取角色的军团ID
        guard let corporationId = try await CharacterDatabaseManager.shared.getCharacterCorporationId(characterId: characterId) else {
            throw NetworkError.authenticationError("无法获取军团ID")
        }
        
        if forceRefresh || shouldRefreshData(corporationId: corporationId) {
            return try await fetchContractsFromServer(corporationId: corporationId, characterId: characterId)
        }
        
        // 尝试从缓存加载
        if let cachedContracts = loadFromCache(corporationId: corporationId) {
            return cachedContracts
        }
        
        // 缓存不存在，从服务器获取
        return try await fetchContractsFromServer(corporationId: corporationId, characterId: characterId)
    }
    
    // 获取合同物品（公开方法）
    public func fetchContractItems(contractId: Int, characterId: Int) async throws -> [ContractItemInfo] {
        // 获取角色的军团ID
        guard let corporationId = try await CharacterDatabaseManager.shared.getCharacterCorporationId(characterId: characterId) else {
            throw NetworkError.authenticationError("无法获取军团ID")
        }
        
        return try await fetchContractItemsFromServer(corporationId: corporationId, contractId: contractId, characterId: characterId)
    }
    
    // 清除指定军团的缓存
    func clearCache(for corporationId: Int) {
        let cacheFile = getCacheFilePath(for: corporationId)
        try? FileManager.default.removeItem(at: cacheFile)
        Logger.debug("清除军团合同缓存 - 军团ID: \(corporationId)")
    }
    
    // 清除所有缓存
    func clearAllCache() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        Logger.debug("清除所有军团合同缓存")
    }
}