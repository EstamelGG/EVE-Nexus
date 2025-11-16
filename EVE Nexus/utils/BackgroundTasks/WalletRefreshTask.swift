import Foundation

/// 钱包数据更新后台任务
/// 负责定期更新所有角色的钱包流水和交易数据
/// 使用 BGProcessingTask 以获得更长的执行时间
@MainActor
class WalletRefreshTask: BaseProcessingTask {
    static let identifier = "com.evenexus.walletrefresh"
    static let interval: TimeInterval = 60 * 60 // 1小时

    init() {
        super.init(identifier: Self.identifier, interval: Self.interval)
    }

    override func perform() async {
        Logger.notice("开始执行后台钱包数据更新")

        // 获取所有已登录的角色
        let allCharacterAuths = EVELogin.shared.loadCharacters()
        guard !allCharacterAuths.isEmpty else {
            Logger.info("没有已登录的角色，跳过钱包数据更新")
            return
        }

        // 获取所有有效的角色ID（token未过期的）
        var validCharacterIds: [Int] = []
        for characterAuth in allCharacterAuths {
            if !characterAuth.character.refreshTokenExpired {
                validCharacterIds.append(characterAuth.character.CharacterID)
            } else {
                Logger.warning("角色token已过期，跳过钱包数据更新: \(characterAuth.character.CharacterID)")
            }
        }

        guard !validCharacterIds.isEmpty else {
            Logger.info("没有有效的角色（token未过期），跳过钱包数据更新")
            return
        }

        Logger.info("准备更新 \(validCharacterIds.count) 个角色的钱包数据")

        // 遍历所有需要更新的角色
        for characterId in validCharacterIds {
            // 检查任务是否被取消
            if Task.isCancelled {
                Logger.warning("钱包数据更新任务被取消")
                return
            }

            // 检查角色是否存在且token未过期
            guard let characterAuth = EVELogin.shared.getCharacterByID(characterId) else {
                Logger.warning("找不到角色: \(characterId)，跳过钱包数据更新")
                continue
            }

            if characterAuth.character.refreshTokenExpired {
                Logger.warning("角色token已过期，跳过钱包数据更新: \(characterId)")
                continue
            }

            // 并发加载钱包流水和交易数据
            async let journalTask = loadWalletJournal(characterId: characterId)
            async let transactionsTask = loadWalletTransactions(characterId: characterId)

            // 等待两个任务完成
            let (journalResult, transactionsResult) = await (journalTask, transactionsTask)

            // 记录结果
            if journalResult {
                Logger.success("成功更新钱包流水数据: \(characterId)")
            } else {
                Logger.error("更新钱包流水数据失败: \(characterId)")
            }

            if transactionsResult {
                Logger.success("成功更新钱包交易数据: \(characterId)")
            } else {
                Logger.error("更新钱包交易数据失败: \(characterId)")
            }
        }

        Logger.success("后台钱包数据更新完成，共处理 \(validCharacterIds.count) 个角色")
    }

    /// 加载钱包流水数据
    private func loadWalletJournal(characterId: Int) async -> Bool {
        do {
            _ = try await WalletJournalAPI.shared.getWalletJournal(
                characterId: characterId,
                forceRefresh: true
            )
            return true
        } catch {
            Logger.error("加载钱包流水失败: \(characterId), 错误: \(error)")
            return false
        }
    }

    /// 加载钱包交易数据
    private func loadWalletTransactions(characterId: Int) async -> Bool {
        do {
            _ = try await WalletTransactionsAPI.shared.getWalletTransactions(
                characterId: characterId,
                forceRefresh: true
            )
            return true
        } catch {
            Logger.error("加载钱包交易失败: \(characterId), 错误: \(error)")
            return false
        }
    }
}
