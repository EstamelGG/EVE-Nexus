import Foundation

/// 静态资源管理器（用于管理图片资源的本地缓存）
class StaticResourceManager {
    static let shared = StaticResourceManager()
    private let fileManager = FileManager.default
    private let cache = NSCache<NSString, CacheData>()
    
    // 同步队列和锁
    private let fileQueue = DispatchQueue(label: "com.eve.nexus.static.file")
    private let cacheLock = NSLock()
    
    // MARK: - 缓存时间常量
    
    /// 缓存时间枚举
    enum CacheDuration {
        /// 联盟图标缓存时间（1周）
        static let allianceIcon: TimeInterval = 7 * 24 * 60 * 60
        
        /// 物品渲染图缓存时间（1周）
        static let itemRender: TimeInterval = 7 * 24 * 60 * 60
        
        /// 角色头像缓存时间（1天）
        static let characterPortrait: TimeInterval = 24 * 60 * 60
    }
    
    // 缓存时间常量
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
        case factionIcons = "factionIcons"
        case netRenders = "netRenders"
        case characterPortraits = "characterPortraits"
        
        var displayName: String {
            switch self {
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
            case .factionIcons:
                return StaticResourceManager.shared.ALLIANCE_ICON_CACHE_DURATION
            case .netRenders:
                return StaticResourceManager.shared.RENDER_CACHE_DURATION
            case .characterPortraits:
                return CacheDuration.characterPortrait
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
    private func loadFromFileAndCache(filePath: String, cacheKey: NSString) throws -> Data {
        let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        cache.setObject(CacheData(data: data, timestamp: Date()), forKey: cacheKey)
        return data
    }
    
    /// 获取静态资源目录路径
    func getStaticDataSetPath() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let staticPath = paths[0].appendingPathComponent("StaticDataSet")
        
        if !FileManager.default.fileExists(atPath: staticPath.path) {
            try? FileManager.default.createDirectory(at: staticPath, withIntermediateDirectories: true)
        }
        
        return staticPath
    }
    
    /// 获取所有静态资源的状态
    func getAllResourcesStatus() -> [ResourceInfo] {
        return ResourceType.allCases.map { type in
            switch type {
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
        }
        
        // 清理内存缓存
        cache.removeAllObjects()
        
        // 清理下载时间记录
        for type in ResourceType.allCases {
            UserDefaults.standard.removeObject(forKey: type.downloadTimeKey)
        }
        
        Logger.info("Cleared all static data")
    }
    
    // MARK: - 图片资源管理
    
    /// 获取联盟图标目录路径
    func getAllianceIconPath() -> URL {
        let iconPath = getStaticDataSetPath().appendingPathComponent("FactionIcons")
        if !fileManager.fileExists(atPath: iconPath.path) {
            try? fileManager.createDirectory(at: iconPath, withIntermediateDirectories: true)
        }
        return iconPath
    }
    
    /// 保存联盟图标
    func saveAllianceIcon(_ data: Data, allianceId: Int) throws {
        let iconPath = getAllianceIconPath()
        if !fileManager.fileExists(atPath: iconPath.path) {
            try fileManager.createDirectory(at: iconPath, withIntermediateDirectories: true)
        }
        let iconFile = iconPath.appendingPathComponent("alliance_\(allianceId).png")
        try data.write(to: iconFile)
        Logger.info("Saved alliance icon: \(allianceId)")
    }
    
    /// 获取联盟图标
    func getAllianceIcon(allianceId: Int) -> Data? {
        let iconFile = getAllianceIconPath().appendingPathComponent("alliance_\(allianceId).png")
        if fileManager.fileExists(atPath: iconFile.path) {
            if isFileExpired(at: iconFile.path, duration: ALLIANCE_ICON_CACHE_DURATION) {
                try? fileManager.removeItem(at: iconFile)
                return nil
            }
            return try? Data(contentsOf: iconFile)
        }
        return nil
    }
    
    /// 获取渲染图目录路径
    func getNetRendersPath() -> URL {
        let renderPath = getStaticDataSetPath().appendingPathComponent("NetRenders")
        if !fileManager.fileExists(atPath: renderPath.path) {
            try? fileManager.createDirectory(at: renderPath, withIntermediateDirectories: true)
        }
        return renderPath
    }
    
    /// 保存渲染图
    func saveNetRender(_ data: Data, typeId: Int) throws {
        let renderPath = getNetRendersPath()
        if !fileManager.fileExists(atPath: renderPath.path) {
            try fileManager.createDirectory(at: renderPath, withIntermediateDirectories: true)
        }
        let renderFile = renderPath.appendingPathComponent("\(typeId).png")
        try data.write(to: renderFile)
        Logger.info("Saved net render: \(typeId)")
    }
    
    /// 获取渲染图
    func getNetRender(typeId: Int) -> Data? {
        let renderFile = getNetRendersPath().appendingPathComponent("\(typeId).png")
        if fileManager.fileExists(atPath: renderFile.path) {
            if isFileExpired(at: renderFile.path, duration: RENDER_CACHE_DURATION) {
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
        
        return ResourceInfo(
            name: NSLocalizedString("Main_Setting_Static_Resource_Net_Renders", comment: ""),
            exists: exists,
            lastModified: lastModified,
            fileSize: totalSize,
            downloadTime: nil
        )
    }
    
    // MARK: - 角色头像管理
    
    /// 获取角色头像目录路径
    func getCharacterPortraitsPath() -> URL {
        let portraitsPath = getStaticDataSetPath().appendingPathComponent("CharacterPortraits")
        if !fileManager.fileExists(atPath: portraitsPath.path) {
            try? fileManager.createDirectory(at: portraitsPath, withIntermediateDirectories: true)
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
        
        return ResourceInfo(
            name: NSLocalizedString("Main_Setting_Static_Resource_Character_Portraits", comment: ""),
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
    
    /// 获取联盟图标数量
    func getFactionIconCount() -> Int {
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
    
    /// 获取势力图标缓存统计
    func getFactionIconsStats() -> ResourceInfo {
        let iconPath = getAllianceIconPath()
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
                        if let fileSize = attributes[FileAttributeKey.size] as? Int64 {
                            totalSize += fileSize
                            iconCount += 1
                        }
                        if let modificationDate = attributes[FileAttributeKey.modificationDate] as? Date {
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
        
        return ResourceInfo(
            name: NSLocalizedString("Main_Setting_Static_Resource_Faction_Icons", comment: ""),
            exists: exists && iconCount > 0,
            lastModified: lastModified,
            fileSize: totalSize,
            downloadTime: nil
        )
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
