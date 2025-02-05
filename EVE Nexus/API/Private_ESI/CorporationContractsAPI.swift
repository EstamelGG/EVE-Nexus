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
    private func fetchContractsFromServer(corporationId: Int, characterId: Int, progressCallback: ((Int) -> Void)? = nil) async throws -> [ContractInfo] {
        var allContracts: [ContractInfo] = []
        var currentPage = 1
        var shouldContinue = true
        
        while shouldContinue {
            do {
                progressCallback?(currentPage)
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
    
    // 从数据库获取合同列表
    private func getContractsFromDB(corporationId: Int) async -> [ContractInfo]? {
        let query = """
            SELECT contract_id, acceptor_id, assignee_id, availability,
                   buyout, collateral, date_accepted, date_completed, date_expired,
                   date_issued, days_to_complete, end_location_id,
                   for_corporation, issuer_corporation_id, issuer_id,
                   price, reward, start_location_id, status, title,
                   type, volume
            FROM corporation_contracts 
            WHERE corporation_id = ?
            ORDER BY date_issued DESC
        """
        
        if case .success(let results) = CharacterDatabaseManager.shared.executeQuery(query, parameters: [corporationId]) {
            Logger.debug("数据库查询成功，获取到\(results.count)行数据")
            
            let contracts = results.compactMap { row -> ContractInfo? in
                let dateFormatter = ISO8601DateFormatter()
                
                let contractId: Int
                if let id = row["contract_id"] as? Int64 {
                    contractId = Int(id)
                } else if let id = row["contract_id"] as? Int {
                    contractId = id
                } else {
                    Logger.error("contract_id 无效或类型不匹配")
                    return nil
                }
                
                // 检查必需的日期字段
                guard let dateIssuedStr = row["date_issued"] as? String else {
                    Logger.error("date_issued 为空")
                    return nil
                }
                
                guard let dateExpiredStr = row["date_expired"] as? String else {
                    Logger.error("date_expired 为空")
                    return nil
                }
                
                // 解析日期
                guard let dateIssued = dateFormatter.date(from: dateIssuedStr),
                      let dateExpired = dateFormatter.date(from: dateExpiredStr) else {
                    Logger.error("日期解析失败")
                    return nil
                }
                
                // 解析可选日期
                let dateAccepted = (row["date_accepted"] as? String).flatMap { dateFormatter.date(from: $0) }
                let dateCompleted = (row["date_completed"] as? String).flatMap { dateFormatter.date(from: $0) }
                
                // 获取location IDs
                let startLocationId: Int64
                if let id = row["start_location_id"] as? Int64 {
                    startLocationId = id
                } else if let id = row["start_location_id"] as? Int {
                    startLocationId = Int64(id)
                } else {
                    Logger.error("start_location_id 无效或类型不匹配")
                    return nil
                }
                
                let endLocationId: Int64
                if let id = row["end_location_id"] as? Int64 {
                    endLocationId = id
                } else if let id = row["end_location_id"] as? Int {
                    endLocationId = Int64(id)
                } else {
                    Logger.error("end_location_id 无效或类型不匹配")
                    return nil
                }
                
                // 获取acceptor_id和assignee_id（可选）
                let acceptorId: Int?
                if let id = row["acceptor_id"] as? Int64 {
                    acceptorId = Int(id)
                } else if let id = row["acceptor_id"] as? Int {
                    acceptorId = id
                } else {
                    acceptorId = nil
                }
                
                let assigneeId: Int?
                if let id = row["assignee_id"] as? Int64 {
                    assigneeId = Int(id)
                } else if let id = row["assignee_id"] as? Int {
                    assigneeId = id
                } else {
                    assigneeId = nil
                }
                
                // 获取issuer_id
                let issuerId: Int
                if let id = row["issuer_id"] as? Int64 {
                    issuerId = Int(id)
                } else if let id = row["issuer_id"] as? Int {
                    issuerId = id
                } else {
                    Logger.error("issuer_id 无效或类型不匹配")
                    return nil
                }
                
                // 获取issuer_corporation_id
                let issuerCorpId: Int
                if let id = row["issuer_corporation_id"] as? Int64 {
                    issuerCorpId = Int(id)
                } else if let id = row["issuer_corporation_id"] as? Int {
                    issuerCorpId = id
                } else {
                    Logger.error("issuer_corporation_id 无效或类型不匹配")
                    return nil
                }
                
                return ContractInfo(
                    acceptor_id: acceptorId,
                    assignee_id: assigneeId,
                    availability: row["availability"] as? String ?? "",
                    buyout: row["buyout"] as? Double,
                    collateral: row["collateral"] as? Double,
                    contract_id: contractId,
                    date_accepted: dateAccepted,
                    date_completed: dateCompleted,
                    date_expired: dateExpired,
                    date_issued: dateIssued,
                    days_to_complete: row["days_to_complete"] as? Int ?? 0,
                    end_location_id: endLocationId,
                    for_corporation: (row["for_corporation"] as? Int ?? 0) != 0,
                    issuer_corporation_id: issuerCorpId,
                    issuer_id: issuerId,
                    price: row["price"] as? Double ?? 0.0,
                    reward: row["reward"] as? Double ?? 0.0,
                    start_location_id: startLocationId,
                    status: row["status"] as? String ?? "",
                    title: row["title"] as? String ?? "",
                    type: row["type"] as? String ?? "",
                    volume: row["volume"] as? Double ?? 0.0
                )
            }
            
            Logger.debug("成功转换\(contracts.count)个合同数据")
            return contracts
        }
        Logger.error("数据库查询失败")
        return nil
    }
    
    // 保存合同列表到数据库
    private func saveContractsToDB(corporationId: Int, contracts: [ContractInfo]) -> Bool {
        // 过滤只保存指定给自己公司且未删除的合同
        let filteredContracts = contracts.filter { contract in
            contract.assignee_id == corporationId && contract.status != "deleted"
        }
        Logger.debug("过滤后需要保存的合同数量: \(filteredContracts.count) / \(contracts.count) (已排除指定给其他公司和已删除的合同)")
        
        // 获取已存在的合同ID和状态
        let checkQuery = "SELECT contract_id, status FROM corporation_contracts WHERE corporation_id = ?"
        var newCount = 0
        var updateCount = 0
        let dateFormatter = ISO8601DateFormatter()
        
        // 获取数据库中现有的合同状态
        guard case .success(let existingResults) = CharacterDatabaseManager.shared.executeQuery(checkQuery, parameters: [corporationId]) else {
            Logger.error("查询现有合同失败")
            return false
        }
        
        // 构建现有合同状态的字典，方便查找
        var existingContracts: [Int: String] = [:]
        for row in existingResults {
            if let contractId = row["contract_id"] as? Int64,
               let status = row["status"] as? String {
                existingContracts[Int(contractId)] = status
            }
        }
        
        let insertSQL = """
            INSERT OR REPLACE INTO corporation_contracts (
                contract_id, corporation_id, status, acceptor_id, assignee_id,
                availability, buyout, collateral, date_accepted, date_completed,
                date_expired, date_issued, days_to_complete,
                end_location_id, for_corporation, issuer_corporation_id,
                issuer_id, price, reward, start_location_id,
                title, type, volume, items_fetched
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        
        for contract in filteredContracts {
            // 检查合同是否存在及其状态
            if let existingStatus = existingContracts[contract.contract_id] {
                // 如果状态没有变化，跳过
                if existingStatus == contract.status {
                    Logger.debug("跳过状态未变化的合同 - ID: \(contract.contract_id), 状态: \(contract.status)")
                    continue
                }
                Logger.debug("合同状态已更新 - ID: \(contract.contract_id), 旧状态: \(existingStatus), 新状态: \(contract.status)")
                updateCount += 1
            } else {
                // 新合同
                newCount += 1
            }
            
            // 处理可选日期
            let dateAccepted = contract.date_accepted.map { dateFormatter.string(from: $0) } ?? ""
            let dateCompleted = contract.date_completed.map { dateFormatter.string(from: $0) } ?? ""
            
            let parameters: [Any] = [
                contract.contract_id,
                corporationId,
                contract.status,
                contract.acceptor_id ?? 0,
                contract.assignee_id ?? 0,
                contract.availability,
                contract.buyout ?? 0,
                contract.collateral ?? 0,
                dateAccepted,
                dateCompleted,
                dateFormatter.string(from: contract.date_expired),
                dateFormatter.string(from: contract.date_issued),
                contract.days_to_complete,
                Int(contract.end_location_id),
                contract.for_corporation ? 1 : 0,
                contract.issuer_corporation_id,
                contract.issuer_id,
                contract.price,
                contract.reward,
                Int(contract.start_location_id),
                contract.title,
                contract.type,
                contract.volume,
                0  // 状态变化时重置items_fetched
            ]
            
            if case .error(let message) = CharacterDatabaseManager.shared.executeQuery(insertSQL, parameters: parameters) {
                Logger.error("保存合同到数据库失败: \(message)")
                return false
            }
            Logger.debug("成功\(newCount > 0 ? "插入" : "更新")合同 - ID: \(contract.contract_id), 状态: \(contract.status)")
        }
        
        if newCount > 0 || updateCount > 0 {
            Logger.info("数据库更新：新增\(newCount)个合同，更新\(updateCount)个合同状态")
        } else {
            Logger.debug("没有需要更新的合同数据")
        }
        return true
    }
    
    // 从数据库获取合同物品
    private func getContractItemsFromDB(corporationId: Int, contractId: Int) -> [ContractItemInfo]? {
        let query = """
            SELECT record_id, is_included, is_singleton,
                   quantity, type_id, raw_quantity
            FROM contract_items 
            WHERE contract_id = ?
            ORDER BY record_id ASC
        """
        
        if case .success(let results) = CharacterDatabaseManager.shared.executeQuery(query, parameters: [contractId]) {
            Logger.debug("数据库查询成功，获取到\(results.count)行数据")
            return results.compactMap { row -> ContractItemInfo? in
                // 获取type_id
                let typeId: Int
                if let id = row["type_id"] as? Int64 {
                    typeId = Int(id)
                } else if let id = row["type_id"] as? Int {
                    typeId = id
                } else {
                    Logger.error("type_id 无效或类型不匹配")
                    return nil
                }
                
                // 获取quantity
                let quantity: Int
                if let q = row["quantity"] as? Int64 {
                    quantity = Int(q)
                } else if let q = row["quantity"] as? Int {
                    quantity = q
                } else {
                    Logger.error("quantity 无效或类型不匹配")
                    return nil
                }
                
                // 获取record_id
                guard let recordId = row["record_id"] as? Int64 else {
                    Logger.error("record_id 无效或类型不匹配")
                    return nil
                }
                
                // 获取 is_included
                let isIncluded: Bool
                if let included = row["is_included"] as? Int64 {
                    isIncluded = included != 0
                } else if let included = row["is_included"] as? Int {
                    isIncluded = included != 0
                } else {
                    Logger.error("is_included 无效或类型不匹配")
                    isIncluded = false
                }
                
                return ContractItemInfo(
                    is_included: isIncluded,
                    is_singleton: (row["is_singleton"] as? Int ?? 0) != 0,
                    quantity: quantity,
                    record_id: recordId,
                    type_id: typeId,
                    raw_quantity: row["raw_quantity"] as? Int
                )
            }
        }
        return nil
    }
    
    // 保存合同物品到数据库
    private func saveContractItemsToDB(corporationId: Int, contractId: Int, items: [ContractItemInfo]) -> Bool {
        var success = true
        let insertSQL = """
            INSERT OR REPLACE INTO contract_items (
                record_id, contract_id, is_included, is_singleton,
                quantity, type_id, raw_quantity
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
        """
        
        for item in items {
            let rawQuantity = item.raw_quantity ?? item.quantity
            let recordId = item.record_id
            
            let parameters: [Any] = [
                recordId,
                contractId,
                item.is_included ? 1 : 0,
                item.is_singleton ? 1 : 0,
                item.quantity,
                item.type_id,
                rawQuantity
            ]
            
            Logger.debug("插入物品 - 记录ID: \(recordId), 合同ID: \(contractId), 类型ID: \(item.type_id), 数量: \(item.quantity)")
            if case .error(let message) = CharacterDatabaseManager.shared.executeQuery(insertSQL, parameters: parameters) {
                Logger.error("保存合同物品到数据库失败: \(message), 参数: \(parameters)")
                success = false
            }
        }
        
        if success {
            Logger.info("成功保存\(items.count)个合同物品到数据库，合同ID: \(contractId)")
        } else {
            Logger.error("保存合同物品时发生错误，合同ID: \(contractId)")
        }
        return success
    }
    
    // 获取合同列表（公开方法）
    public func fetchContracts(characterId: Int, forceRefresh: Bool = false, progressCallback: ((Int) -> Void)? = nil) async throws -> [ContractInfo] {
        // 1. 获取角色的军团ID
        guard let corporationId = try await CharacterDatabaseManager.shared.getCharacterCorporationId(characterId: characterId) else {
            throw NetworkError.authenticationError("无法获取军团ID")
        }
        
        // 2. 检查数据库中是否有数据
        let checkQuery = "SELECT COUNT(*) as count FROM corporation_contracts WHERE corporation_id = ?"
        let result = CharacterDatabaseManager.shared.executeQuery(checkQuery, parameters: [corporationId])
        let isEmpty = if case .success(let rows) = result,
                        let row = rows.first,
                        let count = row["count"] as? Int64 {
            count == 0
        } else {
            true
        }
        
        // 3. 如果数据为空或强制刷新，则从网络获取
        if isEmpty || forceRefresh {
            Logger.debug("军团合同数据为空或强制刷新，从网络获取数据")
            let contracts = try await fetchContractsFromServer(corporationId: corporationId, characterId: characterId, progressCallback: progressCallback)
            if !saveContractsToDB(corporationId: corporationId, contracts: contracts) {
                Logger.error("保存军团合同到数据库失败")
            }
            // 过滤出指定给自己公司且未删除的合同
            let filteredContracts = contracts.filter { contract in
                contract.assignee_id == corporationId && contract.status != "deleted"
            }
            Logger.debug("从服务器获取的合同数量: \(contracts.count)，过滤后数量: \(filteredContracts.count) (已排除指定给其他公司和已删除的合同)")
            return filteredContracts
        }
        
        // 4. 从数据库获取数据并返回
        if let contracts = await getContractsFromDB(corporationId: corporationId) {
            // 不需要再次过滤，因为数据库中已经只有指定给自己公司且未删除的合同
            return contracts
        }
        return []
    }
    
    // 获取合同物品（公开方法）
    public func fetchContractItems(characterId: Int, contractId: Int) async throws -> [ContractItemInfo] {
        Logger.debug("开始获取军团合同物品 - 角色ID: \(characterId), 合同ID: \(contractId)")
        
        // 获取角色的军团ID
        guard let corporationId = try await CharacterDatabaseManager.shared.getCharacterCorporationId(characterId: characterId) else {
            throw NetworkError.authenticationError("无法获取军团ID")
        }
        
        // 检查数据库中是否有数据
        if let items = getContractItemsFromDB(corporationId: corporationId, contractId: contractId) {
            if !items.isEmpty {
                Logger.debug("从数据库获取到\(items.count)个军团合同物品")
                return items
            }
        }
        
        // 从服务器获取数据
        Logger.debug("从服务器获取军团合同物品")
        let items = try await fetchContractItemsFromServer(corporationId: corporationId, contractId: contractId, characterId: characterId)
        Logger.debug("从服务器获取到\(items.count)个军团合同物品")
        
        // 保存到数据库
        if !saveContractItemsToDB(corporationId: corporationId, contractId: contractId, items: items) {
            Logger.error("保存军团合同物品到数据库失败")
        } else {
            Logger.debug("成功保存军团合同物品到数据库")
        }
        
        return items
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
