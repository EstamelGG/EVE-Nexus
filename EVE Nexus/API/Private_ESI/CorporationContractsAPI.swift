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

    private let lastContractsQueryKey = "LastCorporationContractsQuery_"
    private let lastContractItemsQueryKey = "LastCorporationContractItemsQuery_"

    private init() {
        // 创建缓存目录
        try? FileManager.default.createDirectory(
            at: cacheDirectory, withIntermediateDirectories: true
        )
    }

    private func fetchContractItemsFromServer(corporationId: Int, contractId: Int, characterId: Int)
        async throws -> [ContractItemInfo]
    {
        let url = URL(
            string:
                "https://esi.evetech.net/latest/corporations/\(corporationId)/contracts/\(contractId)/items/?datasource=tranquility"
        )!

        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId  // 使用角色ID获取token
        )

        let decoder = JSONDecoder()
        return try decoder.decode([ContractItemInfo].self, from: data)
    }

    // 更新最后查询时间
    private func updateLastQueryTime(corporationId: Int, isItems: Bool = false) {
        let key =
            isItems
            ? lastContractItemsQueryKey + String(corporationId)
            : lastContractsQueryKey + String(corporationId)
        UserDefaults.standard.set(Date(), forKey: key)
    }

    // 从服务器获取合同列表
    private func fetchContractsFromServer(
        corporationId: Int, characterId: Int, progressCallback: ((Int) -> Void)? = nil
    ) async throws -> [ContractInfo] {
        let baseUrlString =
            "https://esi.evetech.net/latest/corporations/\(corporationId)/contracts/?datasource=tranquility"
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
        updateLastQueryTime(corporationId: corporationId)

        // 发送数据更新通知
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Notification.Name(CorporationContractsAPI.contractsUpdatedNotification),
                object: nil,
                userInfo: [CorporationContractsAPI.contractsUpdatedCorporationIdKey: corporationId]
            )
        }

        Logger.debug("成功从服务器获取军团合同数据 - 军团ID: \(corporationId), 合同数量: \(contracts.count)")

        return contracts
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

        if case let .success(results) = CharacterDatabaseManager.shared.executeQuery(
            query, parameters: [corporationId]
        ) {
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
                    let dateExpired = dateFormatter.date(from: dateExpiredStr)
                else {
                    Logger.error("日期解析失败")
                    return nil
                }

                // 解析可选日期
                let dateAccepted = (row["date_accepted"] as? String).flatMap {
                    dateFormatter.date(from: $0)
                }
                let dateCompleted = (row["date_completed"] as? String).flatMap {
                    dateFormatter.date(from: $0)
                }

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
        // 如果没有合同需要保存，直接返回成功
        if contracts.isEmpty {
            Logger.info("没有军团合同需要保存")
            return true
        }

        // 过滤只保存指定给自己公司且未删除的合同
        let filteredContracts = contracts.filter { contract in
            contract.assignee_id == corporationId && contract.status != "deleted"
        }

        if filteredContracts.isEmpty {
            Logger.info("没有符合条件的军团合同需要保存（已排除指定给其他公司和已删除的合同）")
            return true
        }

        Logger.debug(
            "过滤后需要保存的合同数量: \(filteredContracts.count) / \(contracts.count) (已排除指定给其他公司和已删除的合同)")

        // 获取已存在的合同ID和状态
        let checkQuery =
            "SELECT contract_id, status FROM corporation_contracts WHERE corporation_id = ?"

        // 获取数据库中现有的合同状态
        guard
            case let .success(existingResults) = CharacterDatabaseManager.shared.executeQuery(
                checkQuery, parameters: [corporationId]
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

        // 筛选需要更新的合同（状态变化或新合同）
        let contractsToUpdate = filteredContracts.filter { contract in
            if let existingStatus = existingContracts[contract.contract_id] {
                return existingStatus != contract.status  // 状态变化的合同
            }
            return true  // 新合同
        }

        if contractsToUpdate.isEmpty {
            Logger.info("没有需要更新的合同数据")
            return true
        }

        Logger.info("需要更新的合同数量: \(contractsToUpdate.count)")

        // 开始事务
        _ = CharacterDatabaseManager.shared.executeQuery("BEGIN TRANSACTION")

        // 计算每批次的大小（每条记录24个参数）
        let batchSize = 500  // 每批次处理500条记录
        let dateFormatter = ISO8601DateFormatter()
        var success = true
        var newCount = 0
        var updateCount = 0

        // 分批处理数据
        for batchStart in stride(from: 0, to: contractsToUpdate.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, contractsToUpdate.count)
            let currentBatch = Array(contractsToUpdate[batchStart..<batchEnd])

            // 统计新增和更新的数量
            for contract in currentBatch {
                if existingContracts[contract.contract_id] != nil {
                    updateCount += 1
                } else {
                    newCount += 1
                }
            }

            // 构建批量插入语句
            let placeholders = Array(
                repeating:
                    "(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                count: currentBatch.count
            ).joined(separator: ",")
            let insertSQL = """
                    INSERT OR REPLACE INTO corporation_contracts (
                        contract_id, corporation_id, status, acceptor_id, assignee_id,
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
                // 处理可选日期
                let dateAccepted =
                    contract.date_accepted.map { dateFormatter.string(from: $0) } ?? ""
                let dateCompleted =
                    contract.date_completed.map { dateFormatter.string(from: $0) } ?? ""

                let params: [Any] = [
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
                    0,  // 状态变化时重置items_fetched
                ]
                parameters.append(contentsOf: params)
            }

            Logger.debug("执行批量插入军团合同，批次大小: \(currentBatch.count), 参数数量: \(parameters.count)")

            // 执行批量插入
            if case let .error(message) = CharacterDatabaseManager.shared.executeQuery(
                insertSQL, parameters: parameters
            ) {
                Logger.error("批量插入军团合同失败: \(message)")
                success = false
                break
            }
        }

        // 根据执行结果提交或回滚事务
        if success {
            _ = CharacterDatabaseManager.shared.executeQuery("COMMIT")
            Logger.info("数据库更新成功：新增\(newCount)个合同，更新\(updateCount)个合同状态")
            return true
        } else {
            _ = CharacterDatabaseManager.shared.executeQuery("ROLLBACK")
            Logger.error("保存军团合同失败，执行回滚")
            return false
        }
    }

    // 从数据库获取合同物品
    private func getContractItemsFromDB(corporationId _: Int, contractId: Int)
        -> [ContractItemInfo]?
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
    private func saveContractItemsToDB(
        corporationId _: Int, contractId: Int, items: [ContractItemInfo]
    ) -> Bool {
        // 如果没有物品需要保存，直接返回成功
        if items.isEmpty {
            Logger.info("没有合同物品需要保存，合同ID: \(contractId)")
            return true
        }

        // 开始事务
        _ = CharacterDatabaseManager.shared.executeQuery("BEGIN TRANSACTION")

        // 计算每批次的大小（每条记录7个参数）
        let batchSize = 100  // 每批次处理100条记录
        var success = true

        // 分批处理数据
        for batchStart in stride(from: 0, to: items.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, items.count)
            let currentBatch = Array(items[batchStart..<batchEnd])

            // 构建批量插入语句
            let placeholders = Array(repeating: "(?, ?, ?, ?, ?, ?, ?)", count: currentBatch.count)
                .joined(separator: ",")
            let insertSQL = """
                    INSERT OR REPLACE INTO contract_items (
                        record_id, contract_id, is_included, is_singleton,
                        quantity, type_id, raw_quantity
                    ) VALUES \(placeholders)
                """

            // 准备参数数组
            var parameters: [Any] = []
            for item in currentBatch {
                let rawQuantity = item.raw_quantity ?? item.quantity

                let params: [Any] = [
                    item.record_id,
                    contractId,
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

            // 更新合同的items_fetched标志
            let updateSQL =
                "UPDATE corporation_contracts SET items_fetched = 1 WHERE contract_id = ?"
            if case let .error(message) = CharacterDatabaseManager.shared.executeQuery(
                updateSQL, parameters: [contractId]
            ) {
                Logger.error("更新合同items_fetched标志失败: \(message)")
                // 不影响主要功能，继续返回成功
            }

            return true
        } else {
            _ = CharacterDatabaseManager.shared.executeQuery("ROLLBACK")
            Logger.error("保存合同物品失败，执行回滚")
            return false
        }
    }

    // 获取合同列表（公开方法）
    public func fetchContracts(
        characterId: Int, forceRefresh: Bool = false, progressCallback: ((Int) -> Void)? = nil
    ) async throws -> [ContractInfo] {
        // 1. 获取角色的军团ID
        guard
            let corporationId = try await CharacterDatabaseManager.shared.getCharacterCorporationId(
                characterId: characterId)
        else {
            throw NetworkError.authenticationError("无法获取军团ID")
        }

        // 2. 检查数据库中是否有数据
        let checkQuery =
            "SELECT COUNT(*) as count FROM corporation_contracts WHERE corporation_id = ?"
        let result = CharacterDatabaseManager.shared.executeQuery(
            checkQuery, parameters: [corporationId]
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

        // 3. 如果数据为空或强制刷新，则从网络获取
        if isEmpty || forceRefresh {
            Logger.debug("军团合同数据为空或强制刷新，从网络获取数据")
            let contracts = try await fetchContractsFromServer(
                corporationId: corporationId, characterId: characterId,
                progressCallback: progressCallback
            )
            if !saveContractsToDB(corporationId: corporationId, contracts: contracts) {
                Logger.error("保存军团合同到数据库失败")
            }
            // 过滤出指定给自己公司且未删除的合同
            let filteredContracts = contracts.filter { contract in
                contract.assignee_id == corporationId && contract.status != "deleted"
            }
            Logger.debug(
                "从服务器获取的合同数量: \(contracts.count)，过滤后数量: \(filteredContracts.count) (已排除指定给其他公司和已删除的合同)"
            )
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
    public func fetchContractItems(characterId: Int, contractId: Int) async throws
        -> [ContractItemInfo]
    {
        Logger.debug("开始获取军团合同物品 - 角色ID: \(characterId), 合同ID: \(contractId)")

        // 获取角色的军团ID
        guard
            let corporationId = try await CharacterDatabaseManager.shared.getCharacterCorporationId(
                characterId: characterId)
        else {
            throw NetworkError.authenticationError("无法获取军团ID")
        }

        // 检查数据库中是否有数据
        if let items = getContractItemsFromDB(corporationId: corporationId, contractId: contractId)
        {
            if !items.isEmpty {
                Logger.debug("从数据库获取到\(items.count)个军团合同物品")
                return items
            }
        }

        // 从服务器获取数据
        Logger.debug("从服务器获取军团合同物品")
        let items = try await fetchContractItemsFromServer(
            corporationId: corporationId, contractId: contractId, characterId: characterId
        )
        Logger.debug("从服务器获取到\(items.count)个军团合同物品")

        // 保存到数据库
        if !saveContractItemsToDB(
            corporationId: corporationId, contractId: contractId, items: items
        ) {
            Logger.error("保存军团合同物品到数据库失败")
        } else {
            Logger.debug("成功保存军团合同物品到数据库")
        }

        return items
    }
}
