import Foundation

/// 建筑物信息模型
public struct UniverseStructureInfo: Codable {
    public let name: String
    public let owner_id: Int
    public let solar_system_id: Int
    public let type_id: Int

    public init(name: String, owner_id: Int, solar_system_id: Int, type_id: Int) {
        self.name = name
        self.owner_id = owner_id
        self.solar_system_id = solar_system_id
        self.type_id = type_id
    }
}

@globalActor public actor UniverseStructureActor {
    public static let shared = UniverseStructureActor()
    private init() {}
}

@UniverseStructureActor
public class UniverseStructureAPI {
    public static let shared = UniverseStructureAPI()
    private let databaseManager = CharacterDatabaseManager.shared

    /// 会话级禁止访问缓存：key 为 "characterId_structureId"，24h 内同一角色不重复请求无权建筑
    /// 重启后清空（重试成本低），按角色隔离（一个角色 403 不影响其他角色）
    private var forbiddenCache: [String: Date] = [:]
    private let forbiddenTTL: TimeInterval = 24 * 3600

    private init() {}

    // MARK: - Public Methods

    public func fetchStructureInfo(
        structureId: Int64, characterId: Int, forceRefresh: Bool = false, cacheTimeOut: Int64 = 168
    ) async throws
        -> UniverseStructureInfo
    {
        // 1. 检查数据库缓存（有效期内，全局共享）
        if !forceRefresh,
           let cachedStructure = loadStructureFromCache(
               structureId: structureId, cacheTimeOut: cacheTimeOut
           )
        {
            Logger.info("使用数据库缓存的建筑物信息 - 建筑物ID: \(structureId)")
            return cachedStructure
        }

        // 2. 检查会话级禁止缓存（按角色隔离，避免同一角色 24h 内重复请求无权建筑）
        if !forceRefresh, isForbidden(characterId: characterId, structureId: structureId) {
            if let fallback = loadStructureFromCache(structureId: structureId, ignoreTTL: true) {
                Logger.info("角色\(characterId)无权访问建筑\(structureId)，使用过期缓存")
                return fallback
            }
            throw NetworkError.httpError(statusCode: 403, message: "Forbidden")
        }

        // 3. 从API获取
        do {
            return try await fetchFromAPI(structureId: structureId, characterId: characterId)
        } catch {
            // 4. API失败时回退到过期缓存（有旧名称总比"未知建筑"好）
            if let fallback = loadStructureFromCache(structureId: structureId, ignoreTTL: true) {
                Logger.info("API失败，使用过期缓存 - 建筑物ID: \(structureId), 错误: \(error)")
                return fallback
            }
            // 5. 403 时标记此角色禁止，24h 内不重复请求
            if case let NetworkError.httpError(statusCode, _) = error, statusCode == 403 {
                markForbidden(characterId: characterId, structureId: structureId)
            }
            throw error
        }
    }

    private func fetchFromAPI(structureId: Int64, characterId: Int) async throws
        -> UniverseStructureInfo
    {
        let urlString =
            "https://esi.evetech.net/universe/structures/\(structureId)/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        let headers = [
            "Accept": "application/json",
            "Content-Type": "application/json",
        ]

        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId,
            headers: headers,
            noRetryKeywords: ["Forbidden"]
        )

        let structureInfo = try JSONDecoder().decode(UniverseStructureInfo.self, from: data)

        saveStructureToCache(structureInfo, structureId: structureId)

        Logger.info("从API获取建筑物信息成功 - 建筑物ID: \(structureId)")
        return structureInfo
    }

    // MARK: - Cache Methods

    private func loadStructureFromCache(
        structureId: Int64, cacheTimeOut: Int64 = 168, ignoreTTL: Bool = false
    )
        -> UniverseStructureInfo?
    {
        // ignoreTTL=true 时忽略过期时间，用于 API 失败回退（有旧名称总比"未知建筑"好）
        let ttlCondition = ignoreTTL
            ? ""
            : "AND timestamp > datetime('now', '-\(cacheTimeOut) hour')"
        let sql = """
            SELECT name, owner_id, solar_system_id, type_id, timestamp
            FROM structure_cache
            WHERE structure_id = ?
            \(ttlCondition)
        """

        let result = databaseManager.executeQuery(sql, parameters: [structureId])

        switch result {
        case let .success(rows):
            guard let row = rows.first else {
                Logger.info("缓存中没有找到有效的建筑物信息 - 建筑物ID: \(structureId)")
                return nil
            }

            Logger.info("使用有效缓存的建筑物信息 - 建筑物ID: \(structureId)")
            return UniverseStructureInfo(
                name: row["name"] as! String,
                owner_id: Int(row["owner_id"] as! Int64),
                solar_system_id: Int(row["solar_system_id"] as! Int64),
                type_id: Int(row["type_id"] as! Int64)
            )

        case let .error(error):
            Logger.error("从数据库加载建筑物缓存失败 - 建筑物ID: \(structureId), 错误: \(error)")
            return nil
        }
    }

    private func saveStructureToCache(_ structure: UniverseStructureInfo, structureId: Int64) {
        saveStructuresToCache([(structureId, structure)])
    }

    /// 批量保存建筑物信息
    private func saveStructuresToCache(_ structures: [(Int64, UniverseStructureInfo)]) {
        // 直接使用SQL的datetime('now')函数获取当前时间
        // 构建批量插入的SQL
        let valuesSql = structures.map { _ in "(?, ?, ?, ?, ?, datetime('now'))" }.joined(
            separator: ","
        )
        let sql = """
            INSERT OR REPLACE INTO structure_cache (
                structure_id,
                name,
                owner_id,
                solar_system_id,
                type_id,
                timestamp
            ) VALUES \(valuesSql)
        """

        var parameters: [Any] = []
        for (structureId, structure) in structures {
            parameters.append(structureId)
            parameters.append(structure.name)
            parameters.append(structure.owner_id)
            parameters.append(structure.solar_system_id)
            parameters.append(structure.type_id)
            // timestamp通过SQL的datetime('now')自动设置
        }

        let result = databaseManager.executeQuery(sql, parameters: parameters)

        switch result {
        case .success:
            Logger.success("成功批量保存 \(structures.count) 个建筑物信息到缓存")
        case let .error(error):
            Logger.error("批量保存建筑物缓存失败: \(error)")
        }
    }

    // MARK: - Session Forbidden Cache

    private func forbiddenKey(characterId: Int, structureId: Int64) -> String {
        "\(characterId)_\(structureId)"
    }

    private func isForbidden(characterId: Int, structureId: Int64) -> Bool {
        guard let date = forbiddenCache[forbiddenKey(characterId: characterId, structureId: structureId)]
        else { return false }
        return Date().timeIntervalSince(date) < forbiddenTTL
    }

    private func markForbidden(characterId: Int, structureId: Int64) {
        forbiddenCache[forbiddenKey(characterId: characterId, structureId: structureId)] = Date()
        Logger.info("标记角色\(characterId) 24h 内不再请求建筑\(structureId)")
    }

    // MARK: - Helper Methods

    public func clearCache() {
        // 清除数据库缓存
        let sql = "DELETE FROM structure_cache"
        let result = databaseManager.executeQuery(sql)

        switch result {
        case .success:
            Logger.info("建筑物缓存已从数据库清除")
        case let .error(error):
            Logger.error("清除数据库建筑物缓存失败: \(error)")
        }
    }
}
