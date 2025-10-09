import Foundation

/// Metadata 管理器
/// 负责读取和管理 SDE/Icons 的 metadata 信息
class MetadataManager {
    static let shared = MetadataManager()

    private init() {}

    // MARK: - 读取 Metadata

    /// 从 Bundle 读取 metadata
    func readMetadataFromBundle() -> CloudKitMetadata? {
        Logger.info("开始从 Bundle 读取 metadata.json...")

        guard let url = Bundle.main.url(forResource: "metadata", withExtension: "json") else {
            Logger.error("Bundle 中未找到 metadata.json 文件")
            return nil
        }

        return readMetadata(from: url)
    }

    /// 从本地图标目录读取 metadata
    func readMetadataFromIconsDirectory() -> CloudKitMetadata? {
        Logger.info("开始从 Icons 目录读取 metadata.json...")

        let iconsDirectory = getIconsDirectory()
        let metadataURL = iconsDirectory.appendingPathComponent("metadata.json")

        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            Logger.warning("Icons 目录中未找到 metadata.json 文件")
            return nil
        }

        return readMetadata(from: metadataURL)
    }

    /// 从指定路径读取 metadata
    private func readMetadata(from url: URL) -> CloudKitMetadata? {
        do {
            let data = try Data(contentsOf: url)
            let metadata = try JSONDecoder().decode(CloudKitMetadata.self, from: data)

            Logger.info("成功读取 metadata:")
            Logger.info("  - 构建版本: \(metadata.buildNumber)")
            Logger.info("  - 补丁版本: \(metadata.patchNumber)")
            Logger.info("  - 图标版本: \(metadata.iconVersion)")
            Logger.info("  - 发布日期: \(metadata.releaseDate)")

            return metadata
        } catch {
            Logger.error("读取 metadata 失败: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - 保存 Metadata

    /// 保存 metadata 到图标目录
    func saveMetadataToIconsDirectory(_ metadata: CloudKitMetadata) throws {
        Logger.info("开始保存 metadata.json 到 Icons 目录...")

        let iconsDirectory = getIconsDirectory()
        let metadataURL = iconsDirectory.appendingPathComponent("metadata.json")

        // 确保目录存在
        try FileManager.default.createDirectory(at: iconsDirectory, withIntermediateDirectories: true)

        // 编码并保存
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(metadata)
        try data.write(to: metadataURL)

        Logger.info("metadata.json 已保存到: \(metadataURL.path)")
        Logger.info("  - 构建版本: \(metadata.buildNumber)")
        Logger.info("  - 补丁版本: \(metadata.patchNumber)")
        Logger.info("  - 图标版本: \(metadata.iconVersion)")
    }

    /// 从临时下载的文件复制 metadata 到图标目录
    func copyMetadataToIconsDirectory(from sourceURL: URL) throws {
        Logger.info("开始复制 metadata.json 到 Icons 目录...")

        // 先读取 metadata
        guard let metadata = readMetadata(from: sourceURL) else {
            throw NSError(domain: "MetadataManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法读取 metadata 文件"])
        }

        // 保存到图标目录
        try saveMetadataToIconsDirectory(metadata)
    }

    // MARK: - 版本比较

    /// 比较图标版本
    /// - Returns: true 表示远程版本更新
    func compareIconVersion(local: Int, remote: Int) -> Bool {
        Logger.info("比较图标版本: 本地 \(local) vs 远程 \(remote)")
        let hasUpdate = remote > local
        Logger.info("图标版本比较结果: \(hasUpdate ? "有更新" : "无更新")")
        return hasUpdate
    }

    /// 获取本地图标版本（优先从 Icons 目录，其次从 Bundle）
    func getLocalIconVersion() -> Int {
        // 优先读取已下载的版本
        if let metadata = readMetadataFromIconsDirectory() {
            Logger.info("使用 Icons 目录中的图标版本: \(metadata.iconVersion)")
            return metadata.iconVersion
        }

        // 否则读取 Bundle 中的版本
        if let metadata = readMetadataFromBundle() {
            Logger.info("使用 Bundle 中的图标版本: \(metadata.iconVersion)")
            return metadata.iconVersion
        }

        Logger.warning("未找到任何 metadata 文件，使用默认版本 0")
        return 0
    }

    // MARK: - 私有方法

    /// 获取图标目录
    private func getIconsDirectory() -> URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsDirectory.appendingPathComponent("icons")
    }
}
