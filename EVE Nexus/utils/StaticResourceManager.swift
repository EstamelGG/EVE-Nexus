import Foundation

/// 静态资源管理器 - 统一管理SDE数据的加载路径
class StaticResourceManager {
    static let shared = StaticResourceManager()
    private let fileManager = FileManager.default
    private init() {}

    // MARK: - 路径管理

    /// 获取数据库文件路径
    /// - Parameter name: 数据库名称（如 "item_db_en", "item_db_zh"）
    /// - Returns: 数据库文件路径，根据版本比较决定使用Documents/sde/db/还是Bundle
    func getDatabasePath(name: String) -> String? {
        // 检查是否应该使用 Bundle SDE 数据
        if !shouldUseBundleSDE() {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let sdeDbPath = documentsPath.appendingPathComponent("sde/db/\(name).sqlite").path

            if FileManager.default.fileExists(atPath: sdeDbPath) {
                Logger.info("Using SDE database from Documents: \(sdeDbPath)")
                return sdeDbPath
            }
        }

        // 回退到Bundle中的数据库文件
        if let bundlePath = Bundle.main.path(forResource: name, ofType: "sqlite") {
            Logger.info("Using SDE database from Bundle: \(bundlePath)")
            return bundlePath
        }

        Logger.error("Database file not found: \(name).sqlite (checked Documents/sde/db and Bundle)")
        return nil
    }

    /// 获取本地化文件路径
    /// - Parameter filename: 文件名（如 "accountingentrytypes_localized"）
    /// - Returns: 本地化文件路径，根据版本比较决定使用Documents/sde/localization/还是Bundle
    func getLocalizationPath(filename: String) -> String? {
        // 检查是否应该使用本地SDE数据
        if !shouldUseBundleSDE() {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let sdeLocalizationPath = documentsPath.appendingPathComponent("sde/localization/\(filename).json").path

            if FileManager.default.fileExists(atPath: sdeLocalizationPath) {
                Logger.info("Using SDE localization file from Documents: \(sdeLocalizationPath)")
                return sdeLocalizationPath
            }
        }

        // 回退到Bundle中的文件
        if let bundlePath = Bundle.main.path(forResource: filename, ofType: "json") {
            Logger.info("Using SDE localization file from Bundle: \(bundlePath)")
            return bundlePath
        }

        Logger.error("Localization file not found: \(filename).json (checked Documents/sde/localization and Bundle)")
        return nil
    }

    /// 获取地图数据文件路径
    /// - Parameter filename: 文件名（如 "neighbors_data", "regions_data", "systems_data"）
    /// - Returns: 地图数据文件路径，根据版本比较决定使用Documents/sde/maps/还是Bundle
    func getMapDataPath(filename: String) -> String? {
        // 检查是否应该使用本地SDE数据
        if !shouldUseBundleSDE() {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let sdeMapsPath = documentsPath.appendingPathComponent("sde/maps/\(filename).json").path

            if FileManager.default.fileExists(atPath: sdeMapsPath) {
                Logger.info("Using SDE map data from Documents: \(sdeMapsPath)")
                return sdeMapsPath
            }
        }

        // 回退到Bundle中的文件
        if let bundlePath = Bundle.main.path(forResource: filename, ofType: "json") {
            Logger.info("Using SDE map data from Bundle: \(bundlePath)")
            return bundlePath
        }

        Logger.error("Map data file not found: \(filename).json (checked Documents/sde/maps and Bundle)")
        return nil
    }

    /// 获取地图数据文件URL
    /// - Parameter filename: 文件名（如 "neighbors_data", "regions_data", "systems_data"）
    /// - Returns: 地图数据文件URL，根据版本比较决定使用Documents/sde/maps/还是Bundle
    func getMapDataURL(filename: String) -> URL? {
        // 检查是否应该使用本地SDE数据
        if !shouldUseBundleSDE() {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let sdeMapsPath = documentsPath.appendingPathComponent("sde/maps/\(filename).json")

            if FileManager.default.fileExists(atPath: sdeMapsPath.path) {
                Logger.info("Using SDE map data from Documents: \(sdeMapsPath.path)")
                return sdeMapsPath
            }
        }

        // 回退到Bundle中的文件
        if let bundleURL = Bundle.main.url(forResource: filename, withExtension: "json") {
            Logger.info("Using SDE map data from Bundle: \(bundleURL.path)")
            return bundleURL
        }

        Logger.error("Map data file not found: \(filename).json (checked Documents/sde/maps and Bundle)")
        return nil
    }

    // MARK: - 数据源状态检查

    /// 检查是否使用SDE数据源
    /// - Returns: 如果使用Documents/sde目录中的数据返回true，否则返回false
    func isUsingSDEDataSource() -> Bool {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let sdePath = documentsPath.appendingPathComponent("sde")
        return FileManager.default.fileExists(atPath: sdePath.path)
    }

    /// 检查是否应该使用 Bundle 中的 SDE 数据
    /// - Returns: true 表示使用 Bundle 数据，false 表示使用 Documents/sde 数据
    func shouldUseBundleSDE() -> Bool {
        // 如果本地没有SDE数据，使用Bundle数据
        guard isUsingSDEDataSource() else {
            return true // 使用 Bundle
        }

        // 获取应用版本号
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"

        // 获取本地SDE数据的版本信息
        let localSDEVersion = getLocalSDEVersion()

        // 如果本地没有版本信息，说明是旧版本的数据，应该使用Bundle数据
        guard let localVersion = localSDEVersion else {
            Logger.info("Local SDE data has no version info, using Bundle")
            return true // 使用 Bundle
        }

        // 版本比较：只有版本完全相同才使用 Documents 数据
        let shouldUseBundle = (localVersion != appVersion)
        Logger.info("Version comparison - Local SDE: \(localVersion), App: \(appVersion), Use Bundle: \(shouldUseBundle)")

        return shouldUseBundle
    }

    /// 获取本地SDE数据的版本信息
    /// - Returns: 本地SDE数据版本号，如果不存在返回nil
    private func getLocalSDEVersion() -> String? {
        return UserDefaults.standard.string(forKey: "LocalSDEVersion")
    }

    /// 设置本地SDE数据版本信息
    /// - Parameter version: 版本号
    func setLocalSDEVersion(_ version: String) {
        UserDefaults.standard.set(version, forKey: "LocalSDEVersion")
        Logger.info("Set local SDE version to: \(version)")
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

    /// 重置SDE数据库到Bundle版本
    /// 删除本地SDE数据，让应用重新使用Bundle中的数据库
    func resetSDEDatabase() throws {
        let fileManager = FileManager.default
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let sdePath = documentsPath.appendingPathComponent("sde")

        // 删除本地SDE目录
        if fileManager.fileExists(atPath: sdePath.path) {
            try fileManager.removeItem(at: sdePath)
            Logger.info("Removed local SDE directory: \(sdePath.path)")
        }

        // 清除本地SDE版本信息
        UserDefaults.standard.removeObject(forKey: "LocalSDEVersion")
        Logger.info("Cleared local SDE version info")

        // 发送通知，让应用知道SDE数据已重置
        NotificationCenter.default.post(name: NSNotification.Name("SDEDataReset"), object: nil)
    }

    /// 清理下载的临时文件
    func cleanupDownloadFiles() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let downloadDir = documentsPath.appendingPathComponent("SDEDownload")

        do {
            if FileManager.default.fileExists(atPath: downloadDir.path) {
                try FileManager.default.removeItem(at: downloadDir)
                Logger.info("Cleaned up download directory: \(downloadDir.path)")
            }
        } catch {
            Logger.error("Failed to cleanup download directory: \(error)")
        }
    }
}
