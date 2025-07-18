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

    private let cacheTimeout: TimeInterval = 8 * 3600  // 8小时缓存有效期

    private let lastContractsQueryKey = "LastContractsQuery_"
    private let lastContractItemsQueryKey = "LastContractItemsQuery_"

    private init() {
        // 创建缓存目录
        try? FileManager.default.createDirectory(
            at: cacheDirectory, withIntermediateDirectories: true
        )
    }

    // 获取最后查询时间
    private func getLastQueryTime(characterId: Int, isItems: Bool = false) -> Date? {
        let key =
            isItems
            ? lastContractItemsQueryKey + String(characterId)
            : lastContractsQueryKey + String(characterId)
        return UserDefaults.standard.object(forKey: key) as? Date
    }

    // 更新最后查询时间
    private func updateLastQueryTime(characterId: Int, isItems: Bool = false) {
        let key =
            isItems
            ? lastContractItemsQueryKey + String(characterId)
            : lastContractsQueryKey + String(characterId)
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
        if let contracts = contracts, !contracts.isEmpty,
            shouldRefreshData(characterId: characterId)
        {
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
                       buyout, collateral, date_accepted, date_completed, date_expired,
                       date_issued, days_to_complete, end_location_id,
                       for_corporation, issuer_corporation_id, issuer_id,
                       price, reward, start_location_id, status, title,
                       type, volume
                FROM contracts 
                WHERE character_id = ?
                ORDER BY date_issued DESC
            """

        if case let .success(results) = CharacterDatabaseManager.shared.executeQuery(
            query, parameters: [characterId]
        ) {
            Logger.debug("数据库查询成功，获取到\(results.count)行数据")

            let contracts = results.compactMap { row -> ContractInfo? in
                let dateFormatter = ISO8601DateFormatter()

                // 记录原始数据
                // if let rawContractId = row["contract_id"] {
                // Logger.debug("处理合同数据 - contract_id原始值: \(rawContractId), 类型: \(type(of: rawContractId))")
                // }

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
                        Logger.error(
                            "start_location_id 类型不匹配 - 原始值: \(rawValue), 类型: \(type(of: rawValue))")
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
                        Logger.error(
                            "end_location_id 类型不匹配 - 原始值: \(rawValue), 类型: \(type(of: rawValue))")
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
    private func saveContractsToDB(characterId: Int, contracts: [ContractInfo]) -> Bool {
        // 首先获取已存在的合同ID和状态
        let checkQuery = "SELECT contract_id, status FROM contracts WHERE character_id = ?"
        let dateFormatter = ISO8601DateFormatter()

        // 获取数据库中现有的合同状态
        guard
            case let .success(existingResults) = CharacterDatabaseManager.shared.executeQuery(
                checkQuery, parameters: [characterId]
            )
        else {
            Logger.error("查询现有合同失败")
            return false
        }

        // 构建现有合同状态的字典，方便查找
        var existingContracts: [Int: String] = [:]
        for row in existingResults {
            if let contractId = row["contract_id"] as? Int64,
                let status = row["status"] as? String
            {
                existingContracts[Int(contractId)] = status
            }
        }

        // 过滤出需要更新的合同
        let contractsToUpdate = contracts.filter { contract in
            // 如果合同不存在，或者状态已变化，则需要更新
            if let existingStatus = existingContracts[contract.contract_id] {
                return existingStatus != contract.status
            }
            return true
        }

        if contractsToUpdate.isEmpty {
            Logger.info("没有需要更新的合同数据")
            return true
        }

        // 开始事务
        let beginTransaction = "BEGIN TRANSACTION"
        _ = CharacterDatabaseManager.shared.executeQuery(beginTransaction)

        // 计算每批次的大小（每条记录24个参数）
        let batchSize = 500  // 每批次处理500条记录
        var success = true
        var newCount = 0
        var updateCount = 0

        // 分批处理数据
        for batchStart in stride(from: 0, to: contractsToUpdate.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, contractsToUpdate.count)
            let currentBatch = Array(contractsToUpdate[batchStart..<batchEnd])

            // 构建批量插入语句
            let placeholders = Array(
                repeating:
                    "(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                count: currentBatch.count
            ).joined(separator: ",")
            let insertSQL = """
                    INSERT OR REPLACE INTO contracts (
                        contract_id, character_id, status, acceptor_id, assignee_id,
                        availability, buyout, collateral, date_accepted, date_completed,
                        date_expired, date_issued, days_to_complete,
                        end_location_id, for_corporation, issuer_corporation_id,
                        issuer_id, price, reward, start_location_id,
                        title, type, volume, items_fetched
                    ) VALUES \(placeholders)
                """

            // 准备参数数组
            var parameters: [Any] = []
            for contract in currentBatch {
                // 检查合同是否存在及其状态
                if let existingStatus = existingContracts[contract.contract_id] {
                    // 如果状态已变化，记录更新
                    if existingStatus != contract.status {
                        Logger.debug(
                            "合同状态已更新 - ID: \(contract.contract_id), 旧状态: \(existingStatus), 新状态: \(contract.status)"
                        )
                        updateCount += 1
                    }
                } else {
                    // 新合同
                    newCount += 1
                }

                // 处理可选日期
                let dateAccepted =
                    contract.date_accepted.map { dateFormatter.string(from: $0) } ?? ""
                let dateCompleted =
                    contract.date_completed.map { dateFormatter.string(from: $0) } ?? ""

                let params: [Any] = [
                    contract.contract_id,
                    characterId,
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
                    0,  // 状态变化时重置items_fetched
                ]
                parameters.append(contentsOf: params)
            }

            Logger.debug("执行批量插入合同，批次大小: \(currentBatch.count), 参数数量: \(parameters.count)")

            // 执行批量插入
            if case let .error(message) = CharacterDatabaseManager.shared.executeQuery(
                insertSQL, parameters: parameters
            ) {
                Logger.error("批量插入合同失败: \(message)")
                success = false
                break
            }
        }

        // 根据执行结果提交或回滚事务
        if success {
            _ = CharacterDatabaseManager.shared.executeQuery("COMMIT")
            if newCount > 0 || updateCount > 0 {
                Logger.info("数据库更新：新增\(newCount)个合同，更新\(updateCount)个合同状态")
            }
            return true
        } else {
            _ = CharacterDatabaseManager.shared.executeQuery("ROLLBACK")
            Logger.error("保存合同数据失败，执行回滚")
            return false
        }
    }

    // 从数据库获取合同物品
    private func getContractItemsFromDB(characterId _: Int, contractId: Int) -> [ContractItemInfo]?
    {
        let query = """
                SELECT record_id, is_included, is_singleton,
                       quantity, type_id, raw_quantity
                FROM contract_items 
                WHERE contract_id = ?
                ORDER BY record_id ASC
            """

        if case let .success(results) = CharacterDatabaseManager.shared.executeQuery(
            query, parameters: [contractId]
        ) {
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
    private func saveContractItemsToDB(characterId: Int, contractId: Int, items: [ContractItemInfo])
        -> Bool
    {
        Logger.debug("开始保存合同物品 - 角色ID: \(characterId), 合同ID: \(contractId), 物品数量: \(items.count)")

        if items.isEmpty {
            Logger.debug("没有物品需要保存")
            return true
        }

        // 开始事务
        let beginTransaction = "BEGIN TRANSACTION"
        _ = CharacterDatabaseManager.shared.executeQuery(beginTransaction)

        // 计算每批次的大小（每条记录7个参数）
        let batchSize = 500  // 每批次处理500条记录
        var success = true

        // 分批处理数据
        for batchStart in stride(from: 0, to: items.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, items.count)
            let currentBatch = Array(items[batchStart..<batchEnd])

            // 构建批量插入语句
            let placeholders = Array(repeating: "(?, ?, ?, ?, ?, ?, ?)", count: currentBatch.count)
                .joined(separator: ",")
            let insertSQL = """
                    INSERT INTO contract_items (
                        record_id, contract_id,
                        is_included, is_singleton, quantity,
                        type_id, raw_quantity
                    ) VALUES \(placeholders)
                """

            // 准备参数数组
            var parameters: [Any] = []
            for item in currentBatch {
                let recordId = item.record_id

                // 处理raw_quantity的可选值
                let rawQuantity = item.raw_quantity ?? 0

                let params: [Any] = [
                    recordId,
                    contractId,  // 确保存储合同ID
                    item.is_included ? 1 : 0,
                    item.is_singleton ? 1 : 0,
                    item.quantity,
                    item.type_id,
                    rawQuantity,
                ]
                parameters.append(contentsOf: params)
            }

            Logger.debug("执行批量插入合同物品，批次大小: \(currentBatch.count), 参数数量: \(parameters.count)")

            // 执行批量插入
            if case let .error(message) = CharacterDatabaseManager.shared.executeQuery(
                insertSQL, parameters: parameters
            ) {
                Logger.error("批量插入合同物品失败: \(message)")
                success = false
                break
            }
        }

        // 根据执行结果提交或回滚事务
        if success {
            _ = CharacterDatabaseManager.shared.executeQuery("COMMIT")
            Logger.info("成功保存\(items.count)个合同物品到数据库，合同ID: \(contractId)")
            return true
        } else {
            _ = CharacterDatabaseManager.shared.executeQuery("ROLLBACK")
            Logger.error("保存合同物品失败，执行回滚，合同ID: \(contractId)")
            return false
        }
    }

    // 获取合同列表（公开方法）
    public func fetchContracts(
        characterId: Int, forceRefresh: Bool = false, progressCallback: ((Int) -> Void)? = nil
    ) async throws -> [ContractInfo] {
        // 检查数据库中是否有数据
        let checkQuery = "SELECT COUNT(*) as count FROM contracts WHERE character_id = ?"
        let result = CharacterDatabaseManager.shared.executeQuery(
            checkQuery, parameters: [characterId]
        )
        let isEmpty =
            if case let .success(rows) = result,
                let row = rows.first,
                let count = row["count"] as? Int64
            {
                count == 0
            } else {
                true
            }

        // 如果数据为空或强制刷新，则从网络获取
        if isEmpty || forceRefresh {
            Logger.debug("合同数据为空或强制刷新，从网络获取数据")
            let contracts = try await fetchContractsFromServer(
                characterId: characterId, progressCallback: progressCallback
            )
            return contracts
        }

        // 从数据库获取数据并返回
        if let contracts = await getContractsFromDB(characterId: characterId) {
            return contracts
        }
        return []
    }

    // 获取合同物品（公开方法）
    public func fetchContractItems(characterId: Int, contractId: Int, forceRefresh: Bool = false)
        async throws -> [ContractItemInfo]
    {
        Logger.debug("开始获取合同物品 - 角色ID: \(characterId), 合同ID: \(contractId)")

        // 检查合同是否存在且是否已尝试获取过物品
        let checkQuery = """
                SELECT status, items_fetched FROM contracts 
                WHERE contract_id = ? AND character_id = ?
            """

        if case let .success(results) = CharacterDatabaseManager.shared.executeQuery(
            checkQuery, parameters: [contractId, characterId]
        ),
            let row = results.first
        {
            let itemsFetched = (row["items_fetched"] as? Int64 ?? 0) != 0

            if !forceRefresh {
                // 如果已经尝试获取过物品
                if itemsFetched {
                    Logger.debug("已经尝试获取过合同物品，检查数据库")
                    if let items = getContractItemsFromDB(
                        characterId: characterId, contractId: contractId
                    ) {
                        if !items.isEmpty {
                            Logger.debug("从数据库成功获取到\(items.count)个合同物品")
                            return items
                        }
                        Logger.debug("该合同没有物品内容")
                        return []
                    }
                }
            }
        }

        // 从服务器获取数据
        Logger.debug("从服务器获取合同物品")
        let items = try await fetchContractItemsFromServer(
            characterId: characterId, contractId: contractId
        )
        Logger.debug("从服务器获取到\(items.count)个合同物品")

        // 先删除旧数据
        if CharacterDatabaseManager.shared.deleteContractItems(contractId: contractId) {
            Logger.debug("成功删除旧的合同物品数据")
        } else {
            Logger.error("删除旧的合同物品数据失败")
        }

        // 保存到数据库
        if !saveContractItemsToDB(characterId: characterId, contractId: contractId, items: items) {
            Logger.error("保存合同物品到数据库失败")
        } else {
            Logger.debug("成功保存合同物品到数据库")

            // 更新items_fetched标记
            let updateSQL = """
                    UPDATE contracts 
                    SET items_fetched = 1
                    WHERE contract_id = ? AND character_id = ?
                """

            if case let .error(message) = CharacterDatabaseManager.shared.executeQuery(
                updateSQL, parameters: [contractId, characterId]
            ) {
                Logger.error("更新合同items_fetched标记失败: \(message)")
            }
        }

        return items
    }

    // 从服务器获取合同列表
    private func fetchContractsFromServer(
        characterId: Int, progressCallback: ((Int) -> Void)? = nil
    ) async throws -> [ContractInfo] {
        let baseUrlString =
            "https://esi.evetech.net/latest/characters/\(characterId)/contracts/?datasource=tranquility"
        guard let baseUrl = URL(string: baseUrlString) else {
            throw NetworkError.invalidURL
        }

        let contracts = try await NetworkManager.shared.fetchPaginatedData(
            from: baseUrl,
            characterId: characterId,
            maxConcurrentPages: 5,  // 保持原有的最大并发数
            decoder: { data in
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                return try decoder.decode([ContractInfo].self, from: data)
            },
            progressCallback: { currentPage, totalPages in
                progressCallback?(currentPage)
            }
        )

        // 更新最后查询时间
        updateLastQueryTime(characterId: characterId)

        // 保存到数据库
        if !saveContractsToDB(characterId: characterId, contracts: contracts) {
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

        Logger.debug("成功从服务器获取合同数据 - 角色ID: \(characterId), 合同数量: \(contracts.count)")

        return contracts
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

    // 从服务器获取合同物品
    private func fetchContractItemsFromServer(characterId: Int, contractId: Int) async throws
        -> [ContractItemInfo]
    {
        Logger.debug("开始从服务器获取合同物品 - 角色ID: \(characterId), 合同ID: \(contractId)")
        let url = URL(
            string:
                "https://esi.evetech.net/latest/characters/\(characterId)/contracts/\(contractId)/items/?datasource=tranquility"
        )!
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
}

// 合同信息模型
struct ContractInfo: Codable, Identifiable, Hashable {
    let acceptor_id: Int?
    let assignee_id: Int?
    let availability: String
    let buyout: Double?
    let collateral: Double?
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
