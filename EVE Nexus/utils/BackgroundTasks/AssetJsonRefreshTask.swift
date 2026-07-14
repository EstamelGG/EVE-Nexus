import Foundation

/// 资产JSON更新后台任务
/// 负责每4小时更新一次当前所选角色的资产JSON数据
/// 使用 BGProcessingTask 以获得更长的执行时间
@MainActor
class AssetJsonRefreshTask: BaseProcessingTask {
    static let identifier = "com.evenexus.assetjsonrefresh"
    static let interval: TimeInterval = 60 * 60 // 1小时

    init() {
        super.init(identifier: Self.identifier, interval: Self.interval)
    }

    override func perform() async {
        Logger.notice("开始执行后台资产JSON更新")

        // 获取当前所选角色ID
        let currentCharacterId = UserDefaults.standard.integer(forKey: "currentCharacterId")
        guard currentCharacterId != 0 else {
            Logger.info("没有当前所选角色，跳过资产JSON更新")
            return
        }

        // 检查角色是否存在且token未过期
        guard let characterAuth = EVELogin.shared.getCharacterByID(currentCharacterId) else {
            Logger.warning("找不到当前所选角色: \(currentCharacterId)")
            return
        }

        if characterAuth.character.refreshTokenExpired {
            Logger.warning("当前所选角色token已过期，跳过资产JSON更新: \(currentCharacterId)")
            return
        }

        // 检查任务是否被取消
        if Task.isCancelled {
            Logger.warning("资产JSON更新任务被取消")
            return
        }

        do {
            // 强制刷新资产JSON
            _ = try await CharacterAssetsJsonAPI.shared.generateAssetTree(
                characterId: currentCharacterId,
                forceRefresh: true
            )
            Logger.success("成功更新资产JSON: \(currentCharacterId)")
        } catch {
            Logger.error("更新资产JSON失败: \(currentCharacterId), 错误: \(error)")
        }
    }
}
