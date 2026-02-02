import CloudKit
import Foundation
import SwiftUI

// MARK: - 元数据结构

/// 额外语言数据库信息
struct ExtraDBInfo: Codable, Equatable {
    let file: String
    let sha256: String
}

/// CloudKit metadata 文件的结构
struct CloudKitMetadata: Codable {
    let iconVersion: Int
    let iconSha256: String
    let buildNumber: Int
    let patchNumber: Int
    let releaseDate: String
    let sdeSha256: String
    let extraDB: [String: ExtraDBInfo]?

    enum CodingKeys: String, CodingKey {
        case iconVersion = "icon_version"
        case iconSha256 = "icon_sha256"
        case buildNumber = "build_number"
        case patchNumber = "patch_number"
        case releaseDate = "release_date"
        case sdeSha256 = "sde_sha256"
        case extraDB = "extra_db"
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

    // 记录类型（从 Info.plist 读取）
    private var sdeUpdateRecordType: String {
        return AppConfiguration.SDE.recordType
    }

    // 当前 App 要求的最低版本（从 Info.plist 读取）
    private var minimumAppVersion: String {
        return AppConfiguration.SDE.minimumAppVersion
    }

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

    /// 获取最新的 SDE 更新信息（优先使用 metadata_json 字段，降级到 metadata asset）
    func fetchLatestSDEUpdate() async throws -> SDEUpdateInfo? {
        Logger.info("开始从 CloudKit 获取 SDE 更新信息...")
        Logger.info("CloudKit 容器 ID: \(container.containerIdentifier ?? "未知")")
        Logger.info("查询记录类型: \(sdeUpdateRecordType)")

        //  确保缓存目录存在
        SDEDownloader().ensureCacheDirectoriesExist()

        // 获取最新记录的 RecordID（可能返回 nil，表示没有兼容的版本）
        guard let recordID = try await getLatestRecordID() else {
            return nil
        }

        // 尝试从 metadata_json 字段获取（优先）
        if let metadata = try? await fetchMetadataFromJSONField(recordID: recordID) {
            Logger.info(" 成功从 metadata_json 字段获取元数据")
            var updateInfo = try buildUpdateInfo(from: metadata)
            updateInfo.recordID = recordID // 保存 recordID 供后续使用
            return updateInfo
        }

        // 降级：从 metadata asset 文件获取
        Logger.info("metadata_json 字段不可用，尝试从 metadata asset 文件获取...")
        do {
            let metadataURL = try await fetchMetadataFile(recordID: recordID)
            let metadata = try parseMetadataFile(at: metadataURL)

            // 解析完成后立即删除 metadata 文件
            try? FileManager.default.removeItem(at: metadataURL)
            Logger.info("已删除 metadata 文件: \(metadataURL.lastPathComponent)")

            var updateInfo = try buildUpdateInfo(from: metadata)
            updateInfo.recordID = recordID // 保存 recordID 供后续使用
            return updateInfo
        } catch {
            Logger.error("无法从 metadata asset 获取元数据: \(error)")
            throw SDECloudKitError.metadataUnavailable
        }
    }

    /// 构建更新信息对象
    private func buildUpdateInfo(from metadata: CloudKitMetadata) throws -> SDEUpdateInfo {
        Logger.success("成功解析 metadata 文件:")
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
            zipUrls: [:],
            updatedAt: metadata.releaseDate,
            extraDB: metadata.extraDB
        )

        Logger.success("成功从 CloudKit 获取 SDE 更新信息: 版本 \(updateInfo.sdeVersion).\(updateInfo.patchNumber), 标签: \(updateInfo.tag)")

        return updateInfo
    }

    /// 下载 Icons 文件（支持进度回调）
    /// - Parameters:
    ///   - recordID: 要下载的 RecordID（必选）
    ///   - progressHandler: 进度回调 (0.0 ~ 1.0)
    /// - Returns: 本地文件 URL
    func fetchIconsFile(recordID: CKRecord.ID, progressHandler: @escaping (Double) -> Void) async throws -> URL {
        Logger.info("开始获取 Icons 文件...")

        // 使用 CKFetchRecordsOperation 下载指定字段
        return try await fetchSingleAsset(
            recordID: recordID,
            assetFieldName: "icons_file",
            progressHandler: progressHandler
        )
    }

    /// 下载 SDE 文件（支持进度回调）
    /// - Parameters:
    ///   - recordID: 要下载的 RecordID（必选）
    ///   - progressHandler: 进度回调 (0.0 ~ 1.0)
    /// - Returns: 本地文件 URL
    func fetchSDEFile(recordID: CKRecord.ID, progressHandler: @escaping (Double) -> Void) async throws -> URL {
        Logger.info("开始获取 SDE 文件...")

        // 使用 CKFetchRecordsOperation 下载指定字段
        return try await fetchSingleAsset(
            recordID: recordID,
            assetFieldName: "sde_file",
            progressHandler: progressHandler
        )
    }

    /// 下载 metadata 文件用于保存
    /// - Parameter recordID: 要下载的 RecordID（必选）
    /// - Returns: 本地文件 URL
    func fetchMetadataFileForSaving(recordID: CKRecord.ID) async throws -> URL {
        Logger.info("开始获取 metadata 文件用于保存...")

        // 下载 metadata 文件
        return try await fetchMetadataFile(recordID: recordID)
    }

    /// 获取最新记录的 RecordID（使用 CloudKit 查询过滤）
    /// - Returns: 兼容的 RecordID，如果没有兼容记录则返回 nil
    private func getLatestRecordID() async throws -> CKRecord.ID? {
        Logger.info("查询最新兼容记录的 ID...")
        Logger.info("查询条件: minimum_app_version = \(minimumAppVersion)")
        Logger.info("记录类型: \(sdeUpdateRecordType)")

        // 创建查询：只查找 minimum_app_version 等于配置值的记录
        let predicate = NSPredicate(format: "minimum_app_version == %@", minimumAppVersion)
        let query = CKQuery(recordType: sdeUpdateRecordType, predicate: predicate)

        // 按 sde_version 字段降序排列（最大的在前）
        query.sortDescriptors = [NSSortDescriptor(key: "sde_version", ascending: false)]

        let operation = CKQueryOperation(query: query)
        operation.desiredKeys = ["sde_version", "minimum_app_version"]
        operation.resultsLimit = 1 // 只需要最新的一条

        let recordID = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKRecord.ID?, Error>) in
            var resultRecordID: CKRecord.ID?
            var hasResumed = false

            operation.recordMatchedBlock = { (_: CKRecord.ID, result: Result<CKRecord, Error>) in
                switch result {
                case let .success(record):
                    resultRecordID = record.recordID
                    if let sdeVersion = record["sde_version"] as? Double {
                        Logger.info("找到兼容记录: \(record.recordID.recordName), sde_version = \(sdeVersion)")
                    }
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
                    continuation.resume(returning: resultRecordID)
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }

            database.add(operation)
        }

        if let recordID = recordID {
            Logger.info("选择最新兼容记录: \(recordID.recordName)")
        } else {
            Logger.info("没有找到 minimum_app_version = \(minimumAppVersion) 的记录")
        }

        return recordID
    }

    /// 从 metadata_json 字段获取元数据（轻量级字符串字段）
    private func fetchMetadataFromJSONField(recordID: CKRecord.ID) async throws -> CloudKitMetadata? {
        Logger.info("尝试从 metadata_json 字段获取元数据...")

        let operation = CKFetchRecordsOperation(recordIDs: [recordID])
        operation.desiredKeys = ["metadata_json"]

        let record = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKRecord, Error>) in
            var hasResumed = false

            operation.perRecordResultBlock = { _, result in
                guard !hasResumed else { return }
                hasResumed = true

                switch result {
                case let .success(record):
                    continuation.resume(returning: record)
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }

            database.add(operation)
        }

        // 尝试获取 metadata_json 字段
        guard let jsonString = record["metadata_json"] as? String, !jsonString.isEmpty else {
            Logger.warning("metadata_json 字段不存在或为空")
            return nil
        }

        Logger.info("获取到 metadata_json 字段，长度: \(jsonString.count) 字符")

        // 解析 JSON 字符串
        guard let jsonData = jsonString.data(using: .utf8) else {
            Logger.error("无法将 metadata_json 转换为 Data")
            return nil
        }

        do {
            let metadata = try JSONDecoder().decode(CloudKitMetadata.self, from: jsonData)
            Logger.success("成功解析 metadata_json 字段")
            return metadata
        } catch let DecodingError.keyNotFound(key, context) {
            Logger.error("解析 metadata_json 失败: 缺少字段 '\(key.stringValue)'")
            Logger.error("  - 上下文路径: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
            Logger.error("  - 调试描述: \(context.debugDescription)")

            // 尝试解析原始 JSON 显示可用字段
            if let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                Logger.error("  - 可用字段: \(json.keys.joined(separator: ", "))")
            }
            return nil
        } catch let DecodingError.typeMismatch(type, context) {
            Logger.error("解析 metadata_json 失败: 字段类型不匹配")
            Logger.error("  - 期望类型: \(type)")
            Logger.error("  - 字段路径: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
            Logger.error("  - 调试描述: \(context.debugDescription)")
            return nil
        } catch let DecodingError.valueNotFound(type, context) {
            Logger.error("解析 metadata_json 失败: 字段值为 null")
            Logger.error("  - 期望类型: \(type)")
            Logger.error("  - 字段路径: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
            Logger.error("  - 调试描述: \(context.debugDescription)")
            return nil
        } catch let DecodingError.dataCorrupted(context) {
            Logger.error("解析 metadata_json 失败: 数据损坏")
            Logger.error("  - 字段路径: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
            Logger.error("  - 调试描述: \(context.debugDescription)")

            // 显示原始 JSON 内容
            Logger.error("  - JSON 内容: \(jsonString)")
            return nil
        } catch {
            Logger.error("解析 metadata_json 失败: \(error.localizedDescription)")
            Logger.error("  - 错误类型: \(type(of: error))")
            Logger.error("  - JSON 内容: \(jsonString)")
            return nil
        }
    }

    /// 下载 metadata 文件（降级方案）
    private func fetchMetadataFile(recordID: CKRecord.ID) async throws -> URL {
        Logger.info("开始下载 metadata asset 文件...")

        return try await fetchSingleAsset(
            recordID: recordID,
            assetFieldName: "metadata_file",
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
                // Logger.info("[\(assetFieldName)] 下载进度: \(Int(progress * 100))%")
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

    /// 下载额外语言数据库文件（支持进度回调）
    /// - Parameters:
    ///   - recordID: 要下载的 RecordID
    ///   - fieldName: CloudKit 字段名（如 "sde_de"）
    ///   - progressHandler: 进度回调 (0.0 ~ 1.0)
    /// - Returns: 本地文件 URL
    func fetchExtraDBFile(recordID: CKRecord.ID, fieldName: String, progressHandler: @escaping (Double) -> Void) async throws -> URL {
        Logger.info("开始获取额外语言数据库文件: \(fieldName)")

        return try await fetchSingleAsset(
            recordID: recordID,
            assetFieldName: fieldName,
            progressHandler: progressHandler
        )
    }

    // MARK: - 私有方法
}

// MARK: - 错误类型

enum SDECloudKitError: LocalizedError {
    case noRecordsFound
    case invalidRecordFormat
    case metadataParseError(Error)
    case metadataUnavailable
    case cloudKitError(Error)

    var errorDescription: String? {
        switch self {
        case .noRecordsFound:
            return "未找到 SDE 更新记录"
        case .invalidRecordFormat:
            return "SDE 更新记录格式无效"
        case let .metadataParseError(error):
            return "metadata 文件解析失败: \(error.localizedDescription)"
        case .metadataUnavailable:
            return "无法获取 metadata 信息（metadata_json 和 metadata asset 都不可用）"
        case let .cloudKitError(error):
            return "CloudKit 错误: \(error.localizedDescription)"
        }
    }
}
