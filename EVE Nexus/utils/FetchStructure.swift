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

// 缓存数据结构
private struct StructureCacheData: Codable {
    let data: UniverseStructureInfo
    let timestamp: Date
    
    var isExpired: Bool {
        // 设置缓存有效期为7天
        return Date().timeIntervalSince(timestamp) > 7 * 24 * 3600
    }
}

@globalActor public actor UniverseStructureActor {
    public static let shared = UniverseStructureActor()
    private init() {}
}

@UniverseStructureActor
public class UniverseStructureAPI {
    public static let shared = UniverseStructureAPI()
    
    // 内存缓存
    private var structureInfoCache: [Int64: UniverseStructureInfo] = [:]
    
    private init() {}
    
    // MARK: - Public Methods
    public func fetchStructureInfo(structureId: Int64, characterId: Int) async throws -> UniverseStructureInfo {
        // 1. 检查内存缓存
        if let cachedStructure = structureInfoCache[structureId] {
            Logger.info("使用内存缓存的建筑物信息 - 建筑物ID: \(structureId)")
            return cachedStructure
        }
        
        // 2. 检查文件缓存
        if let cachedStructure = loadStructureFromCache(structureId: structureId) {
            // 保存到内存缓存
            structureInfoCache[structureId] = cachedStructure
            Logger.info("使用文件缓存的建筑物信息 - 建筑物ID: \(structureId)")
            return cachedStructure
        }
        
        // 3. 从API获取
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
            
            // 保存到文件缓存
            saveStructureToCache(structureInfo, structureId: structureId)
            
            // 保存到内存缓存
            structureInfoCache[structureId] = structureInfo
            
            Logger.info("从API获取建筑物信息成功 - 建筑物ID: \(structureId)")
            return structureInfo
            
        } catch {
            Logger.error("获取建筑物信息失败 - 建筑物ID: \(structureId), 错误: \(error)")
            throw error
        }
    }
    
    // MARK: - Cache Methods
    private func getCacheDirectory() -> URL? {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let cacheDirectory = documentsDirectory.appendingPathComponent("StructureCache", isDirectory: true)
        
        // 确保缓存目录存在
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true, attributes: nil)
        
        return cacheDirectory
    }
    
    private func getCacheFilePath(structureId: Int64) -> URL? {
        guard let cacheDirectory = getCacheDirectory() else { return nil }
        return cacheDirectory.appendingPathComponent("Structure_\(structureId).json")
    }
    
    private func loadStructureFromCache(structureId: Int64) -> UniverseStructureInfo? {
        guard let cacheFile = getCacheFilePath(structureId: structureId) else {
            Logger.error("获取缓存文件路径失败 - 建筑物ID: \(structureId)")
            return nil
        }
        
        do {
            guard FileManager.default.fileExists(atPath: cacheFile.path) else {
                Logger.info("缓存文件不存在 - 建筑物ID: \(structureId)")
                return nil
            }
            
            let data = try Data(contentsOf: cacheFile)
            let cached = try JSONDecoder().decode(StructureCacheData.self, from: data)
            
            if cached.isExpired {
                Logger.info("缓存已过期 - 建筑物ID: \(structureId)")
                try? FileManager.default.removeItem(at: cacheFile)
                return nil
            }
            
            Logger.info("成功从缓存加载建筑物信息 - 建筑物ID: \(structureId)")
            return cached.data
        } catch {
            Logger.error("读取缓存文件失败 - 建筑物ID: \(structureId), 错误: \(error)")
            try? FileManager.default.removeItem(at: cacheFile)
            return nil
        }
    }
    
    private func saveStructureToCache(_ structure: UniverseStructureInfo, structureId: Int64) {
        guard let cacheFile = getCacheFilePath(structureId: structureId) else {
            Logger.error("获取缓存文件路径失败 - 建筑物ID: \(structureId)")
            return
        }
        
        do {
            let cachedData = StructureCacheData(data: structure, timestamp: Date())
            let encodedData = try JSONEncoder().encode(cachedData)
            try encodedData.write(to: cacheFile)
            Logger.info("建筑物信息已缓存到文件 - 建筑物ID: \(structureId)")
        } catch {
            Logger.error("保存建筑物缓存失败: \(error)")
            try? FileManager.default.removeItem(at: cacheFile)
        }
    }
    
    // MARK: - Helper Methods
    public func clearCache() {
        // 清除内存缓存
        structureInfoCache.removeAll()
        
        // 清除文件缓存
        guard let cacheDirectory = getCacheDirectory() else { return }
        do {
            let fileManager = FileManager.default
            let cacheFiles = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            for file in cacheFiles {
                try fileManager.removeItem(at: file)
            }
            Logger.info("建筑物缓存已清除")
        } catch {
            Logger.error("清除建筑物缓存失败: \(error)")
        }
    }
} 