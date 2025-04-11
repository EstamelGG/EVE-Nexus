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
        case factionIcons
        case netRenders
        case characterPortraits
        var downloadTimeKey: String {
            return "StaticResource_\(rawValue)_DownloadTime"
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

    /// 获取静态资源目录路径
    func getStaticDataSetPath() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let staticPath = paths[0].appendingPathComponent("StaticDataSet")

        if !FileManager.default.fileExists(atPath: staticPath.path) {
            try? FileManager.default.createDirectory(
                at: staticPath, withIntermediateDirectories: true
            )
        }

        return staticPath
    }

    /// 清理所有静态资源数据
    func clearAllStaticData() throws {
        let staticDataSetPath = getStaticDataSetPath()
        if fileManager.fileExists(atPath: staticDataSetPath.path) {
            try fileManager.removeItem(at: staticDataSetPath)

            // 重新创建必要的目录
            try fileManager.createDirectory(
                at: staticDataSetPath, withIntermediateDirectories: true
            )
            try fileManager.createDirectory(
                at: getCharacterPortraitsPath(), withIntermediateDirectories: true
            )
            try fileManager.createDirectory(
                at: getNetRendersPath(), withIntermediateDirectories: true
            )
        }

        // 清理内存缓存
        cache.removeAllObjects()

        // 清理下载时间记录
        for type in ResourceType.allCases {
            UserDefaults.standard.removeObject(forKey: type.downloadTimeKey)
        }

        Logger.info("Cleared all static data")
    }

    /// 获取渲染图目录路径
    func getNetRendersPath() -> URL {
        let renderPath = getStaticDataSetPath().appendingPathComponent("NetRenders")
        if !fileManager.fileExists(atPath: renderPath.path) {
            try? fileManager.createDirectory(at: renderPath, withIntermediateDirectories: true)
        }
        return renderPath
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
}
