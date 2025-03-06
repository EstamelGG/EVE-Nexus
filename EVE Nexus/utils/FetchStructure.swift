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
    public func fetchStructureInfo(structureId: Int64, characterId: Int) async throws -> UniverseStructureInfo {
        // 1. 检查数据库缓存
        if let cachedStructure = loadStructureFromCache(structureId: structureId) {
            Logger.info("使用数据库缓存的建筑物信息 - 建筑物ID: \(structureId)")
            return cachedStructure
        }
        
        // 2. 从API获取
        return try await fetchFromAPI(structureId: structureId, characterId: characterId)
    }
    
    private func fetchFromAPI(structureId: Int64, characterId: Int) async throws -> UniverseStructureInfo {
        let urlString = "https://esi.evetech.net/latest/universe/structures/\(structureId)/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        
        do {
            let headers = [
                "Accept": "application/json",
                "Content-Type": "application/json"
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
    private func loadStructureFromCache(structureId: Int64) -> UniverseStructureInfo? {
        let sql = """
            SELECT name, owner_id, solar_system_id, type_id, timestamp
            FROM structure_cache
            WHERE structure_id = ?
        """
        
        let result = databaseManager.executeQuery(sql, parameters: [structureId])
        
        switch result {
        case .success(let rows):
            guard let row = rows.first else {
                Logger.info("缓存中没有找到建筑物信息 - 建筑物ID: \(structureId)")
                return nil
            }
            
            // 检查缓存是否过期（7天）
            let timestamp = row["timestamp"] as! Int64
            let currentTime = Int64(Date().timeIntervalSince1970)
            if currentTime - timestamp > 7 * 24 * 3600 {
                Logger.info("建筑物缓存已过期 - 建筑物ID: \(structureId)")
                // 删除过期缓存
                deleteStructureCache(structureId: structureId)
                return nil
            }
            
            return UniverseStructureInfo(
                name: row["name"] as! String,
                owner_id: Int(row["owner_id"] as! Int64),
                solar_system_id: Int(row["solar_system_id"] as! Int64),
                type_id: Int(row["type_id"] as! Int64)
            )
            
        case .error(let error):
            Logger.error("从数据库加载建筑物缓存失败 - 建筑物ID: \(structureId), 错误: \(error)")
            return nil
        }
    }
    
    // 批量加载建筑物信息
    private func loadStructuresFromCache(structureIds: [Int64]) -> [Int64: UniverseStructureInfo] {
        var results: [Int64: UniverseStructureInfo] = [:]
        
        // 构建IN查询的占位符
        let placeholders = String(repeating: "?,", count: structureIds.count).dropLast()
        let sql = """
            SELECT structure_id, name, owner_id, solar_system_id, type_id, timestamp
            FROM structure_cache
            WHERE structure_id IN (\(placeholders))
        """
        
        let result = databaseManager.executeQuery(sql, parameters: structureIds)
        
        switch result {
        case .success(let rows):
            let currentTime = Int64(Date().timeIntervalSince1970)
            var expiredIds: [Int64] = []
            
            for row in rows {
                let structureId = row["structure_id"] as! Int64
                let timestamp = row["timestamp"] as! Int64
                
                // 检查是否过期
                if currentTime - timestamp > 7 * 24 * 3600 {
                    expiredIds.append(structureId)
                    continue
                }
                
                results[structureId] = UniverseStructureInfo(
                    name: row["name"] as! String,
                    owner_id: Int(row["owner_id"] as! Int64),
                    solar_system_id: Int(row["solar_system_id"] as! Int64),
                    type_id: Int(row["type_id"] as! Int64)
                )
            }
            
            // 批量删除过期缓存
            if !expiredIds.isEmpty {
                deleteStructureCacheBatch(structureIds: expiredIds)
            }
            
        case .error(let error):
            Logger.error("批量加载建筑物缓存失败: \(error)")
        }
        
        return results
    }
    
    private func saveStructureToCache(_ structure: UniverseStructureInfo, structureId: Int64) {
        saveStructuresToCache([(structureId, structure)])
    }
    
    // 批量保存建筑物信息
    private func saveStructuresToCache(_ structures: [(Int64, UniverseStructureInfo)]) {
        let timestamp = Int64(Date().timeIntervalSince1970)
        
        // 构建批量插入的SQL
        let valuesSql = structures.map { _ in "(?, ?, ?, ?, ?, ?)" }.joined(separator: ",")
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
        
        // 构建参数数组
        var parameters: [Any] = []
        for (structureId, structure) in structures {
            parameters.append(structureId)
            parameters.append(structure.name)
            parameters.append(structure.owner_id)
            parameters.append(structure.solar_system_id)
            parameters.append(structure.type_id)
            parameters.append(timestamp)
        }
        
        let result = databaseManager.executeQuery(sql, parameters: parameters)
        
        switch result {
        case .success:
            Logger.info("成功批量保存 \(structures.count) 个建筑物信息到缓存")
        case .error(let error):
            Logger.error("批量保存建筑物缓存失败: \(error)")
        }
    }
    
    private func deleteStructureCache(structureId: Int64) {
        deleteStructureCacheBatch(structureIds: [structureId])
    }
    
    // 批量删除建筑物缓存
    private func deleteStructureCacheBatch(structureIds: [Int64]) {
        let placeholders = String(repeating: "?,", count: structureIds.count).dropLast()
        let sql = "DELETE FROM structure_cache WHERE structure_id IN (\(placeholders))"
        
        let result = databaseManager.executeQuery(sql, parameters: structureIds)
        
        if case .error(let error) = result {
            Logger.error("批量删除建筑物缓存失败: \(error)")
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
        case .error(let error):
            Logger.error("清除数据库建筑物缓存失败: \(error)")
        }
    }
}
