import CloudKit
import Foundation
import SwiftUI

/// 额外语言数据库管理器
/// 负责下载、验证、安装非内置语言（de/es/fr/ja/ko/ru）的 SDE 数据库
@MainActor
class ExtraLanguageDBManager: ObservableObject {
    static let shared = ExtraLanguageDBManager()

    // MARK: - 下载状态

    enum DownloadStatus: Equatable {
        case idle
        case preparing
        case downloading(Double)
        case verifying
        case extracting
        case failed(String)

        var isInProgress: Bool {
            switch self {
            case .preparing, .downloading, .verifying, .extracting:
                return true
            default:
                return false
            }
        }
    }

    // MARK: - Properties

    @Published var languageStatus: [String: DownloadStatus] = [:]

    // MARK: - 语言定义

    struct LanguageInfo: Sendable {
        let code: String
        let displayName: String
        let cloudKitField: String
    }

    nonisolated static let extraLanguages: [LanguageInfo] = [
        LanguageInfo(code: "de", displayName: "Deutsch", cloudKitField: "sde_de"),
        LanguageInfo(code: "es", displayName: "Español", cloudKitField: "sde_es"),
        LanguageInfo(code: "fr", displayName: "Français", cloudKitField: "sde_fr"),
        LanguageInfo(code: "ja", displayName: "日本語", cloudKitField: "sde_ja"),
        LanguageInfo(code: "ko", displayName: "한국어", cloudKitField: "sde_ko"),
        LanguageInfo(code: "ru", displayName: "Русский", cloudKitField: "sde_ru"),
    ]

    nonisolated static func isBuiltinLanguage(_ code: String) -> Bool {
        return code == "en" || code == "zh-Hans"
    }

    nonisolated static func languageInfo(for code: String) -> LanguageInfo? {
        return extraLanguages.first { $0.code == code }
    }

    // MARK: - 检查数据库是否可用

    func isExtraDBAvailable(languageCode: String) -> Bool {
        let dbName = Self.databaseFileName(for: languageCode)
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dbPath = documentsPath.appendingPathComponent("sde/db/\(dbName).sqlite").path
        return FileManager.default.fileExists(atPath: dbPath)
    }

    /// 获取数据库文件名（不含扩展名）
    nonisolated static func databaseFileName(for languageCode: String) -> String {
        switch languageCode {
        case "zh-Hans":
            return "item_db_zh"
        default:
            return "item_db_\(languageCode)"
        }
    }

    // MARK: - 下载并安装

    func downloadAndInstall(languageCode: String) async {
        guard let langInfo = Self.languageInfo(for: languageCode) else {
            languageStatus[languageCode] = .failed("不支持的语言")
            return
        }

        languageStatus[languageCode] = .preparing

        do {
            // 确保有 CloudKit recordID 和 metadata
            let recordID = try await ensureRecordID()
            guard let extraDBInfo = try await getExtraDBInfo(for: languageCode) else {
                throw ExtraDBError.noMetadataForLanguage
            }

            // 下载
            languageStatus[languageCode] = .downloading(0)
            let downloadedURL = try await SDECloudKitManager.shared.fetchExtraDBFile(
                recordID: recordID,
                fieldName: langInfo.cloudKitField,
                progressHandler: { [weak self] progress in
                    Task { @MainActor in
                        // 仅在仍处于 downloading 状态时更新进度，避免异步回调覆盖后续状态
                        if case .downloading = self?.languageStatus[languageCode] {
                            self?.languageStatus[languageCode] = .downloading(progress)
                        }
                    }
                }
            )

            // 复制到下载目录
            let downloader = SDEDownloader()
            let downloadDir = downloader.getDownloadDirectory()
            let targetZipURL = downloadDir.appendingPathComponent(extraDBInfo.file)

            if FileManager.default.fileExists(atPath: targetZipURL.path) {
                try FileManager.default.removeItem(at: targetZipURL)
            }
            try FileManager.default.copyItem(at: downloadedURL, to: targetZipURL)
            try? FileManager.default.removeItem(at: downloadedURL)

            // 校验
            languageStatus[languageCode] = .verifying
            let isValid = try downloader.verifyExtraDBHash(zipURL: targetZipURL, expectedHash: extraDBInfo.sha256)
            guard isValid else {
                throw ExtraDBError.sha256Mismatch
            }

            // 解压
            languageStatus[languageCode] = .extracting
            try downloader.extractExtraDB(zipURL: targetZipURL, languageCode: languageCode)

            // 清理 zip
            try? FileManager.default.removeItem(at: targetZipURL)

            // 清除下载状态，让视图根据文件存在和选中状态自动显示正确指示器
            languageStatus[languageCode] = nil
            Logger.info("额外语言数据库安装完成: \(languageCode)")

        } catch {
            Logger.error("额外语言数据库安装失败 (\(languageCode)): \(error)")
            languageStatus[languageCode] = .failed(error.localizedDescription)
        }
    }

    // MARK: - 删除已下载的额外语言数据库

    func removeExtraDB(languageCode: String) {
        let dbName = Self.databaseFileName(for: languageCode)
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dbPath = documentsPath.appendingPathComponent("sde/db/\(dbName).sqlite")

        try? FileManager.default.removeItem(at: dbPath)
        languageStatus[languageCode] = .idle
        Logger.info("已删除额外语言数据库: \(languageCode)")
    }

    // MARK: - Private

    private func ensureRecordID() async throws -> CKRecord.ID {
        if let recordID = SDEUpdateChecker.shared.currentUpdateInfo?.recordID {
            return recordID
        }
        await SDEUpdateChecker.shared.checkForUpdates()
        guard let recordID = SDEUpdateChecker.shared.currentUpdateInfo?.recordID else {
            throw ExtraDBError.noRecordID
        }
        return recordID
    }

    private func getExtraDBInfo(for languageCode: String) async throws -> ExtraDBInfo? {
        if let metadata = SDEUpdateChecker.shared.currentMetadata,
           let info = metadata.extraDB?[languageCode]
        {
            return info
        }
        // 尝试重新检查
        await SDEUpdateChecker.shared.checkForUpdates()
        return SDEUpdateChecker.shared.currentMetadata?.extraDB?[languageCode]
    }
}

// MARK: - 错误类型

enum ExtraDBError: LocalizedError {
    case noRecordID
    case noMetadataForLanguage
    case sha256Mismatch
    case unsupportedLanguage

    var errorDescription: String? {
        switch self {
        case .noRecordID:
            return NSLocalizedString("ExtraDB_Error_NoRecordID", comment: "无法获取 CloudKit 记录")
        case .noMetadataForLanguage:
            return NSLocalizedString("ExtraDB_Error_NoMetadata", comment: "未找到该语言的元数据")
        case .sha256Mismatch:
            return NSLocalizedString("ExtraDB_Error_SHA256", comment: "文件校验失败")
        case .unsupportedLanguage:
            return NSLocalizedString("ExtraDB_Error_Unsupported", comment: "不支持的语言")
        }
    }
}
