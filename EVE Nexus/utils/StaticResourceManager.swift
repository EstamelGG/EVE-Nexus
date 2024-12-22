import Foundation

/// 静态资源管理器
class StaticResourceManager {
    static let shared = StaticResourceManager()
    private let fileManager = FileManager.default
    private let cache = NSCache<NSString, CacheData>()
    private let defaults = UserDefaults.standard
    
    // 同步队列和锁
    private let fileQueue = DispatchQueue(label: "com.eve.nexus.static.file")
    private let cacheLock = NSLock()
    
    // MARK: - 缓存时间常量
    
    /// 缓存时间枚举
    enum CacheDuration {
        /// 市场订单缓存时间（5分钟）
        static let marketOrders: TimeInterval = 5 * 60
        
        /// 市场历史缓存时间（1小时）
        static let marketHistory: TimeInterval = 60 * 60
        
        /// 星系主权归属数据缓存时间（8小时）
        static let sovereignty: TimeInterval = 8 * 60 * 60
        
        /// 入侵数据缓存时间（60分钟）
        static let incursions: TimeInterval = 60 * 60
        
        /// 主权战争数据缓存时间（8小时）
        static let sovereigntyCampaigns: TimeInterval = 8 * 60 * 60
        
        /// 联盟图标缓存时间（1周）
        static let allianceIcon: TimeInterval = 7 * 24 * 60 * 60
        
        /// 物品渲染图缓存时间（1周）
        static let itemRender: TimeInterval = 7 * 24 * 60 * 60
        
        /// 角色头像缓存时间（1天）
        static let characterPortrait: TimeInterval = 24 * 60 * 60
        
        /// 角色技能缓存时间（1小时）
        static let characterSkills: TimeInterval = 60 * 60
    }
    
    // 修改原有的缓存时间常量，使用新的枚举
    var SOVEREIGNTY_CACHE_DURATION: TimeInterval { CacheDuration.sovereignty }
    var INCURSIONS_CACHE_DURATION: TimeInterval { CacheDuration.incursions }
    var SOVEREIGNTY_CAMPAIGNS_CACHE_DURATION: TimeInterval { CacheDuration.sovereigntyCampaigns }
    var ALLIANCE_ICON_CACHE_DURATION: TimeInterval { CacheDuration.allianceIcon }
    var RENDER_CACHE_DURATION: TimeInterval { CacheDuration.itemRender }
    
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
        case sovereignty_campaigns = "sovereignty_campaigns"
        case factionIcons = "factionIcons"
        case netRenders = "netRenders"
        case marketData = "marketData"
        case characterPortraits = "characterPortraits"
        
        var filename: String {
            switch self {
            case .sovereignty:
                return "sovereignty.json"
            case .incursions:
                return "incursions.json"
            case .sovereignty_campaigns:
                return "sovereignty_campaigns.json"
            case .factionIcons, .netRenders, .marketData, .characterPortraits:
                return ""  // 这些类型使用目录而不是单个文件
            }
        }
        
        var displayName: String {
            switch self {
            case .sovereignty:
                return NSLocalizedString("Main_Setting_Static_Resource_Sovereignty", comment: "")
            case .incursions:
                return NSLocalizedString("Main_Setting_Static_Resource_Incursions", comment: "")
            case .factionIcons:
                let stats = StaticResourceManager.shared.getFactionIconsStats()
                var name = NSLocalizedString("Main_Setting_Static_Resource_Faction_Icons", comment: "")
                if stats.exists {
                    let count = StaticResourceManager.shared.getFactionIconCount()
                    if count > 0 {
                        name += String(format: NSLocalizedString("Main_Setting_Static_Resource_Icon_Count", comment: ""), count)
                    }
                }
                return name
            case .netRenders:
                let stats = StaticResourceManager.shared.getNetRendersStats()
                var name = NSLocalizedString("Main_Setting_Static_Resource_Net_Renders", comment: "")
                if stats.exists {
                    let count = StaticResourceManager.shared.getNetRenderCount()
                    if count > 0 {
                        name += String(format: NSLocalizedString("Main_Setting_Static_Resource_Icon_Count", comment: ""), count)
                    }
                }
                return name
            case .marketData:
                let stats = StaticResourceManager.shared.getMarketDataStats()
                return stats.name
            case .sovereignty_campaigns:
                return NSLocalizedString("Main_Sovereignty_Title", comment: "")
            case .characterPortraits:
                let stats = StaticResourceManager.shared.getCharacterPortraitsStats()
                var name = NSLocalizedString("Main_Setting_Static_Resource_Character_Portraits", comment: "")
                if stats.exists {
                    let count = StaticResourceManager.shared.getCharacterPortraitCount()
                    if count > 0 {
                        name += String(format: NSLocalizedString("Main_Setting_Static_Resource_Icon_Count", comment: ""), count)
                    }
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
            case .factionIcons:
                return StaticResourceManager.shared.ALLIANCE_ICON_CACHE_DURATION
            case .netRenders:
                return StaticResourceManager.shared.RENDER_CACHE_DURATION
            case .sovereignty_campaigns:
                return StaticResourceManager.shared.SOVEREIGNTY_CAMPAIGNS_CACHE_DURATION
            case .characterPortraits:
                return CacheDuration.characterPortrait
            case .marketData:
                return CacheDuration.marketHistory
            }
        }
    }
    
    private init() {}
    
    // 缓存包装类
    class CacheData {
        let data: Data
        let timestamp: Date
        
        init(data: Data, timestamp: Date) {
            self.data = data
            self.timestamp = timestamp
        }
    }
    
    /// 从文件加载数据并更新内存缓存
    /// - Parameters:
    ///   - filePath: 文件路径
    ///   - cacheKey: 缓存键
    /// - Returns: 文件数据
    private func loadFromFileAndCache(filePath: String, cacheKey: NSString) throws -> Data {
        let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        // 更新内存缓存
        cache.setObject(CacheData(data: data, timestamp: Date()), forKey: cacheKey)
        return data
    }
    
    /// 获取静态资源目录路径
    func getStaticDataSetPath() -> URL {
        // 直接返回路径，不使用同步队列
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let staticPath = paths[0].appendingPathComponent("StaticDataSet")
        
        // 确保目录存在
        if !FileManager.default.fileExists(atPath: staticPath.path) {
            try? FileManager.default.createDirectory(at: staticPath, withIntermediateDirectories: true)
        }
        
        return staticPath
    }
    
    /// 获取所有静态资源的状态
    func getAllResourcesStatus() -> [ResourceInfo] {
        return ResourceType.allCases.map { type in
            switch type {
            case .sovereignty, .incursions, .sovereignty_campaigns:
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
                        
                        // 如果文件存在但没有记录下载时间，使用文件修改时间作为下载时间
                        if downloadTime == nil {
                            defaults.set(lastModified, forKey: type.downloadTimeKey)
                        }
                    } catch {
                        Logger.error("Error getting attributes for \(type.filename): \(error)")
                    }
                }
                
                return ResourceInfo(
                    name: type.displayName,
                    exists: exists,
                    lastModified: lastModified,
                    fileSize: fileSize,
                    downloadTime: downloadTime ?? lastModified  // 如果没有下载时间，使用最后修改时间
                )
                
            case .factionIcons:
                let stats = getFactionIconsStats()
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
                
            case .marketData:
                let stats = getMarketDataStats()
                return ResourceInfo(
                    name: type.displayName,
                    exists: stats.exists,
                    lastModified: stats.lastModified,
                    fileSize: stats.fileSize,
                    downloadTime: nil
                )
                
            case .characterPortraits:
                let stats = getCharacterPortraitsStats()
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
    
    /// 保存数据到文件并更新内存缓存
    /// - Parameters:
    ///   - data: 要保存的数据
    ///   - filename: 文件名（包含扩展名）
    ///   - cacheKey: 缓存键
    func saveToFileAndCache(_ data: Data, filename: String, cacheKey: String) throws {
        // 异步保存到文件
        fileQueue.async {
            do {
                let fileURL = self.getStaticDataSetPath().appendingPathComponent(filename)
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: fileURL)
                
                // 更新下载时间
                if let type = ResourceType.allCases.first(where: { $0.filename == filename }) {
                    UserDefaults.standard.set(Date(), forKey: type.downloadTimeKey)
                }
                
                Logger.info("Successfully saved data to file: \(filename)")
            } catch {
                Logger.error("Error saving data to file \(filename): \(error)")
            }
        }
        
        // 更新内存缓存
        cacheLock.lock()
        cache.setObject(CacheData(data: data, timestamp: Date()), forKey: cacheKey as NSString)
        cacheLock.unlock()
    }
    
    /// 强制刷新指定资源
    /// - Parameter type: 资源类型
    /// - Returns: 是否刷新成功
    func forceRefresh(_ type: ResourceType) async throws {
        switch type {
        case .sovereignty:
            Logger.info("Force refreshing sovereignty data")
            // 从网络获取新数据
            let sovereigntyData = try await SovereigntyDataAPI.shared.fetchSovereigntyData()
            let jsonData = try JSONEncoder().encode(sovereigntyData)
            
            // 保存到文件
            try saveToFileAndCache(jsonData, filename: type.filename, cacheKey: type.rawValue)
            
            Logger.info("Successfully refreshed sovereignty data")
            
        case .incursions:
            Logger.info("Force refreshing incursions data")
            // 从网络获取新数据
            let incursionsData = try await IncursionsAPI.shared.fetchIncursions(forceRefresh: true)
            let jsonData = try JSONEncoder().encode(incursionsData)
            
            // 保存到文件
            try saveToFileAndCache(jsonData, filename: type.filename, cacheKey: type.rawValue)
            
            Logger.info("Successfully refreshed incursions data")
            
        case .sovereignty_campaigns:
            Logger.info("Force refreshing sovereignty campaigns data")
            // 从网络获取新数据
            let campaignsData = try await SovereigntyCampaignsAPI.shared.fetchSovereigntyCampaigns(forceRefresh: true)
            let jsonData = try JSONEncoder().encode(campaignsData)
            
            // 保存到文件
            try saveToFileAndCache(jsonData, filename: type.filename, cacheKey: type.rawValue)
            
            Logger.info("Successfully refreshed sovereignty campaigns data")
            
        case .factionIcons, .netRenders:
            // 这两种类型的资源是按需获取的，不支持批量刷新
            Logger.info("Faction icons and net renders are refreshed on-demand")
            break
            
        case .marketData:
            // 市场数据不支持批量刷新
            Logger.info("Market data is refreshed on-demand")
            break
            
        case .characterPortraits:
            // 角色头像是按需获取的，不支持批量刷新
            Logger.info("Character portraits are refreshed on-demand")
            break
        }
    }
    
    /// 清理内存缓存
    func clearMemoryCache() {
        cache.removeAllObjects()
    }
    
    // MARK: - 缓存时间计算
    private func getRemainingCacheTime(lastModified: Date, duration: TimeInterval) -> TimeInterval {
        let elapsed = Date().timeIntervalSince(lastModified)
        return max(0, duration - elapsed)
    }
    
    private func isFileExpired(at filePath: String, duration: TimeInterval) -> Bool {
        guard let attributes = try? fileManager.attributesOfItem(atPath: filePath),
              let modificationDate = attributes[.modificationDate] as? Date else {
            return true
        }
        return getRemainingCacheTime(lastModified: modificationDate, duration: duration) <= 0
    }
    
    /// 获取主权数据
    /// - Parameter forceRefresh: 是否强制刷新
    /// - Returns: 主权数据数组
    func fetchSovereigntyData(forceRefresh: Bool = false) async throws -> [SovereigntyData] {
        return try await SovereigntyDataAPI.shared.fetchSovereigntyData(forceRefresh: forceRefresh)
    }
    
    /// 清理所有静态资源数据
    func clearAllStaticData() throws {
        let staticDataSetPath = getStaticDataSetPath()
        if fileManager.fileExists(atPath: staticDataSetPath.path) {
            try fileManager.removeItem(at: staticDataSetPath)
            Logger.info("Cleared all static data")
            
            // 重新创建必要的目录
            try fileManager.createDirectory(at: staticDataSetPath, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: getCharacterPortraitsPath(), withIntermediateDirectories: true)
            try fileManager.createDirectory(at: getNetRendersPath(), withIntermediateDirectories: true)
            try fileManager.createDirectory(at: getMarketDataPath(), withIntermediateDirectories: true)
        }
        
        // 清理内存缓存
        cache.removeAllObjects()
        
        // 清理下载时间记录
        for type in ResourceType.allCases {
            UserDefaults.standard.removeObject(forKey: type.downloadTimeKey)
        }
        
        // 清除 UserDefaults 中的数据
        defaults.removeObject(forKey: DefaultsKey.incursions.rawValue)
        defaults.removeObject(forKey: DefaultsKey.sovereignty.rawValue)
        defaults.removeObject(forKey: DefaultsKey.sovereigntyCampaigns.rawValue)
        
        // 清除所有市场数据
        let allKeys = defaults.dictionaryRepresentation().keys
        for key in allKeys {
            if key.starts(with: "market_history_") || key.starts(with: "market_orders_") {
                defaults.removeObject(forKey: key)
            }
        }
        
        Logger.info("Cleared all static data from UserDefaults")
    }
    
    /// 获取联盟图标目录路径
    func getAllianceIconPath() -> URL {
        let iconPath = getStaticDataSetPath().appendingPathComponent("FactionIcons")
        // 确保目录存在
        if !FileManager.default.fileExists(atPath: iconPath.path) {
            try? FileManager.default.createDirectory(at: iconPath, withIntermediateDirectories: true)
        }
        return iconPath
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
        
        let iconFile = iconPath.appendingPathComponent("alliance_\(allianceId).png")
        try data.write(to: iconFile)
        Logger.info("Saved alliance icon: \(allianceId)")
    }
    
    /// 获取联盟图标
    /// - Parameter allianceId: 联盟ID
    /// - Returns: 图标数据
    func getAllianceIcon(allianceId: Int) -> Data? {
        let iconFile = getAllianceIconPath().appendingPathComponent("alliance_\(allianceId).png")
        
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

    
    /// 获取市场数据目录路径
    func getMarketDataPath() -> URL {
        let marketPath = getStaticDataSetPath().appendingPathComponent("Market")
        // 确保目录存在
        if !FileManager.default.fileExists(atPath: marketPath.path) {
            try? FileManager.default.createDirectory(at: marketPath, withIntermediateDirectories: true)
        }
        return marketPath
    }
    
    /// 保存市场订单数据
    /// - Parameters:
    ///   - orders: 订单数据
    ///   - itemId: 物品ID
    ///   - regionId: 星域ID
    func saveMarketOrders(_ orders: [MarketOrder], itemId: Int, regionId: Int) throws {
        let marketPath = getMarketDataPath()
        let orderFile = marketPath.appendingPathComponent("order_\(itemId)_\(regionId).json")
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
        let marketPath = getMarketDataPath()
        let historyFile = marketPath.appendingPathComponent("history_\(itemId)_\(regionId).json")
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
        let orderFile = getMarketDataPath().appendingPathComponent("order_\(itemId)_\(regionId).json")
        guard let data = try? Data(contentsOf: orderFile),
              let container = try? JSONDecoder().decode(MarketDataContainer<[MarketOrder]>.self, from: data),
              Date().timeIntervalSince(container.timestamp) < CacheDuration.marketOrders
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
        let historyFile = getMarketDataPath().appendingPathComponent("history_\(itemId)_\(regionId).json")
        guard let data = try? Data(contentsOf: historyFile),
              let container = try? JSONDecoder().decode(MarketDataContainer<[MarketHistory]>.self, from: data),
              Date().timeIntervalSince(container.timestamp) < CacheDuration.marketHistory
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
        var itemCount = Set<Int>()
        var dataCount: Int = 0
        
        if exists {
            if let enumerator = fileManager.enumerator(atPath: marketPath.path) {
                for case let fileName as String in enumerator {
                    if fileName.hasSuffix(".json") {
                        dataCount += 1
                        let filePath = (marketPath.path as NSString).appendingPathComponent(fileName)
                        
                        // 从文件名提取物品ID
                        let components = fileName.components(separatedBy: "_")
                        if components.count >= 3,
                           let itemId = Int(components[1]) {  // 直接获取第二个部分作为物品ID
                            itemCount.insert(itemId)
                        }
                        
                        do {
                            let attributes = try fileManager.attributesOfItem(atPath: filePath)
                            totalSize += attributes[.size] as? Int64 ?? 0
                            
                            if let fileModified = attributes[.modificationDate] as? Date {
                                if lastModified == nil || fileModified > lastModified! {
                                    lastModified = fileModified
                                }
                            }
                        } catch {
                            Logger.error("Error getting market data attributes: \(error)")
                        }
                    }
                }
            }
        }
        var name = String()
        if itemCount.count > 0 {
            name = String(format: NSLocalizedString("Main_Setting_Market_Data", comment: ""), itemCount.count, dataCount)
        } else {
            name = String(format: NSLocalizedString("Main_Setting_Market_Data_0", comment: ""))
        }
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
        let renderPath = getStaticDataSetPath().appendingPathComponent("NetRenders")
        // 确保目录存在
        if !FileManager.default.fileExists(atPath: renderPath.path) {
            try? FileManager.default.createDirectory(at: renderPath, withIntermediateDirectories: true)
        }
        return renderPath
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
        // 如果强制刷新，直接从网络获取
        if forceRefresh {
            Logger.info("Force refreshing incursions data from network")
            let incursionsData = try await IncursionsAPI.shared.fetchIncursions(forceRefresh: true)
            try saveToDefaults(incursionsData, key: DefaultsKey.incursions.rawValue)
            return incursionsData
        }
        
        // 尝试从缓存获取
        if let cached: [Incursion] = getFromDefaults(DefaultsKey.incursions.rawValue, duration: INCURSIONS_CACHE_DURATION) {
            Logger.info("Got incursions data from cache")
            return cached
        }
        
        // 从网络获取
        Logger.info("Fetching incursions data from network")
        let incursionsData = try await IncursionsAPI.shared.fetchIncursions()
        try saveToDefaults(incursionsData, key: DefaultsKey.incursions.rawValue)
        return incursionsData
    }
    
    /// 获取联盟图标数量
    func getAllianceIconCount() -> Int {
        let iconPath = getAllianceIconPath()
        var count = 0
        
        if fileManager.fileExists(atPath: iconPath.path),
           let enumerator = fileManager.enumerator(atPath: iconPath.path) {
            for case let fileName as String in enumerator {
                if fileName.starts(with: "alliance_") && fileName.hasSuffix(".png") {
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
    
    /// 获取主权战役数据
    /// - Parameter forceRefresh: 是否强制刷新
    /// - Returns: 主权战役数据数组
    func fetchSovereigntyCampaigns(forceRefresh: Bool = false) async throws -> [SovereigntyCampaign] {
        // 如果强制刷新，直接从网络获取
        if forceRefresh {
            Logger.info("Force refreshing sovereignty campaigns data from network")
            let campaignsData = try await SovereigntyCampaignsAPI.shared.fetchSovereigntyCampaigns(forceRefresh: true)
            try saveToDefaults(campaignsData, key: DefaultsKey.sovereigntyCampaigns.rawValue)
            return campaignsData
        }
        
        // 尝试从缓存获取
        if let cached: [SovereigntyCampaign] = getFromDefaults(DefaultsKey.sovereigntyCampaigns.rawValue, duration: SOVEREIGNTY_CAMPAIGNS_CACHE_DURATION) {
            Logger.info("Got sovereignty campaigns data from cache")
            return cached
        }
        
        // 从网络获取
        Logger.info("Fetching sovereignty campaigns data from network")
        let campaignsData = try await SovereigntyCampaignsAPI.shared.fetchSovereigntyCampaigns()
        try saveToDefaults(campaignsData, key: DefaultsKey.sovereigntyCampaigns.rawValue)
        return campaignsData
    }
    
    /// 数据容器
    private struct DataContainer<T: Codable>: Codable {
        let data: T
        let timestamp: Date
    }
    
    // MARK: - UserDefaults 数据管理
    enum DefaultsKey: String {
        case incursions = "incursions_data"
        case sovereignty = "sovereignty_data"
        case sovereigntyCampaigns = "sovereignty_campaigns_data"
        
        // 市场数据使用动态键
        static func marketHistory(typeID: Int, regionID: Int) -> String {
            return "market_history_\(typeID)_\(regionID)"
        }
        
        static func marketOrders(typeID: Int, regionID: Int) -> String {
            return "market_orders_\(typeID)_\(regionID)"
        }
    }
    
    /// 从 UserDefaults 获取数据
    /// - Parameters:
    ///   - key: 数据键
    ///   - duration: 缓存时间
    /// - Returns: 解码后的数据（如果存在且未过期）
    func getFromDefaults<T: Codable>(_ key: String, duration: TimeInterval) -> T? {
        guard let data = defaults.data(forKey: key),
              let container = try? JSONDecoder().decode(DataContainer<T>.self, from: data),
              Date().timeIntervalSince(container.timestamp) < duration else {
            return nil
        }
        return container.data
    }
    
    /// 保存数据到 UserDefaults
    /// - Parameters:
    ///   - data: 要保存的数据
    ///   - key: 数据键
    func saveToDefaults<T: Codable>(_ data: T, key: String) throws {
        let container = DataContainer(data: data, timestamp: Date())
        let encodedData = try JSONEncoder().encode(container)
        defaults.set(encodedData, forKey: key)
    }
    
    // MARK: - 入侵数据管理
    func getIncursions() -> [Incursion]? {
        return getFromDefaults(DefaultsKey.incursions.rawValue, duration: INCURSIONS_CACHE_DURATION)
    }
    
    func saveIncursions(_ incursions: [Incursion]) throws {
        try saveToDefaults(incursions, key: DefaultsKey.incursions.rawValue)
        Logger.info("Saved incursions data to UserDefaults")
    }
    
    // MARK: - 主权归属数据管理
    func getSovereignty() -> [SovereigntyData]? {
        return getFromDefaults(DefaultsKey.sovereignty.rawValue, duration: SOVEREIGNTY_CACHE_DURATION)
    }
    
    func saveSovereignty(_ sovereignty: [SovereigntyData]) throws {
        try saveToDefaults(sovereignty, key: DefaultsKey.sovereignty.rawValue)
        Logger.info("Saved sovereignty data to UserDefaults")
    }
    
    // MARK: - 主权战争数据管理
    func getSovereigntyCampaigns() -> [EVE_Nexus.SovereigntyCampaign]? {
        return getFromDefaults(DefaultsKey.sovereigntyCampaigns.rawValue, duration: SOVEREIGNTY_CAMPAIGNS_CACHE_DURATION)
    }
    
    func saveSovereigntyCampaigns(_ campaigns: [EVE_Nexus.SovereigntyCampaign]) throws {
        try saveToDefaults(campaigns, key: DefaultsKey.sovereigntyCampaigns.rawValue)
        Logger.info("Saved sovereignty campaigns data to UserDefaults")
    }
    
    // 添加角色头像相关的函数
    /// 获取角色头像目录路径
    func getCharacterPortraitsPath() -> URL {
        let portraitsPath = getStaticDataSetPath().appendingPathComponent("CharacterPortraits")
        // 确保目录存在
        if !FileManager.default.fileExists(atPath: portraitsPath.path) {
            try? FileManager.default.createDirectory(at: portraitsPath, withIntermediateDirectories: true)
        }
        return portraitsPath
    }
    
    /// 获取角色头像数量
    func getCharacterPortraitCount() -> Int {
        let portraitsPath = getCharacterPortraitsPath()
        var count = 0
        
        if let enumerator = fileManager.enumerator(atPath: portraitsPath.path) {
            for case let fileName as String in enumerator {
                if fileName.hasSuffix(".png") {
                    count += 1
                }
            }
        }
        
        return count
    }
    
    /// 获取角色头像统计信息
    func getCharacterPortraitsStats() -> ResourceInfo {
        let portraitsPath = getCharacterPortraitsPath()
        let exists = fileManager.fileExists(atPath: portraitsPath.path)
        var totalSize: Int64 = 0
        var lastModified: Date? = nil
        var portraitCount: Int = 0
        
        if exists {
            if let enumerator = fileManager.enumerator(atPath: portraitsPath.path) {
                for case let fileName as String in enumerator {
                    if fileName.hasSuffix(".png") {
                        portraitCount += 1
                        let filePath = (portraitsPath.path as NSString).appendingPathComponent(fileName)
                        do {
                            let attributes = try fileManager.attributesOfItem(atPath: filePath)
                            totalSize += attributes[.size] as? Int64 ?? 0
                            
                            if let fileModified = attributes[.modificationDate] as? Date {
                                if lastModified == nil || fileModified > lastModified! {
                                    lastModified = fileModified
                                }
                            }
                        } catch {
                            Logger.error("Error getting character portrait attributes: \(error)")
                        }
                    }
                }
            }
        }
        
        var name = NSLocalizedString("Main_Setting_Static_Resource_Character_Portraits", comment: "")
        if portraitCount > 0 {
            name += String(format: NSLocalizedString("Main_Setting_Static_Resource_Icon_Count", comment: ""), portraitCount)
        }
        
        return ResourceInfo(
            name: name,
            exists: exists,
            lastModified: lastModified,
            fileSize: totalSize,
            downloadTime: nil
        )
    }
    
    /// 清理角色头像缓存
    func clearCharacterPortraits() throws {
        let portraitsPath = getCharacterPortraitsPath()
        if fileManager.fileExists(atPath: portraitsPath.path) {
            try fileManager.removeItem(at: portraitsPath)
            Logger.info("Cleared character portraits cache")
        }
    }
    
    /// 获取势力图标目录路径
    func getFactionIconPath() -> URL {
        let iconPath = getStaticDataSetPath().appendingPathComponent("FactionIcons")
        // 确保目录存在
        if !FileManager.default.fileExists(atPath: iconPath.path) {
            try? FileManager.default.createDirectory(at: iconPath, withIntermediateDirectories: true)
        }
        return iconPath
    }
    
    /// 获取势力图标缓存统计
    func getFactionIconsStats() -> ResourceInfo {
        let iconPath = getFactionIconPath()
        let exists = fileManager.fileExists(atPath: iconPath.path)
        var totalSize: Int64 = 0
        var lastModified: Date? = nil
        var iconCount: Int = 0
        
        if exists,
           let enumerator = fileManager.enumerator(at: iconPath, 
                                                 includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) {
            for case let fileURL as URL in enumerator {
                if fileURL.pathExtension == "png" {
                    do {
                        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
                        if let fileSize = attributes[.size] as? Int64 {
                            totalSize += fileSize
                            iconCount += 1
                        }
                        if let modificationDate = attributes[.modificationDate] as? Date {
                            if lastModified == nil || modificationDate > lastModified! {
                                lastModified = modificationDate
                            }
                        }
                    } catch {
                        Logger.error("Error getting faction icon attributes: \(error)")
                    }
                }
            }
        }
        
        var name = NSLocalizedString("Main_Setting_Static_Resource_Faction_Icons", comment: "")
        if iconCount > 0 {
            name += String(format: NSLocalizedString("Main_Setting_Static_Resource_Icon_Count", comment: ""), iconCount)
        }
        
        return ResourceInfo(
            name: name,
            exists: exists && iconCount > 0,
            lastModified: lastModified,
            fileSize: totalSize,
            downloadTime: nil
        )
    }
    
    /// 获取势力图标数量
    func getFactionIconCount() -> Int {
        let iconPath = getFactionIconPath()
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
} 
