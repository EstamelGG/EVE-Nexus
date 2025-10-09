import Foundation

struct LPStoreOffer: Codable {
    let akCost: Int
    let iskCost: Int
    let lpCost: Int
    let offerId: Int
    let quantity: Int
    let requiredItems: [RequiredItem]
    let typeId: Int

    enum CodingKeys: String, CodingKey {
        case akCost = "ak_cost"
        case iskCost = "isk_cost"
        case lpCost = "lp_cost"
        case offerId = "offer_id"
        case quantity
        case requiredItems = "required_items"
        case typeId = "type_id"
    }
}

struct RequiredItem: Codable {
    let quantity: Int
    let typeId: Int

    enum CodingKeys: String, CodingKey {
        case quantity
        case typeId = "type_id"
    }
}

// MARK: - 错误类型

enum LPStoreAPIError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case decodingError(Error)
    case httpError(Int)
    case rateLimitExceeded

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的URL"
        case let .networkError(error):
            return "网络错误: \(error.localizedDescription)"
        case .invalidResponse:
            return "无效的响应"
        case let .decodingError(error):
            return "数据解码错误: \(error.localizedDescription)"
        case let .httpError(code):
            return "HTTP错误: \(code)"
        case .rateLimitExceeded:
            return "超出请求限制"
        }
    }
}

// MARK: - LP商店API

@globalActor actor LPStoreAPIActor {
    static let shared = LPStoreAPIActor()
}

@LPStoreAPIActor
class LPStoreAPI {
    static let shared = LPStoreAPI()
    private let cacheDuration: TimeInterval = 3600 * 24 * 30 // 30 天缓存

    private init() {}

    // MARK: - 公共方法

    /// 获取单个军团的LP商店兑换列表
    /// - Parameters:
    ///   - corporationId: 军团ID
    ///   - forceRefresh: 是否强制刷新缓存
    /// - Returns: LP商店兑换列表
    func fetchCorporationLPStoreOffers(corporationId: Int, forceRefresh: Bool = false) async throws
        -> [LPStoreOffer]
    {
        // 如果不是强制刷新，尝试从数据库获取
        if !forceRefresh {
            if let cached = try? loadFromDatabase(corporationId: corporationId) {
                return cached
            }
        }

        // 获取数据
        let data = try await fetchLPStoreDataFromAPI(corporationId: corporationId)
        let offers = try JSONDecoder().decode([LPStoreOffer].self, from: data)

        // 保存到数据库
        saveLPStoreOffers(corporationId: corporationId, offersData: data)

        return offers
    }

    /// 从数据库加载多个军团的LP商店数据并检查缓存状态
    /// - Parameter corporationIds: 军团ID数组
    /// - Returns: 如果缓存有效则返回数据，否则返回nil
    private func loadMultipleCorporationsFromDatabase(corporationIds: [Int]) -> [Int:
        [LPStoreOffer]]?
    {
        // 首先检查全量加载条数记录
        let cachedCount = UserDefaultsManager.shared.LPStoreFullLoadCount
        if cachedCount == 0 {
            Logger.info("未找到LP商店全量加载条数记录，需要全量加载")
            return nil
        }

        Logger.info("缓存的全量加载条数: \(cachedCount)")

        let query = """
            SELECT corporation_id, offer_id, type_id, offers_data
            FROM LPStoreOffers_v2
            WHERE corporation_id IN (\(corporationIds.map { String($0) }.joined(separator: ",")))
            ORDER BY corporation_id, offer_id
        """

        if case let .success(rows) = CharacterDatabaseManager.shared.executeQuery(query) {
            Logger.info("从数据库查询到 \(rows.count) 条LP商店数据")

            // 如果数据库为空，需要重新加载
            if rows.isEmpty {
                Logger.info("数据库中没有LP商店数据，需要全量加载")
                return nil
            }

            // 比较缓存条数与数据库实际条数
            if rows.count != cachedCount {
                Logger.info("数据库条数(\(rows.count))与缓存条数(\(cachedCount))不匹配，需要全量加载")
                return nil
            }

            Logger.info("数据库条数与缓存条数匹配，使用缓存数据")

            // 加载数据
            var results: [Int: [LPStoreOffer]] = [:]
            var currentCorpId: Int64?
            var currentOffers: [LPStoreOffer] = []
            var decodeFailCount = 0

            for row in rows {
                // 检查必要字段
                guard let corpId = row["corporation_id"] as? Int64 else {
                    Logger.error("无法获取corporation_id: \(row)")
                    continue
                }

                guard let offersData = row["offers_data"] as? String else {
                    Logger.error("无法获取offers_data: \(row)")
                    continue
                }

                guard let data = offersData.data(using: .utf8) else {
                    Logger.error("无法将offers_data转换为Data: \(offersData)")
                    continue
                }

                do {
                    let offer = try JSONDecoder().decode(LPStoreOffer.self, from: data)
                    if currentCorpId != corpId {
                        if let corpId = currentCorpId {
                            results[Int(corpId)] = currentOffers
                        }
                        currentCorpId = corpId
                        currentOffers = []
                    }
                    currentOffers.append(offer)
                } catch {
                    decodeFailCount += 1
                    Logger.error(
                        "LP商店数据JSON解码失败 - corpId: \(corpId), error: \(error), data: \(offersData)")
                }
            }

            // 添加最后一个军团的数据
            if let corpId = currentCorpId {
                results[Int(corpId)] = currentOffers
            }

            if !results.isEmpty {
                Logger.info("从数据库加载LP商店数据成功 - 军团数量: \(results.count)，解码失败: \(decodeFailCount) 条")
                return results
            } else {
                Logger.warning("所有LP商店数据解码失败，需要重新加载")
                return nil
            }
        }

        return nil
    }

    /// 批量获取多个军团的LP商店兑换列表
    /// - Parameters:
    ///   - corporationIds: 军团ID数组
    ///   - maxConcurrent: 最大并发请求数，默认100
    ///   - progressCallback: 进度回调，返回已完成的军团ID数量
    ///   - forceRefresh: 是否强制刷新缓存
    /// - Returns: 包含军团ID和对应LP兑换列表的字典
    func fetchMultipleCorporationsLPStoreOffers(
        corporationIds: [Int],
        maxConcurrent: Int = 100,
        progressCallback: ((Int) -> Void)? = nil,
        forceRefresh: Bool = false
    ) async throws -> [Int: [LPStoreOffer]] {
        // 如果不是强制刷新，尝试从数据库加载数据
        if !forceRefresh {
            if let cachedResults = loadMultipleCorporationsFromDatabase(
                corporationIds: corporationIds)
            {
                Logger.info("使用缓存的LP商店数据 - 军团数量: \(cachedResults.count)")
                return cachedResults
            }
        }

        Logger.info("缓存无效或不存在，开始从网络获取数据")
        var results: [Int: [LPStoreOffer]] = [:]
        var completedCount = 0

        // 使用TaskGroup进行并发网络请求
        try await withThrowingTaskGroup(of: (corporationId: Int, data: Data).self) { group in
            // 添加初始任务
            for corporationId in corporationIds.prefix(maxConcurrent) {
                group.addTask(priority: .userInitiated) {
                    let data = try await self.fetchLPStoreDataFromAPI(corporationId: corporationId)
                    return (corporationId: corporationId, data: data)
                }
            }

            // 处理完成的任务并添加新任务
            var remainingIds = Array(corporationIds.dropFirst(maxConcurrent))

            for try await result in group {
                if let offers = try? JSONDecoder().decode([LPStoreOffer].self, from: result.data) {
                    results[result.corporationId] = offers
                }
                completedCount += 1
                progressCallback?(completedCount)

                // 如果还有剩余军团ID，添加新任务
                if let nextId = remainingIds.first {
                    remainingIds.removeFirst()
                    group.addTask(priority: .userInitiated) {
                        let data = try await self.fetchLPStoreDataFromAPI(corporationId: nextId)
                        return (corporationId: nextId, data: data)
                    }
                }
            }
        }

        // 所有网络请求完成后，批量保存数据
        if !results.isEmpty {
            await saveLPStoreOffersBatch(results)
            // 计算总条数并设置全量加载条数
            let totalCount = results.values.flatMap { $0 }.count
            UserDefaultsManager.shared.LPStoreFullLoadCount = totalCount
            Logger.info("设置LP商店全量加载条数: \(totalCount)")
        }

        return results
    }

    /// 从ESI API获取LP商店数据
    private func fetchLPStoreDataFromAPI(corporationId: Int) async throws -> Data {
        let baseURL = "https://esi.evetech.net/loyalty/stores/\(corporationId)/offers/"
        var components = URLComponents(string: baseURL)
        components?.queryItems = [
            URLQueryItem(name: "datasource", value: "tranquility"),
        ]

        guard let url = components?.url else {
            throw LPStoreAPIError.invalidURL
        }

        return try await NetworkManager.shared.fetchData(from: url)
    }

    /// 批量保存LP商店数据
    private func saveLPStoreOffersBatch(_ offers: [Int: [LPStoreOffer]]) async {
        // 开始事务
        _ = CharacterDatabaseManager.shared.executeQuery("BEGIN TRANSACTION")

        // 设置每批次的大小
        let batchSize = 300
        var success = true

        // 收集所有需要保存的数据
        var allOffers: [(corporationId: Int, offer: LPStoreOffer)] = []
        for (corporationId, corpOffers) in offers {
            for offer in corpOffers {
                allOffers.append((corporationId: corporationId, offer: offer))
            }
        }

        // 分批处理数据
        for batchStart in stride(from: 0, to: allOffers.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, allOffers.count)
            let currentBatch = Array(allOffers[batchStart ..< batchEnd])

            // 构建批量插入语句
            let placeholders = Array(repeating: "(?, ?, ?, ?)", count: currentBatch.count).joined(
                separator: ",")
            let batchInsertQuery = """
                INSERT OR REPLACE INTO LPStoreOffers_v2 (
                    corporation_id, offer_id, type_id, offers_data
                ) VALUES \(placeholders)
            """

            // 准备参数数组
            var parameters: [Any] = []
            for (corporationId, offer) in currentBatch {
                guard let offerData = try? JSONEncoder().encode(offer),
                      let offerString = String(data: offerData, encoding: .utf8)
                else {
                    continue
                }
                parameters.append(contentsOf: [
                    corporationId, offer.offerId, offer.typeId, offerString,
                ])
            }

            Logger.debug("执行批量插入LP商店数据，批次大小: \(currentBatch.count), 参数数量: \(parameters.count)")

            // 执行批量插入
            if case let .error(error) = CharacterDatabaseManager.shared.executeQuery(
                batchInsertQuery, parameters: parameters
            ) {
                Logger.error("批量插入LP商店数据失败: \(error)")
                success = false
                break
            }
        }

        // 保存物品索引数据
        if success {
            success = await saveLPStoreItemIndex(offers)
        }

        // 根据执行结果提交或回滚事务
        if success {
            _ = CharacterDatabaseManager.shared.executeQuery("COMMIT")
            // 更新UserDefaults中的更新时间
            UserDefaultsManager.shared.LPStoreUpdatetime = Date()
            Logger.info("批量保存LP商店数据到数据库 - 军团数量: \(offers.count), 总记录数: \(allOffers.count)")
        } else {
            _ = CharacterDatabaseManager.shared.executeQuery("ROLLBACK")
            Logger.error("批量保存LP商店数据失败，执行回滚")
        }
    }

    /// 保存LP商店物品索引数据
    private func saveLPStoreItemIndex(_ offers: [Int: [LPStoreOffer]]) async -> Bool {
        // 收集所有物品类型ID
        var allTypeIds = Set<Int>()
        var allCorporationIds = Set<Int>()

        for (corporationId, corpOffers) in offers {
            allCorporationIds.insert(corporationId)
            for offer in corpOffers {
                allTypeIds.insert(offer.typeId)
            }
        }

        // 批量查询物品名称
        let itemNames = await getItemNames(typeIds: Array(allTypeIds))

        // 批量查询军团所属势力
        let corporationFactions = await getCorporationFactions(
            corporationIds: Array(allCorporationIds))

        // 删除旧的索引数据
        let deleteQuery = """
            DELETE FROM LPStoreItemIndex 
            WHERE corporation_id IN (\(allCorporationIds.map { String($0) }.joined(separator: ",")))
        """
        _ = CharacterDatabaseManager.shared.executeQuery(deleteQuery)

        // 准备批量插入索引数据
        let batchSize = 300
        var indexData:
            [(
                typeId: Int, typeNameZh: String?, typeNameEn: String?, offerId: Int,
                factionId: Int?, corporationId: Int
            )] = []

        for (corporationId, corpOffers) in offers {
            let factionId = corporationFactions[corporationId]
            for offer in corpOffers {
                let itemName = itemNames[offer.typeId]
                indexData.append(
                    (
                        typeId: offer.typeId,
                        typeNameZh: itemName?.zh,
                        typeNameEn: itemName?.en,
                        offerId: offer.offerId,
                        factionId: factionId,
                        corporationId: corporationId
                    ))
            }
        }

        // 分批插入索引数据
        for batchStart in stride(from: 0, to: indexData.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, indexData.count)
            let currentBatch = Array(indexData[batchStart ..< batchEnd])

            let placeholders = Array(repeating: "(?, ?, ?, ?, ?, ?)", count: currentBatch.count)
                .joined(separator: ",")
            let batchInsertQuery = """
                INSERT OR REPLACE INTO LPStoreItemIndex (
                    type_id, type_name_zh, type_name_en, offer_id, faction_id, corporation_id
                ) VALUES \(placeholders)
            """

            var parameters: [Any] = []
            for item in currentBatch {
                parameters.append(contentsOf: [
                    item.typeId,
                    item.typeNameZh as Any,
                    item.typeNameEn as Any,
                    item.offerId,
                    item.factionId as Any,
                    item.corporationId,
                ])
            }

            if case let .error(error) = CharacterDatabaseManager.shared.executeQuery(
                batchInsertQuery, parameters: parameters
            ) {
                Logger.error("批量插入LP商店物品索引失败: \(error)")
                return false
            }
        }

        Logger.info("保存LP商店物品索引成功 - 索引记录数: \(indexData.count)")
        return true
    }

    /// 批量获取物品名称
    private func getItemNames(typeIds: [Int]) async -> [Int: (zh: String, en: String)] {
        guard !typeIds.isEmpty else { return [:] }

        let placeholders = Array(repeating: "?", count: typeIds.count).joined(separator: ",")
        let query = """
            SELECT type_id, zh_name, en_name
            FROM types
            WHERE type_id IN (\(placeholders))
        """

        var itemNames: [Int: (zh: String, en: String)] = [:]

        if case let .success(rows) = DatabaseManager.shared.executeQuery(query, parameters: typeIds) {
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                   let zhName = row["zh_name"] as? String,
                   let enName = row["en_name"] as? String
                {
                    itemNames[typeId] = (zh: zhName, en: enName)
                }
            }
        }

        return itemNames
    }

    /// 批量获取军团所属势力
    private func getCorporationFactions(corporationIds: [Int]) async -> [Int: Int] {
        guard !corporationIds.isEmpty else { return [:] }

        let placeholders = Array(repeating: "?", count: corporationIds.count).joined(separator: ",")
        let query = """
            SELECT corporation_id, faction_id
            FROM npcCorporations
            WHERE corporation_id IN (\(placeholders))
        """

        var corporationFactions: [Int: Int] = [:]

        if case let .success(rows) = DatabaseManager.shared.executeQuery(
            query, parameters: corporationIds
        ) {
            for row in rows {
                if let corporationId = row["corporation_id"] as? Int,
                   let factionId = row["faction_id"] as? Int
                {
                    corporationFactions[corporationId] = factionId
                }
            }
        }

        return corporationFactions
    }

    // MARK: - 私有方法

    private func loadFromDatabase(corporationId: Int) throws -> [LPStoreOffer]? {
        // 首先检查UserDefaults中的更新时间
        guard let lastUpdateTime = UserDefaultsManager.shared.LPStoreUpdatetime else {
            Logger.info("未找到LP商店数据更新时间记录 - 军团ID: \(corporationId)")
            return nil
        }

        let currentDate = Date()
        let timeSinceUpdate = currentDate.timeIntervalSince(lastUpdateTime)

        if timeSinceUpdate >= cacheDuration {
            Logger.info(
                "缓存已过期 - 军团ID: \(corporationId), 最后更新: \(lastUpdateTime), 已过期: \(Int(timeSinceUpdate))秒"
            )
            return nil
        }

        let query = """
            SELECT offer_id, type_id, offers_data
            FROM LPStoreOffers_v2 
            WHERE corporation_id = ?
            ORDER BY offer_id
        """

        if case let .success(rows) = CharacterDatabaseManager.shared.executeQuery(
            query, parameters: [corporationId]
        ),
            !rows.isEmpty
        {
            // 解析数据
            var offers: [LPStoreOffer] = []
            for row in rows {
                if let offersData = row["offers_data"] as? String,
                   let data = offersData.data(using: .utf8),
                   let offer = try? JSONDecoder().decode(LPStoreOffer.self, from: data)
                {
                    offers.append(offer)
                } else {
                    Logger.error(
                        "无法解析LP商店数据 - 军团ID: \(corporationId), offer_id: \(row["offer_id"] ?? "unknown")"
                    )
                }
            }
            if !offers.isEmpty {
                Logger.info(
                    "使用缓存的LP商店数据 - 军团ID: \(corporationId), 记录数: \(offers.count), 缓存时间: \(Int(timeSinceUpdate))秒"
                )
                return offers
            } else {
                Logger.warning("缓存数据为空 - 军团ID: \(corporationId)")
            }
        } else {
            Logger.info("未找到缓存数据 - 军团ID: \(corporationId)")
        }
        return nil
    }

    private func saveLPStoreOffers(corporationId: Int, offersData: Data) {
        // 首先删除该军团的所有旧数据
        let deleteQuery = "DELETE FROM LPStoreOffers_v2 WHERE corporation_id = ?"
        _ = CharacterDatabaseManager.shared.executeQuery(deleteQuery, parameters: [corporationId])

        // 解析数据
        guard let offers = try? JSONDecoder().decode([LPStoreOffer].self, from: offersData) else {
            Logger.error("无法解析LP商店数据")
            return
        }

        // 开始事务
        _ = CharacterDatabaseManager.shared.executeQuery("BEGIN TRANSACTION")

        // 设置每批次的大小
        let batchSize = 300 // 每批次处理300条记录
        var success = true

        // 分批处理数据
        for batchStart in stride(from: 0, to: offers.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, offers.count)
            let currentBatch = Array(offers[batchStart ..< batchEnd])

            // 构建批量插入语句
            let placeholders = Array(repeating: "(?, ?, ?, ?)", count: currentBatch.count).joined(
                separator: ",")
            let batchInsertQuery = """
                INSERT OR REPLACE INTO LPStoreOffers_v2 (
                    corporation_id, offer_id, type_id, offers_data
                ) VALUES \(placeholders)
            """

            // 准备参数数组
            var parameters: [Any] = []
            for offer in currentBatch {
                guard let offerData = try? JSONEncoder().encode(offer),
                      let offerString = String(data: offerData, encoding: .utf8)
                else {
                    continue
                }
                parameters.append(contentsOf: [
                    corporationId, offer.offerId, offer.typeId, offerString,
                ])
            }

            Logger.debug("执行批量插入LP商店数据，批次大小: \(currentBatch.count), 参数数量: \(parameters.count)")

            // 执行批量插入
            if case let .error(error) = CharacterDatabaseManager.shared.executeQuery(
                batchInsertQuery, parameters: parameters
            ) {
                Logger.error("批量插入LP商店数据失败: \(error)")
                success = false
                break
            }
        }

        // 保存物品索引数据
        if success {
            Task {
                let offersDict = [corporationId: offers]
                success = await saveLPStoreItemIndex(offersDict)

                // 根据执行结果提交或回滚事务
                if success {
                    _ = CharacterDatabaseManager.shared.executeQuery("COMMIT")
                    // 更新UserDefaults中的更新时间（单个军团加载不影响全量加载时间戳）
                    UserDefaultsManager.shared.LPStoreUpdatetime = Date()
                    Logger.info("保存LP商店数据到数据库 - 军团ID: \(corporationId), 总记录数: \(offers.count)")
                } else {
                    _ = CharacterDatabaseManager.shared.executeQuery("ROLLBACK")
                    Logger.error("保存LP商店数据失败，执行回滚")
                }
            }
        } else {
            _ = CharacterDatabaseManager.shared.executeQuery("ROLLBACK")
            Logger.error("保存LP商店数据失败，执行回滚")
        }
    }
}
