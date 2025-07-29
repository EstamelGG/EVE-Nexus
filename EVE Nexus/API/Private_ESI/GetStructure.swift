import Foundation

// 建筑物信息模型
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

    private init() {}

    // MARK: - Public Methods

    public func fetchStructureInfo(structureId: Int64, characterId: Int, forceRefresh: Bool = false, cacheTimeOut: Int64 = 168) async throws
        -> UniverseStructureInfo
    {
        // 1. 检查数据库缓存
        if !forceRefresh, let cachedStructure = loadStructureFromCache(structureId: structureId, cacheTimeOut: cacheTimeOut) {
            Logger.info("使用数据库缓存的建筑物信息 - 建筑物ID: \(structureId)")
            return cachedStructure
        }

        // 2. 从API获取
        return try await fetchFromAPI(structureId: structureId, characterId: characterId)
    }

    private func fetchFromAPI(structureId: Int64, characterId: Int) async throws
        -> UniverseStructureInfo
    {
        let urlString =
            "https://esi.evetech.net/universe/structures/\(structureId)/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        do {
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

            // 保存到数据库缓存
            saveStructureToCache(structureInfo, structureId: structureId)

            Logger.info("从API获取建筑物信息成功 - 建筑物ID: \(structureId)")
            return structureInfo

        } catch {
            Logger.error("获取建筑物信息失败 - 建筑物ID: \(structureId), 错误: \(error)")
            throw error
        }
    }

    // MARK: - Cache Methods

    private func loadStructureFromCache(structureId: Int64, cacheTimeOut: Int64 = 168) -> UniverseStructureInfo? {
        // 在SQL中直接过滤过期缓存（168小时 = 7天）
        let sql = """
                SELECT name, owner_id, solar_system_id, type_id, timestamp
                FROM structure_cache
                WHERE structure_id = ?
                AND timestamp > datetime('now', '-\(cacheTimeOut) hour')
            """  // 自定义缓存超时时间，默认 7 天

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

    // 批量保存建筑物信息
    private func saveStructuresToCache(_ structures: [(Int64, UniverseStructureInfo)]) {
        // 直接使用SQL的datetime('now')函数获取当前时间
        // 构建批量插入的SQL
        let valuesSql = structures.map { _ in "(?, ?, ?, ?, ?, datetime('now'))" }.joined(separator: ",")
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

        // 构建参数数组（不再需要timestamp参数）
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
            Logger.info("成功批量保存 \(structures.count) 个建筑物信息到缓存")
        case let .error(error):
            Logger.error("批量保存建筑物缓存失败: \(error)")
        }
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
