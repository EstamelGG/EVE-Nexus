import Foundation

// 星堡详细信息模型
public struct StarbaseDetailInfo: Codable {
    public let allow_alliance_members: Bool
    public let allow_corporation_members: Bool
    public let anchor: String
    public let attack_if_at_war: Bool
    public let attack_if_other_security_status_dropping: Bool
    public let attack_security_status_threshold: Double
    public let attack_standing_threshold: Double
    public let fuel_bay_take: String
    public let fuel_bay_view: String
    public let fuels: [StarbaseFuel]
    public let offline: String
    public let online: String
    public let unanchor: String
    public let use_alliance_standings: Bool
}

// 星堡燃料信息模型
public struct StarbaseFuel: Codable {
    public let quantity: Int
    public let type_id: Int
}

// 星堡查询参数
public struct StarbaseQueryParams: Hashable, Codable {
    public let starbaseId: Int
    public let corporationId: Int
    public let systemId: Int

    public init(starbaseId: Int, corporationId: Int, systemId: Int) {
        self.starbaseId = starbaseId
        self.corporationId = corporationId
        self.systemId = systemId
    }
}

// 缓存数据结构
private struct StarbaseDetailCacheData: Codable {
    let data: StarbaseDetailInfo
    let timestamp: Date

    var isExpired: Bool {
        // 设置缓存有效期为8小时
        return Date().timeIntervalSince(timestamp) > 8 * 3600
    }
}

public class CorpStarbaseDetailAPI {
    public static let shared = CorpStarbaseDetailAPI()

    private init() {}

    // MARK: - Public Methods

    /// 获取单个星堡详细信息
    /// - Parameters:
    ///   - starbaseId: 星堡ID
    ///   - corporationId: 军团ID
    ///   - systemId: 星系ID
    ///   - characterId: 角色ID（用于认证）
    ///   - forceRefresh: 是否强制刷新
    /// - Returns: 星堡详细信息
    public func fetchStarbaseDetail(
        starbaseId: Int,
        corporationId: Int,
        systemId: Int,
        characterId: Int,
        forceRefresh: Bool = false
    ) async throws -> StarbaseDetailInfo {
        // 检查缓存
        if !forceRefresh, let cachedData = loadStarbaseDetailFromCache(
            starbaseId: starbaseId,
            corporationId: corporationId,
            systemId: systemId
        ) {
            Logger.info(
                "使用缓存的星堡详细信息 - 星堡ID: \(starbaseId), 军团ID: \(corporationId), 星系ID: \(systemId)"
            )
            return cachedData
        }

        let urlString =
            "https://esi.evetech.net/corporations/\(corporationId)/starbases/\(starbaseId)?system_id=\(systemId)&datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        Logger.info(
            "开始获取星堡详细信息 - 星堡ID: \(starbaseId), 军团ID: \(corporationId), 星系ID: \(systemId)"
        )

        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId,
            forceRefresh: forceRefresh,
            timeouts: [2, 10, 15, 15, 15]
        )

        let decoder = JSONDecoder()
        let detail = try decoder.decode(StarbaseDetailInfo.self, from: data)

        // 保存到缓存
        saveStarbaseDetailToCache(
            detail,
            starbaseId: starbaseId,
            corporationId: corporationId,
            systemId: systemId
        )

        Logger.success(
            "成功获取星堡详细信息 - 星堡ID: \(starbaseId), 军团ID: \(corporationId), 星系ID: \(systemId)"
        )

        return detail
    }

    /// 批量获取星堡详细信息（最多10个并发）
    /// - Parameters:
    ///   - queries: 查询参数数组，每个元素包含 [starbaseId, corporationId, systemId]
    ///   - characterId: 角色ID（用于认证）
    ///   - forceRefresh: 是否强制刷新
    ///   - progressCallback: 进度回调，参数为 (当前完成数, 总数)
    /// - Returns: 查询结果字典，key为查询参数，value为详细信息（如果查询失败则为nil）
    public func fetchStarbaseDetailsBatch(
        queries: [StarbaseQueryParams],
        characterId: Int,
        forceRefresh: Bool = false,
        progressCallback: ((Int, Int) -> Void)? = nil
    ) async -> [StarbaseQueryParams: StarbaseDetailInfo?] {
        guard !queries.isEmpty else {
            Logger.info("批量查询星堡详细信息：查询列表为空")
            return [:]
        }

        let maxConcurrency = min(10, queries.count)
        Logger.info(
            "开始批量获取星堡详细信息 - 总数: \(queries.count), 并发数: \(maxConcurrency)"
        )

        var results: [StarbaseQueryParams: StarbaseDetailInfo?] = [:]
        var completedCount = 0
        let totalCount = queries.count

        do {
            try await withThrowingTaskGroup(of: (StarbaseQueryParams, StarbaseDetailInfo?).self) { group in
                var pendingQueries = queries
                var inProgressCount = 0

                // 初始添加并发数量的任务
                while !pendingQueries.isEmpty, inProgressCount < maxConcurrency {
                    let query = pendingQueries.removeFirst()
                    group.addTask(priority: .userInitiated) {
                        do {
                            let detail = try await CorpStarbaseDetailAPI.shared.fetchStarbaseDetail(
                                starbaseId: query.starbaseId,
                                corporationId: query.corporationId,
                                systemId: query.systemId,
                                characterId: characterId,
                                forceRefresh: forceRefresh
                            )
                            return (query, detail)
                        } catch {
                            Logger.error(
                                "获取星堡详细信息失败 - 星堡ID: \(query.starbaseId), 军团ID: \(query.corporationId), 星系ID: \(query.systemId), 错误: \(error)"
                            )
                            return (query, nil)
                        }
                    }
                    inProgressCount += 1
                }

                // 处理结果并添加新任务
                while let result = try await group.next() {
                    let (query, detail) = result
                    results[query] = detail
                    completedCount += 1
                    inProgressCount -= 1

                    // 调用进度回调
                    progressCallback?(completedCount, totalCount)

                    // 如果还有待处理的查询，添加新任务
                    if !pendingQueries.isEmpty {
                        let nextQuery = pendingQueries.removeFirst()
                        group.addTask(priority: .userInitiated) {
                            do {
                                let detail = try await CorpStarbaseDetailAPI.shared.fetchStarbaseDetail(
                                    starbaseId: nextQuery.starbaseId,
                                    corporationId: nextQuery.corporationId,
                                    systemId: nextQuery.systemId,
                                    characterId: characterId,
                                    forceRefresh: forceRefresh
                                )
                                return (nextQuery, detail)
                            } catch {
                                Logger.error(
                                    "获取星堡详细信息失败 - 星堡ID: \(nextQuery.starbaseId), 军团ID: \(nextQuery.corporationId), 星系ID: \(nextQuery.systemId), 错误: \(error)"
                                )
                                return (nextQuery, nil)
                            }
                        }
                        inProgressCount += 1
                    }
                }
            }
        } catch {
            Logger.error("批量获取星堡详细信息时发生错误: \(error)")
            // 即使发生错误，也返回已获取的结果
        }

        Logger.success(
            "批量获取星堡详细信息完成 - 总数: \(totalCount), 成功: \(results.values.compactMap { $0 }.count), 失败: \(results.values.filter { $0 == nil }.count)"
        )

        return results
    }

    // MARK: - Cache Methods

    private func getCacheDirectory() -> URL? {
        guard
            let documentsDirectory = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask
            ).first
        else {
            return nil
        }
        let cacheDirectory = documentsDirectory.appendingPathComponent(
            "CorpStarbaseDetail", isDirectory: true
        )

        // 确保缓存目录存在
        try? FileManager.default.createDirectory(
            at: cacheDirectory, withIntermediateDirectories: true, attributes: nil
        )

        return cacheDirectory
    }

    private func getCacheFilePath(
        starbaseId: Int,
        corporationId: Int,
        systemId: Int
    ) -> URL? {
        guard let cacheDirectory = getCacheDirectory() else { return nil }
        return cacheDirectory.appendingPathComponent(
            "corp_\(corporationId)_starbase_\(starbaseId)_system_\(systemId).json"
        )
    }

    private func loadStarbaseDetailFromCache(
        starbaseId: Int,
        corporationId: Int,
        systemId: Int
    ) -> StarbaseDetailInfo? {
        guard let cacheFile = getCacheFilePath(
            starbaseId: starbaseId,
            corporationId: corporationId,
            systemId: systemId
        ) else {
            Logger.error(
                "获取缓存文件路径失败 - 星堡ID: \(starbaseId), 军团ID: \(corporationId), 星系ID: \(systemId)"
            )
            return nil
        }

        do {
            guard FileManager.default.fileExists(atPath: cacheFile.path) else {
                Logger.info(
                    "缓存文件不存在 - 星堡ID: \(starbaseId), 军团ID: \(corporationId), 星系ID: \(systemId)"
                )
                return nil
            }

            let data = try Data(contentsOf: cacheFile)
            let cached = try JSONDecoder().decode(StarbaseDetailCacheData.self, from: data)

            if cached.isExpired {
                Logger.info(
                    "缓存已过期 - 星堡ID: \(starbaseId), 军团ID: \(corporationId), 星系ID: \(systemId)"
                )
                try? FileManager.default.removeItem(at: cacheFile)
                return nil
            }

            Logger.success(
                "成功从缓存加载星堡详细信息 - 星堡ID: \(starbaseId), 军团ID: \(corporationId), 星系ID: \(systemId)"
            )
            return cached.data
        } catch {
            Logger.error(
                "读取缓存文件失败 - 星堡ID: \(starbaseId), 军团ID: \(corporationId), 星系ID: \(systemId), 错误: \(error)"
            )
            try? FileManager.default.removeItem(at: cacheFile)
            return nil
        }
    }

    private func saveStarbaseDetailToCache(
        _ detail: StarbaseDetailInfo,
        starbaseId: Int,
        corporationId: Int,
        systemId: Int
    ) {
        guard let cacheFile = getCacheFilePath(
            starbaseId: starbaseId,
            corporationId: corporationId,
            systemId: systemId
        ) else {
            Logger.error(
                "获取缓存文件路径失败 - 星堡ID: \(starbaseId), 军团ID: \(corporationId), 星系ID: \(systemId)"
            )
            return
        }

        do {
            let cachedData = StarbaseDetailCacheData(data: detail, timestamp: Date())
            let encodedData = try JSONEncoder().encode(cachedData)
            try encodedData.write(to: cacheFile)
            Logger.info(
                "星堡详细信息已缓存到文件 - 星堡ID: \(starbaseId), 军团ID: \(corporationId), 星系ID: \(systemId)"
            )
        } catch {
            Logger.error(
                "保存星堡详细信息缓存失败 - 星堡ID: \(starbaseId), 军团ID: \(corporationId), 星系ID: \(systemId), 错误: \(error)"
            )
            try? FileManager.default.removeItem(at: cacheFile)
        }
    }
}
