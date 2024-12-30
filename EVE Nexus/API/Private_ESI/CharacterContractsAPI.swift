import Foundation

class CharacterContractsAPI {
    static let shared = CharacterContractsAPI()
    
    // 通知名称常量
    static let contractsUpdatedNotification = "ContractsUpdatedNotification"
    static let contractsUpdatedCharacterIdKey = "CharacterId"
    
    private let cacheDirectory: URL = {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("ContractsCache")
    }()
    
    private let maxConcurrentPages = 2 // 最大并发页数
    private let cacheTimeout: TimeInterval = 8 * 3600 // 8小时缓存有效期
    
    private let lastContractsQueryKey = "LastContractsQuery_"
    private let lastContractItemsQueryKey = "LastContractItemsQuery_"
    
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
    
    // 获取最后查询时间
    private func getLastQueryTime(characterId: Int, isItems: Bool = false) -> Date? {
        let key = isItems ? lastContractItemsQueryKey + String(characterId) : lastContractsQueryKey + String(characterId)
        return UserDefaults.standard.object(forKey: key) as? Date
    }
    
    // 更新最后查询时间
    private func updateLastQueryTime(characterId: Int, isItems: Bool = false) {
        let key = isItems ? lastContractItemsQueryKey + String(characterId) : lastContractsQueryKey + String(characterId)
        UserDefaults.standard.set(Date(), forKey: key)
    }
    
    // 检查是否需要刷新数据
    private func shouldRefreshData(characterId: Int) -> Bool {
        guard let lastQueryTime = getLastQueryTime(characterId: characterId) else {
            return true
        }
        return Date().timeIntervalSince(lastQueryTime) >= cacheTimeout
    }
    
    // 从数据库获取合同列表，如果数据过期则在后台刷新
    func getContractsFromDB(characterId: Int) async -> [ContractInfo]? {
        let contracts = getContractsFromDBSync(characterId: characterId)
        
        // 只有在有数据且数据过期的情况下才在后台刷新
        if let contracts = contracts, !contracts.isEmpty, shouldRefreshData(characterId: characterId) {
            Logger.info("合同数据已过期，在后台刷新 - 角色ID: \(characterId)")
            
            // 在后台刷新数据
            Task {
                do {
                    let _ = try await fetchContractsFromServer(characterId: characterId)
                    Logger.info("后台刷新合同数据完成 - 角色ID: \(characterId)")
                } catch {
                    Logger.error("后台刷新合同数据失败 - 角色ID: \(characterId), 错误: \(error)")
                }
            }
        } else if let lastQueryTime = getLastQueryTime(characterId: characterId) {
            let remainingTime = cacheTimeout - Date().timeIntervalSince(lastQueryTime)
            let remainingHours = Int(remainingTime / 3600)
            let remainingMinutes = Int((remainingTime.truncatingRemainder(dividingBy: 3600)) / 60)
            Logger.info("使用有效的合同缓存数据 - 剩余有效期: \(remainingHours)小时\(remainingMinutes)分钟")
        }
        
        return contracts
    }
    
    // 同步方法：从数据库获取合同列表
    private func getContractsFromDBSync(characterId: Int) -> [ContractInfo]? {
        let query = """
            SELECT contract_id, acceptor_id, assignee_id, availability,
                   collateral, date_accepted, date_completed, date_expired,
                   date_issued, days_to_complete, end_location_id,
                   for_corporation, issuer_corporation_id, issuer_id,
                   price, reward, start_location_id, status, title,
                   type, volume
            FROM contracts 
            WHERE character_id = ?
            ORDER BY date_issued DESC
        """
        
        if case .success(let results) = CharacterDatabaseManager.shared.executeQuery(query, parameters: [characterId]) {
            Logger.debug("数据库查询成功，获取到\(results.count)行数据")
            
            let contracts = results.compactMap { row -> ContractInfo? in
                let dateFormatter = ISO8601DateFormatter()
                
                // 记录原始数据
                //if let rawContractId = row["contract_id"] {
                    // Logger.debug("处理合同数据 - contract_id原始值: \(rawContractId), 类型: \(type(of: rawContractId))")
                //}
                
                // 获取contract_id
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
                guard let dateIssued = dateFormatter.date(from: dateIssuedStr) else {
                    Logger.error("无法解析 date_issued: \(dateIssuedStr)")
                    return nil
                }
                guard let dateExpired = dateFormatter.date(from: dateExpiredStr) else {
                    Logger.error("无法解析 date_expired: \(dateExpiredStr)")
                    return nil
                }
                
                // 处理可选日期
                let dateAccepted = (row["date_accepted"] as? String)
                    .flatMap { str in str.isEmpty ? nil : str }
                    .flatMap { dateFormatter.date(from: $0) }
                
                let dateCompleted = (row["date_completed"] as? String)
                    .flatMap { str in str.isEmpty ? nil : str }
                    .flatMap { dateFormatter.date(from: $0) }
                
                // 处理可能为null的整数字段
                let acceptorId = row["acceptor_id"] as? Int64
                let assigneeId = row["assignee_id"] as? Int64
                
                // 获取位置ID
                let startLocationId: Int64
                let endLocationId: Int64
                
                if let startId = row["start_location_id"] as? Int64 {
                    startLocationId = startId
                    // Logger.debug("从数据库获取到 start_location_id (Int64): \(startId)")
                } else if let startId = row["start_location_id"] as? Int {
                    startLocationId = Int64(startId)
                    // Logger.debug("从数据库获取到 start_location_id (Int): \(startId)")
                } else {
                    if let rawValue = row["start_location_id"] {
                        Logger.error("start_location_id 类型不匹配 - 原始值: \(rawValue), 类型: \(type(of: rawValue))")
                    } else {
                        Logger.error("start_location_id 为空")
                    }
                    return nil
                }
                
                if let endId = row["end_location_id"] as? Int64 {
                    endLocationId = endId
                    // Logger.debug("从数据库获取到 end_location_id (Int64): \(endId)")
                } else if let endId = row["end_location_id"] as? Int {
                    endLocationId = Int64(endId)
                    // Logger.debug("从数据库获取到 end_location_id (Int): \(endId)")
                } else {
                    if let rawValue = row["end_location_id"] {
                        Logger.error("end_location_id 类型不匹配 - 原始值: \(rawValue), 类型: \(type(of: rawValue))")
                    } else {
                        Logger.error("end_location_id 为空")
                    }
                    return nil
                }
                
                // 获取 issuer_id 和 issuer_corporation_id
                let issuerId: Int
                if let id = row["issuer_id"] as? Int64 {
                    issuerId = Int(id)
                } else if let id = row["issuer_id"] as? Int {
                    issuerId = id
                } else {
                    Logger.error("issuer_id 无效或类型不匹配")
                    return nil
                }
                
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
                    acceptor_id: acceptorId.map(Int.init),
                    assignee_id: assigneeId.map(Int.init),
                    availability: row["availability"] as? String ?? "",
                    collateral: row["collateral"] as? Double ?? 0.0,
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
    private func saveContractsToDB(characterId: Int, contracts: [ContractInfo]) -> Bool {
        // 首先获取已存在的合同ID
        let checkQuery = "SELECT contract_id FROM contracts WHERE contract_id = ? AND character_id = ? AND status = ?"
        var newCount = 0
        let dateFormatter = ISO8601DateFormatter()
        
        let insertSQL = """
            INSERT OR REPLACE INTO contracts (
                contract_id, character_id, status, acceptor_id, assignee_id,
                availability, collateral, date_accepted, date_completed,
                date_expired, date_issued, days_to_complete,
                end_location_id, for_corporation, issuer_corporation_id,
                issuer_id, price, reward, start_location_id,
                title, type, volume
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        
        for contract in contracts {
            // 检查合同状态是否已存在
            if case .success(let results) = CharacterDatabaseManager.shared.executeQuery(
                checkQuery, 
                parameters: [contract.contract_id, characterId, contract.status]
            ),
            !results.isEmpty {
                Logger.debug("跳过已存在的合同状态记录 - ID: \(contract.contract_id), 状态: \(contract.status)")
                continue
            }
            
            // 处理可选日期
            let dateAccepted = contract.date_accepted.map { dateFormatter.string(from: $0) } ?? ""
            let dateCompleted = contract.date_completed.map { dateFormatter.string(from: $0) } ?? ""
            
            let parameters: [Any] = [
                contract.contract_id,
                characterId,
                contract.status,
                contract.acceptor_id ?? 0,
                contract.assignee_id ?? 0,
                contract.availability,
                contract.collateral,
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
                contract.volume
            ]
            
            if case .error(let message) = CharacterDatabaseManager.shared.executeQuery(insertSQL, parameters: parameters) {
                Logger.error("保存合同到数据库失败: \(message)")
                return false
            }
            newCount += 1
            Logger.debug("成功插入新合同状态记录 - ID: \(contract.contract_id), 状态: \(contract.status)")
        }
        
        if newCount > 0 {
            Logger.info("新增\(newCount)个合同状态记录到数据库")
        } else {
            Logger.debug("没有新的合同状态记录需要插入")
        }
        return true
    }
    
    // 从数据库获取合同物品
    private func getContractItemsFromDB(characterId: Int, contractId: Int) -> [ContractItemInfo]? {
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
                // 记录原始数据
//                if let rawTypeId = row["type_id"] {
//                    Logger.debug("处理物品数据 - type_id原始值: \(rawTypeId), 类型: \(type(of: rawTypeId))")
//                }
//                if let rawQuantity = row["quantity"] {
//                    Logger.debug("处理物品数据 - quantity原始值: \(rawQuantity), 类型: \(type(of: rawQuantity))")
//                }
                
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
    private func saveContractItemsToDB(characterId: Int, contractId: Int, items: [ContractItemInfo]) -> Bool {
        Logger.debug("开始保存合同物品 - 角色ID: \(characterId), 合同ID: \(contractId), 物品数量: \(items.count)")
        
        // 首先获取已存在的记录ID
        let checkQuery = "SELECT record_id FROM contract_items WHERE character_id = ? AND contract_id = ?"
        guard case .success(let existingResults) = CharacterDatabaseManager.shared.executeQuery(checkQuery, parameters: [characterId, contractId]) else {
            Logger.error("查询现有合同物品失败")
            return false
        }
        
        let existingIds = Set(existingResults.compactMap { ($0["record_id"] as? Int64) })
        Logger.debug("数据库中已存在\(existingIds.count)个物品记录")
        
        let insertSQL = """
            INSERT OR REPLACE INTO contract_items (
                record_id, contract_id, character_id,
                is_included, is_singleton, quantity,
                type_id, raw_quantity
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """
        
        var newCount = 0
        for item in items {
            let recordId = item.record_id
            // 如果记录ID已存在，跳过
            if existingIds.contains(recordId) {
                Logger.debug("跳过已存在的合同物品 - 记录ID: \(recordId), 合同ID: \(contractId)")
                continue
            }
            
            // 处理raw_quantity的可选值
            let rawQuantity = item.raw_quantity ?? 0
            
            let parameters: [Any] = [
                recordId,
                contractId,  // 确保存储合同ID
                characterId,
                item.is_included ? 1 : 0,
                item.is_singleton ? 1 : 0,
                item.quantity,
                item.type_id,
                rawQuantity
            ]
            
            Logger.debug("准备插入物品 - 记录ID: \(recordId), 合同ID: \(contractId), 类型ID: \(item.type_id), 数量: \(item.quantity)")
            if case .error(let message) = CharacterDatabaseManager.shared.executeQuery(insertSQL, parameters: parameters) {
                Logger.error("保存合同物品到数据库失败: \(message), 参数: \(parameters)")
                return false
            }
            newCount += 1
            Logger.debug("成功插入新合同物品 - 记录ID: \(recordId), 合同ID: \(contractId)")
        }
        
        if newCount > 0 {
            Logger.info("新增\(newCount)个合同物品到数据库，合同ID: \(contractId)")
        } else {
            Logger.debug("没有新的合同物品需要插入，合同ID: \(contractId)")
        }
        return true
    }
    
    // 获取合同列表（公开方法）
    public func fetchContracts(characterId: Int, forceRefresh: Bool = false) async throws -> [ContractInfo] {
        // 检查数据库中是否有数据
        let checkQuery = "SELECT COUNT(*) as count FROM contracts WHERE character_id = ?"
        let result = CharacterDatabaseManager.shared.executeQuery(checkQuery, parameters: [characterId])
        let isEmpty = if case .success(let rows) = result,
                        let row = rows.first,
                        let count = row["count"] as? Int64 {
            count == 0
        } else {
            true
        }
        
        // 如果数据为空或强制刷新，则从网络获取
        if isEmpty || forceRefresh {
            Logger.debug("合同数据为空或强制刷新，从网络获取数据")
            let contracts = try await fetchContractsFromServer(characterId: characterId)
            if !saveContractsToDB(characterId: characterId, contracts: contracts) {
                Logger.error("保存合同到数据库失败")
            }
        }
        
        // 从数据库获取数据并返回
        if let contracts = await getContractsFromDB(characterId: characterId) {
            return contracts
        }
        return []
    }
    
    // 获取合同物品（公开方法）
    public func fetchContractItems(characterId: Int, contractId: Int, forceRefresh: Bool = false) async throws -> [ContractItemInfo] {
        Logger.debug("获取合同物品 - 角色ID: \(characterId), 合同ID: \(contractId)")
        
        // 检查合同是否存在
        let checkQuery = """
            SELECT status FROM contracts 
            WHERE contract_id = ?
        """
        
        if case .success(let results) = CharacterDatabaseManager.shared.executeQuery(checkQuery, parameters: [contractId]),
           !results.isEmpty,
           !forceRefresh {
            Logger.debug("合同存在，尝试从数据库获取物品")
            // 尝试从数据库获取物品
            if let items = getContractItemsFromDB(characterId: characterId, contractId: contractId) {
                if !items.isEmpty {
                    Logger.debug("从数据库成功获取到\(items.count)个合同物品")
                    return items
                }
                Logger.debug("数据库中没有找到合同物品，尝试从网络获取")
            }
        }
        
        // 从服务器获取数据
        Logger.debug("从服务器获取合同物品")
        let items = try await fetchContractItemsFromServer(characterId: characterId, contractId: contractId)
        Logger.debug("从服务器获取到\(items.count)个合同物品")
        
        // 保存到数据库
        if !saveContractItemsToDB(characterId: characterId, contractId: contractId, items: items) {
            Logger.error("保存合同物品到数据库失败")
        } else {
            Logger.debug("成功保存合同物品到数据库")
        }
        
        return items
    }
    
    private func fetchContractsFromServer(characterId: Int) async throws -> [ContractInfo] {
        var allContracts: [ContractInfo] = []
        var currentPage = 1
        var shouldContinue = true
        
        while shouldContinue {
            do {
                let pageContracts = try await fetchContractsPage(characterId: characterId, page: currentPage)
                if pageContracts.isEmpty {
                    shouldContinue = false
                } else {
                    allContracts.append(contentsOf: pageContracts)
                    currentPage += 1
                }
            } catch let error as NetworkError {
                if case .httpError(let statusCode, let message) = error,
                   [404, 500].contains(statusCode) ,
                   message?.contains("Requested page does not exist") == true {
                    shouldContinue = false
                } else {
                    throw error
                }
            }
        }
        
        // 更新最后查询时间
        updateLastQueryTime(characterId: characterId)
        
        // 保存到数据库
        if !saveContractsToDB(characterId: characterId, contracts: allContracts) {
            Logger.error("保存合同到数据库失败")
        } else {
            // 发送数据更新通知
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Notification.Name(CharacterContractsAPI.contractsUpdatedNotification),
                    object: nil,
                    userInfo: [CharacterContractsAPI.contractsUpdatedCharacterIdKey: characterId]
                )
            }
        }
        
        Logger.debug("成功从服务器获取合同数据 - 角色ID: \(characterId), 合同数量: \(allContracts.count)")
        
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
    
    // 从服务器获取合同物品
    private func fetchContractItemsFromServer(characterId: Int, contractId: Int) async throws -> [ContractItemInfo] {
        Logger.debug("开始从服务器获取合同物品 - 角色ID: \(characterId), 合同ID: \(contractId)")
        let url = URL(string: "https://esi.evetech.net/latest/characters/\(characterId)/contracts/\(contractId)/items/?datasource=tranquility")!
        Logger.debug("请求URL: \(url.absoluteString)")
        
        do {
            let data = try await NetworkManager.shared.fetchDataWithToken(
                from: url,
                characterId: characterId
            )
        
        let decoder = JSONDecoder()
        let items = try decoder.decode([ContractItemInfo].self, from: data)
            Logger.debug("成功从服务器获取合同物品 - 合同ID: \(contractId), 物品数量: \(items.count)")
            
            // 打印每个物品的详细信息
//            for item in items {
//                Logger.debug("""
//                    物品详情:
//                    - 记录ID: \(item.record_id)
//                    - 类型ID: \(item.type_id)
//                    - 数量: \(item.quantity)
//                    - 是否包含: \(item.is_included)
//                    - 是否单例: \(item.is_singleton)
//                    - 原始数量: \(item.raw_quantity ?? 0)
//                    """)
//            }
        
        return items
        } catch {
            Logger.error("从服务器获取合同物品失败 - 合同ID: \(contractId), 错误: \(error.localizedDescription)")
            throw error
        }
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
