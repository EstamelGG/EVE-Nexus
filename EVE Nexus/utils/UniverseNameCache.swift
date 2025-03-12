import Foundation

actor UniverseNameCache {
    static let shared = UniverseNameCache()

    // 内存缓存，作为第一级缓存
    private var memoryCache: [Int: String] = [:]

    private init() {}

    func getName(for id: Int) -> String? {
        // 先检查内存缓存
        if let name = memoryCache[id] {
            return name
        }

        // 如果内存缓存没有，检查数据库
        let query = """
                SELECT name 
                FROM universe_names 
                WHERE id = ? 
                AND datetime(last_updated) > datetime('now', '-24 hours')
            """
        if case let .success(results) = CharacterDatabaseManager.shared.executeQuery(
            query, parameters: [id]
        ),
            let row = results.first,
            let name = row["name"] as? String
        {
            // 找到后更新内存缓存
            memoryCache[id] = name
            return name
        }

        return nil
    }

    func setName(_ name: String, for id: Int, category: String = "unknown") {
        // 更新内存缓存
        memoryCache[id] = name

        // 更新数据库
        let query = """
                INSERT OR REPLACE INTO universe_names (id, category, name)
                VALUES (?, ?, ?)
            """
        _ = CharacterDatabaseManager.shared.executeQuery(query, parameters: [id, category, name])
    }

    func getNames(for ids: Set<Int>) async throws -> [Int: String] {
        var result: [Int: String] = [:]
        var uncachedIds = Set<Int>()

        // 1. 检查内存缓存
        for id in ids {
            if let name = memoryCache[id] {
                result[id] = name
            } else {
                uncachedIds.insert(id)
            }
        }

        if uncachedIds.isEmpty {
            return result
        }

        // 2. 检查数据库缓存（包含过期检查）
        if !uncachedIds.isEmpty {
            let idList = uncachedIds.sorted().map { String($0) }.joined(separator: ",")
            let query = """
                    SELECT id, name 
                    FROM universe_names 
                    WHERE id IN (\(idList))
                """
            Logger.debug("执行查询: \(query)")

            if case let .success(rows) = CharacterDatabaseManager.shared.executeQuery(query) {
                Logger.debug("查询结果: \(rows.count) 行")
                for row in rows {
                    Logger.debug("处理行: \(row)")
                    // 处理多种可能的类型
                    let id: Int?
                    if let intId = row["id"] as? Int {
                        id = intId
                    } else if let int64Id = row["id"] as? Int64 {
                        id = Int(int64Id)
                    } else {
                        id = nil
                        Logger.error("无法解析ID - Row: \(row)")
                    }

                    if let validId = id,
                        let name = row["name"] as? String
                    {
                        result[validId] = name
                        memoryCache[validId] = name
                        uncachedIds.remove(validId)
                        Logger.debug("缓存命中 - ID: \(validId), Name: \(name)")
                    } else if let validId = id {
                        Logger.debug("缓存过期 - ID: \(validId)")
                    } else {
                        Logger.error("行数据类型不匹配 - Row: \(row)")
                    }
                }
                Logger.debug("数据库缓存命中: \(rows.count) 条记录")
            } else {
                Logger.error("数据库查询失败")
            }
        }

        if uncachedIds.isEmpty {
            return result
        }

        // 3. 从ESI获取未缓存的ID
        let url = URL(
            string: "https://esi.evetech.net/latest/universe/names/?datasource=tranquility")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        let jsonData = try JSONEncoder().encode(Array(uncachedIds))
        request.httpBody = jsonData

        let (data, _) = try await URLSession.shared.data(for: request)
        let names = try JSONDecoder().decode([UniverseNameResponse].self, from: data)

        // 更新缓存和结果
        for name in names {
            result[name.id] = name.name
            setName(name.name, for: name.id, category: name.category)
        }

        return result
    }
}
