import Foundation

class AllianceContractsAPI {
    static let shared = AllianceContractsAPI()

    private let cacheDirectory: URL = {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("AllianceContractsCache")
    }()

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
            "https://esi.evetech.net/corporations/\(corporationId)/contracts/\(contractId)/items/?datasource=tranquility"
        )!

        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId // 使用角色ID获取token
        )

        let decoder = JSONDecoder()
        return try decoder.decode([ContractItemInfo].self, from: data)
    }

    /// 从服务器获取合同列表
    private func fetchContractsFromServer(
        corporationId: Int, characterId: Int, progressCallback: ((Int) -> Void)? = nil
    ) async throws -> [ContractInfo] {
        let baseUrlString =
            "https://esi.evetech.net/corporations/\(corporationId)/contracts/?datasource=tranquility"
        guard let baseUrl = URL(string: baseUrlString) else {
            throw NetworkError.invalidURL
        }

        let contracts = try await NetworkManager.shared.fetchPaginatedData(
            from: baseUrl,
            characterId: characterId,
            maxConcurrentPages: 5, // 保持原有的最大并发数
            decoder: { data in
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                return try decoder.decode([ContractInfo].self, from: data)
            },
            progressCallback: { currentPage, _ in
                progressCallback?(currentPage)
            }
        )

        Logger.success("成功从服务器获取联盟合同数据 - 军团ID: \(corporationId), 合同数量: \(contracts.count)")

        return contracts
    }

    /// 从数据库获取合同列表
    private func getContractsFromDB(allianceId: Int) async -> [ContractInfo]? {
        let query = """
            SELECT contract_id, acceptor_id, assignee_id, availability,
                   buyout, collateral, date_accepted, date_completed, date_expired,
                   date_issued, days_to_complete, end_location_id,
                   for_corporation, issuer_corporation_id, issuer_id,
                   price, reward, start_location_id, status, title,
                   type, volume
            FROM alliance_contracts 
            WHERE alliance_id = ?
            ORDER BY date_issued DESC
        """

        if case let .success(results) = CharacterDatabaseManager.shared.executeQuery(
            query, parameters: [allianceId]
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

            Logger.success("成功转换\(contracts.count)个联盟合同数据")
            return contracts
        }
        Logger.error("数据库查询失败")
        return nil
    }

    /// 保存合同列表到数据库
    private func saveContractsToDB(allianceId: Int, contracts: [ContractInfo]) -> Bool {
        // 如果没有合同需要保存，直接返回成功
        if contracts.isEmpty {
            Logger.info("没有联盟合同需要保存")
            return true
        }

        // 过滤只保存指定给联盟且未删除的合同
        let filteredContracts = contracts.filter { contract in
            contract.assignee_id == allianceId && contract.status != "deleted"
        }

        if filteredContracts.isEmpty {
            Logger.info("没有符合条件的联盟合同需要保存（已排除指定给其他组织和已删除的合同）")
            return true
        }

        Logger.debug(
            "过滤后需要保存的合同数量: \(filteredContracts.count) / \(contracts.count) (已排除指定给其他组织和已删除的合同)"
        )

        // 获取已存在的合同ID和状态
        let checkQuery =
            "SELECT contract_id, status FROM alliance_contracts WHERE alliance_id = ?"

        // 获取数据库中现有的合同状态
        guard
            case let .success(existingResults) = CharacterDatabaseManager.shared.executeQuery(
                checkQuery, parameters: [allianceId]
            )
        else {
            Logger.error("查询现有联盟合同失败")
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
            // 如果是新合同，或者状态发生变化，则需要更新
            guard let existingStatus = existingContracts[contract.contract_id] else {
                return true // 新合同，需要插入
            }
            return existingStatus != contract.status // 状态变化，需要更新
        }

        if contractsToUpdate.isEmpty {
            Logger.info("所有联盟合同都是最新的，无需更新")
            return true
        }

        Logger.debug("需要更新的联盟合同数量: \(contractsToUpdate.count)")

        let dateFormatter = ISO8601DateFormatter()

        // 开始事务
        _ = CharacterDatabaseManager.shared.executeQuery("BEGIN TRANSACTION")

        // 计算每批次的大小（每条记录24个参数）
        let batchSize = 500 // 每批次处理500条记录
        var success = true
        var newCount = 0
        var updateCount = 0

        // 分批处理数据
        for batchStart in stride(from: 0, to: contractsToUpdate.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, contractsToUpdate.count)
            let currentBatch = Array(contractsToUpdate[batchStart ..< batchEnd])

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
                INSERT OR REPLACE INTO alliance_contracts (
                    contract_id, alliance_id, acceptor_id, assignee_id, availability,
                    buyout, collateral, date_accepted, date_completed, date_expired,
                    date_issued, days_to_complete, end_location_id,
                    for_corporation, issuer_corporation_id, issuer_id,
                    price, reward, start_location_id, status, title,
                    type, volume, items_fetched
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
                    allianceId,
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
                    contract.status,
                    contract.title,
                    contract.type,
                    contract.volume,
                    0, // 状态变化时重置items_fetched
                ]
                parameters.append(contentsOf: params)
            }

            Logger.debug("执行批量插入联盟合同，批次大小: \(currentBatch.count), 参数数量: \(parameters.count)")

            // 执行批量插入
            if case let .error(message) = CharacterDatabaseManager.shared.executeQuery(
                insertSQL, parameters: parameters
            ) {
                Logger.error("批量插入联盟合同失败: \(message)")
                success = false
                break
            }
        }

        // 根据执行结果提交或回滚事务
        if success {
            _ = CharacterDatabaseManager.shared.executeQuery("COMMIT")
            Logger.info("数据库更新成功：新增\(newCount)个联盟合同，更新\(updateCount)个合同状态")
            return true
        } else {
            _ = CharacterDatabaseManager.shared.executeQuery("ROLLBACK")
            Logger.error("保存联盟合同失败，执行回滚")
            return false
        }
    }

    /// 获取合同物品
    func fetchContractItems(
        characterId: Int, contractId: Int, forceRefresh: Bool = false
    ) async throws -> [ContractItemInfo] {
        // 1. 获取角色的军团ID
        guard
            let corporationId = try await CharacterDatabaseManager.shared.getCharacterCorporationId(
                characterId: characterId
            )
        else {
            throw NetworkError.authenticationError("无法获取军团ID")
        }

        // 2. 检查缓存
        let cacheKey = "\(corporationId)_\(contractId)"
        let cacheFile = cacheDirectory.appendingPathComponent("\(cacheKey).json")

        if !forceRefresh, FileManager.default.fileExists(atPath: cacheFile.path) {
            do {
                let data = try Data(contentsOf: cacheFile)
                let items = try JSONDecoder().decode([ContractItemInfo].self, from: data)
                Logger.debug("从缓存获取联盟合同物品数据 - 合同ID: \(contractId), 物品数量: \(items.count)")
                return items
            } catch {
                Logger.warning("读取联盟合同物品缓存失败: \(error)")
            }
        }

        // 3. 从服务器获取数据
        let items = try await fetchContractItemsFromServer(
            corporationId: corporationId, contractId: contractId, characterId: characterId
        )

        // 4. 保存到缓存
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: cacheFile)
            Logger.success("成功缓存联盟合同物品数据 - 合同ID: \(contractId), 物品数量: \(items.count)")
        } catch {
            Logger.warning("缓存联盟合同物品数据失败: \(error)")
        }

        return items
    }

    /// 主要的公共接口：获取联盟合同列表
    func fetchContracts(
        characterId: Int, corporationId: Int, allianceId: Int,
        forceRefresh: Bool = false, progressCallback: ((Int) -> Void)? = nil
    ) async throws -> [ContractInfo] {
        // 2. 检查数据库中是否有数据
        let checkQuery =
            "SELECT COUNT(*) as count FROM alliance_contracts WHERE alliance_id = ?"
        let result = CharacterDatabaseManager.shared.executeQuery(
            checkQuery, parameters: [allianceId]
        )
        let isEmpty =
            if case let .success(rows) = result,
            let row = rows.first,
            let count = row["count"] as? Int64 {
                count == 0
            } else {
                true
            }

        // 3. 如果数据为空或强制刷新，则从网络获取
        if isEmpty || forceRefresh {
            Logger.debug("联盟合同数据为空或强制刷新，从网络获取数据")
            let contracts = try await fetchContractsFromServer(
                corporationId: corporationId, characterId: characterId,
                progressCallback: progressCallback
            )
            if !saveContractsToDB(allianceId: allianceId, contracts: contracts) {
                Logger.error("保存联盟合同到数据库失败")
            }
            // 过滤出指定给联盟且未删除的合同
            let filteredContracts = contracts.filter { contract in
                contract.assignee_id == allianceId && contract.status != "deleted"
            }
            Logger.debug(
                "从服务器获取的合同数量: \(contracts.count)，过滤后数量: \(filteredContracts.count) (已排除指定给其他组织和已删除的合同)"
            )
            return filteredContracts
        }

        // 4. 从数据库获取数据并返回
        if let contracts = await getContractsFromDB(allianceId: allianceId) {
            // 不需要再次过滤，因为数据库中已经只有指定给联盟且未删除的合同
            return contracts
        }

        Logger.warning("无法从数据库获取联盟合同数据")
        return []
    }
}
