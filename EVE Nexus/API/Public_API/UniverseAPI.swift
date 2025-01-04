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
    func fetchAndSaveNames(ids: [Int]) async throws -> Int {
        Logger.info("开始获取实体名称信息 - IDs: \(ids)")
        
        // 构建请求URL
        let urlString = "https://esi.evetech.net/latest/universe/names/?datasource=tranquility"
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
        
        // 保存到数据库
        let insertSQL = """
            INSERT OR REPLACE INTO universe_names (
                id,
                name,
                category
            ) VALUES (?, ?, ?)
        """
        
        var savedCount = 0
        for response in responses {
            let result = databaseManager.executeQuery(
                insertSQL,
                parameters: [
                    response.id,
                    response.name,
                    response.category
                ]
            )
            
            if case .success = result {
                savedCount += 1
                Logger.debug("成功保存实体信息 - ID: \(response.id), 名称: \(response.name), 类型: \(response.category)")
            } else if case .error(let error) = result {
                Logger.error("保存实体信息失败 - ID: \(response.id), 错误: \(error)")
            }
        }
        
        Logger.info("成功保存 \(savedCount) 个实体的名称信息到数据库")
        return savedCount
    }
    
    /// 从数据库获取ID对应的名称信息
    /// - Parameter id: 要查询的ID
    /// - Returns: 名称和类型（如果存在）
    func getNameFromDatabase(id: Int) async throws -> (name: String, category: String)? {
        let query = "SELECT name, category FROM universe_names WHERE id = ? LIMIT 1"
        let result = databaseManager.executeQuery(query, parameters: [id])
        
        switch result {
        case .success(let rows):
            if let row = rows.first,
               let name = row["name"] as? String,
               let category = row["category"] as? String {
                return (name: name, category: category)
            }
            return nil
            
        case .error(let error):
            Logger.error("从数据库获取实体信息失败 - ID: \(id), 错误: \(error)")
            throw DatabaseError.fetchError(error)
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
        case .success(let rows):
            var namesMap: [Int: (name: String, category: String)] = [:]
            for row in rows {
                if let id = row["id"] as? Int64,
                   let name = row["name"] as? String,
                   let category = row["category"] as? String {
                    namesMap[Int(id)] = (name: name, category: category)
                }
            }
            return namesMap
            
        case .error(let error):
            Logger.error("从数据库批量获取实体信息失败 - IDs: \(ids), 错误: \(error)")
            throw DatabaseError.fetchError(error)
        }
    }
} 
