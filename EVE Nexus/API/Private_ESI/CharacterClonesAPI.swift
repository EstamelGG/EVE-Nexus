import Foundation

// 克隆体数据模型
struct CharacterCloneInfo: Codable {
    let home_location: CloneLocation
    let jump_clones: [JumpClone]
    let last_clone_jump_date: String?
    let last_station_change_date: String?
}

struct CloneLocation: Codable {
    let location_id: Int
    let location_type: String
}

struct JumpClone: Codable {
    let implants: [Int]
    let jump_clone_id: Int
    let location_id: Int
    let location_type: String
    let name: String?
}

class CharacterClonesAPI {
    static let shared = CharacterClonesAPI()
    private let databaseManager = CharacterDatabaseManager.shared

    // 缓存相关常量
    private let lastClonesQueryKey = "LastClonesQuery_"
    private let queryInterval: TimeInterval = 3600  // 1小时的查询间隔

    private init() {}

    // 获取最后查询时间
    private func getLastQueryTime(characterId: Int) -> Date? {
        let key = lastClonesQueryKey + String(characterId)
        return UserDefaults.standard.object(forKey: key) as? Date
    }

    // 更新最后查询时间
    private func updateLastQueryTime(characterId: Int) {
        let key = lastClonesQueryKey + String(characterId)
        UserDefaults.standard.set(Date(), forKey: key)
    }

    // 保存克隆体数据到数据库
    private func saveClonesToDatabase(characterId: Int, clones: CharacterCloneInfo) -> Bool {
        do {
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(clones)

            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                Logger.error("克隆体数据JSON编码失败")
                return false
            }

            let query = """
                    INSERT OR REPLACE INTO clones (
                        character_id, clones_data, home_location_id, last_clone_jump_date
                    ) VALUES (?, ?, ?, ?)
                """

            if case let .error(error) = databaseManager.executeQuery(
                query,
                parameters: [
                    characterId,
                    jsonString,
                    clones.home_location.location_id,
                    clones.last_clone_jump_date ?? NSNull(),
                ]
            ) {
                Logger.error("保存克隆体数据失败: \(error)")
                return false
            }

            Logger.info("成功保存克隆体数据到数据库 - 角色ID: \(characterId)")
            return true
        } catch {
            Logger.error("保存克隆体数据失败: \(error)")
            return false
        }
    }

    // 从数据库加载克隆体数据
    private func loadClonesFromDatabase(characterId: Int) -> CharacterCloneInfo? {
        let query = """
                SELECT clones_data FROM clones 
                WHERE character_id = ? 
                AND datetime(last_updated) > datetime('now', '-1 hour')
            """

        if case let .success(rows) = databaseManager.executeQuery(query, parameters: [characterId]),
            rows.count > 0,
            let row = rows.first,
            let jsonString = row["clones_data"] as? String,
            let jsonData = jsonString.data(using: .utf8)
        {
            do {
                let decoder = JSONDecoder()
                let clones = try decoder.decode(CharacterCloneInfo.self, from: jsonData)
                Logger.info("成功从数据库加载克隆体数据 - 角色ID: \(characterId)")
                return clones
            } catch {
                Logger.error("解析克隆体数据失败: \(error)")
                return nil
            }
        }
        return nil
    }

    // 获取克隆体跳跃剩余时间（小时）
    func getJumpCooldownHours(characterId: Int) async -> Double? {
        let query = """
                SELECT last_clone_jump_date 
                FROM clones 
                WHERE character_id = ?
                ORDER BY last_updated DESC
                LIMIT 1
            """

        if case let .success(rows) = databaseManager.executeQuery(query, parameters: [characterId]),
            let row = rows.first,
            let lastJumpDateStr = row["last_clone_jump_date"] as? String
        {
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime]

            if let lastJumpDate = dateFormatter.date(from: lastJumpDateStr) {
                let now = Date()
                let timeSinceLastJump = now.timeIntervalSince(lastJumpDate)
                let cooldownPeriod: TimeInterval = 24 * 3600  // 24小时的冷却时间

                if timeSinceLastJump >= cooldownPeriod {
                    return 0  // 可以跳跃
                } else {
                    let remainingTime = cooldownPeriod - timeSinceLastJump
                    return remainingTime / 3600  // 转换为小时
                }
            }
        }

        return nil  // 没有找到上次跳跃记录，说明可以跳跃
    }

    // 获取克隆体信息
    func fetchCharacterClones(characterId: Int, forceRefresh: Bool = false) async throws
        -> CharacterCloneInfo
    {
        // 如果不是强制刷新，先尝试从数据库加载
        if !forceRefresh {
            if let cachedClones = loadClonesFromDatabase(characterId: characterId) {
                Logger.info("使用缓存的克隆体数据 - 角色ID: \(characterId)")
                return cachedClones
            }
        }

        let urlString =
            "https://esi.evetech.net/latest/characters/\(characterId)/clones/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId
        )

        let clones = try JSONDecoder().decode(CharacterCloneInfo.self, from: data)

        // 保存到数据库
        if saveClonesToDatabase(characterId: characterId, clones: clones) {
            Logger.info("成功缓存克隆体数据 - 角色ID: \(characterId)")
        }

        return clones
    }
}
