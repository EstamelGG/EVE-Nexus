import Foundation

/// 静态资源管理器
class StaticResourceManager {
    static let shared = StaticResourceManager()
    private let fileManager = FileManager.default
    private let cache = NSCache<NSString, CachedResource>()
    private let defaults = UserDefaults.standard
    
    // 静态资源信息结构
    struct ResourceInfo {
        let name: String
        let exists: Bool
        let lastModified: Date?
        let fileSize: Int64?
        let downloadTime: Date?
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
                return NSLocalizedString("Main_Setting_Static_Resource_Sovereignty", comment: "")
            }
        }
        
        var downloadTimeKey: String {
            return "StaticResource_\(self.rawValue)_DownloadTime"
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
    
    /// 获取静态资源目录路径
    func getStaticDataSetPath() -> URL {
        return fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StaticDataSet")
    }
    
    /// 获取所有静态资源的状态
    func getAllResourcesStatus() -> [ResourceInfo] {
        return ResourceType.allCases.map { type in
            let filePath = getStaticDataSetPath().appendingPathComponent(type.filename)
            
            let exists = fileManager.fileExists(atPath: filePath.path)
            var lastModified: Date? = nil
            var fileSize: Int64? = nil
            let downloadTime = defaults.object(forKey: type.downloadTimeKey) as? Date
            
            if exists {
                do {
                    let attributes = try fileManager.attributesOfItem(atPath: filePath.path)
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
                fileSize: fileSize,
                downloadTime: downloadTime
            )
        }
    }
    
    /// 保存数据到文件
    /// - Parameters:
    ///   - data: 要保存的数据
    ///   - filename: 文件名（包含扩展名）
    func saveToFile(_ data: Data, filename: String) throws {
        let staticDataSetPath = getStaticDataSetPath()
        
        // 确保目录存在
        if !fileManager.fileExists(atPath: staticDataSetPath.path) {
            try fileManager.createDirectory(at: staticDataSetPath, withIntermediateDirectories: true)
        }
        
        let fileURL = staticDataSetPath.appendingPathComponent(filename)
        try data.write(to: fileURL)
        
        // 保存下载时间
        if let resourceType = ResourceType.allCases.first(where: { $0.filename == filename }) {
            defaults.set(Date(), forKey: resourceType.downloadTimeKey)
        }
        
        Logger.info("Saved static resource to file: \(filename)")
    }
    
    /// 强制刷新指定资源
    /// - Parameter type: 资源类型
    /// - Returns: 是否刷新成功
    func forceRefresh(_ type: ResourceType) async throws {
        switch type {
        case .sovereignty:
            Logger.info("Force refreshing sovereignty data")
            // 从网络获取新数据
            let sovereigntyData = try await NetworkManager.shared.fetchSovereigntyData()
            let jsonData = try JSONEncoder().encode(sovereigntyData)
            
            // 保存到文件
            try saveToFile(jsonData, filename: type.filename)
            
            // 更新缓存
            cache.setObject(CachedResource(data: jsonData, timestamp: Date()), forKey: type.rawValue as NSString)
            
            Logger.info("Successfully refreshed sovereignty data")
        }
    }
    
    /// 清理内存缓存
    func clearMemoryCache() {
        cache.removeAllObjects()
    }
    
    /// 获取主权数据
    /// - Parameter forceRefresh: 是否强制刷新
    /// - Returns: 主权数据数组
    func fetchSovereigntyData(forceRefresh: Bool = false) async throws -> [SovereigntyData] {
        // 如果需要强制刷新，先执行刷新操作
        if forceRefresh {
            try await self.forceRefresh(.sovereignty)
            return try await fetchSovereigntyData(forceRefresh: false)
        }
        
        let cacheKey = "sovereignty_data" as NSString
        let filename = ResourceType.sovereignty.filename
        
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
        let filePath = getStaticDataSetPath().appendingPathComponent(filename)
        
        if fileManager.fileExists(atPath: filePath.path) {
            do {
                let data = try Data(contentsOf: filePath)
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
    
    /// 清理所有静态资源数据
    func clearAllStaticData() throws {
        let staticDataSetPath = getStaticDataSetPath()
        if fileManager.fileExists(atPath: staticDataSetPath.path) {
            try fileManager.removeItem(at: staticDataSetPath)
            Logger.info("Cleared all static data")
            
            // 清理下载时间记录
            for type in ResourceType.allCases {
                defaults.removeObject(forKey: type.downloadTimeKey)
            }
        }
        // 清理内存缓存
        cache.removeAllObjects()
    }
    
    /// 获取联盟图标目录路径
    func getAllianceIconPath() -> URL {
        return getStaticDataSetPath().appendingPathComponent("AllianceIcons")
    }
    
    /// 保存联盟图标
    /// - Parameters:
    ///   - data: 图标数据
    ///   - allianceId: 联盟ID
    func saveAllianceIcon(_ data: Data, allianceId: Int) throws {
        let iconPath = getAllianceIconPath()
        
        // 确保目录存在
        if !fileManager.fileExists(atPath: iconPath.path) {
            try fileManager.createDirectory(at: iconPath, withIntermediateDirectories: true)
        }
        
        let iconFile = iconPath.appendingPathComponent("\(allianceId).png")
        try data.write(to: iconFile)
        Logger.info("Saved alliance icon: \(allianceId)")
    }
    
    /// 获取联盟图标
    /// - Parameter allianceId: 联盟ID
    /// - Returns: 图标数据
    func getAllianceIcon(allianceId: Int) -> Data? {
        let iconFile = getAllianceIconPath().appendingPathComponent("\(allianceId).png")
        return try? Data(contentsOf: iconFile)
    }
    
    /// 清理联盟图标缓存
    func clearAllianceIcons() throws {
        let iconPath = getAllianceIconPath()
        if fileManager.fileExists(atPath: iconPath.path) {
            try fileManager.removeItem(at: iconPath)
            Logger.info("Cleared alliance icons cache")
        }
    }
    
    /// 获取联盟图标缓存统计
    func getAllianceIconsStats() -> ResourceInfo {
        let iconPath = getAllianceIconPath()
        let exists = fileManager.fileExists(atPath: iconPath.path)
        var totalSize: Int64 = 0
        var lastModified: Date? = nil
        var iconCount: Int = 0
        
        if exists {
            if let enumerator = fileManager.enumerator(atPath: iconPath.path) {
                for case let fileName as String in enumerator {
                    if fileName.hasSuffix(".png") {
                        iconCount += 1
                        let filePath = (iconPath.path as NSString).appendingPathComponent(fileName)
                        do {
                            let attributes = try fileManager.attributesOfItem(atPath: filePath)
                            totalSize += attributes[.size] as? Int64 ?? 0
                            
                            // 使用最新的修改时间
                            if let fileModified = attributes[.modificationDate] as? Date {
                                if lastModified == nil || fileModified > lastModified! {
                                    lastModified = fileModified
                                }
                            }
                        } catch {
                            Logger.error("Error getting alliance icon attributes: \(error)")
                        }
                    }
                }
            }
        }
        
        var name = NSLocalizedString("Main_Setting_Static_Resource_Alliance_Icons", comment: "")
        if iconCount > 0 {
            name += String(format: NSLocalizedString("Main_Setting_Static_Resource_Icon_Count", comment: ""), iconCount)
        }
        
        return ResourceInfo(
            name: name,
            exists: exists,
            lastModified: lastModified,
            fileSize: totalSize,
            downloadTime: nil
        )
    }
} 
