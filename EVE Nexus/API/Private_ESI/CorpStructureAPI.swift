import Foundation

// 军团建筑物信息模型
public struct StructureInfo: Codable {
    public let structure_id: Int64
    public let type_id: Int
    public let corporation_id: Int
    public let system_id: Int
    public let profile_id: Int
    public let fuel_expires: String?
    public let state: String
    public let state_timer_start: String?
    public let state_timer_end: String?
    public let unanchors_at: String?
    public let services: [StructureService]?
    
    public init(structure_id: Int64, type_id: Int, corporation_id: Int, system_id: Int, profile_id: Int, fuel_expires: String?, state: String, state_timer_start: String?, state_timer_end: String?, unanchors_at: String?, services: [StructureService]?) {
        self.structure_id = structure_id
        self.type_id = type_id
        self.corporation_id = corporation_id
        self.system_id = system_id
        self.profile_id = profile_id
        self.fuel_expires = fuel_expires
        self.state = state
        self.state_timer_start = state_timer_start
        self.state_timer_end = state_timer_end
        self.unanchors_at = unanchors_at
        self.services = services
    }
}

// 建筑物服务信息
public struct StructureService: Codable {
    public let name: String
    public let state: String
    
    public init(name: String, state: String) {
        self.name = name
        self.state = state
    }
}

// 缓存数据结构
private struct StructureCacheData: Codable {
    let data: [StructureInfo]
    let timestamp: Date
    
    var isExpired: Bool {
        // 设置缓存有效期为1天
        return Date().timeIntervalSince(timestamp) > 24 * 3600
    }
}

@globalActor public actor CorpStructureActor {
    public static let shared = CorpStructureActor()
    private init() {}
}

@CorpStructureActor
public class CorpStructureAPI {
    public static let shared = CorpStructureAPI()
    private let itemsPerPage = 50
    
    private init() {}
    
    // MARK: - Public Methods
    public func fetchStructures(characterId: Int, forceRefresh: Bool = false) async throws -> [StructureInfo] {
        // 1. 获取角色的军团ID
        guard let corporationId = try await CharacterDatabaseManager.shared.getCharacterCorporationId(characterId: characterId) else {
            throw NetworkError.authenticationError("无法获取军团ID")
        }
        
        // 2. 检查缓存
        if !forceRefresh, let cachedData = loadStructuresFromCache(corporationId: corporationId) {
            Logger.info("使用缓存的建筑物信息 - 军团ID: \(corporationId)")
            return cachedData
        }
        
        // 3. 从API获取
        return try await fetchFromAPI(corporationId: corporationId, characterId: characterId)
    }
    
    private func fetchFromAPI(corporationId: Int, characterId: Int) async throws -> [StructureInfo] {
        var allStructures: [StructureInfo] = []
        var currentPage = 1
        var hasMorePages = true
        
        Logger.info("开始获取军团建筑物信息 - 军团ID: \(corporationId)")
        
        while hasMorePages {
            Logger.debug("正在获取第 \(currentPage) 页数据")
            
            let urlString = "https://esi.evetech.net/latest/corporations/\(corporationId)/structures/?datasource=tranquility&page=\(currentPage)"
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
                    noRetryKeywords: ["Requested page does not exist"]
                )
                
                let structures = try JSONDecoder().decode([StructureInfo].self, from: data)
                Logger.debug("成功获取第 \(currentPage) 页数据，共 \(structures.count) 条记录")
                allStructures.append(contentsOf: structures)
                currentPage += 1
                
            } catch let error as NetworkError {
                if case .httpError(_, let message) = error,
                   message?.contains("Requested page does not exist") == true {
                    Logger.debug("第 \(currentPage) 页不存在，停止获取")
                    hasMorePages = false
                    break
                }
                Logger.error("获取建筑物信息失败 - 军团ID: \(corporationId), 页码: \(currentPage), 错误: \(error)")
                throw error
            }
        }
        
        // 保存到缓存
        saveStructuresToCache(allStructures, corporationId: corporationId)
        
        Logger.info("成功获取所有建筑物信息 - 军团ID: \(corporationId), 总条数: \(allStructures.count)")
        return allStructures
    }
    
    // MARK: - Cache Methods
    private func getCacheDirectory() -> URL? {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let cacheDirectory = documentsDirectory.appendingPathComponent("CorpStructure", isDirectory: true)
        
        // 确保缓存目录存在
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true, attributes: nil)
        
        return cacheDirectory
    }
    
    private func getCacheFilePath(corporationId: Int) -> URL? {
        guard let cacheDirectory = getCacheDirectory() else { return nil }
        return cacheDirectory.appendingPathComponent("corp_\(corporationId)_structure.json")
    }
    
    private func loadStructuresFromCache(corporationId: Int) -> [StructureInfo]? {
        guard let cacheFile = getCacheFilePath(corporationId: corporationId) else {
            Logger.error("获取缓存文件路径失败 - 军团ID: \(corporationId)")
            return nil
        }
        
        do {
            guard FileManager.default.fileExists(atPath: cacheFile.path) else {
                Logger.info("缓存文件不存在 - 军团ID: \(corporationId)")
                return nil
            }
            
            let data = try Data(contentsOf: cacheFile)
            let cached = try JSONDecoder().decode(StructureCacheData.self, from: data)
            
            if cached.isExpired {
                Logger.info("缓存已过期 - 军团ID: \(corporationId)")
                try? FileManager.default.removeItem(at: cacheFile)
                return nil
            }
            
            Logger.info("成功从缓存加载建筑物信息 - 军团ID: \(corporationId)")
            return cached.data
        } catch {
            Logger.error("读取缓存文件失败 - 军团ID: \(corporationId), 错误: \(error)")
            try? FileManager.default.removeItem(at: cacheFile)
            return nil
        }
    }
    
    private func saveStructuresToCache(_ structures: [StructureInfo], corporationId: Int) {
        guard let cacheFile = getCacheFilePath(corporationId: corporationId) else {
            Logger.error("获取缓存文件路径失败 - 军团ID: \(corporationId)")
            return
        }
        
        do {
            let cachedData = StructureCacheData(data: structures, timestamp: Date())
            let encodedData = try JSONEncoder().encode(cachedData)
            try encodedData.write(to: cacheFile)
            Logger.info("建筑物信息已缓存到文件 - 军团ID: \(corporationId)")
        } catch {
            Logger.error("保存建筑物信息缓存失败: \(error)")
            try? FileManager.default.removeItem(at: cacheFile)
        }
    }
    
    // MARK: - Helper Methods
    public func clearCache() {
        guard let cacheDirectory = getCacheDirectory() else { return }
        do {
            let fileManager = FileManager.default
            let cacheFiles = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            for file in cacheFiles {
                try fileManager.removeItem(at: file)
            }
            Logger.info("建筑物信息缓存已清除")
        } catch {
            Logger.error("清除建筑物信息缓存失败: \(error)")
        }
    }
} 