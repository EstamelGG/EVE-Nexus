import Foundation
import SwiftUI

// MARK: - Update UI Logs

enum LogMessageType {
    case info, warning, error, success

    var color: Color {
        switch self {
        case .info: return .secondary
        case .warning: return .orange
        case .error: return .red
        case .success: return .green
        }
    }
}

struct LogMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let type: LogMessageType
}

enum SDEUpdateStatus {
    case notChecked, checking, noUpdate, hasUpdate
}

enum SDEPackageKind {
    case icons, sde
}

enum PackageUpdatePhase: Equatable {
    case pending, running, skipped, done, failed
}

struct PackageUpdateState: Equatable {
    var phase: PackageUpdatePhase = .pending
    var progress: Double = 0
    var lines: [LogMessage] = []
}

// MARK: - Checker

@MainActor
final class SDEUpdateChecker: ObservableObject {
    static let shared = SDEUpdateChecker()

    @Published var updateStatus: SDEUpdateStatus = .notChecked
    @Published var isChecking = false
    @Published var lastCheckTime: Date?
    @Published var updateVersion: String?
    @Published var isButtonDisabled = false

    @Published var currentSDEVersion: String = "0"
    @Published var latestSDEVersion: String = "0"
    @Published var currentIconVersion: Int = 0
    @Published var latestIconVersion: Int = 0

    var currentUpdateInfo: SDEUpdateInfo?
    var currentMetadata: CloudKitMetadata?

    private let lastCheckTimeKey = "SDE_LastCheckTime"
    private let checkInterval: TimeInterval = 60

    private init() {
        if let t = UserDefaults.standard.object(forKey: lastCheckTimeKey) as? TimeInterval {
            lastCheckTime = Date(timeIntervalSince1970: t)
        }
    }

    func clearCheckCache() {
        lastCheckTime = nil
        UserDefaults.standard.removeObject(forKey: lastCheckTimeKey)
        updateStatus = .notChecked
    }

    func checkForUpdates() async {
        await checkForUpdates(force: false)
    }

    func forceCheckForUpdates() async {
        guard !isButtonDisabled else { return }
        isButtonDisabled = true
        let start = Date()
        await checkForUpdates(force: true)
        let remain = max(0, 2.0 - Date().timeIntervalSince(start))
        if remain > 0 { try? await Task.sleep(nanoseconds: UInt64(remain * 1e9)) }
        isButtonDisabled = false
    }

    private func checkForUpdates(force: Bool) async {
        guard !isChecking else { return }
        if !force,
           let last = lastCheckTime,
           Date().timeIntervalSince(last) <= checkInterval,
           updateStatus == .noUpdate
        {
            return
        }

        isChecking = true
        updateStatus = .checking
        defer { isChecking = false }

        SDEDownloader().clearCloudKitAssets()

        guard let info = await SDECloudKitManager.shared.fetchLatestSDEUpdate() else {
            Logger.warning("CloudKit 无 SDE 更新信息，继续使用本地数据")
            await markLocalAsLatest()
            return
        }

        let meta = info.metadata
        let localVersion = await localVersionLabel()
        let localIcon = MetadataManager.shared.getLocalIconVersion()
        let (localBuild, localPatch) = await localBuildPatch()

        currentSDEVersion = localVersion
        latestSDEVersion = info.versionLabel
        currentIconVersion = localIcon
        latestIconVersion = meta.iconVersion
        currentUpdateInfo = info
        currentMetadata = meta

        let sdeNewer = meta.buildNumber > localBuild
            || (meta.buildNumber == localBuild && meta.patchNumber > localPatch)
        let iconsNewer = meta.iconVersion > localIcon

        if sdeNewer || iconsNewer {
            updateStatus = .hasUpdate
            updateVersion = info.versionLabel
            Logger.info("发现 SDE 更新: \(info.versionLabel)")
        } else {
            updateStatus = .noUpdate
            updateVersion = nil
            persistCheckTime()
            Logger.info("SDE 已是最新")
        }
    }

    private func markLocalAsLatest() async {
        let local = await localVersionLabel()
        let icon = MetadataManager.shared.getLocalIconVersion()
        currentSDEVersion = local
        latestSDEVersion = local
        currentIconVersion = icon
        latestIconVersion = icon
        updateStatus = .noUpdate
        updateVersion = nil
        currentUpdateInfo = nil
        currentMetadata = nil
        persistCheckTime()
    }

    private func persistCheckTime() {
        lastCheckTime = Date()
        UserDefaults.standard.set(lastCheckTime?.timeIntervalSince1970, forKey: lastCheckTimeKey)
    }

    private func localVersionLabel() async -> String {
        let (b, p) = await localBuildPatch()
        return p > 0 ? "\(b).\(p)" : "\(b)"
    }

    private func localBuildPatch() async -> (Int, Int) {
        await Task.detached {
            let q = "SELECT build_number, patch_number FROM version_info WHERE id = 1"
            guard case let .success(rows) = DatabaseManager.shared.executeQuery(q, useCache: false),
                  let row = rows.first
            else { return (0, 0) }
            return (Self.intValue(row["build_number"]), Self.intValue(row["patch_number"]))
        }.value
    }

    private nonisolated static func intValue(_ value: Any?) -> Int {
        switch value {
        case let i as Int: return i
        case let d as Double: return Int(d)
        case let n as Int64: return Int(n)
        case let s as String: return Int(s) ?? 0
        default: return 0
        }
    }
}

// MARK: - Installer

@MainActor
final class SDEUpdateManager: ObservableObject {
    static let shared = SDEUpdateManager()

    @Published var isDownloading = false
    @Published var iconsState = PackageUpdateState()
    @Published var sdeState = PackageUpdateState()
    @Published var hasError = false
    @Published var isCompleted = false

    private let updateChecker = SDEUpdateChecker.shared
    private let downloader = SDEDownloader()

    private init() {}

    func startUpdate() {
        isDownloading = true
        iconsState = PackageUpdateState()
        sdeState = PackageUpdateState()
        hasError = false
        isCompleted = false
        Task { await performUpdate() }
    }

    func reset() {
        isDownloading = false
        iconsState = PackageUpdateState()
        sdeState = PackageUpdateState()
        hasError = false
        isCompleted = false
    }

    private func performUpdate() async {
        do {
            try downloader.clearDownloadDirectory()

            let needsSDE = updateChecker.currentSDEVersion != updateChecker.latestSDEVersion
            let needsIcons = updateChecker.currentIconVersion < updateChecker.latestIconVersion

            if needsIcons {
                try await downloadAndInstall(
                    kind: .icons,
                    field: SDECloudKitManager.fieldIcons,
                    zipName: SDECloudKitManager.iconsZipName,
                    expectedHash: updateChecker.currentMetadata?.iconSha256 ?? "",
                    downloadLog: String(localized: "SDE_Log_Downloading_Icons"),
                    prepareLog: String(localized: "SDE_Log_Preparing_Icons"),
                    verifyLog: String(localized: "SDE_Log_Verifying_Icons_SHA"),
                    extractLog: String(localized: "SDE_Log_Extracting_Icons"),
                    successLog: String(localized: "SDE_Log_Extract_Icons_Success"),
                    extract: { [downloader] p in try await downloader.extractIcons(progress: p) }
                )
            } else {
                skipPackage(.icons, message: String(localized: "SDE_Log_Icons_Up_To_Date"))
            }

            if needsSDE {
                try await downloadAndInstall(
                    kind: .sde,
                    field: SDECloudKitManager.fieldSDE,
                    zipName: SDECloudKitManager.sdeZipName,
                    expectedHash: updateChecker.currentMetadata?.sdeSha256 ?? "",
                    downloadLog: String(localized: "SDE_Log_Downloading_SDE"),
                    prepareLog: String(localized: "SDE_Log_Preparing_SDE"),
                    verifyLog: String(localized: "SDE_Log_Verifying_SDE_SHA"),
                    extractLog: String(localized: "SDE_Log_Extracting_SDE"),
                    successLog: String(localized: "SDE_Log_Extract_SDE_Success"),
                    extract: { [downloader] p in try await downloader.extractSDE(progress: p) }
                )
            } else {
                skipPackage(.sde, message: String(localized: "SDE_Log_SDE_Up_To_Date"))
            }

            if needsIcons || needsSDE {
                saveMetadataJSON(to: needsSDE ? .sde : .icons)
            }

            isCompleted = true
            try? downloader.clearDownloadDirectory()
            updateChecker.clearCheckCache()
            reloadDataWithNewSDE()
        } catch {
            if iconsState.phase == .running {
                markFailed(.icons, error)
            } else {
                markFailed(.sde, error)
            }
            hasError = true
        }
    }

    private func downloadAndInstall(
        kind: SDEPackageKind,
        field: String,
        zipName: String,
        expectedHash: String,
        downloadLog: String,
        prepareLog: String,
        verifyLog: String,
        extractLog: String,
        successLog: String,
        extract: @escaping (@escaping (Double) -> Void) async throws -> Void
    ) async throws {
        setPhase(kind, .running)
        setProgress(kind, 0)
        appendLine(kind, downloadLog)

        guard let recordID = updateChecker.currentUpdateInfo?.recordID else {
            throw NSError(domain: "SDEUpdateManager", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "RecordID not found"])
        }

        let assetURL = try await SDECloudKitManager.shared.fetchAsset(recordID: recordID, field: field) {
            [weak self] p in
            Task { @MainActor in
                self?.setProgress(kind, p * 0.6)
            }
        }
        appendLine(kind, String(localized: "SDE_Log_Download_Completed"), .success)
        setProgress(kind, 0.6)

        appendLine(kind, prepareLog)
        let staged = try downloader.stageAsset(assetURL, as: zipName)
        setProgress(kind, 0.65)

        appendLine(kind, String(localized: "SDE_Log_Calculating_SHA", defaultValue: "正在计算 SHA256…"))
        setProgress(kind, 0.7)
        appendLine(kind, verifyLog)
        guard try downloader.verifySHA256(of: staged, expected: expectedHash) else {
            appendLine(kind, String(localized: "SDE_Log_SHA_Failed"), .error)
            throw NSError(domain: "SDEUpdateManager", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "\(zipName) SHA256 failed"])
        }
        appendLine(kind, String(localized: "SDE_Log_SHA_Verified"), .success)
        setProgress(kind, 0.75)

        appendLine(kind, extractLog)
        try await extract { [weak self] p in
            Task { @MainActor in
                self?.setProgress(kind, 0.75 + p * 0.25)
            }
        }
        appendLine(kind, successLog, .success)
        setProgress(kind, 1)
        setPhase(kind, .done)
    }

    private func saveMetadataJSON(to kind: SDEPackageKind) {
        guard let meta = updateChecker.currentMetadata else { return }
        do {
            try MetadataManager.shared.saveLocalMetadata(meta)
            appendLine(kind, NSLocalizedString("SDE_Log_Metadata_Saved", comment: ""), .success)
        } catch {
            appendLine(
                kind,
                String.localizedStringWithFormat(
                    NSLocalizedString("SDE_Log_Metadata_Failed", comment: ""),
                    error.localizedDescription
                ),
                .warning
            )
        }
    }

    private func skipPackage(_ kind: SDEPackageKind, message: String) {
        appendLine(kind, message, .success)
        setProgress(kind, 1)
        setPhase(kind, .skipped)
    }

    private func markFailed(_ kind: SDEPackageKind, _ error: Error) {
        appendLine(
            kind,
            String.localizedStringWithFormat(
                NSLocalizedString("SDE_Log_Update_Failed", comment: ""),
                error.localizedDescription
            ),
            .error
        )
        setPhase(kind, .failed)
    }

    private func appendLine(_ kind: SDEPackageKind, _ message: String, _ type: LogMessageType = .info) {
        guard !message.isEmpty else { return }
        switch kind {
        case .icons: iconsState.lines.append(LogMessage(text: message, type: type))
        case .sde: sdeState.lines.append(LogMessage(text: message, type: type))
        }
    }

    private func setProgress(_ kind: SDEPackageKind, _ value: Double) {
        let clamped = min(max(value, 0), 1)
        switch kind {
        case .icons: iconsState.progress = clamped
        case .sde: sdeState.progress = clamped
        }
    }

    private func setPhase(_ kind: SDEPackageKind, _ phase: PackageUpdatePhase) {
        switch kind {
        case .icons: iconsState.phase = phase
        case .sde: sdeState.phase = phase
        }
    }

    private func reloadDataWithNewSDE() {
        LocalizationManager.shared.loadAccountingEntryTypes()
        DatabaseManager.shared.loadDatabase()
        ItemTextStore.shared.syncWithActiveSDE()
        AttributeCompareMarketPolicy.reload()
        Task { await updateChecker.forceCheckForUpdates() }
    }
}
