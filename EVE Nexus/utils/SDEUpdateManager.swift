import CloudKit
import Foundation
import SwiftUI

// MARK: - 日志消息类型

enum LogMessageType {
    case info // [*] 白色
    case warning // 橘黄色
    case error // [×] 红色
    case success // [✓] 绿色

    var prefix: String {
        switch self {
        case .info: return "[*]"
        case .warning: return "[!]"
        case .error: return "[×]"
        case .success: return "[✓]"
        }
    }

    var color: Color {
        switch self {
        case .info: return .white
        case .warning: return .orange
        case .error: return .red
        case .success: return .green
        }
    }
}

struct LogMessage: Identifiable {
    let id = UUID()
    let text: String
    let type: LogMessageType

    var displayText: String {
        if text.isEmpty {
            return "" // 空行用于进度条占位
        }
        return "\(type.prefix) \(text)"
    }
}

/// SDE 更新管理器
/// 负责协调 SDE 数据包和图标包的检查、下载、验证和更新流程
@MainActor
class SDEUpdateManager: ObservableObject {
    static let shared = SDEUpdateManager()

    // MARK: - Published Properties

    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0.0
    @Published var downloadLogs: [LogMessage] = []
    @Published var hasError = false
    @Published var isCompleted = false

    // MARK: - Private Properties

    private let updateChecker = SDEUpdateChecker.shared
    private let downloader = SDEDownloader()

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// 开始更新流程
    func startUpdate() {
        isDownloading = true
        downloadProgress = 0.0
        downloadLogs = []
        hasError = false
        isCompleted = false
        progressBarIndices = [:]

        Task {
            await performUpdate()
        }
    }

    /// 重置状态（用户手动关闭更新界面时调用）
    func reset() {
        isDownloading = false
        downloadProgress = 0.0
        downloadLogs = []
        hasError = false
        isCompleted = false
        progressBarIndices = [:]
    }

    // MARK: - Private Methods

    /// 执行更新流程
    private func performUpdate() async {
        do {
            //  清空下载目录
            await addLog(NSLocalizedString("SDE_Log_Clearing_Directory", comment: ""), type: .info)
            try downloader.clearDownloadDirectory()

            //  检查哪些组件需要更新
            let needsSDEUpdate = updateChecker.currentSDEVersion != updateChecker.latestSDEVersion
            let needsIconsUpdate = updateChecker.currentIconVersion < updateChecker.latestIconVersion

            await addLog(NSLocalizedString("SDE_Log_Checking_Requirements", comment: ""), type: .info)
            await addLog(String.localizedStringWithFormat(NSLocalizedString("SDE_Log_SDE_Needs_Update", comment: ""),
                                                          needsSDEUpdate ? "true" : "false",
                                                          updateChecker.currentSDEVersion,
                                                          updateChecker.latestSDEVersion), type: .info)
            await addLog(String.localizedStringWithFormat(NSLocalizedString("SDE_Log_Icons_Need_Update", comment: ""),
                                                          needsIconsUpdate ? "true" : "false",
                                                          updateChecker.currentIconVersion,
                                                          updateChecker.latestIconVersion), type: .info)

            //  下载 icons.zip（如果需要）
            if needsIconsUpdate {
                try await downloadAndInstallIcons()
            } else {
                await addLog(NSLocalizedString("SDE_Log_Icons_Up_To_Date", comment: ""), type: .success)
            }

            //  下载 sde.zip（如果需要）
            if needsSDEUpdate {
                try await downloadAndInstallSDE()
            } else {
                await addLog(NSLocalizedString("SDE_Log_SDE_Up_To_Date", comment: ""), type: .success)
            }

            //  如果当前选择的是额外语言，也更新该语言的数据库
            if needsSDEUpdate {
                try await downloadExtraLanguageIfNeeded()
            }

            //  更新完成
            isCompleted = true

            // 清理检查缓存，以便下次能立即检查更新
            updateChecker.clearCheckCache()

            // 重新加载数据以使用新的SDE数据
            reloadDataWithNewSDE()

        } catch {
            await addLog(String.localizedStringWithFormat(NSLocalizedString("SDE_Log_Update_Failed", comment: ""), error.localizedDescription), type: .error)
            hasError = true
        }
    }

    /// 下载并安装图标包
    private func downloadAndInstallIcons() async throws {
        await addLog(NSLocalizedString("SDE_Log_Downloading_Icons", comment: ""), type: .info)
        await addLog("") // 为下载进度条预留空行

        // 获取 recordID（必须存在）
        guard let recordID = updateChecker.currentUpdateInfo?.recordID else {
            throw NSError(domain: "SDEUpdateManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "RecordID not found, please check for updates first"])
        }

        // 使用 CloudKit 下载 Icons 文件（支持进度）
        let localIconsURL = try await SDECloudKitManager.shared.fetchIconsFile(recordID: recordID) { [weak self] progress in
            Task { @MainActor in
                self?.downloadProgress = progress
                self?.updateProgressBar(progress: progress, label: "icons_download")
            }
        }

        await addLog(NSLocalizedString("SDE_Log_Download_Completed", comment: ""), type: .success)

        // 复制到下载目录
        let downloadDir = downloader.getDownloadDirectory()
        let targetIconsURL = downloadDir.appendingPathComponent("icons.zip")

        if FileManager.default.fileExists(atPath: targetIconsURL.path) {
            try FileManager.default.removeItem(at: targetIconsURL)
        }

        try FileManager.default.copyItem(at: localIconsURL, to: targetIconsURL)
        await addLog(NSLocalizedString("SDE_Log_Preparing_Icons", comment: ""), type: .info)

        // 验证
        await addLog(NSLocalizedString("SDE_Log_Verifying_Icons_SHA", comment: ""), type: .info)
        let expectedHash = updateChecker.latestIconsHashFull
        let iconsValid = try await downloader.verifyIconsHash(expectedHash: expectedHash)
        if !iconsValid {
            await addLog(NSLocalizedString("SDE_Log_SHA_Failed", comment: ""), type: .error)
            throw NSError(domain: "SDEUpdateManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Icons SHA256 verification failed"])
        }
        await addLog(NSLocalizedString("SDE_Log_SHA_Verified", comment: ""), type: .success)

        // 解压
        await addLog(NSLocalizedString("SDE_Log_Extracting_Icons", comment: ""), type: .info)
        await addLog("") // 为解压进度条预留空行
        try await downloader.extractIcons { [weak self] progress in
            Task { @MainActor in
                self?.downloadProgress = progress
                self?.updateProgressBar(progress: progress, label: "icons_extract")
            }
        }
        await addLog(NSLocalizedString("SDE_Log_Extract_Icons_Success", comment: ""), type: .success)

        //  解压完成后删除 CloudKit 缓存中的 icons.zip
        try? FileManager.default.removeItem(at: localIconsURL)
        Logger.info("已删除 CloudKit 缓存中的 icons.zip")

        // 下载并保存 metadata.json 到 icons 目录（从 CloudKit 的 metadata_file 资产字段下载）
        await addLog(NSLocalizedString("SDE_Log_Downloading_Metadata", comment: ""), type: .info)
        do {
            let metadataURL = try await SDECloudKitManager.shared.fetchMetadataFileForSaving(recordID: recordID)
            try MetadataManager.shared.copyMetadataToIconsDirectory(from: metadataURL)

            //  保存完成后删除 CloudKit 缓存中的 metadata
            try? FileManager.default.removeItem(at: metadataURL)
            Logger.info("已删除 CloudKit 缓存中的 metadata 临时文件")

            await addLog(NSLocalizedString("SDE_Log_Metadata_Saved", comment: ""), type: .success)
        } catch {
            await addLog(String.localizedStringWithFormat(NSLocalizedString("SDE_Log_Metadata_Failed", comment: ""), error.localizedDescription), type: .warning)
            Logger.warning("Failed to save metadata.json: \(error)")
        }
    }

    /// 如果当前选择的是额外语言（非中英文），也下载该语言的数据库
    private func downloadExtraLanguageIfNeeded() async throws {
        let dbLanguage = UserDefaults.standard.string(forKey: "selectedDatabaseLanguage") ?? "en"

        guard !ExtraLanguageDBManager.isBuiltinLanguage(dbLanguage) else { return }
        guard let langInfo = ExtraLanguageDBManager.languageInfo(for: dbLanguage) else { return }
        guard let recordID = updateChecker.currentUpdateInfo?.recordID else { return }
        guard let extraDBInfo = updateChecker.currentMetadata?.extraDB?[dbLanguage] else {
            await addLog("⚠ 未找到 \(langInfo.displayName) 的元数据，跳过", type: .warning)
            return
        }

        await addLog(String(format: NSLocalizedString("SDE_Log_Downloading_ExtraDB", comment: "正在下载 %@ 数据库..."), langInfo.displayName), type: .info)
        await addLog("")

        // 下载
        let downloadedURL = try await SDECloudKitManager.shared.fetchExtraDBFile(
            recordID: recordID,
            fieldName: langInfo.cloudKitField,
            progressHandler: { [weak self] progress in
                Task { @MainActor in
                    self?.downloadProgress = progress
                    self?.updateProgressBar(progress: progress, label: "extra_db_download")
                }
            }
        )

        await addLog(NSLocalizedString("SDE_Log_Download_Completed", comment: ""), type: .success)

        // 复制到下载目录
        let sdeDownloader = SDEDownloader()
        let downloadDir = sdeDownloader.getDownloadDirectory()
        let targetZipURL = downloadDir.appendingPathComponent(extraDBInfo.file)

        if FileManager.default.fileExists(atPath: targetZipURL.path) {
            try FileManager.default.removeItem(at: targetZipURL)
        }
        try FileManager.default.copyItem(at: downloadedURL, to: targetZipURL)
        try? FileManager.default.removeItem(at: downloadedURL)

        // 验证
        await addLog(NSLocalizedString("SDE_Log_Verifying_SDE_SHA", comment: ""), type: .info)
        let isValid = try sdeDownloader.verifyExtraDBHash(zipURL: targetZipURL, expectedHash: extraDBInfo.sha256)
        guard isValid else {
            await addLog(NSLocalizedString("SDE_Log_SHA_Failed", comment: ""), type: .error)
            throw NSError(domain: "SDEUpdateManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "\(langInfo.displayName) SHA256 verification failed"])
        }
        await addLog(NSLocalizedString("SDE_Log_SHA_Verified", comment: ""), type: .success)

        // 解压
        await addLog(String(format: NSLocalizedString("SDE_Log_Extracting_ExtraDB", comment: "正在解压 %@ 数据库..."), langInfo.displayName), type: .info)
        try sdeDownloader.extractExtraDB(zipURL: targetZipURL, languageCode: dbLanguage)
        await addLog(String(format: NSLocalizedString("SDE_Log_ExtraDB_Success", comment: "%@ 数据库更新完成"), langInfo.displayName), type: .success)

        // 清理
        try? FileManager.default.removeItem(at: targetZipURL)
    }

    /// 下载并安装SDE数据包
    private func downloadAndInstallSDE() async throws {
        await addLog(NSLocalizedString("SDE_Log_Downloading_SDE", comment: ""), type: .info)
        await addLog("") // 为下载进度条预留空行

        // 获取 recordID（必须存在）
        guard let recordID = updateChecker.currentUpdateInfo?.recordID else {
            throw NSError(domain: "SDEUpdateManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "RecordID not found, please check for updates first"])
        }

        // 使用 CloudKit 下载 SDE 文件（支持进度）
        let localSDEURL = try await SDECloudKitManager.shared.fetchSDEFile(recordID: recordID) { [weak self] progress in
            Task { @MainActor in
                self?.downloadProgress = progress
                self?.updateProgressBar(progress: progress, label: "sde_download")
            }
        }

        await addLog(NSLocalizedString("SDE_Log_Download_Completed", comment: ""), type: .success)

        // 复制到下载目录
        let downloadDir = downloader.getDownloadDirectory()
        let targetSDEURL = downloadDir.appendingPathComponent("sde.zip")

        if FileManager.default.fileExists(atPath: targetSDEURL.path) {
            try FileManager.default.removeItem(at: targetSDEURL)
        }

        try FileManager.default.copyItem(at: localSDEURL, to: targetSDEURL)
        await addLog(NSLocalizedString("SDE_Log_Preparing_SDE", comment: ""), type: .info)

        // 验证
        await addLog(NSLocalizedString("SDE_Log_Verifying_SDE_SHA", comment: ""), type: .info)
        let expectedHash = updateChecker.latestSDEHashFull
        let sdeValid = try await downloader.verifySDEHash(expectedHash: expectedHash)
        if !sdeValid {
            await addLog(NSLocalizedString("SDE_Log_SHA_Failed", comment: ""), type: .error)
            throw NSError(domain: "SDEUpdateManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "SDE SHA256 verification failed"])
        }
        await addLog(NSLocalizedString("SDE_Log_SHA_Verified", comment: ""), type: .success)

        // 解压
        await addLog(NSLocalizedString("SDE_Log_Extracting_SDE", comment: ""), type: .info)
        await addLog("") // 为解压进度条预留空行
        try await downloader.extractSDE { [weak self] progress in
            Task { @MainActor in
                self?.downloadProgress = progress
                self?.updateProgressBar(progress: progress, label: "sde_extract")
            }
        }
        await addLog(NSLocalizedString("SDE_Log_Extract_SDE_Success", comment: ""), type: .success)

        //  解压完成后删除 CloudKit 缓存中的 sde.zip
        try? FileManager.default.removeItem(at: localSDEURL)
        Logger.info("已删除 CloudKit 缓存中的 sde.zip")
    }

    /// 添加日志
    private func addLog(_ message: String, type: LogMessageType = .info) async {
        let logMessage = LogMessage(text: message, type: type)
        downloadLogs.append(logMessage)
    }

    // 存储每个阶段进度条的索引
    private var progressBarIndices: [String: Int] = [:]

    /// 更新进度条
    private func updateProgressBar(progress: Double, label: String) {
        let barLength = 24
        let filledLength = Int(progress * Double(barLength))
        let bar = String(repeating: "=", count: filledLength) +
            String(repeating: " ", count: barLength - filledLength)
        let percentage = String(format: "%.1f%%", progress * 100)
        let progressBar = "[\(bar)] \(percentage)"

        // 如果这个标签的进度条还没有创建，找到最后一个空行并记录索引
        if progressBarIndices[label] == nil {
            // 找到最后一个空行的索引
            if let lastIndex = downloadLogs.indices.last,
               downloadLogs[lastIndex].text.isEmpty
            {
                progressBarIndices[label] = lastIndex
            }
        }

        // 更新对应标签的进度条（进度条不需要添加类型前缀）
        if let index = progressBarIndices[label], index < downloadLogs.count {
            downloadLogs[index] = LogMessage(text: progressBar, type: .info)
        }
    }

    /// 重新加载数据以使用新的SDE数据
    private func reloadDataWithNewSDE() {
        Logger.info("Reloading data with new SDE...")

        // 重新加载本地化数据
        LocalizationManager.shared.loadAccountingEntryTypes()

        // 重新加载数据库
        DatabaseManager.shared.loadDatabase()

        // 重新检查更新状态
        Task {
            await updateChecker.forceCheckForUpdates()
        }

        Logger.info("Data reload completed with new SDE")
    }
}
