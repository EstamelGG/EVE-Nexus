import CloudKit
import Foundation
import SwiftUI

// MARK: - 元数据结构

/// CloudKit metadata 文件的结构
struct CloudKitMetadata: Codable {
    let iconVersion: Int
    let iconSha256: String
    let buildNumber: Int
    let patchNumber: Int
    let releaseDate: String
    let sdeSha256: String

    enum CodingKeys: String, CodingKey {
        case iconVersion = "icon_version"
        case iconSha256 = "icon_sha256"
        case buildNumber = "build_number"
        case patchNumber = "patch_number"
        case releaseDate = "release_date"
        case sdeSha256 = "sde_sha256"
    }
}

/// SDE CloudKit 管理器
/// 负责从 CloudKit 获取 SDE 更新信息
@MainActor
class SDECloudKitManager: ObservableObject {
    static let shared = SDECloudKitManager()

    // MARK: - CloudKit 配置

    private let container: CKContainer
    private let database: CKDatabase

    // 记录类型
    private let sdeUpdateRecordType = "Tritanium_SDE"

    // MARK: - 初始化

    private init() {
        // 使用默认的 CloudKit 容器（从 entitlements 文件中读取）
        container = CKContainer.default()
        // 使用 Production 环境的公共数据库
        database = container.publicCloudDatabase
    }

    // MARK: - 公共方法
    
    /// 获取容器标识符
    func getContainerIdentifier() -> String? {
        return container.containerIdentifier
    }

    /// 获取最新的 SDE 更新信息（从 metadata 文件解析）
    func fetchLatestSDEUpdate() async throws -> SDEUpdateInfo {
        Logger.info("开始从 CloudKit 获取 SDE 更新信息（从 metadata 文件）...")
        Logger.info("CloudKit 容器 ID: \(container.containerIdentifier ?? "未知")")
        Logger.info("查询记录类型: \(sdeUpdateRecordType)")
        
        // [+] 确保缓存目录存在
        SDEDownloader().ensureCacheDirectoriesExist()

        do {
            // 获取最新记录的 RecordID
            let recordID = try await getLatestRecordID()

            // 下载 metadata 文件
            let metadataURL = try await fetchMetadataFile(recordID: recordID)

            // 解析 metadata JSON
            let metadata = try parseMetadataFile(at: metadataURL)
            
            // [+] 解析完成后立即删除 metadata 文件
            try? FileManager.default.removeItem(at: metadataURL)
            Logger.info("已删除 metadata 文件: \(metadataURL.lastPathComponent)")
            
            return try buildUpdateInfo(from: metadata)
            
        } catch {
            Logger.error("获取 SDE 更新信息失败: \(error)")
            throw error
        }
    }
    
    /// 构建更新信息对象
    private func buildUpdateInfo(from metadata: CloudKitMetadata) throws -> SDEUpdateInfo {

        Logger.info("成功解析 metadata 文件:")
        Logger.info("  - 构建版本: \(metadata.buildNumber)")
        Logger.info("  - 补丁版本: \(metadata.patchNumber)")
        Logger.info("  - 图标版本: \(metadata.iconVersion)")
        Logger.info("  - 图标 SHA256: \(String(metadata.iconSha256.prefix(16)))...")
        Logger.info("  - SDE SHA256: \(String(metadata.sdeSha256.prefix(16)))...")
        Logger.info("  - 发布日期: \(metadata.releaseDate)")

        // 直接创建 SDEUpdateInfo 对象
        let tag = "sde-build-\(metadata.buildNumber).\(metadata.patchNumber)"
        let sha256sum = [
            "icons.zip": metadata.iconSha256,
            "sde.zip": metadata.sdeSha256,
        ]

        let updateInfo = SDEUpdateInfo(
            tag: tag,
            sdeVersion: metadata.buildNumber,
            patchNumber: metadata.patchNumber,
            iconVersion: metadata.iconVersion,
            sha256sum: sha256sum,
            zipUrls: [:], // 不再需要 zipUrls
            updatedAt: metadata.releaseDate
        )

        Logger.info("成功从 CloudKit 获取 SDE 更新信息: 版本 \(updateInfo.sdeVersion).\(updateInfo.patchNumber), 标签: \(updateInfo.tag)")

        return updateInfo
    }

    /// 下载 Icons 文件（支持进度回调）
    /// - Parameter progressHandler: 进度回调 (0.0 ~ 1.0)
    /// - Returns: 本地文件 URL
    func fetchIconsFile(progressHandler: @escaping (Double) -> Void) async throws -> URL {
        Logger.info("开始获取 Icons 文件...")

        // 获取最新记录的 RecordID
        let recordID = try await getLatestRecordID()

        // 使用 CKFetchRecordsOperation 下载指定字段
        return try await fetchSingleAsset(
            recordID: recordID,
            assetFieldName: "icons_file",
            progressHandler: progressHandler
        )
    }

    /// 下载 SDE 文件（支持进度回调）
    /// - Parameter progressHandler: 进度回调 (0.0 ~ 1.0)
    /// - Returns: 本地文件 URL
    func fetchSDEFile(progressHandler: @escaping (Double) -> Void) async throws -> URL {
        Logger.info("开始获取 SDE 文件...")

        // 获取最新记录的 RecordID
        let recordID = try await getLatestRecordID()

        // 使用 CKFetchRecordsOperation 下载指定字段
        return try await fetchSingleAsset(
            recordID: recordID,
            assetFieldName: "sde_file",
            progressHandler: progressHandler
        )
    }

    /// 下载 metadata 文件用于保存
    /// - Returns: 本地文件 URL
    func fetchMetadataFileForSaving() async throws -> URL {
        Logger.info("开始获取 metadata 文件用于保存...")

        // 获取最新记录的 RecordID
        let recordID = try await getLatestRecordID()

        // 下载 metadata 文件
        return try await fetchMetadataFile(recordID: recordID)
    }

    /// 获取最新记录的 RecordID
    private func getLatestRecordID() async throws -> CKRecord.ID {
        Logger.info("查询最新记录的 ID...")

        let query = CKQuery(recordType: sdeUpdateRecordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let operation = CKQueryOperation(query: query)
        operation.desiredKeys = [] // 不需要任何字段，只要 RecordID
        operation.resultsLimit = 1

        let recordID = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKRecord.ID, Error>) in
            var resultRecordID: CKRecord.ID?
            var hasResumed = false

            operation.recordMatchedBlock = { (_: CKRecord.ID, result: Result<CKRecord, Error>) in
                switch result {
                case let .success(record):
                    resultRecordID = record.recordID
                case let .failure(error):
                    if !hasResumed {
                        hasResumed = true
                        continuation.resume(throwing: error)
                    }
                    return
                }
            }

            operation.queryResultBlock = { (result: Result<CKQueryOperation.Cursor?, Error>) in
                guard !hasResumed else { return }
                hasResumed = true

                switch result {
                case .success:
                    if let recordID = resultRecordID {
                        continuation.resume(returning: recordID)
                    } else {
                        continuation.resume(throwing: SDECloudKitError.noRecordsFound)
                    }
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }

            database.add(operation)
        }

        Logger.info("找到最新记录 ID: \(recordID.recordName)")
        return recordID
    }

    /// 下载 metadata 文件
    private func fetchMetadataFile(recordID: CKRecord.ID) async throws -> URL {
        Logger.info("开始下载 metadata 文件...")

        return try await fetchSingleAsset(
            recordID: recordID,
            assetFieldName: "metadata",
            progressHandler: { _ in
                // metadata 文件很小，不需要显示进度
            }
        )
    }

    /// 解析 metadata JSON 文件
    private func parseMetadataFile(at url: URL) throws -> CloudKitMetadata {
        Logger.info("开始解析 metadata 文件: \(url.path)")

        do {
            let data = try Data(contentsOf: url)
            let metadata = try JSONDecoder().decode(CloudKitMetadata.self, from: data)

            Logger.info("metadata 文件解析成功")
            return metadata
        } catch {
            Logger.error("metadata 文件解析失败: \(error.localizedDescription)")
            throw SDECloudKitError.metadataParseError(error)
        }
    }

    /// 下载单个 Asset 字段
    private func fetchSingleAsset(
        recordID: CKRecord.ID,
        assetFieldName: String,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> URL {
        Logger.info("开始下载 Asset 字段: \(assetFieldName)")

        let operation = CKFetchRecordsOperation(recordIDs: [recordID])
        operation.desiredKeys = [assetFieldName] // 只获取指定的 Asset 字段

        // 进度回调
        operation.perRecordProgressBlock = { _, progress in
            Task { @MainActor in
                progressHandler(progress)
                Logger.info("[\(assetFieldName)] 下载进度: \(Int(progress * 100))%")
            }
        }

        let asset = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKAsset, Error>) in
            var hasResumed = false

            operation.perRecordResultBlock = { _, result in
                guard !hasResumed else { return }

                switch result {
                case let .success(record):
                    if let asset = record[assetFieldName] as? CKAsset {
                        hasResumed = true
                        continuation.resume(returning: asset)
                    } else {
                        hasResumed = true
                        continuation.resume(throwing: SDECloudKitError.invalidRecordFormat)
                    }
                case let .failure(error):
                    hasResumed = true
                    continuation.resume(throwing: error)
                }
            }

            database.add(operation)
        }

        guard let fileURL = asset.fileURL else {
            Logger.error("Asset 没有文件 URL")
            throw SDECloudKitError.invalidRecordFormat
        }

        let fileSize = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64 ?? 0
        let formattedSize = FormatUtil.formatFileSize(fileSize ?? 0)
        Logger.info("[\(assetFieldName)] 下载完成，文件大小: \(formattedSize)")

        return fileURL
    }

    // MARK: - 私有方法
}

// MARK: - 错误类型

enum SDECloudKitError: LocalizedError {
    case noRecordsFound
    case invalidRecordFormat
    case metadataParseError(Error)
    case cloudKitError(Error)

    var errorDescription: String? {
        switch self {
        case .noRecordsFound:
            return "未找到 SDE 更新记录"
        case .invalidRecordFormat:
            return "SDE 更新记录格式无效"
        case let .metadataParseError(error):
            return "metadata 文件解析失败: \(error.localizedDescription)"
        case let .cloudKitError(error):
            return "CloudKit 错误: \(error.localizedDescription)"
        }
    }
}
