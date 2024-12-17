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
        case incursions = "incursions"
        case allianceIcons = "allianceIcons"
        case netRenders = "netRenders"
        
        var filename: String {
            return "\(self.rawValue).json"
        }
        
        var displayName: String {
            switch self {
            case .sovereignty:
                return NSLocalizedString("Main_Setting_Static_Resource_Sovereignty", comment: "")
            case .incursions:
                return NSLocalizedString("Main_Setting_Static_Resource_Incursions", comment: "")
            case .allianceIcons:
                let stats = StaticResourceManager.shared.getAllianceIconsStats()
                var name = NSLocalizedString("Main_Setting_Static_Resource_Alliance_Icons", comment: "")
                if stats.exists {
                    let count = StaticResourceManager.shared.getAllianceIconCount()
                    name += String(format: NSLocalizedString("Main_Setting_Static_Resource_Icon_Count", comment: ""), count)
                }
                return name
            case .netRenders:
                let stats = StaticResourceManager.shared.getNetRendersStats()
                var name = NSLocalizedString("Main_Setting_Static_Resource_Net_Renders", comment: "")
                if stats.exists {
                    let count = StaticResourceManager.shared.getNetRenderCount()
                    name += String(format: NSLocalizedString("Main_Setting_Static_Resource_Icon_Count", comment: ""), count)
                }
                return name
            }
        }
        
        var downloadTimeKey: String {
            return "StaticResource_\(self.rawValue)_DownloadTime"
        }
        
        var cacheDuration: TimeInterval {
            switch self {
            case .sovereignty:
                return StaticResourceManager.shared.SOVEREIGNTY_CACHE_DURATION
            case .incursions:
                return StaticResourceManager.shared.INCURSIONS_CACHE_DURATION
            case .allianceIcons:
                return StaticResourceManager.shared.ALLIANCE_ICON_CACHE_DURATION
            case .netRenders:
                return StaticResourceManager.shared.RENDER_CACHE_DURATION
            }
        }
    }
    
    // 缓存有效期常量
    public let SOVEREIGNTY_CACHE_DURATION: TimeInterval = 7 * 24 * 3600  // 7天
    public let RENDER_CACHE_DURATION: TimeInterval = 60 * 24 * 3600      // 30天
    public let ALLIANCE_ICON_CACHE_DURATION: TimeInterval = 30 * 24 * 3600 // 30天
    public let INCURSIONS_CACHE_DURATION: TimeInterval = 4 * 3600        // 4小时
    
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
            switch type {
            case .sovereignty, .incursions:
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
                
            case .allianceIcons:
                let stats = getAllianceIconsStats()
                return ResourceInfo(
                    name: type.displayName,
                    exists: stats.exists,
                    lastModified: stats.lastModified,
                    fileSize: stats.fileSize,
                    downloadTime: nil
                )
                
            case .netRenders:
                let stats = getNetRendersStats()
                return ResourceInfo(
                    name: type.displayName,
                    exists: stats.exists,
                    lastModified: stats.lastModified,
                    fileSize: stats.fileSize,
                    downloadTime: nil
                )
            }
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
            // 同时更新内存缓存
            cache.setObject(CachedResource(data: data, timestamp: Date()), forKey: resourceType.rawValue as NSString)
        }
        
        Logger.info("Saved static resource to file: \(filename)")
    }
    
    /// 从文件加载数据并更新内存缓存
    /// - Parameters:
    ///   - filePath: 文件路径
    ///   - cacheKey: 缓存键
    /// - Returns: 文件数据
    private func loadFromFileAndCache(filePath: String, cacheKey: NSString) throws -> Data {
        let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        // 更新内存缓存
        cache.setObject(CachedResource(data: data, timestamp: Date()), forKey: cacheKey)
        return data
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
            
        case .incursions:
            Logger.info("Force refreshing incursions data")
            // 从网络获取新数据
            let incursionsData = try await NetworkManager.shared.fetchIncursions()
            let jsonData = try JSONEncoder().encode(incursionsData)
            
            // 保存到文件
            try saveToFile(jsonData, filename: type.filename)
            
            // 更新缓存
            cache.setObject(CachedResource(data: jsonData, timestamp: Date()), forKey: type.rawValue as NSString)
            
            Logger.info("Successfully refreshed incursions data")
            
        case .allianceIcons, .netRenders:
            // 这两种类型的资源是按需获取的，不支持批量刷新
            Logger.info("Alliance icons and net renders are refreshed on-demand")
            break
        }
    }
    
    /// 清理内存缓存
    func clearMemoryCache() {
        cache.removeAllObjects()
    }
    
    /// 检查文件是否过期
    /// - Parameters:
    ///   - filePath: 文件路径
    ///   - duration: 有效期（秒）
    /// - Returns: 是否过期
    private func isFileExpired(at filePath: String, duration: TimeInterval) -> Bool {
        guard let attributes = try? fileManager.attributesOfItem(atPath: filePath),
              let modificationDate = attributes[.modificationDate] as? Date else {
            return true
        }
        return Date().timeIntervalSince(modificationDate) >= duration
    }
    
    /// 获取主权数据
    /// - Parameter forceRefresh: 是否强制刷新
    /// - Returns: 主权数据数组
    func fetchSovereigntyData(forceRefresh: Bool = false) async throws -> [SovereigntyData] {
        let cacheKey = ResourceType.sovereignty.rawValue as NSString
        let filename = ResourceType.sovereignty.filename
        let filePath = getStaticDataSetPath().appendingPathComponent(filename)
        
        // 确定是否需要刷新
        var shouldRefresh = forceRefresh
        
        // 检查文件是否过期
        if fileManager.fileExists(atPath: filePath.path) && 
           isFileExpired(at: filePath.path, duration: ResourceType.sovereignty.cacheDuration) {
            shouldRefresh = true
        }
        
        // 如果需要强制刷新，先执行刷新操作
        if shouldRefresh {
            try await self.forceRefresh(.sovereignty)
            return try await fetchSovereigntyData(forceRefresh: false)
        }
        
        // 1. 尝试从内存缓存获取
        if let cached = cache.object(forKey: cacheKey) {
            do {
                let data = try JSONDecoder().decode([SovereigntyData].self, from: cached.data)
                Logger.info("Got sovereignty data from memory cache")
                return data
            } catch {
                Logger.error("Failed to decode cached sovereignty data: \(error)")
            }
        }
        
        // 2. 尝试从文件读取
        if fileManager.fileExists(atPath: filePath.path) {
            do {
                let data = try loadFromFileAndCache(filePath: filePath.path, cacheKey: cacheKey)
                let sovereigntyData = try JSONDecoder().decode([SovereigntyData].self, from: data)
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
        
        // 保存到文件（同时会更新内存缓存）
        try saveToFile(jsonData, filename: filename)
        
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
        
        // 检查文件是否存在且未过期
        if fileManager.fileExists(atPath: iconFile.path) {
            if isFileExpired(at: iconFile.path, duration: ALLIANCE_ICON_CACHE_DURATION) {
                // 如果过期，删除文件
                try? fileManager.removeItem(at: iconFile)
                return nil
            }
            return try? Data(contentsOf: iconFile)
        }
        return nil
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
    
    /// 获取市场数据目录路径
    func getMarketDataPath() -> URL {
        return getStaticDataSetPath().appendingPathComponent("Market")
    }
    
    /// 获取指定物品的市场数据目录
    /// - Parameter itemId: 物品ID
    /// - Returns: 目录URL
    func getItemMarketPath(itemId: Int) -> URL {
        return getMarketDataPath().appendingPathComponent("Market_\(itemId)")
    }
    
    /// 保存市场订单数据
    /// - Parameters:
    ///   - orders: 订单数据
    ///   - itemId: 物品ID
    ///   - regionId: 星域ID
    func saveMarketOrders(_ orders: [MarketOrder], itemId: Int, regionId: Int) throws {
        let marketPath = getItemMarketPath(itemId: itemId)
        
        // 确保目录存在
        if !fileManager.fileExists(atPath: marketPath.path) {
            try fileManager.createDirectory(at: marketPath, withIntermediateDirectories: true)
        }
        
        let orderFile = marketPath.appendingPathComponent("orders_\(regionId).json")
        let data = try JSONEncoder().encode(MarketDataContainer(data: orders, timestamp: Date()))
        try data.write(to: orderFile)
        Logger.info("Saved market orders for item \(itemId) in region \(regionId)")
    }
    
    /// 保存市场历史数据
    /// - Parameters:
    ///   - history: 历史数据
    ///   - itemId: 物品ID
    ///   - regionId: 星域ID
    func saveMarketHistory(_ history: [MarketHistory], itemId: Int, regionId: Int) throws {
        let marketPath = getItemMarketPath(itemId: itemId)
        
        // 确保目录存在
        if !fileManager.fileExists(atPath: marketPath.path) {
            try fileManager.createDirectory(at: marketPath, withIntermediateDirectories: true)
        }
        
        let historyFile = marketPath.appendingPathComponent("history_\(regionId).json")
        let data = try JSONEncoder().encode(MarketDataContainer(data: history, timestamp: Date()))
        try data.write(to: historyFile)
        Logger.info("Saved market history for item \(itemId) in region \(regionId)")
    }
    
    /// 获取市场订单数据
    /// - Parameters:
    ///   - itemId: 物品ID
    ///   - regionId: 星域ID
    /// - Returns: 订单数据（如果存在且未过期）
    func getMarketOrders(itemId: Int, regionId: Int) -> [MarketOrder]? {
        let orderFile = getItemMarketPath(itemId: itemId).appendingPathComponent("orders_\(regionId).json")
        guard let data = try? Data(contentsOf: orderFile),
              let container = try? JSONDecoder().decode(MarketDataContainer<[MarketOrder]>.self, from: data),
              Date().timeIntervalSince(container.timestamp) < 300 // 5分钟有效期
        else {
            return nil
        }
        return container.data
    }
    
    /// 获取市场历史数据
    /// - Parameters:
    ///   - itemId: 物品ID
    ///   - regionId: 星域ID
    /// - Returns: 历史数据（如果存在且未过期）
    func getMarketHistory(itemId: Int, regionId: Int) -> [MarketHistory]? {
        let historyFile = getItemMarketPath(itemId: itemId).appendingPathComponent("history_\(regionId).json")
        guard let data = try? Data(contentsOf: historyFile),
              let container = try? JSONDecoder().decode(MarketDataContainer<[MarketHistory]>.self, from: data),
              Date().timeIntervalSince(container.timestamp) < 3600 // 1小时有效期
        else {
            return nil
        }
        return container.data
    }
    
    /// 清理市场数据缓存
    func clearMarketData() throws {
        let marketPath = getMarketDataPath()
        if fileManager.fileExists(atPath: marketPath.path) {
            try fileManager.removeItem(at: marketPath)
            Logger.info("Cleared market data cache")
        }
    }
    
    /// 市场数据容器
    private struct MarketDataContainer<T: Codable>: Codable {
        let data: T
        let timestamp: Date
    }
    
    /// 获取市场数据统计
    func getMarketDataStats() -> ResourceInfo {
        let marketPath = getMarketDataPath()
        let exists = fileManager.fileExists(atPath: marketPath.path)
        var totalSize: Int64 = 0
        var lastModified: Date? = nil
        var itemCount: Int = 0
        var dataCount: Int = 0
        
        if exists {
            if let enumerator = fileManager.enumerator(atPath: marketPath.path) {
                for case let fileName as String in enumerator {
                    if fileName.hasSuffix(".json") {
                        dataCount += 1
                        let filePath = (marketPath.path as NSString).appendingPathComponent(fileName)
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
                            Logger.error("Error getting market data attributes: \(error)")
                        }
                    } else if fileName.hasPrefix("Market_") {
                        itemCount += 1
                    }
                }
            }
        }
        
        let name = String(format: NSLocalizedString("Main_Setting_Market_Data", comment: ""), itemCount, dataCount)
        
        return ResourceInfo(
            name: name,
            exists: exists,
            lastModified: lastModified,
            fileSize: totalSize,
            downloadTime: nil
        )
    }
    
    /// 获取渲染图目录路径
    func getNetRendersPath() -> URL {
        return getStaticDataSetPath().appendingPathComponent("NetRenders")
    }
    
    /// 保存渲染图
    /// - Parameters:
    ///   - data: 图片数据
    ///   - typeId: 物品ID
    func saveNetRender(_ data: Data, typeId: Int) throws {
        let renderPath = getNetRendersPath()
        
        // 确保目录存在
        if !fileManager.fileExists(atPath: renderPath.path) {
            try fileManager.createDirectory(at: renderPath, withIntermediateDirectories: true)
        }
        
        let renderFile = renderPath.appendingPathComponent("\(typeId).png")
        try data.write(to: renderFile)
        Logger.info("Saved net render: \(typeId)")
    }
    
    /// 获取渲染图
    /// - Parameter typeId: 物品ID
    /// - Returns: 图片数据
    func getNetRender(typeId: Int) -> Data? {
        let renderFile = getNetRendersPath().appendingPathComponent("\(typeId).png")
        
        // 检查文件是否存在且未过期
        if fileManager.fileExists(atPath: renderFile.path) {
            if isFileExpired(at: renderFile.path, duration: RENDER_CACHE_DURATION) {
                // 如果过期，删除文件
                try? fileManager.removeItem(at: renderFile)
                return nil
            }
            return try? Data(contentsOf: renderFile)
        }
        return nil
    }
    
    /// 清理渲染图缓存
    func clearNetRenders() throws {
        let renderPath = getNetRendersPath()
        if fileManager.fileExists(atPath: renderPath.path) {
            try fileManager.removeItem(at: renderPath)
            Logger.info("Cleared net renders cache")
        }
    }
    
    /// 获取渲染图缓存统计
    func getNetRendersStats() -> ResourceInfo {
        let renderPath = getNetRendersPath()
        let exists = fileManager.fileExists(atPath: renderPath.path)
        var totalSize: Int64 = 0
        var lastModified: Date? = nil
        var renderCount: Int = 0
        
        if exists {
            if let enumerator = fileManager.enumerator(atPath: renderPath.path) {
                for case let fileName as String in enumerator {
                    if fileName.hasSuffix(".png") {
                        renderCount += 1
                        let filePath = (renderPath.path as NSString).appendingPathComponent(fileName)
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
                            Logger.error("Error getting net render attributes: \(error)")
                        }
                    }
                }
            }
        }
        
        var name = NSLocalizedString("Main_Setting_Static_Resource_Net_Renders", comment: "")
        if renderCount > 0 {
            name += String(format: NSLocalizedString("Main_Setting_Static_Resource_Icon_Count", comment: ""), renderCount)
        }
        
        return ResourceInfo(
            name: name,
            exists: exists,
            lastModified: lastModified,
            fileSize: totalSize,
            downloadTime: nil
        )
    }
    
    /// 获取入侵数据
    /// - Parameter forceRefresh: 是否强制刷新
    /// - Returns: 入侵数据数组
    func fetchIncursionsData(forceRefresh: Bool = false) async throws -> [Incursion] {
        let cacheKey = ResourceType.incursions.rawValue as NSString
        let filename = ResourceType.incursions.filename
        let filePath = getStaticDataSetPath().appendingPathComponent(filename)
        
        // 确定是否需要刷新
        var shouldRefresh = forceRefresh
        
        // 检查文件是否过期
        if fileManager.fileExists(atPath: filePath.path) && 
           isFileExpired(at: filePath.path, duration: ResourceType.incursions.cacheDuration) {
            shouldRefresh = true
        }
        
        // 如果需要强制刷新，先执行刷新操作
        if shouldRefresh {
            try await self.forceRefresh(.incursions)
            return try await fetchIncursionsData(forceRefresh: false)
        }
        
        // 1. 尝试从内存缓存获取
        if let cached = cache.object(forKey: cacheKey) {
            do {
                let data = try JSONDecoder().decode([Incursion].self, from: cached.data)
                Logger.info("Got incursions data from memory cache")
                return data
            } catch {
                Logger.error("Failed to decode cached incursions data: \(error)")
            }
        }
        
        // 2. 尝试从文件读取
        if fileManager.fileExists(atPath: filePath.path) {
            do {
                let data = try loadFromFileAndCache(filePath: filePath.path, cacheKey: cacheKey)
                let incursionsData = try JSONDecoder().decode([Incursion].self, from: data)
                Logger.info("Got incursions data from file")
                return incursionsData
            } catch {
                Logger.error("Failed to load incursions data from file: \(error)")
            }
        }
        
        // 3. 从网络获取
        Logger.info("Fetching incursions data from network")
        let incursionsData = try await NetworkManager.shared.fetchIncursions()
        let jsonData = try JSONEncoder().encode(incursionsData)
        
        // 保存到文件（同时会更新内存缓存）
        try saveToFile(jsonData, filename: filename)
        
        return incursionsData
    }
    
    /// 获取联盟图标数量
    func getAllianceIconCount() -> Int {
        let iconPath = getAllianceIconPath()
        var count = 0
        
        if fileManager.fileExists(atPath: iconPath.path),
           let enumerator = fileManager.enumerator(atPath: iconPath.path) {
            for case let fileName as String in enumerator {
                if fileName.hasSuffix(".png") {
                    count += 1
                }
            }
        }
        
        return count
    }
    
    /// 获取渲染图数量
    func getNetRenderCount() -> Int {
        let renderPath = getNetRendersPath()
        var count = 0
        
        if fileManager.fileExists(atPath: renderPath.path),
           let enumerator = fileManager.enumerator(atPath: renderPath.path) {
            for case let fileName as String in enumerator {
                if fileName.hasSuffix(".png") {
                    count += 1
                }
            }
        }
        
        return count
    }
} 
