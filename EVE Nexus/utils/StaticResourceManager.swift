import Foundation
import SQLite3

/// 静态资源管理器 - 统一管理SDE数据的加载路径
class StaticResourceManager {
    static let shared = StaticResourceManager()
    private let fileManager = FileManager.default
    private init() {}

    // MARK: - 路径管理

    /// 获取数据库文件路径
    /// - Parameter name: 数据库名称（如 "item_db"）
    /// - Returns: 数据库文件路径；运行时只使用 Documents/sde（由 Bundle sde.zip 播种或 OTA 更新）
    func getDatabasePath(name: String) -> String? {
        // 兼容旧调用：item_db_en / item_db_zh 等均映射到单库 item_db
        let resolvedName = name.hasPrefix("item_db") ? "item_db" : name

        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let sdeDbPath = documentsPath.appendingPathComponent("sde/db/\(resolvedName).sqlite").path

        if fileManager.fileExists(atPath: sdeDbPath) {
            Logger.info("Using SDE database from Documents: \(sdeDbPath)")
            return sdeDbPath
        }

        // 兼容旧 Documents 文件名
        if resolvedName == "item_db" {
            let legacy = documentsPath.appendingPathComponent("sde/db/item_db_en.sqlite").path
            if fileManager.fileExists(atPath: legacy) {
                Logger.info("Using legacy Documents database: \(legacy)")
                return legacy
            }
        }

        Logger.error("Database file not found: \(resolvedName).sqlite (Documents/sde/db)")
        return nil
    }

    /// 获取本地化文件路径
    /// - Parameter filename: 文件名（如 "accountingentrytypes_localized"）
    /// - Returns: 本地化文件路径
    func getLocalizationPath(filename: String) -> String? {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let sdeLocalizationPath = documentsPath.appendingPathComponent("sde/localization/\(filename).json").path

        if fileManager.fileExists(atPath: sdeLocalizationPath) {
            Logger.info("Using SDE localization file from Documents: \(sdeLocalizationPath)")
            return sdeLocalizationPath
        }

        if let bundlePath = Bundle.main.path(forResource: filename, ofType: "json") {
            Logger.info("Using SDE localization file from Bundle: \(bundlePath)")
            return bundlePath
        }

        Logger.error("Localization file not found: \(filename).json")
        return nil
    }

    /// 获取地图数据文件路径
    func getMapDataPath(filename: String) -> String? {
        getMapDataURL(filename: filename)?.path
    }

    /// 获取地图数据文件URL
    func getMapDataURL(filename: String) -> URL? {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let sdeMapsPath = documentsPath.appendingPathComponent("sde/maps/\(filename).json")

        if fileManager.fileExists(atPath: sdeMapsPath.path) {
            Logger.info("Using SDE map data from Documents: \(sdeMapsPath.path)")
            return sdeMapsPath
        }

        if let bundleURL = Bundle.main.url(forResource: filename, withExtension: "json") {
            Logger.info("Using SDE map data from Bundle: \(bundleURL.path)")
            return bundleURL
        }

        Logger.error("Map data file not found: \(filename).json")
        return nil
    }

    // MARK: - 数据源状态检查

    /// Documents/sde 是否完整可用（库存在且能读出版本，核心资源与 icons 齐全）
    func isDocumentsSDEHealthy() -> Bool {
        Logger.info("[SDE初始化] 开始检查 Documents SDE 完整性")

        guard let dbPath = documentsDatabasePath() else {
            let expectedPath = LocalSDELayout.root.appendingPathComponent("db/item_db.sqlite").path
            Logger.warning("[SDE初始化] 未找到数据库: \(expectedPath)")
            return false
        }
        Logger.info("[SDE初始化] 数据库存在: \(dbPath)")

        guard let version = getSDEVersionFromDatabase(path: dbPath) else {
            Logger.warning("[SDE初始化] 数据库无法读取 version_info，判定损坏: \(dbPath)")
            return false
        }
        Logger.info("[SDE初始化] 本地数据库版本: build=\(version.buildNumber), patch=\(version.patchNumber)")

        let maps = LocalSDELayout.root.appendingPathComponent("maps/systems_data.json")
        guard fileManager.fileExists(atPath: maps.path) else {
            Logger.warning("[SDE初始化] 缺少地图数据，判定不完整: \(maps.path)")
            return false
        }
        Logger.info("[SDE初始化] 地图数据存在: \(maps.path)")

        let icons = LocalSDELayout.iconsDirectory
        let iconContents = (try? fileManager.contentsOfDirectory(atPath: icons.path)) ?? []
        Logger.info(
            "[SDE初始化] 图标目录: \(icons.path), 文件数=\(iconContents.count), extractionComplete=\(IconManager.shared.isExtractionComplete)"
        )
        guard !iconContents.isEmpty else {
            Logger.warning("[SDE初始化] Documents/sde/icons 为空，判定不完整")
            return false
        }

        Logger.info("[SDE初始化] Documents SDE 健康检查通过")
        return true
    }

    /// Documents 版本是否与 Bundle 种子相同（关于页「内置」标记；OTA 更高时为 false）
    func shouldUseBundleSDE() -> Bool {
        guard let bundle = getBundleSDEVersion(),
              let local = getDocumentsSDEVersion()
        else { return false }
        return bundle.buildNumber == local.buildNumber
            && bundle.patchNumber == local.patchNumber
    }

    /// 若 Documents 缺失/损坏或 Bundle 种子更新（版本号或 SHA256 变更），需要从 Bundle 完整重播
    func needsSeedSDEExtraction() -> Bool {
        if !isDocumentsSDEHealthy() {
            Logger.info("[SDE初始化] Documents SDE 缺失或不健康，需要从 Bundle 播种")
            return true
        }

        var checkLog = SDECheckLog(title: "[SDE初始化] 版本检查")
        let bundleMeta = MetadataManager.shared.readMetadataFromBundle()
        let localMeta = MetadataManager.shared.readLocalMetadata()

        if let bundleMeta {
            checkLog.append("Bundle metadata: \(bundleMeta.debugSummary)")
        }
        if let localMeta {
            checkLog.append("本地 metadata: \(localMeta.debugSummary)")
        } else {
            checkLog.append("本地 metadata: <missing>，无法执行 SHA256 兜底比较")
        }

        guard let bundleMeta else {
            checkLog.append("结果: 无法读取 Bundle metadata，跳过种子版本比较")
            checkLog.emit(isWarning: true)
            return false
        }
        let bundleVersion = SDEVersion(metadata: bundleMeta)

        guard let localVersion = getDocumentsSDEVersion() else {
            checkLog.append("结果: 无法读取本地数据库版本，需要从 Bundle 播种")
            checkLog.emit(isWarning: true)
            return true
        }

        checkLog.append(
            "数据库版本: Bundle build=\(bundleVersion.buildNumber), patch=\(bundleVersion.patchNumber); "
                + "Local build=\(localVersion.buildNumber), patch=\(localVersion.patchNumber)"
        )

        if bundleVersion.buildNumber > localVersion.buildNumber {
            checkLog.append("结果: Bundle build 更高，需要从 Bundle 播种")
            checkLog.emit()
            return true
        }

        if bundleVersion.buildNumber == localVersion.buildNumber,
           bundleVersion.patchNumber > localVersion.patchNumber
        {
            checkLog.append("结果: Bundle patch 更高，需要从 Bundle 播种")
            checkLog.emit()
            return true
        }

        // SHA256 仅用于检测相同 build/patch 下的 Bundle 内容变更。
        // 本地版本高于 Bundle 时，OTA 与 Bundle 的 SHA 必然不同，不能因此降级重播。
        guard bundleVersion.buildNumber == localVersion.buildNumber,
              bundleVersion.patchNumber == localVersion.patchNumber
        else {
            checkLog.append("结果: Bundle 版本不高于本地且版本号不同，跳过 sde_sha256 比较，无需完整播种")
            checkLog.emit()
            return false
        }

        if let localMeta {
            if bundleMeta.sdeSha256.isEmpty {
                checkLog.append("结果: Bundle metadata 缺少 sde_sha256，跳过 SHA256 比较")
                checkLog.emit(isWarning: true)
                return false
            }
            if bundleMeta.sdeSha256 != localMeta.sdeSha256 {
                checkLog.append(
                    "结果: 相同版本但 sde_sha256 不同: Bundle=\(bundleMeta.sdeSha256Short), "
                        + "Local=\(localMeta.sdeSha256Short)，需要从 Bundle 播种"
                )
                checkLog.emit()
                return true
            }
            checkLog.append("SHA256: 相同版本且 sde_sha256 一致")
        }

        checkLog.append("结果: Bundle SDE 未比本地更新，无需完整播种")
        checkLog.emit()
        return false
    }

    private func documentsDatabasePath() -> String? {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let candidates = [
            documentsPath.appendingPathComponent("sde/db/item_db.sqlite").path,
            documentsPath.appendingPathComponent("sde/db/item_db_en.sqlite").path,
        ]
        return candidates.first { fileManager.fileExists(atPath: $0) }
    }

    /// SDE 版本信息结构
    private struct SDEVersion {
        let buildNumber: Int
        let patchNumber: Int

        init(buildNumber: Int, patchNumber: Int) {
            self.buildNumber = buildNumber
            self.patchNumber = patchNumber
        }

        init(metadata: CloudKitMetadata) {
            buildNumber = metadata.buildNumber
            patchNumber = metadata.patchNumber
        }
    }

    /// Bundle 种子版本来自 metadata.json
    private func getBundleSDEVersion() -> SDEVersion? {
        guard let meta = MetadataManager.shared.readMetadataFromBundle() else {
            Logger.error("Bundle 中未找到 metadata.json")
            return nil
        }
        return SDEVersion(metadata: meta)
    }

    /// 获取 Documents/sde 中数据库的版本信息
    private func getDocumentsSDEVersion() -> SDEVersion? {
        guard let sdeDbPath = documentsDatabasePath() else {
            Logger.warning("Documents/sde 中未找到数据库文件")
            return nil
        }
        return getSDEVersionFromDatabase(path: sdeDbPath)
    }

    /// 从指定路径的数据库读取版本信息
    private func getSDEVersionFromDatabase(path: String) -> SDEVersion? {
        var db: OpaquePointer?

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

        let query = "SELECT build_number, patch_number FROM version_info WHERE id = 1"
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            Logger.error("无法准备查询语句")
            return nil
        }

        defer {
            sqlite3_finalize(statement)
        }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            Logger.error("version_info 表中没有数据")
            return nil
        }

        let buildNumber = Int(sqlite3_column_int64(statement, 0))
        let patchNumber = Int(sqlite3_column_int64(statement, 1))

        return SDEVersion(buildNumber: buildNumber, patchNumber: patchNumber)
    }

    /// 获取静态资源目录路径
    func getStaticDataSetPath() -> URL {
        let paths = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let staticPath = paths[0].appendingPathComponent("StaticDataSet")

        if !fileManager.fileExists(atPath: staticPath.path) {
            try? fileManager.createDirectory(
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

    /// 重置为待重新播种状态（删除 Documents/sde，下次从 Bundle sde.zip 解压）
    func resetSDEDatabase() throws {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let sdePath = documentsPath.appendingPathComponent("sde")

        if fileManager.fileExists(atPath: sdePath.path) {
            try fileManager.removeItem(at: sdePath)
            Logger.info("Removed local SDE directory: \(sdePath.path)")
        }
        ItemTextStore.shared.invalidateAfterSDECleanup()

        NotificationCenter.default.post(name: NSNotification.Name("SDEDataReset"), object: nil)
    }
}
