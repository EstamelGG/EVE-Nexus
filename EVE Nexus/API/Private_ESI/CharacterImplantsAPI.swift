import Foundation

class CharacterImplantsAPI {
    static let shared = CharacterImplantsAPI()
    private let databaseManager = CharacterDatabaseManager.shared

    // 缓存相关常量
    private let lastImplantsQueryKey = "LastImplantsQuery_"
    private let queryInterval: TimeInterval = 3600  // 1小时的查询间隔

    private init() {}

    // 获取最后查询时间
    private func getLastQueryTime(characterId: Int) -> Date? {
        let key = lastImplantsQueryKey + String(characterId)
        return UserDefaults.standard.object(forKey: key) as? Date
    }

    // 更新最后查询时间
    private func updateLastQueryTime(characterId: Int) {
        let key = lastImplantsQueryKey + String(characterId)
        UserDefaults.standard.set(Date(), forKey: key)
    }

    // 保存植入体数据到数据库
    private func saveImplantsToDatabase(characterId: Int, implants: [Int]) -> Bool {
        do {
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(implants)

            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                Logger.error("植入体数据JSON编码失败")
                return false
            }

            let query = """
                    INSERT OR REPLACE INTO implants (
                        character_id, implants_data
                    ) VALUES (?, ?)
                """

            if case let .error(error) = databaseManager.executeQuery(
                query,
                parameters: [
                    characterId,
                    jsonString,
                ]
            ) {
                Logger.error("保存植入体数据失败: \(error)")
                return false
            }

            Logger.info("成功保存植入体数据到数据库 - 角色ID: \(characterId)")
            return true
        } catch {
            Logger.error("保存植入体数据失败: \(error)")
            return false
        }
    }

    // 从数据库加载植入体数据
    private func loadImplantsFromDatabase(characterId: Int) -> [Int]? {
        let query = """
                SELECT implants_data FROM implants 
                WHERE character_id = ? 
                AND datetime(last_updated) > datetime('now', '-12 hour')
            """

        if case let .success(rows) = databaseManager.executeQuery(query, parameters: [characterId]),
            rows.count > 0,
            let row = rows.first,
            let jsonString = row["implants_data"] as? String,
            let jsonData = jsonString.data(using: .utf8)
        {
            do {
                let decoder = JSONDecoder()
                let implants = try decoder.decode([Int].self, from: jsonData)
                Logger.info("成功从数据库加载植入体数据 - 角色ID: \(characterId)")
                return implants
            } catch {
                Logger.error("解析植入体数据失败: \(error)")
                return nil
            }
        }
        return nil
    }

    // 获取植入体信息
    func fetchCharacterImplants(characterId: Int, forceRefresh: Bool = false) async throws -> [Int]
    {
        // 如果不是强制刷新，先尝试从数据库加载
        if !forceRefresh {
            if let cachedImplants = loadImplantsFromDatabase(characterId: characterId) {
                Logger.info("使用缓存的植入体数据 - 角色ID: \(characterId)")
                return cachedImplants
            }
        }

        let urlString =
            "https://esi.evetech.net/latest/characters/\(characterId)/implants/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId
        )

        let implants = try JSONDecoder().decode([Int].self, from: data)

        // 保存到数据库
        if saveImplantsToDatabase(characterId: characterId, implants: implants) {
            Logger.info("成功缓存植入体数据 - 角色ID: \(characterId)")
        }

        return implants.sorted()
    }
}
