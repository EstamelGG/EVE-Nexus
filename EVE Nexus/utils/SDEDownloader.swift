import CommonCrypto
import Foundation
import Zip

class SDEDownloader {
    // 获取下载目录
    func getDownloadDirectory() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let downloadDir = documentsPath.appendingPathComponent("SDEDownload")

        // 确保目录存在
        try? FileManager.default.createDirectory(at: downloadDir, withIntermediateDirectories: true)
        return downloadDir
    }

    // 清空下载目录
    func clearDownloadDirectory() throws {
        let downloadDir = getDownloadDirectory()
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: downloadDir.path) {
            Logger.info("清空下载目录: \(downloadDir.path)")
            try fileManager.removeItem(at: downloadDir)
        }
        try fileManager.createDirectory(at: downloadDir, withIntermediateDirectories: true)

        // 不清理 CloudKit 缓存 - CloudKit 需要在下载过程中使用缓存目录
        // 如果清理了缓存目录，CloudKit 下载完成后无处存放文件，会导致 "Moving downloaded asset failed"
    }

    /// 确保缓存目录存在
    ///
    /// CloudKit 和 MMCS 目录会由系统自动创建，我们只需要确保自己的缓存目录存在。
    /// 如果目录不存在，会自动创建。
    func ensureCacheDirectoriesExist() {
        let fileManager = FileManager.default

        guard let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            Logger.warning("无法获取 Caches 目录")
            return
        }

        // 只创建我们自己的缓存目录
        let sdeDownloadCache = cachesDir.appendingPathComponent("SDEDownloadCache")

        if !fileManager.fileExists(atPath: sdeDownloadCache.path) {
            do {
                try fileManager.createDirectory(at: sdeDownloadCache, withIntermediateDirectories: true)
                Logger.info(" SDEDownloadCache 目录已创建")
            } catch {
                Logger.error("创建 SDEDownloadCache 目录失败: \(error.localizedDescription)")
            }
        }

        // CloudKit 和 MMCS 目录由系统自动管理，无需我们创建
        Logger.info("缓存目录检查完成")
    }

    /// 清理特定容器的 Assets 目录中的文件
    ///
    /// 只删除文件，不删除目录结构。CloudKit 会在需要时自动重新创建。
    /// - Parameter containerIdentifier: 容器标识符（可选，如果不指定则清理所有容器）
    func clearContainerAssets(containerIdentifier: String? = nil) {
        let fileManager = FileManager.default

        guard let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            Logger.warning("[清理 Assets] 无法获取 Caches 目录")
            return
        }

        let cloudKitCacheDir = cachesDir.appendingPathComponent("CloudKit")

        guard fileManager.fileExists(atPath: cloudKitCacheDir.path) else {
            Logger.info("[清理 Assets] CloudKit 缓存目录不存在，无需清理")
            return
        }

        if let containerID = containerIdentifier {
            Logger.info("[清理 Assets] 准备清理容器 \(containerID) 的 Assets")
        } else {
            Logger.info("[清理 Assets] 准备清理所有容器的 Assets")
        }

        do {
            let containers = try fileManager.contentsOfDirectory(at: cloudKitCacheDir, includingPropertiesForKeys: [.isDirectoryKey])

            // 过滤掉系统文件
            let validContainers = containers.filter { !$0.lastPathComponent.hasPrefix(".") }

            var totalClearedFiles = 0
            var totalClearedSize: Int64 = 0

            for containerDir in validContainers {
                let assetsDir = containerDir.appendingPathComponent("Assets")

                if fileManager.fileExists(atPath: assetsDir.path) {
                    let assetFiles = try fileManager.contentsOfDirectory(at: assetsDir, includingPropertiesForKeys: [.fileSizeKey])

                    if !assetFiles.isEmpty {
                        for file in assetFiles {
                            let attributes = try? fileManager.attributesOfItem(atPath: file.path)
                            let size = attributes?[.size] as? Int64 ?? 0

                            do {
                                try fileManager.removeItem(at: file)
                                totalClearedFiles += 1
                                totalClearedSize += size
                                Logger.info("[清理 Assets] 已删除: \(file.lastPathComponent) (\(String(format: "%.2f", Double(size) / 1024 / 1024)) MB)")
                            } catch {
                                Logger.warning("[清理 Assets] 删除失败: \(file.lastPathComponent) - \(error.localizedDescription)")
                            }
                        }
                    }
                }
            }

            let totalSizeInMB = Double(totalClearedSize) / 1024 / 1024
            Logger.info("[清理 Assets] 清理完成: 共删除 \(totalClearedFiles) 个文件，释放 \(String(format: "%.2f", totalSizeInMB)) MB")

        } catch {
            Logger.warning("[清理 Assets] 清理失败: \(error.localizedDescription)")
        }
    }

    /// 列出 CloudKit Assets 目录中的文件（用于诊断）
    ///
    /// 这个方法会扫描 CloudKit 缓存目录，列出所有 Assets 子目录中的文件。
    /// - Parameter containerIdentifier: 可选的容器标识符，用于筛选特定容器
    func listCloudKitAssets(containerIdentifier: String? = nil) {
        let fileManager = FileManager.default

        guard let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            Logger.info("无法获取 Caches 目录")
            return
        }

        let cloudKitCacheDir = cachesDir.appendingPathComponent("CloudKit")

        // 检查 CloudKit 目录是否存在
        guard fileManager.fileExists(atPath: cloudKitCacheDir.path) else {
            Logger.info("CloudKit 缓存目录不存在")
            return
        }

        // 输出我们正在查找的容器 ID
        if let containerID = containerIdentifier {
            Logger.info("查找容器: \(containerID)")
        }

        do {
            let containers = try fileManager.contentsOfDirectory(at: cloudKitCacheDir, includingPropertiesForKeys: [.isDirectoryKey])

            // 过滤掉系统文件（如 .DS_Store）
            let validContainers = containers.filter { !$0.lastPathComponent.hasPrefix(".") }

            Logger.info("找到 \(validContainers.count) 个有效容器")

            for containerDir in validContainers {
                let containerName = containerDir.lastPathComponent

                let assetsDir = containerDir.appendingPathComponent("Assets")

                if fileManager.fileExists(atPath: assetsDir.path) {
                    let assetFiles = try fileManager.contentsOfDirectory(at: assetsDir, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey])

                    if assetFiles.isEmpty {
                        Logger.info("\(containerName)/Assets: 空目录")
                    } else {
                        Logger.info("\(containerName)/Assets: \(assetFiles.count) 个文件")

                        var totalSize: Int64 = 0
                        for file in assetFiles {
                            let attributes = try? fileManager.attributesOfItem(atPath: file.path)
                            let size = attributes?[.size] as? Int64 ?? 0
                            totalSize += size
                            let sizeInMB = Double(size) / 1024 / 1024

                            Logger.info("  - \(file.lastPathComponent): \(String(format: "%.2f", sizeInMB)) MB")
                        }

                        let totalSizeInMB = Double(totalSize) / 1024 / 1024
                        Logger.info("  总大小: \(String(format: "%.2f", totalSizeInMB)) MB")
                    }
                }
            }
        } catch {
            Logger.warning("扫描失败: \(error.localizedDescription)")
        }
    }

    // 验证icons.zip的SHA256
    func verifyIconsHash(expectedHash: String) async throws -> Bool {
        let localFile = getDownloadDirectory().appendingPathComponent("icons.zip")

        // 检查文件是否存在
        guard FileManager.default.fileExists(atPath: localFile.path) else {
            Logger.error("Icons.zip file not found at: \(localFile.path)")
            throw NSError(domain: "SDEDownloader", code: -1, userInfo: [NSLocalizedDescriptionKey: "Icons.zip file not found"])
        }

        // 检查文件大小
        let fileSize = try FileManager.default.attributesOfItem(atPath: localFile.path)[.size] as? Int64 ?? 0
        Logger.info("Icons.zip file size: \(fileSize) bytes")

        let localHash = try calculateSHA256(fileURL: localFile)
        Logger.info("Local icons.zip SHA256: \(localHash)")
        Logger.info("Expected icons.zip SHA256: \(expectedHash)")

        let isValid = localHash == expectedHash
        Logger.info("Icons.zip SHA256 verification: \(isValid ? "PASSED" : "FAILED")")

        return isValid
    }

    // 验证sde.zip的SHA256
    func verifySDEHash(expectedHash: String) async throws -> Bool {
        let localFile = getDownloadDirectory().appendingPathComponent("sde.zip")

        // 检查文件是否存在
        guard FileManager.default.fileExists(atPath: localFile.path) else {
            Logger.error("SDE.zip file not found at: \(localFile.path)")
            throw NSError(domain: "SDEDownloader", code: -1, userInfo: [NSLocalizedDescriptionKey: "SDE.zip file not found"])
        }

        // 检查文件大小
        let fileSize = try FileManager.default.attributesOfItem(atPath: localFile.path)[.size] as? Int64 ?? 0
        Logger.info("SDE.zip file size: \(fileSize) bytes")

        let localHash = try calculateSHA256(fileURL: localFile)
        Logger.info("Local sde.zip SHA256: \(localHash)")
        Logger.info("Expected sde.zip SHA256: \(expectedHash)")

        let isValid = localHash == expectedHash
        Logger.info("SDE.zip SHA256 verification: \(isValid ? "PASSED" : "FAILED")")

        if !isValid {
            Logger.error("SHA256 comparison failed:")
            Logger.error("Local:    '\(localHash)'")
            Logger.error("Expected: '\(expectedHash)'")
        }

        return isValid
    }

    // 计算文件SHA256
    private func calculateSHA256(fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))

        _ = data.withUnsafeBytes { buffer in
            CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &digest)
        }

        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // 解压SDE数据包
    func extractSDE(progressCallback: @escaping (Double) -> Void) async throws {
        let sdeZipFile = getDownloadDirectory().appendingPathComponent("sde.zip")
        let sdeDestination = getDocumentsDirectory().appendingPathComponent("sde")

        Logger.info("Starting SDE extraction from: \(sdeZipFile.path)")
        Logger.info("SDE extraction destination: \(sdeDestination.path)")

        // 检查源文件是否存在
        guard FileManager.default.fileExists(atPath: sdeZipFile.path) else {
            Logger.error("SDE.zip file not found for extraction: \(sdeZipFile.path)")
            throw NSError(domain: "SDEDownloader", code: -1, userInfo: [NSLocalizedDescriptionKey: "SDE.zip file not found for extraction"])
        }

        // 检查源文件大小
        let sourceFileSize = try FileManager.default.attributesOfItem(atPath: sdeZipFile.path)[.size] as? Int64 ?? 0
        Logger.info("SDE.zip source file size: \(sourceFileSize) bytes")

        // 清空现有 SDE 目录
        if FileManager.default.fileExists(atPath: sdeDestination.path) {
            Logger.info("Removing existing SDE directory: \(sdeDestination.path)")
            try FileManager.default.removeItem(at: sdeDestination)
        }

        // 创建新的 SDE 目录
        try FileManager.default.createDirectory(at: sdeDestination, withIntermediateDirectories: true)
        Logger.info("Created SDE destination directory: \(sdeDestination.path)")

        try await withCheckedThrowingContinuation { continuation in
            do {
                try Zip.unzipFile(sdeZipFile, destination: sdeDestination, overwrite: true, password: nil) { progress in
                    progressCallback(progress)
                }
                Logger.info("SDE extraction completed successfully")
                continuation.resume()
            } catch {
                Logger.error("SDE extraction failed: \(error)")
                continuation.resume(throwing: error)
            }
        }

        // 验证解压是否成功
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: sdeDestination.path),
           !contents.isEmpty
        {
            Logger.info("SDE extraction verification: SUCCESS - \(contents.count) files extracted")
            Logger.info("SDE extracted files: \(contents.prefix(10).joined(separator: ", "))")

            // 更新SDE版本信息到UserDefaults
            updateSDEVersionInfo()
        } else {
            Logger.error("SDE extraction verification: FAILED - directory is empty")
            throw NSError(domain: "SDEDownloader", code: -1, userInfo: [NSLocalizedDescriptionKey: "SDE extraction failed: directory is empty"])
        }
    }

    // 解压图标包
    func extractIcons(progressCallback: @escaping (Double) -> Void) async throws {
        let iconsZipFile = getDownloadDirectory().appendingPathComponent("icons.zip")
        let iconsDestination = getDocumentsDirectory().appendingPathComponent("icons")

        Logger.info("Starting Icons extraction from: \(iconsZipFile.path)")
        Logger.info("Icons extraction destination: \(iconsDestination.path)")

        // 检查源文件是否存在
        guard FileManager.default.fileExists(atPath: iconsZipFile.path) else {
            Logger.error("Icons.zip file not found for extraction: \(iconsZipFile.path)")
            throw NSError(domain: "SDEDownloader", code: -1, userInfo: [NSLocalizedDescriptionKey: "Icons.zip file not found for extraction"])
        }

        // 检查源文件大小
        let sourceFileSize = try FileManager.default.attributesOfItem(atPath: iconsZipFile.path)[.size] as? Int64 ?? 0
        Logger.info("Icons.zip source file size: \(sourceFileSize) bytes")

        // 清空现有图标目录
        if FileManager.default.fileExists(atPath: iconsDestination.path) {
            Logger.info("Removing existing Icons directory: \(iconsDestination.path)")
            try FileManager.default.removeItem(at: iconsDestination)
        }

        // 创建新的图标目录
        try FileManager.default.createDirectory(at: iconsDestination, withIntermediateDirectories: true)
        Logger.info("Created Icons destination directory: \(iconsDestination.path)")

        // 重置图标解压状态
        IconManager.shared.isExtractionComplete = false
        Logger.info("Reset IconManager extraction state")

        try await withCheckedThrowingContinuation { continuation in
            do {
                try Zip.unzipFile(iconsZipFile, destination: iconsDestination, overwrite: true, password: nil) { progress in
                    progressCallback(progress)
                }
                Logger.info("Icons extraction completed successfully")
                continuation.resume()
            } catch {
                Logger.error("Icons extraction failed: \(error)")
                continuation.resume(throwing: error)
            }
        }

        // 验证解压是否成功
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: iconsDestination.path),
           !contents.isEmpty
        {
            Logger.info("Icons extraction verification: SUCCESS - \(contents.count) files extracted")
            // 设置解压完成状态
            IconManager.shared.isExtractionComplete = true
        } else {
            Logger.error("Icons extraction verification: FAILED - directory is empty")
            throw NSError(domain: "SDEDownloader", code: -1, userInfo: [NSLocalizedDescriptionKey: "Icon extraction failed: directory is empty"])
        }
    }

    // 验证额外语言数据库 zip 的 SHA256
    func verifyExtraDBHash(zipURL: URL, expectedHash: String) throws -> Bool {
        guard FileManager.default.fileExists(atPath: zipURL.path) else {
            Logger.error("Extra DB zip not found: \(zipURL.path)")
            throw NSError(domain: "SDEDownloader", code: -1, userInfo: [NSLocalizedDescriptionKey: "Extra DB zip not found"])
        }

        let localHash = try calculateSHA256(fileURL: zipURL)
        Logger.info("Extra DB SHA256: local=\(localHash), expected=\(expectedHash)")
        return localHash == expectedHash
    }

    // 解压额外语言数据库
    func extractExtraDB(zipURL: URL, languageCode: String) throws {
        let tempDir = getDownloadDirectory().appendingPathComponent("temp_\(languageCode)")

        // 清理临时目录
        if FileManager.default.fileExists(atPath: tempDir.path) {
            try FileManager.default.removeItem(at: tempDir)
        }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // 解压到临时目录
        try Zip.unzipFile(zipURL, destination: tempDir, overwrite: true, password: nil)

        // 查找 sqlite 文件
        let expectedFileName = "item_db_\(languageCode).sqlite"
        let sqliteFileURL = try findFile(named: expectedFileName, in: tempDir)

        // 确保目标目录存在
        let destDir = getDocumentsDirectory().appendingPathComponent("sde/db")
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        let destPath = destDir.appendingPathComponent(expectedFileName)
        if FileManager.default.fileExists(atPath: destPath.path) {
            try FileManager.default.removeItem(at: destPath)
        }

        try FileManager.default.moveItem(at: sqliteFileURL, to: destPath)
        Logger.info("Extra DB installed: \(destPath.path)")

        // 清理临时目录
        try? FileManager.default.removeItem(at: tempDir)
    }

    // 在目录中递归查找指定名称的文件
    private func findFile(named fileName: String, in directory: URL) throws -> URL {
        let fileManager = FileManager.default
        if let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) {
            while let fileURL = enumerator.nextObject() as? URL {
                if fileURL.lastPathComponent == fileName {
                    return fileURL
                }
            }
        }
        throw NSError(domain: "SDEDownloader", code: -1, userInfo: [NSLocalizedDescriptionKey: "File \(fileName) not found in archive"])
    }

    // 获取Documents目录
    private func getDocumentsDirectory() -> URL {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // 更新SDE版本信息到UserDefaults
    private func updateSDEVersionInfo() {
        Logger.info(" SDE 数据已成功更新，新的数据库现在可用")

        // 清理下载的临时文件
        StaticResourceManager.shared.cleanupDownloadFiles()

        // 发送通知，让应用知道SDE数据已更新
        NotificationCenter.default.post(name: NSNotification.Name("SDEDataUpdated"), object: nil)
    }
}
