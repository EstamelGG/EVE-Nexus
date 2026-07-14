import Foundation
import SQLite3
import Zip

/// 物品描述文本仓库：与当前生效的 SDE sqlite 同版本、同生命周期
final class ItemTextStore {
    static let shared = ItemTextStore()

    private let fileManager = FileManager.default
    private let defaults = UserDefaults.standard
    private let versionKey = "ItemTextsExtractedVersion"
    private let lock = NSLock()
    private var texts: [String: String] = [:]
    private var activeJSONURL: URL?
    private(set) var isLoaded = false

    private init() {}

    /// Documents SDE 配套描述：随 `Documents/sde/` 一起被清理/替换
    private var documentsTextsDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("sde/texts", isDirectory: true)
    }

    /// Bundle SDE 时的解压缓存（Bundle 只读）
    private var bundleTextsCacheDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("item_texts", isDirectory: true)
    }

    // MARK: - Sync with SDE

    /// 按当前生效的 SDE 数据源同步描述文本（应在 SDE 路径决策之后调用）
    func syncWithActiveSDE() {
        do {
            try syncFromDocumentsSDE()
            activeJSONURL = documentsTextsDirectory.appendingPathComponent("texts.json")
            reloadFromDisk()
        } catch {
            Logger.error("同步物品描述失败: \(error)")
        }
    }

    /// SDE 被清理/重置后调用：丢弃内存与 Bundle 侧缓存
    func invalidateAfterSDECleanup() {
        lock.lock()
        texts.removeAll()
        isLoaded = false
        activeJSONURL = nil
        lock.unlock()
        defaults.removeObject(forKey: versionKey)
        try? fileManager.removeItem(at: bundleTextsCacheDirectory)
        Logger.info("已随 SDE 清理失效物品描述缓存")
    }

    /// CloudKit / 本地解压 SDE 后：安装包内 texts.zip 到 Documents/sde/texts
    func installFromSDEPackage(textsZipURL: URL) throws {
        try extract(zipURL: textsZipURL, to: documentsTextsDirectory)
        markVersion(sdeVersionMarker(preferDocuments: true))
        activeJSONURL = documentsTextsDirectory.appendingPathComponent("texts.json")
        try? fileManager.removeItem(at: bundleTextsCacheDirectory)
        reloadFromDisk()
        Logger.info("已安装与 Documents SDE 配套的 texts.zip")
    }

    // MARK: - Private sync

    private func syncFromDocumentsSDE() throws {
        let expected = sdeVersionMarker(preferDocuments: true)
        let dest = documentsTextsDirectory
        let jsonURL = dest.appendingPathComponent("texts.json")
        let zipInPlace = dest.deletingLastPathComponent().appendingPathComponent("texts.zip")

        if fileManager.fileExists(atPath: jsonURL.path),
           defaults.string(forKey: versionKey) == expected
        {
            Logger.info("Documents 描述已与 SDE \(expected) 对齐")
            try? fileManager.removeItem(at: bundleTextsCacheDirectory)
            return
        }

        if fileManager.fileExists(atPath: zipInPlace.path) {
            try extract(zipURL: zipInPlace, to: dest)
            try? fileManager.removeItem(at: zipInPlace)
            markVersion(expected)
        } else if fileManager.fileExists(atPath: jsonURL.path) {
            markVersion(expected)
        } else if let zipURL = BundleSDEResources.url(forResource: "texts", withExtension: "zip") {
            Logger.warning("Documents/sde 缺少 texts，临时回退 Bundle texts.zip")
            try extract(zipURL: zipURL, to: dest)
            markVersion(expected)
        } else {
            throw TextStoreError.zipNotFound
        }

        try? fileManager.removeItem(at: bundleTextsCacheDirectory)
        Logger.info("Documents 描述已同步到 SDE \(expected)")
    }

    private func extract(zipURL: URL, to dest: URL) throws {
        if fileManager.fileExists(atPath: dest.path) {
            try fileManager.removeItem(at: dest)
        }
        try fileManager.createDirectory(at: dest, withIntermediateDirectories: true)

        try Zip.unzipFile(zipURL, destination: dest, overwrite: true, password: nil, progress: nil)

        let jsonURL = dest.appendingPathComponent("texts.json")
        if !fileManager.fileExists(atPath: jsonURL.path) {
            guard let nested = findTextsJSON(in: dest) else {
                throw TextStoreError.jsonNotFound
            }
            if nested != jsonURL {
                try? fileManager.removeItem(at: jsonURL)
                try fileManager.moveItem(at: nested, to: jsonURL)
            }
        }

        lock.lock()
        texts.removeAll()
        isLoaded = false
        lock.unlock()
    }

    private func findTextsJSON(in directory: URL) -> URL? {
        let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            if url.lastPathComponent == "texts.json" {
                return url
            }
        }
        return nil
    }

    private func markVersion(_ version: String) {
        defaults.set(version, forKey: versionKey)
    }

    private func sdeVersionMarker(preferDocuments: Bool) -> String {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let documentsDB = docs.appendingPathComponent("sde/db/item_db.sqlite").path
        let legacyDB = docs.appendingPathComponent("sde/db/item_db_en.sqlite").path

        if preferDocuments {
            if let v = versionFromDB(path: documentsDB) ?? versionFromDB(path: legacyDB) {
                return v
            }
        }

        if let meta = MetadataManager.shared.readMetadataFromBundle() {
            return "\(meta.buildNumber).\(meta.patchNumber)"
        }
        return "unknown"
    }

    private func versionFromDB(path: String) -> String? {
        guard fileManager.fileExists(atPath: path) else { return nil }

        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            return nil
        }
        defer { sqlite3_close(db) }

        let sql = "SELECT build_number, patch_number FROM version_info WHERE id = 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return "\(sqlite3_column_int64(stmt, 0)).\(sqlite3_column_int64(stmt, 1))"
    }

    // MARK: - Load / query

    private func reloadFromDisk() {
        lock.lock()
        defer { lock.unlock() }

        guard let url = activeJSONURL else {
            texts.removeAll()
            isLoaded = false
            return
        }

        guard fileManager.fileExists(atPath: url.path) else {
            Logger.error("texts.json 不存在: \(url.path)")
            texts.removeAll()
            isLoaded = false
            return
        }

        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            let decoded = try JSONDecoder().decode([String: String].self, from: data)
            texts = decoded
            isLoaded = true
            Logger.info("已加载物品描述 \(decoded.count) 条 ← \(url.path)")
        } catch {
            Logger.error("加载 texts.json 失败: \(error)")
            texts.removeAll()
            isLoaded = false
        }
    }

    func text(for descID: String?) -> String {
        guard let descID, !descID.isEmpty else { return "" }
        lock.lock()
        let needsSync = !isLoaded
        lock.unlock()
        if needsSync {
            syncWithActiveSDE()
        }
        lock.lock()
        defer { lock.unlock() }
        return texts[descID] ?? ""
    }

    enum TextStoreError: LocalizedError {
        case zipNotFound
        case jsonNotFound

        var errorDescription: String? {
            switch self {
            case .zipNotFound: return "Bundle 中未找到 texts.zip"
            case .jsonNotFound: return "解压后未找到 texts.json"
            }
        }
    }
}
