import Foundation

// 战斗记录数据模型
struct KillMailInfo: Codable, Equatable {
    let killmail_hash: String
    let killmail_id: Int
    let locationID: Int?
    let totalValue: Double?
    let npc: Bool?
    let solo: Bool?
    let awox: Bool?

    private struct ZKB: Codable, Equatable {
        let locationID: Int?
        let hash: String
        let totalValue: Double?
        let npc: Bool?
        let solo: Bool?
        let awox: Bool?
    }

    enum CodingKeys: String, CodingKey {
        case killmail_id
        case zkb
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        killmail_id = try container.decode(Int.self, forKey: .killmail_id)

        let zkb = try container.decode(ZKB.self, forKey: .zkb)
        killmail_hash = zkb.hash
        locationID = zkb.locationID
        totalValue = zkb.totalValue
        npc = zkb.npc
        solo = zkb.solo
        awox = zkb.awox
    }

    init(
        killmail_hash: String, killmail_id: Int, locationID: Int?, totalValue: Double?, npc: Bool?,
        solo: Bool?, awox: Bool?
    ) {
        self.killmail_hash = killmail_hash
        self.killmail_id = killmail_id
        self.locationID = locationID
        self.totalValue = totalValue
        self.npc = npc
        self.solo = solo
        self.awox = awox
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(killmail_id, forKey: .killmail_id)

        let zkb = ZKB(
            locationID: locationID,
            hash: killmail_hash,
            totalValue: totalValue,
            npc: npc,
            solo: solo,
            awox: awox
        )
        try container.encode(zkb, forKey: .zkb)
    }
}

// 查询类型枚举
enum KillMailQueryType {
    case character(Int)
    case corporation(Int)

    var endpoint: String {
        switch self {
        case let .character(id):
            return "characterID/\(id)"
        case let .corporation(id):
            return "corporationID/\(id)"
        }
    }

    var tableName: String {
        switch self {
        case .character:
            return "killmails"
        case .corporation:
            return "corp_killmails"
        }
    }

    var idColumnName: String {
        switch self {
        case .character:
            return "character_id"
        case .corporation:
            return "corporation_id"
        }
    }

    var id: Int {
        switch self {
        case let .character(id), let .corporation(id):
            return id
        }
    }
}

// MARK: - 战斗统计相关结构体

struct CharBattleIsk: Codable {
    let iskDestroyed: Double
    let iskLost: Double

    enum CodingKeys: String, CodingKey {
        case iskDestroyed = "s-a-id"
        case iskLost = "s-a-il"
    }
}

class ZKillMailsAPI {
    static let shared = ZKillMailsAPI()

    // 通知名称常量
    static let killmailsUpdatedNotification = "KillmailsUpdatedNotification"
    static let killmailsUpdatedIdKey = "UpdatedId"
    static let killmailsUpdatedTypeKey = "UpdatedType"

    private let lastKillmailsQueryKey = "LastKillmailsQuery_"
    private let cacheTimeout: TimeInterval = 8 * 3600  // 8小时缓存有效期
    private let maxPages = 20  // zKillboard最大页数限制

    private init() {}

    // 获取最后查询时间
    private func getLastQueryTime(queryType: KillMailQueryType) -> Date? {
        let key = lastKillmailsQueryKey + String(queryType.id)
        return UserDefaults.standard.object(forKey: key) as? Date
    }

    // 更新最后查询时间
    private func updateLastQueryTime(queryType: KillMailQueryType) {
        let key = lastKillmailsQueryKey + String(queryType.id)
        UserDefaults.standard.set(Date(), forKey: key)
    }

    // 检查是否需要刷新数据
    private func shouldRefreshData(queryType: KillMailQueryType) -> Bool {
        guard let lastQueryTime = getLastQueryTime(queryType: queryType) else {
            return true
        }
        return Date().timeIntervalSince(lastQueryTime) >= cacheTimeout
    }

    // 从服务器获取战斗记录
    private func fetchKillMailsFromServer(queryType: KillMailQueryType, saveToDatabase: Bool)
        async throws -> [KillMailInfo]
    {
        var allKillMails: [KillMailInfo] = []
        var currentPage = 1

        // 获取数据库中最大的killmail_id
        var maxExistingKillmailId = 0
        if saveToDatabase {
            let maxIdQuery = """
                    SELECT MAX(killmail_id) as max_id 
                    FROM \(queryType.tableName) 
                    WHERE \(queryType.idColumnName) = ?
                """
            if case let .success(results) = CharacterDatabaseManager.shared.executeQuery(
                maxIdQuery, parameters: [queryType.id]
            ),
                let row = results.first,
                let maxId = row["max_id"] as? Int64
            {
                maxExistingKillmailId = Int(maxId)
                Logger.debug("数据库中最大的killmail_id: \(maxExistingKillmailId)")
            }
        }

        while currentPage <= maxPages {
            Logger.debug("开始获取第 \(currentPage) 页数据")
            let pageKillMails = try await fetchKillMailsPage(
                queryType: queryType, page: currentPage
            )

            if pageKillMails.isEmpty {
                Logger.debug("第 \(currentPage) 页数据为空，停止获取")
                break  // 如果返回空数组，说明没有更多数据
            }

            // 按killmail_id从大到小排序
            let sortedKillMails = pageKillMails.sorted { $0.killmail_id > $1.killmail_id }
            Logger.debug(
                "第 \(currentPage) 页数据排序完成，最大ID: \(sortedKillMails.first?.killmail_id ?? 0), 最小ID: \(sortedKillMails.last?.killmail_id ?? 0)"
            )

            // 检查是否存在已知的最大killmail_id
            if maxExistingKillmailId > 0 {
                let containsExistingId = sortedKillMails.contains {
                    $0.killmail_id <= maxExistingKillmailId
                }
                if containsExistingId {
                    // 只添加大于最大ID的记录
                    let newKillMails = sortedKillMails.filter {
                        $0.killmail_id > maxExistingKillmailId
                    }
                    Logger.debug("发现已存在的killmail_id，过滤后新增 \(newKillMails.count) 条记录")
                    allKillMails.append(contentsOf: newKillMails)
                    break
                }
            }

            allKillMails.append(contentsOf: sortedKillMails)
            Logger.debug("累计获取 \(allKillMails.count) 条记录")
            currentPage += 1
        }

        if saveToDatabase, !allKillMails.isEmpty {
            Logger.debug("开始保存 \(allKillMails.count) 条记录到数据库")
            // 更新最后查询时间
            updateLastQueryTime(queryType: queryType)

            // 保存到数据库
            if !saveKillMailsToDB(queryType: queryType, killmails: allKillMails) {
                Logger.error("保存战斗记录到数据库失败")
            } else {
                Logger.debug("成功保存战斗记录到数据库")
                // 发送数据更新通知
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: Notification.Name(ZKillMailsAPI.killmailsUpdatedNotification),
                        object: nil,
                        userInfo: [
                            ZKillMailsAPI.killmailsUpdatedIdKey: queryType.id,
                            ZKillMailsAPI.killmailsUpdatedTypeKey: String(describing: queryType),
                        ]
                    )
                }
            }
        }

        Logger.info("成功从zKillboard获取战斗记录 - ID: \(queryType.id), 记录数量: \(allKillMails.count)")

        return allKillMails
    }

    // 获取单页战斗记录
    private func fetchKillMailsPage(queryType: KillMailQueryType, page: Int) async throws
        -> [KillMailInfo]
    {
        let url = URL(string: "https://zkillboard.com/api/\(queryType.endpoint)/page/\(page)/")!

        var request = URLRequest(url: url)
        request.setValue("EVE-Nexus", forHTTPHeaderField: "User-Agent")

        Logger.debug("开始请求zKillboard API - 页码: \(page)")
        let data = try await NetworkManager.shared.fetchData(
            from: url, headers: ["User-Agent": "EVE-Nexus"]
        )
        Logger.debug("收到zKillboard响应 - 数据大小: \(data.count) bytes")

        do {
            let decoder = JSONDecoder()
            let killmails = try decoder.decode([KillMailInfo].self, from: data)
            Logger.debug("成功解析战斗记录 - 页码: \(page), 记录数量: \(killmails.count)")
            return killmails
        } catch {
            Logger.error("解析战斗记录失败 - 页码: \(page), 错误: \(error)")
            if let jsonString = String(data: data, encoding: .utf8) {
                Logger.debug("原始JSON数据: \(jsonString)")
            }
            throw error
        }
    }

    // 保存战斗记录到数据库
    private func saveKillMailsToDB(queryType: KillMailQueryType, killmails: [KillMailInfo]) -> Bool
    {
        Logger.debug("开始保存战斗记录到数据库，记录数量: \(killmails.count)")
        var newCount = 0

        let insertSQL = """
                INSERT OR IGNORE INTO \(queryType.tableName) (
                    \(queryType.idColumnName), killmail_id, killmail_hash,
                    location_id, total_value, npc, solo, awox
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """

        // 按killmail_id从大到小排序
        let sortedKillMails = killmails.sorted { $0.killmail_id > $1.killmail_id }

        for killmail in sortedKillMails {
            let parameters: [Any] = [
                queryType.id,
                killmail.killmail_id,
                killmail.killmail_hash,
                killmail.locationID as Any,
                killmail.totalValue as Any,
                killmail.npc ?? false,
                killmail.solo ?? false,
                killmail.awox ?? false,
            ]

            Logger.debug("尝试插入记录 - killmail_id: \(killmail.killmail_id)")
            if case let .error(message) = CharacterDatabaseManager.shared.executeQuery(
                insertSQL, parameters: parameters
            ) {
                Logger.error("保存战斗记录到数据库失败: \(message), killmail_id: \(killmail.killmail_id)")
                return false
            }

            newCount += 1
            if newCount % 100 == 0 {
                Logger.debug("已处理 \(newCount) 条记录")
            }
        }

        if newCount > 0 {
            Logger.info("数据库更新：新增\(newCount)条战斗记录")
        } else {
            Logger.debug("没有需要更新的战斗记录")
        }
        return true
    }

    // 从数据库获取战斗记录
    private func getKillMailsFromDB(queryType: KillMailQueryType) -> [KillMailInfo]? {
        let query = """
                SELECT killmail_id, killmail_hash, location_id, total_value, npc, solo, awox
                FROM \(queryType.tableName)
                WHERE \(queryType.idColumnName) = ?
                ORDER BY killmail_id DESC
            """

        if case let .success(results) = CharacterDatabaseManager.shared.executeQuery(
            query, parameters: [queryType.id]
        ) {
            return results.compactMap { row -> KillMailInfo? in
                guard let killmailId = row["killmail_id"] as? Int64,
                    let killmailHash = row["killmail_hash"] as? String
                else {
                    return nil
                }

                let locationId = row["location_id"] as? Int64
                let totalValue = row["total_value"] as? Double
                let npc = row["npc"] as? Bool ?? false
                let solo = row["solo"] as? Bool ?? false
                let awox = row["awox"] as? Bool ?? false

                return KillMailInfo(
                    killmail_hash: killmailHash,
                    killmail_id: Int(killmailId),
                    locationID: locationId != nil ? Int(locationId!) : nil,
                    totalValue: totalValue,
                    npc: npc,
                    solo: solo,
                    awox: awox
                )
            }
        }
        return nil
    }

    // 获取角色战斗记录（公开方法）
    public func fetchCharacterKillMails(
        characterId: Int, page: Int = 1, forceRefresh _: Bool = false, saveToDatabase _: Bool = true
    ) async throws -> [KillMailInfo] {
        let url = URL(
            string: "https://zkillboard.com/api/characterID/\(characterId)/page/\(page)/")!
        let headers = ["User-Agent": "EVE-Nexus"]

        Logger.info("开始获取角色战斗记录")
        Logger.debug("开始获取第 \(page) 页数据")

        let data = try await NetworkManager.shared.fetchData(from: url, headers: headers)
        let killMails = try JSONDecoder().decode([KillMailInfo].self, from: data)

        // 按killmail_id从大到小排序
        let sortedKillMails = killMails.sorted { $0.killmail_id > $1.killmail_id }

        if !sortedKillMails.isEmpty {
            Logger.debug("成功获取第 \(page) 页数据，共 \(sortedKillMails.count) 条记录")
        } else {
            Logger.debug("第 \(page) 页数据为空")
        }

        return sortedKillMails
    }

    // 获取军团战斗记录（公开方法）
    public func fetchCorporationKillMails(
        characterId: Int, forceRefresh: Bool = false, saveToDatabase: Bool = true
    ) async throws -> [KillMailInfo] {
        // 获取角色的军团ID
        guard
            let corporationId = try await CharacterDatabaseManager.shared.getCharacterCorporationId(
                characterId: characterId)
        else {
            throw NetworkError.authenticationError("无法获取军团ID")
        }

        return try await fetchKillMails(
            queryType: .corporation(corporationId), forceRefresh: forceRefresh,
            saveToDatabase: saveToDatabase
        )
    }

    // 通用获取战斗记录方法
    private func fetchKillMails(
        queryType: KillMailQueryType, forceRefresh: Bool, saveToDatabase: Bool
    ) async throws -> [KillMailInfo] {
        if saveToDatabase {
            // 检查数据库中是否有数据
            let checkQuery =
                "SELECT COUNT(*) as count FROM \(queryType.tableName) WHERE \(queryType.idColumnName) = ?"
            let result = CharacterDatabaseManager.shared.executeQuery(
                checkQuery, parameters: [queryType.id]
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
                Logger.debug("战斗记录为空或强制刷新，从zKillboard获取数据")
                return try await fetchKillMailsFromServer(
                    queryType: queryType, saveToDatabase: saveToDatabase
                )
            }

            // 检查是否需要在后台刷新
            if shouldRefreshData(queryType: queryType) {
                Logger.info("战斗记录数据已过期，在后台刷新 - ID: \(queryType.id)")

                // 在后台刷新数据
                Task {
                    do {
                        let _ = try await fetchKillMailsFromServer(
                            queryType: queryType, saveToDatabase: saveToDatabase
                        )
                        Logger.info("后台刷新战斗记录完成 - ID: \(queryType.id)")
                    } catch {
                        Logger.error("后台刷新战斗记录失败 - ID: \(queryType.id), 错误: \(error)")
                    }
                }
            }

            // 从数据库获取数据
            if let killmails = getKillMailsFromDB(queryType: queryType) {
                return killmails
            }
        } else {
            // 如果不保存到数据库，直接从服务器获取数据
            return try await fetchKillMailsFromServer(queryType: queryType, saveToDatabase: false)
        }

        return []
    }

    // 清除缓存
    func clearCache(queryType: KillMailQueryType) {
        let key = lastKillmailsQueryKey + String(queryType.id)
        UserDefaults.standard.removeObject(forKey: key)
        Logger.debug("清除战斗记录缓存 - ID: \(queryType.id)")
    }

    // 获取最近的战斗记录（公开方法）
    public func fetchRecentKillMails(characterId: Int, limit: Int = 5) async throws
        -> [KillMailInfo]
    {
        Logger.debug("开始获取最近\(limit)条战斗记录")

        // 只获取第一页数据
        let url = URL(string: "https://zkillboard.com/api/characterID/\(characterId)/page/1/")!
        let data = try await NetworkManager.shared.fetchData(
            from: url, headers: ["User-Agent": "EVE-Nexus"]
        )

        do {
            let decoder = JSONDecoder()
            var killmails = try decoder.decode([KillMailInfo].self, from: data)

            // 按killmail_id从大到小排序，只取指定数量
            killmails.sort { $0.killmail_id > $1.killmail_id }
            killmails = Array(killmails.prefix(limit))

            Logger.debug("成功获取\(killmails.count)条最近战斗记录")
            return killmails
        } catch {
            Logger.error("解析战斗记录失败: \(error)")
            throw error
        }
    }

    // 获取指定月份的战斗记录
    public func fetchMonthlyKillMails(
        characterId: Int, year: Int, month: Int, page: Int = 1, saveToDatabase _: Bool = true
    ) async throws -> [KillMailInfo] {
        let url = URL(
            string:
                "https://zkillboard.com/api/characterID/\(characterId)/year/\(year)/month/\(month)/page/\(page)/"
        )!
        let headers = ["User-Agent": "EVE-Nexus"]

        Logger.info("开始获取 \(year)年\(month)月 的战斗记录")
        Logger.debug("开始获取第 \(page) 页数据")

        let data = try await NetworkManager.shared.fetchData(from: url, headers: headers)
        let killMails = try JSONDecoder().decode([KillMailInfo].self, from: data)

        // 按killmail_id从大到小排序
        let sortedKillMails = killMails.sorted { $0.killmail_id > $1.killmail_id }

        if !sortedKillMails.isEmpty {
            Logger.debug("成功获取第 \(page) 页数据，共 \(sortedKillMails.count) 条记录")
        } else {
            Logger.debug("第 \(page) 页数据为空")
        }

        return sortedKillMails
    }

    // 获取最近一周的战斗记录
    public func fetchLastWeekKillMails(
        characterId: Int, page: Int = 1, saveToDatabase _: Bool = true
    )
        async throws -> [KillMailInfo]
    {
        let url = URL(
            string:
                "https://zkillboard.com/api/characterID/\(characterId)/pastSeconds/604800/page/\(page)/"
        )!
        let headers = ["User-Agent": "EVE-Nexus"]

        Logger.info("开始获取最近一周的战斗记录")
        Logger.debug("开始获取第 \(page) 页数据")

        let data = try await NetworkManager.shared.fetchData(from: url, headers: headers)
        let killMails = try JSONDecoder().decode([KillMailInfo].self, from: data)

        // 按killmail_id从大到小排序
        let sortedKillMails = killMails.sorted { $0.killmail_id > $1.killmail_id }

        if !sortedKillMails.isEmpty {
            Logger.debug("成功获取第 \(page) 页数据，共 \(sortedKillMails.count) 条记录")
        } else {
            Logger.debug("第 \(page) 页数据为空")
        }

        return sortedKillMails
    }

    /// 获取战斗详情
    /// - Parameters:
    ///   - killmailId: 战斗ID
    ///   - killmailHash: 战斗哈希值
    /// - Returns: 战斗详情数据
    func fetchKillMailDetail(killmailId: Int, killmailHash: String) async throws -> KillMailDetail {
        let url = URL(
            string:
                "https://esi.evetech.net/latest/killmails/\(killmailId)/\(killmailHash)/?datasource=tranquility"
        )!

        Logger.info("正在获取战斗详情 - ID: \(killmailId)")
        let data = try await NetworkManager.shared.fetchData(
            from: url, headers: ["User-Agent": "EVE-Nexus"]
        )

        do {
            let detail = try JSONDecoder().decode(KillMailDetail.self, from: data)

            // 保存到数据库
            let insertSQL = """
                    INSERT OR REPLACE INTO killmails (
                        killmail_id, killmail_time, solar_system_id,
                        victim_character_id, victim_alliance_id, victim_faction_id, victim_corporation_id,
                        attacker_final_blow_character_id, attacker_final_blow_alliance_id, attacker_final_blow_faction_id, attacker_final_blow_corporation_id,
                        attackers_num
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """

            // 获取最后一击者信息
            let finalBlow = detail.attackers.first { $0.finalBlow }

            let parameters: [Any?] = [
                detail.killmailId,
                detail.killmailTime,
                detail.solarSystemId,
                detail.victim.characterId,
                detail.victim.allianceId,
                detail.victim.factionId,
                detail.victim.corporationId,
                finalBlow?.characterId,
                finalBlow?.allianceId,
                finalBlow?.factionId,
                finalBlow?.corporationId,
                detail.attackers.count,
            ]

            if case let .error(error) = CharacterDatabaseManager.shared.executeQuery(
                insertSQL, parameters: parameters as [Any]
            ) {
                Logger.error("保存战斗详情到数据库失败: \(error)")
            }

            Logger.info("成功获取战斗详情 - ID: \(killmailId)")
            return detail
        } catch {
            Logger.error("解析战斗详情失败 - ID: \(killmailId), 错误: \(error)")
            throw error
        }
    }

    // 获取角色战斗统计信息
    public func fetchCharacterStats(characterId: Int) async throws -> CharBattleIsk {
        let url = URL(
            string: "https://zkillboard.com/cache/1hour/stats/?type=characterID&id=\(characterId)")!
        let headers = ["User-Agent": "EVE-Nexus"]

        Logger.info("开始获取角色战斗统计信息 - ID: \(characterId)")
        let data = try await NetworkManager.shared.fetchData(from: url, headers: headers)

        do {
            let stats = try JSONDecoder().decode(CharBattleIsk.self, from: data)
            Logger.info("成功获取角色战斗统计信息")
            return stats
        } catch {
            Logger.error("解析角色战斗统计信息失败: \(error)")
            throw error
        }
    }
}

// MARK: - 战斗详情相关结构体

struct KillMailDetail: Codable {
    let killmailId: Int
    let killmailTime: String
    let solarSystemId: Int
    let attackers: [Attacker]
    let victim: Victim

    enum CodingKeys: String, CodingKey {
        case killmailId = "killmail_id"
        case killmailTime = "killmail_time"
        case solarSystemId = "solar_system_id"
        case attackers
        case victim
    }
}

struct Attacker: Codable {
    let allianceId: Int?
    let characterId: Int?
    let corporationId: Int?
    let factionId: Int?
    let damageDone: Int
    let finalBlow: Bool
    let securityStatus: Double
    let shipTypeId: Int?
    let weaponTypeId: Int?

    enum CodingKeys: String, CodingKey {
        case allianceId = "alliance_id"
        case characterId = "character_id"
        case corporationId = "corporation_id"
        case factionId = "faction_id"
        case damageDone = "damage_done"
        case finalBlow = "final_blow"
        case securityStatus = "security_status"
        case shipTypeId = "ship_type_id"
        case weaponTypeId = "weapon_type_id"
    }
}

struct Victim: Codable {
    let allianceId: Int?
    let characterId: Int?
    let corporationId: Int?
    let factionId: Int?
    let damageTaken: Int
    let items: [Item]?
    let position: Position?
    let shipTypeId: Int

    enum CodingKeys: String, CodingKey {
        case allianceId = "alliance_id"
        case characterId = "character_id"
        case corporationId = "corporation_id"
        case factionId = "faction_id"
        case damageTaken = "damage_taken"
        case items
        case position
        case shipTypeId = "ship_type_id"
    }
}

struct Item: Codable {
    let flag: Int
    let itemTypeId: Int
    let quantityDropped: Int?
    let quantityDestroyed: Int?
    let singleton: Int

    enum CodingKeys: String, CodingKey {
        case flag
        case itemTypeId = "item_type_id"
        case quantityDropped = "quantity_dropped"
        case quantityDestroyed = "quantity_destroyed"
        case singleton
    }
}

struct Position: Codable {
    let x: Double
    let y: Double
    let z: Double
}
