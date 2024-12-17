import Foundation

/// 静态资源管理器
class StaticResourceManager {
    static let shared = StaticResourceManager()
    private let fileManager = FileManager.default
    private let cache = NSCache<NSString, CachedResource>()
    
    // 静态资源信息结构
    struct ResourceInfo {
        let name: String
        let exists: Bool
        let lastModified: Date?
        let fileSize: Int64?
    }
    
    // 资源类型枚举
    enum ResourceType: String, CaseIterable {
        case sovereignty = "sovereignty"
        
        var filename: String {
            return "\(self.rawValue).json"
        }
        
        var displayName: String {
            switch self {
            case .sovereignty:
                return "主权数据"
            }
        }
    }
    
    private init() {}
    
    // 缓存包装类
    class CachedResource {
        let data: Data
        let timestamp: Date
        
        init(data: Data, timestamp: Date) {
            self.data = data
            self.timestamp = timestamp
        }
    }
    
    /// 获取所有静态资源的状态
    func getAllResourcesStatus() -> [ResourceInfo] {
        return ResourceType.allCases.map { type in
            let documentPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("StaticResources")
                .appendingPathComponent(type.filename)
            
            let exists = fileManager.fileExists(atPath: documentPath.path)
            var lastModified: Date? = nil
            var fileSize: Int64? = nil
            
            if exists {
                do {
                    let attributes = try fileManager.attributesOfItem(atPath: documentPath.path)
                    lastModified = attributes[.modificationDate] as? Date
                    fileSize = attributes[.size] as? Int64
                } catch {
                    Logger.error("Error getting attributes for \(type.filename): \(error)")
                }
            }
            
            return ResourceInfo(
                name: type.displayName,
                exists: exists,
                lastModified: lastModified,
                fileSize: fileSize
            )
        }
    }
    
    /// 保存数据到文件
    /// - Parameters:
    ///   - data: 要保存的数据
    ///   - filename: 文件名（包含扩展名）
    func saveToFile(_ data: Data, filename: String) throws {
        let documentPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StaticResources")
        
        // 确保目录存在
        if !fileManager.fileExists(atPath: documentPath.path) {
            try fileManager.createDirectory(at: documentPath, withIntermediateDirectories: true)
        }
        
        let fileURL = documentPath.appendingPathComponent(filename)
        try data.write(to: fileURL)
        Logger.info("Saved static resource to file: \(filename)")
    }
    
    /// 获取主权数据
    /// - Returns: 主权数据数组
    func getSovereigntyData() async throws -> [SovereigntyData] {
        let cacheKey = "sovereignty_data" as NSString
        let filename = "sovereignty.json"
        
        // 1. 尝试从缓存获取
        if let cached = cache.object(forKey: cacheKey) {
            do {
                let data = try JSONDecoder().decode([SovereigntyData].self, from: cached.data)
                Logger.info("Got sovereignty data from cache")
                return data
            } catch {
                Logger.error("Failed to decode cached sovereignty data: \(error)")
            }
        }
        
        // 2. 尝试从文件读取
        let documentPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StaticResources")
            .appendingPathComponent(filename)
        
        if fileManager.fileExists(atPath: documentPath.path) {
            do {
                let data = try Data(contentsOf: documentPath)
                let sovereigntyData = try JSONDecoder().decode([SovereigntyData].self, from: data)
                
                // 更新缓存
                cache.setObject(CachedResource(data: data, timestamp: Date()), forKey: cacheKey)
                
                Logger.info("Got sovereignty data from file")
                return sovereigntyData
            } catch {
                Logger.error("Failed to load sovereignty data from file: \(error)")
            }
        }
        
        // 3. 从网络获取
        Logger.info("Fetching sovereignty data from network")
        let sovereigntyData = try await NetworkManager.shared.fetchSovereigntyData()
        let jsonData = try JSONEncoder().encode(sovereigntyData)
        
        // 保存到文件
        try saveToFile(jsonData, filename: filename)
        
        // 更新缓存
        cache.setObject(CachedResource(data: jsonData, timestamp: Date()), forKey: cacheKey)
        
        return sovereigntyData
    }
} 