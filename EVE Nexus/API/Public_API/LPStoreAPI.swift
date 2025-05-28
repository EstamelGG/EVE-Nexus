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
    private let cacheDuration: TimeInterval = 3600 * 24 * 7 // 7 天缓存

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
    private func loadMultipleCorporationsFromDatabase(corporationIds: [Int]) -> [Int: [LPStoreOffer]]? {
        let query = """
            SELECT corporation_id, offer_id, type_id, offers_data, last_updated
            FROM LPStoreOffers
            WHERE corporation_id IN (\(corporationIds.map { String($0) }.joined(separator: ",")))
            ORDER BY corporation_id, last_updated DESC
        """
        
        if case let .success(rows) = CharacterDatabaseManager.shared.executeQuery(query) {
            Logger.info("从数据库查询到 \(rows.count) 条LP商店数据")
            
            // 找到最老的更新时间
            var oldestUpdate: Date?
            for row in rows {
                // 处理Int64类型的时间戳
                if let lastUpdated = row["last_updated"] as? Int64 {
                    let updateDate = Date(timeIntervalSince1970: TimeInterval(lastUpdated))
                    if oldestUpdate == nil || updateDate < oldestUpdate! {
                        oldestUpdate = updateDate
                    }
                } else {
                    Logger.error("无法获取时间戳: \(row)")
                }
            }
            
            // 检查缓存是否过期
            if let oldestUpdate = oldestUpdate {
                let currentDate = Date()
                let timeSinceUpdate = currentDate.timeIntervalSince(oldestUpdate)
                
                // 转换为本地时间用于日志显示
                let localDateFormatter = DateFormatter()
                localDateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                localDateFormatter.locale = Locale(identifier: "en_US_POSIX")
                localDateFormatter.timeZone = TimeZone.current
                
                Logger.info("当前时间: \(localDateFormatter.string(from: currentDate))")
                Logger.info("最老更新时间: \(localDateFormatter.string(from: oldestUpdate))")
                Logger.info("缓存时间: \(Int(timeSinceUpdate))秒, 缓存期限: \(Int(cacheDuration))秒")
                
                if timeSinceUpdate >= cacheDuration {
                    Logger.info("LP商店数据缓存已过期 - 最老更新时间: \(localDateFormatter.string(from: oldestUpdate)), 距离上次更新: \(Int(timeSinceUpdate))秒")
                    return nil
                }
                Logger.info("LP商店数据缓存有效 - 最老更新时间: \(localDateFormatter.string(from: oldestUpdate)), 距离上次更新: \(Int(timeSinceUpdate))秒")
            } else {
                Logger.info("未找到LP商店数据缓存 - 没有有效的时间戳")
                return nil
            }
            
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
                    Logger.error("LP商店数据JSON解码失败 - corpId: \(corpId), error: \(error), data: \(offersData)")
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
                Logger.warning("所有LP商店数据解码失败")
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
            if let cachedResults = loadMultipleCorporationsFromDatabase(corporationIds: corporationIds) {
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
                group.addTask {
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
                    group.addTask {
                        let data = try await self.fetchLPStoreDataFromAPI(corporationId: nextId)
                        return (corporationId: nextId, data: data)
                    }
                }
            }
        }
        
        // 所有网络请求完成后，批量保存数据
        if !results.isEmpty {
            await saveLPStoreOffersBatch(results)
        }
        
        return results
    }
    
    /// 从ESI API获取LP商店数据
    private func fetchLPStoreDataFromAPI(corporationId: Int) async throws -> Data {
        let baseURL = "https://esi.evetech.net/latest/loyalty/stores/\(corporationId)/offers/"
        var components = URLComponents(string: baseURL)
        components?.queryItems = [
            URLQueryItem(name: "datasource", value: "tranquility")
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
            let currentBatch = Array(allOffers[batchStart..<batchEnd])
            
            // 构建批量插入语句
            let placeholders = Array(repeating: "(?, ?, ?, ?, strftime('%s', 'now'))", count: currentBatch.count).joined(separator: ",")
            let batchInsertQuery = """
                INSERT OR REPLACE INTO LPStoreOffers (
                    corporation_id, offer_id, type_id, offers_data, last_updated
                ) VALUES \(placeholders)
            """
            
            // 准备参数数组
            var parameters: [Any] = []
            for (corporationId, offer) in currentBatch {
                guard let offerData = try? JSONEncoder().encode(offer),
                      let offerString = String(data: offerData, encoding: .utf8) else {
                    continue
                }
                parameters.append(contentsOf: [corporationId, offer.offerId, offer.typeId, offerString])
            }
            
            Logger.debug("执行批量插入LP商店数据，批次大小: \(currentBatch.count), 参数数量: \(parameters.count)")
            
            // 执行批量插入
            if case let .error(error) = CharacterDatabaseManager.shared.executeQuery(batchInsertQuery, parameters: parameters) {
                Logger.error("批量插入LP商店数据失败: \(error)")
                success = false
                break
            }
        }
        
        // 根据执行结果提交或回滚事务
        if success {
            _ = CharacterDatabaseManager.shared.executeQuery("COMMIT")
            Logger.info("批量保存LP商店数据到数据库 - 军团数量: \(offers.count), 总记录数: \(allOffers.count)")
        } else {
            _ = CharacterDatabaseManager.shared.executeQuery("ROLLBACK")
            Logger.error("批量保存LP商店数据失败，执行回滚")
        }
    }

    // MARK: - 私有方法

    private func loadFromDatabase(corporationId: Int) throws -> [LPStoreOffer]? {
        let query = """
                SELECT offer_id, type_id, offers_data, last_updated 
                FROM LPStoreOffers 
                WHERE corporation_id = ?
                ORDER BY offer_id
            """

        if case let .success(rows) = CharacterDatabaseManager.shared.executeQuery(
            query, parameters: [corporationId]
        ),
            !rows.isEmpty,
            let lastUpdated = rows.first?["last_updated"] as? String
        {
            // 检查是否过期
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.timeZone = TimeZone(identifier: "UTC")  // 使用UTC时区
            
            if let updateDate = dateFormatter.date(from: lastUpdated) {
                let currentDate = Date()
                let timeSinceUpdate = currentDate.timeIntervalSince(updateDate)
                
                if timeSinceUpdate < cacheDuration {
                    // 解析数据
                    var offers: [LPStoreOffer] = []
                    for row in rows {
                        if let offersData = row["offers_data"] as? String,
                           let data = offersData.data(using: .utf8),
                           let offer = try? JSONDecoder().decode(LPStoreOffer.self, from: data) {
                            offers.append(offer)
                        } else {
                            Logger.error("无法解析LP商店数据 - 军团ID: \(corporationId), offer_id: \(row["offer_id"] ?? "unknown")")
                        }
                    }
                    if !offers.isEmpty {
                        Logger.info("使用缓存的LP商店数据 - 军团ID: \(corporationId), 记录数: \(offers.count), 缓存时间: \(Int(timeSinceUpdate))秒")
                        return offers
                    } else {
                        Logger.warning("缓存数据为空 - 军团ID: \(corporationId)")
                    }
                } else {
                    Logger.info("缓存已过期 - 军团ID: \(corporationId), 最后更新: \(lastUpdated), 已过期: \(Int(timeSinceUpdate))秒")
                }
            } else {
                Logger.error("无法解析缓存时间 - 军团ID: \(corporationId), 时间字符串: \(lastUpdated)")
            }
        } else {
            Logger.info("未找到缓存数据 - 军团ID: \(corporationId)")
        }
        return nil
    }

    private func saveLPStoreOffers(corporationId: Int, offersData: Data) {
        // 首先删除该军团的所有旧数据
        let deleteQuery = "DELETE FROM LPStoreOffers WHERE corporation_id = ?"
        _ = CharacterDatabaseManager.shared.executeQuery(deleteQuery, parameters: [corporationId])

        // 解析数据
        guard let offers = try? JSONDecoder().decode([LPStoreOffer].self, from: offersData) else {
            Logger.error("无法解析LP商店数据")
            return
        }

        // 开始事务
        _ = CharacterDatabaseManager.shared.executeQuery("BEGIN TRANSACTION")

        // 设置每批次的大小
        let batchSize = 300  // 每批次处理300条记录
        var success = true

        // 分批处理数据
        for batchStart in stride(from: 0, to: offers.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, offers.count)
            let currentBatch = Array(offers[batchStart..<batchEnd])

            // 构建批量插入语句
            let placeholders = Array(repeating: "(?, ?, ?, ?, strftime('%s', 'now'))", count: currentBatch.count).joined(separator: ",")
            let batchInsertQuery = """
                INSERT OR REPLACE INTO LPStoreOffers (
                    corporation_id, offer_id, type_id, offers_data, last_updated
                ) VALUES \(placeholders)
            """
            
            // 准备参数数组
            var parameters: [Any] = []
            for offer in currentBatch {
                guard let offerData = try? JSONEncoder().encode(offer),
                      let offerString = String(data: offerData, encoding: .utf8) else {
                    continue
                }
                parameters.append(contentsOf: [corporationId, offer.offerId, offer.typeId, offerString])
            }

            Logger.debug("执行批量插入LP商店数据，批次大小: \(currentBatch.count), 参数数量: \(parameters.count)")

            // 执行批量插入
            if case let .error(error) = CharacterDatabaseManager.shared.executeQuery(batchInsertQuery, parameters: parameters) {
                Logger.error("批量插入LP商店数据失败: \(error)")
                success = false
                break
            }
        }

        // 根据执行结果提交或回滚事务
        if success {
            _ = CharacterDatabaseManager.shared.executeQuery("COMMIT")
            Logger.info("保存LP商店数据到数据库 - 军团ID: \(corporationId), 总记录数: \(offers.count)")
        } else {
            _ = CharacterDatabaseManager.shared.executeQuery("ROLLBACK")
            Logger.error("保存LP商店数据失败，执行回滚")
        }
    }
}
