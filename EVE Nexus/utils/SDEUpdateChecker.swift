import CloudKit
import Foundation
import SwiftUI

// SDE 更新检查器
@MainActor
class SDEUpdateChecker: ObservableObject {
    static let shared = SDEUpdateChecker()

    @Published var updateStatus: SDEUpdateStatus = .notChecked
    @Published var isChecking = false
    @Published var lastCheckTime: Date?
    @Published var updateVersion: String?
    @Published var isButtonDisabled = false

    // 详细信息
    @Published var currentSDEVersion: String = "0"
    @Published var latestSDEVersion: String = "0"
    @Published var currentIconVersion: Int = 0
    @Published var latestIconVersion: Int = 0

    // 完整的SHA256哈希值（用于验证）
    var latestIconsHashFull: String = ""
    var latestSDEHashFull: String = ""

    // CloudKit Asset 引用
    var latestIconsAsset: CKAsset?
    var latestSDEAsset: CKAsset?

    private let lastCheckTimeKey = "SDE_LastCheckTime"
    private let lastCheckSDEVersionKey = "SDE_LastCheckSDEVersion"
    private let lastCheckIconVersionKey = "SDE_LastCheckIconVersion"
    private let checkInterval: TimeInterval = 60 // 1分钟
    
    private var lastCheckSDEVersion: String?
    private var lastCheckIconVersion: Int?

    private init() {
        loadLastCheckTime()
        loadLastCheckVersions()
    }

    // 加载上次检查时间
    private func loadLastCheckTime() {
        if let timeInterval = UserDefaults.standard.object(forKey: lastCheckTimeKey) as? TimeInterval {
            lastCheckTime = Date(timeIntervalSince1970: timeInterval)
        }
    }
    
    // 加载上次检查时的版本信息
    private func loadLastCheckVersions() {
        lastCheckSDEVersion = UserDefaults.standard.string(forKey: lastCheckSDEVersionKey)
        lastCheckIconVersion = UserDefaults.standard.object(forKey: lastCheckIconVersionKey) as? Int
    }

    // 保存检查时间和版本信息
    private func saveLastCheckTime() {
        lastCheckTime = Date()
        UserDefaults.standard.set(lastCheckTime?.timeIntervalSince1970, forKey: lastCheckTimeKey)
        
        // 保存当前的版本信息
        UserDefaults.standard.set(currentSDEVersion, forKey: lastCheckSDEVersionKey)
        UserDefaults.standard.set(currentIconVersion, forKey: lastCheckIconVersionKey)
        
        lastCheckSDEVersion = currentSDEVersion
        lastCheckIconVersion = currentIconVersion
    }

    // 检查是否需要更新检查
    private func shouldCheckForUpdate() -> Bool {
        // 1. 如果从未检查过，需要检查
        guard let lastCheck = lastCheckTime else { return true }
        
        // 2. 如果本地 SDE 版本变更了，立即重新检查
        if let lastSDEVersion = lastCheckSDEVersion, lastSDEVersion != currentSDEVersion {
            Logger.info("检测到 SDE 版本变更 (\(lastSDEVersion) -> \(currentSDEVersion))，需要重新检查更新")
            return true
        }
        
        // 3. 如果本地图标版本变更了，立即重新检查
        if let lastIconVer = lastCheckIconVersion, lastIconVer != currentIconVersion {
            Logger.info("检测到图标版本变更 (\(lastIconVer) -> \(currentIconVersion))，需要重新检查更新")
            return true
        }
        
        // 4. 检查时间间隔
        return Date().timeIntervalSince(lastCheck) > checkInterval
    }

    // 检查更新
    func checkForUpdates() async {
        await checkForUpdates(force: false)
    }

    // 强制检查更新（忽略时间间隔）
    func forceCheckForUpdates() async {
        // 如果按钮已禁用，直接返回
        guard !isButtonDisabled else { return }

        // 禁用按钮
        isButtonDisabled = true

        // 记录开始时间
        let startTime = Date()

        // 开始检查
        await checkForUpdates(force: true)

        // 计算已用时间
        let elapsedTime = Date().timeIntervalSince(startTime)
        let remainingTime = max(0, 2.0 - elapsedTime) // 确保至少显示2秒

        // 如果还有剩余时间，等待剩余时间
        if remainingTime > 0 {
            try? await Task.sleep(nanoseconds: UInt64(remainingTime * 1_000_000_000))
        }

        // 重新启用按钮
        isButtonDisabled = false
    }

    // 内部检查更新方法
    private func checkForUpdates(force: Bool) async {
        // 如果正在检查，直接返回
        guard !isChecking else { return }

        // 如果不是强制检查，且不需要检查（1分钟内已检查过且无更新，且版本未变更），直接返回
        if !force, !shouldCheckForUpdate(), updateStatus == .noUpdate {
            Logger.info("1分钟内已检查过且无更新，且版本未变更，跳过检查")
            return
        }

        isChecking = true
        updateStatus = .checking

        Logger.info("开始检查SDE更新...")
        
        // [+] 输出 CloudKit 容器信息
        let containerID = SDECloudKitManager.shared.getContainerIdentifier()
        Logger.info("CloudKit 容器 ID: \(containerID ?? "未知")")
        
        // [+] 检查更新前先列出当前缓存
        Logger.info("=== 检查更新前的缓存状态 ===")
        SDEDownloader().listCloudKitAssets(containerIdentifier: containerID)
        
        // [+] 清理容器的 Assets 目录
        Logger.info("=== 清理旧缓存 ===")
        SDEDownloader().clearContainerAssets(containerIdentifier: containerID)
        
        // [+] 清理后再次列出（应该为空）
        Logger.info("=== 清理后的缓存状态 ===")
        SDEDownloader().listCloudKitAssets(containerIdentifier: containerID)

        do {
            // 使用 CloudKit 获取更新信息（内部会自动处理缓存过期问题）
            Logger.info("使用 CloudKit 获取更新信息")
            let updateInfo = try await SDECloudKitManager.shared.fetchLatestSDEUpdate()

            Logger.info("获取到远程SDE信息: 版本 \(updateInfo.sdeVersion).\(updateInfo.patchNumber), 标签: \(updateInfo.tag)")

            // 获取当前版本信息
            let currentVersion = await getCurrentSDEVersion()
            let localIconVer = MetadataManager.shared.getLocalIconVersion()
            let remoteIcons = updateInfo.sha256sum["icons.zip"] ?? ""
            let remoteSDE = updateInfo.sha256sum["sde.zip"] ?? ""

            // 格式化远程版本字符串
            let remoteVersion = updateInfo.patchNumber > 0 ?
                "\(updateInfo.sdeVersion).\(updateInfo.patchNumber)" :
                "\(updateInfo.sdeVersion)"

            // 更新详细信息
            currentSDEVersion = currentVersion
            latestSDEVersion = remoteVersion
            currentIconVersion = localIconVer
            latestIconVersion = updateInfo.iconVersion

            // 存储完整的SHA256哈希值（用于下载验证）
            latestIconsHashFull = remoteIcons
            latestSDEHashFull = remoteSDE

            // 存储 CloudKit Asset 引用
            latestIconsAsset = updateInfo.iconAsset
            latestSDEAsset = updateInfo.sdeAsset

            // 检查是否有更新
            let hasUpdate = await checkIfUpdateAvailable(
                remoteBuild: updateInfo.sdeVersion,
                remotePatch: updateInfo.patchNumber,
                remoteIconVersion: updateInfo.iconVersion
            )

            if hasUpdate {
                updateStatus = .hasUpdate
                updateVersion = remoteVersion
                Logger.info("发现数据包更新: 远程版本 \(remoteVersion)")
            } else {
                updateStatus = .noUpdate
                updateVersion = nil
                saveLastCheckTime() // 只有无更新时才保存时间
                Logger.info("数据包已是最新版本")
            }

        } catch {
            Logger.error("检查SDE更新失败: \(error)")
            updateStatus = .checkFailed
            updateVersion = nil
        }

        isChecking = false
    }

    // 检查是否有更新可用
    private func checkIfUpdateAvailable(remoteBuild: Int, remotePatch: Int, remoteIconVersion: Int) async -> Bool {
        // 一次性获取当前版本信息并比较
        let (currentBuild, currentPatch) = await getCurrentVersion()

        // 比较版本号
        let sdeHasUpdate = compareVersions(
            remoteBuild: remoteBuild,
            remotePatch: remotePatch,
            currentBuild: currentBuild,
            currentPatch: currentPatch
        )

        Logger.info("SDE版本比较: 当前 \(currentBuild).\(currentPatch) vs 远程 \(remoteBuild).\(remotePatch), 有更新: \(sdeHasUpdate)")

        // 检查图标版本更新
        let localIconVer = MetadataManager.shared.getLocalIconVersion()
        let iconsHasUpdate = MetadataManager.shared.compareIconVersion(local: localIconVer, remote: remoteIconVersion)

        Logger.info("Icons更新检查: 有更新: \(iconsHasUpdate)")

        // 只要SDE或icons任一有更新，就返回true
        return sdeHasUpdate || iconsHasUpdate
    }

    // 一次性获取当前版本（build_number 和 patch_number）
    private func getCurrentVersion() async -> (buildNumber: Int, patchNumber: Int) {
        return await Task.detached {
            let databaseManager = DatabaseManager.shared
            let query = "SELECT build_number, patch_number FROM version_info WHERE id = 1"

            if case let .success(results) = databaseManager.executeQuery(query, useCache: false),
               let row = results.first
            {
                let buildNumber = Int(self.getBuildNumber(from: row["build_number"]))
                let patchNumber = Int(self.getBuildNumber(from: row["patch_number"]))
                return (buildNumber, patchNumber)
            } else {
                Logger.warning("无法获取当前版本，使用默认值 0.0")
                return (0, 0)
            }
        }.value
    }

    // 获取当前SDE版本（字符串格式，用于UI显示）
    private func getCurrentSDEVersion() async -> String {
        let (buildNumber, patchNumber) = await getCurrentVersion()

        if patchNumber > 0 {
            return "\(buildNumber).\(patchNumber)"
        } else {
            return "\(buildNumber)"
        }
    }

    // 处理数值字段可能是Int、Double或String的情况
    private nonisolated func getBuildNumber(from value: Any?) -> Double {
        if let intValue = value as? Int {
            return Double(intValue)
        } else if let doubleValue = value as? Double {
            return doubleValue
        } else if let int64Value = value as? Int64 {
            return Double(int64Value)
        } else if let stringValue = value as? String, let doubleValue = Double(stringValue) {
            return doubleValue
        } else {
            Logger.warning("无法解析数值: \(String(describing: value))")
            return 0.0
        }
    }

    // 获取SHA256的前8位
    private func getShortHash(_ hash: String) -> String {
        return String(hash.prefix(8))
    }

    // 比较版本号（直接比较整数）
    private func compareVersions(remoteBuild: Int, remotePatch: Int, currentBuild: Int, currentPatch: Int) -> Bool {
        // 先比较 build_number
        if remoteBuild > currentBuild {
            return true
        } else if remoteBuild < currentBuild {
            return false
        }

        // build_number 相同，再比较 patch_number
        return remotePatch > currentPatch
    }
}

// SDE 更新状态枚举
enum SDEUpdateStatus {
    case notChecked // 未检查
    case checking // 正在检查
    case noUpdate // 无更新
    case hasUpdate // 有更新
    case checkFailed // 检查失败
}

// 远程更新信息结构
struct SDEUpdateInfo: Codable {
    let tag: String
    let sdeVersion: Int
    let patchNumber: Int
    let iconVersion: Int
    let sha256sum: [String: String]
    let zipUrls: [String: String]
    let updatedAt: String

    // CloudKit Asset 引用（不参与 Codable）
    var iconAsset: CKAsset?
    var sdeAsset: CKAsset?

    enum CodingKeys: String, CodingKey {
        case tag
        case sdeVersion = "sde_version"
        case patchNumber = "patch_number"
        case iconVersion = "icon_version"
        case sha256sum
        case zipUrls = "zip_urls"
        case updatedAt = "updated_at"
    }
}
