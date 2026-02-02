import Foundation
import SQLite3

/// 静态资源管理器 - 统一管理SDE数据的加载路径
class StaticResourceManager {
    static let shared = StaticResourceManager()
    private let fileManager = FileManager.default
    private init() {}

    // MARK: - 路径管理

    /// 获取数据库文件路径
    /// - Parameter name: 数据库名称（如 "item_db_en", "item_db_zh", "item_db_de" 等）
    /// - Returns: 数据库文件路径，根据版本比较决定使用Documents/sde/db/还是Bundle
    func getDatabasePath(name: String) -> String? {
        let isBuiltinDB = (name == "item_db_en" || name == "item_db_zh")

        // 额外语言数据库始终从 Documents/sde/db/ 加载（Bundle 中不包含）
        // 内置语言（en/zh）根据版本比较决定数据源
        if !isBuiltinDB || !shouldUseBundleSDE() {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let sdeDbPath = documentsPath.appendingPathComponent("sde/db/\(name).sqlite").path

            if FileManager.default.fileExists(atPath: sdeDbPath) {
                Logger.info("Using SDE database from Documents: \(sdeDbPath)")
                return sdeDbPath
            }
        }

        // 回退到 Bundle（仅 en/zh 存在于 Bundle 中）
        if let bundlePath = Bundle.main.path(forResource: name, ofType: "sqlite") {
            Logger.info("Using SDE database from Bundle: \(bundlePath)")
            return bundlePath
        }

        if !isBuiltinDB {
            Logger.warning("Extra language database not found: \(name).sqlite (needs download)")
        } else {
            Logger.error("Database file not found: \(name).sqlite (checked Documents/sde/db and Bundle)")
        }
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
            Logger.info("本地没有 SDE 数据，使用 Bundle")
            return true // 使用 Bundle
        }

        // 获取 Bundle 数据库的版本
        guard let bundleVersion = getBundleSDEVersion() else {
            Logger.warning("无法读取 Bundle SDE 版本，使用本地数据")
            return false // 无法读取 Bundle 版本，使用本地
        }

        // 获取本地数据库的版本
        guard let localVersion = getDocumentsSDEVersion() else {
            Logger.info("无法读取本地 SDE 版本，使用 Bundle")
            // 检查 item_db_en.sqlite 是否存在：
            // - 不存在：可能只有额外语言数据库，不清理
            // - 存在但无法读取：数据损坏，清理
            let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let enDbPath = documentsPath.appendingPathComponent("sde/db/item_db_en.sqlite")
            if fileManager.fileExists(atPath: enDbPath.path) {
                Logger.warning("item_db_en.sqlite 存在但无法读取版本，数据可能损坏，执行清理")
                cleanupLocalSDEData()
            }
            return true
        }

        // 比较版本号：选择版本更高的数据库
        let shouldUseBundle = compareSDEVersions(bundle: bundleVersion, local: localVersion)

        Logger.info("SDE 版本比较:Bundle: \(bundleVersion.buildNumber).\(bundleVersion.patchNumber), Local:  \(localVersion.buildNumber).\(localVersion.patchNumber), 使用: \(shouldUseBundle ? "Bundle" : "Documents")")

        // 如果决定使用 Bundle，删除 Documents 中的旧版本以节省空间
        if shouldUseBundle {
            cleanupLocalSDEData()
        }

        return shouldUseBundle
    }

    /// 比较 SDE 版本号
    /// - Returns: true 表示 Bundle 版本更高或相同，false 表示本地版本更高
    private func compareSDEVersions(bundle: SDEVersion, local: SDEVersion) -> Bool {
        // 先比较 build_number
        if bundle.buildNumber > local.buildNumber {
            return true // Bundle 更新
        } else if bundle.buildNumber < local.buildNumber {
            return false // 本地更新
        }

        // build_number 相同，比较 patch_number
        if bundle.patchNumber > local.patchNumber {
            return true // Bundle 更新
        } else if bundle.patchNumber < local.patchNumber {
            return false // 本地更新
        }

        // 版本完全相同，优先使用 Bundle（因为 Bundle 是官方打包的）
        return true
    }

    /// SDE 版本信息结构
    private struct SDEVersion {
        let buildNumber: Int
        let patchNumber: Int
    }

    /// 获取 Bundle 中 SDE 数据库的版本信息
    private func getBundleSDEVersion() -> SDEVersion? {
        // 使用英文数据库作为参考（中英文数据库版本应该一致）
        guard let bundlePath = Bundle.main.path(forResource: "item_db_en", ofType: "sqlite") else {
            Logger.error("Bundle 中未找到 item_db_en.sqlite")
            return nil
        }

        return getSDEVersionFromDatabase(path: bundlePath)
    }

    /// 获取 Documents/sde 中数据库的版本信息
    private func getDocumentsSDEVersion() -> SDEVersion? {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let sdeDbPath = documentsPath.appendingPathComponent("sde/db/item_db_en.sqlite").path

        guard FileManager.default.fileExists(atPath: sdeDbPath) else {
            Logger.warning("Documents/sde 中未找到数据库文件")
            return nil
        }

        return getSDEVersionFromDatabase(path: sdeDbPath)
    }

    /// 从指定路径的数据库读取版本信息
    private func getSDEVersionFromDatabase(path: String) -> SDEVersion? {
        var db: OpaquePointer?

        // 打开数据库
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            Logger.error("无法打开数据库: \(path)")
            if let db = db {
                sqlite3_close(db)
            }
            return nil
        }

        defer {
            sqlite3_close(db)
        }

        // 准备查询语句
        let query = "SELECT build_number, patch_number FROM version_info WHERE id = 1"
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            Logger.error("无法准备查询语句")
            return nil
        }

        defer {
            sqlite3_finalize(statement)
        }

        // 执行查询并读取结果
        guard sqlite3_step(statement) == SQLITE_ROW else {
            Logger.error("version_info 表中没有数据")
            return nil
        }

        // 读取 build_number 和 patch_number
        let buildNumber = Int(sqlite3_column_int64(statement, 0))
        let patchNumber = Int(sqlite3_column_int64(statement, 1))

        return SDEVersion(buildNumber: buildNumber, patchNumber: patchNumber)
    }

    /// 清理本地 SDE 数据（删除 Documents/sde 目录）
    /// 此方法会在决定使用 Bundle 版本时调用，以节省存储空间
    private func cleanupLocalSDEData() {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let sdePath = documentsPath.appendingPathComponent("sde")

        // 检查目录是否存在
        guard fileManager.fileExists(atPath: sdePath.path) else {
            return // 目录不存在，无需清理
        }

        do {
            // 删除目录
            try fileManager.removeItem(at: sdePath)
            Logger.info("Bundle 版本较新，已删除本地旧 SDE 数据: \(sdePath.path)")
        } catch {
            Logger.error("删除本地 SDE 数据失败: \(error.localizedDescription)")
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
