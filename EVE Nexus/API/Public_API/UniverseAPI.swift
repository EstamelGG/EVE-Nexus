import Foundation

struct UniverseNameResponse: Codable {
    let category: String
    let id: Int
    let name: String
}

@NetworkManagerActor
class UniverseAPI {
    static let shared = UniverseAPI()
    private let networkManager = NetworkManager.shared
    private let databaseManager = CharacterDatabaseManager.shared

    private init() {}

    /// 从ESI获取ID对应的名称信息
    /// - Parameter ids: 要查询的ID数组
    /// - Returns: 成功获取的数量
    /// Resolve a set of IDs to names and categories. Supported ID's for resolving are: Characters, Corporations, Alliances, Stations, Solar Systems, Constellations, Regions, Types, Factions
    func fetchAndSaveNames(ids: [Int]) async throws -> Int {
        Logger.info("开始获取实体名称信息 - IDs: \(ids)")

        // 构建请求URL
        let urlString = "https://esi.evetech.net/universe/names/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        // 准备请求数据
        let jsonData = try JSONEncoder().encode(ids)

        // 发送POST请求
        let data = try await networkManager.fetchData(
            from: url,
            method: "POST",
            body: jsonData
        )

        // 解析响应数据
        let responses = try JSONDecoder().decode([UniverseNameResponse].self, from: data)
        Logger.info("成功获取 \(responses.count) 个实体的名称信息")

        // 准备批量插入的SQL语句
        let insertSQL = """
                INSERT OR REPLACE INTO universe_names (
                    id,
                    name,
                    category
                ) VALUES 
            """

        // 构建值部分和参数数组
        let valuePlaceholders = responses.map { _ in "(?, ?, ?)" }.joined(separator: ",")
        let finalSQL = insertSQL + valuePlaceholders

        // 准备参数数组
        var parameters: [Any] = []
        for response in responses {
            parameters.append(response.id)
            parameters.append(response.name)
            parameters.append(response.category)
        }

        // 执行批量插入
        let result = databaseManager.executeQuery(finalSQL, parameters: parameters)

        switch result {
        case .success:
            Logger.info("成功批量保存 \(responses.count) 个实体的名称信息到数据库")
            return responses.count
        case let .error(error):
            Logger.error("批量保存实体信息失败 - 错误: \(error)")
            return 0
        }
    }

    /// 从数据库批量获取ID对应的名称信息
    /// - Parameter ids: 要查询的ID数组
    /// - Returns: ID到名称和类型的映射
    func getNamesFromDatabase(ids: [Int]) async throws -> [Int: (name: String, category: String)] {
        let placeholders = String(repeating: "?,", count: ids.count).dropLast()
        let query = "SELECT id, name, category FROM universe_names WHERE id IN (\(placeholders))"

        let result = databaseManager.executeQuery(query, parameters: ids)

        switch result {
        case let .success(rows):
            var namesMap: [Int: (name: String, category: String)] = [:]
            for row in rows {
                if let id = row["id"] as? Int64,
                    let name = row["name"] as? String,
                    let category = row["category"] as? String
                {
                    namesMap[Int(id)] = (name: name, category: category)
                }
            }
            return namesMap

        case let .error(error):
            Logger.error("从数据库批量获取实体信息失败 - IDs: \(ids), 错误: \(error)")
            throw DatabaseError.fetchError(error)
        }
    }

    /// 批量获取ID对应的名称信息，对于数据库中不存在的条目会自动从API获取
    /// - Parameter ids: 要查询的ID数组
    /// - Returns: ID到名称和类型的映射
    func getNamesWithFallback(ids: [Int]) async throws -> [Int: (name: String, category: String)] {
        // 将ID数组分成每批1000个的子数组
        let batchSize = 1000
        let batches = stride(from: 0, to: ids.count, by: batchSize).map {
            Array(ids[$0..<min($0 + batchSize, ids.count)])
        }

        var allNamesMap: [Int: (name: String, category: String)] = [:]

        // 处理每一批
        for batch in batches {
            // 首先从数据库获取所有可用的名称
            Logger.debug("Fetch batch from DB. Size: \(batch.count)")
            let namesMap = try await getNamesFromDatabase(ids: batch)

            // 找出数据库中不存在的ID
            let missingIds = batch.filter { !namesMap.keys.contains($0) }

            // 如果有缺失的ID，从API获取
            if !missingIds.isEmpty {
                Logger.debug("Fetch from api. Missing IDs count: \(missingIds.count)")
                let result = try await fetchAndSaveNames(ids: missingIds)
                if result > 0 {
                    // 获取新保存的数据
                    let newNames = try await getNamesFromDatabase(ids: missingIds)
                    // 合并结果
                    allNamesMap.merge(newNames) { current, _ in current }
                }
            }

            // 合并当前批次的结果
            allNamesMap.merge(namesMap) { current, _ in current }
        }

        return allNamesMap
    }
}
