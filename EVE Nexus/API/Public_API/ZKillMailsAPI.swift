import Foundation

// MARK: - 战斗统计相关结构体

struct CharBattleIsk: Codable {
    let iskDestroyed: Double
    let iskLost: Double

    enum CodingKeys: String, CodingKey {
        case iskDestroyed = "s-a-id"
        case iskLost = "s-a-il"
    }
}

class ZKillMailsAPI {
    static let shared = ZKillMailsAPI()

    // 通知名称常量
    static let killmailsUpdatedNotification = "KillmailsUpdatedNotification"
    static let killmailsUpdatedIdKey = "UpdatedId"
    static let killmailsUpdatedTypeKey = "UpdatedType"

    private let lastKillmailsQueryKey = "LastKillmailsQuery_"
    private let cacheTimeout: TimeInterval = 8 * 3600  // 8小时缓存有效期
    private let maxPages = 20  // zKillboard最大页数限制

    private init() {}

    // 获取角色战斗统计信息
    public func fetchCharacterStats(characterId: Int) async throws -> CharBattleIsk {
        let url = URL(
            string: "https://zkillboard.com/cache/1hour/stats/?type=characterID&id=\(characterId)")!

        Logger.info("开始获取角色战斗统计信息 - ID: \(characterId)")
        let data = try await NetworkManager.shared.fetchData(from: url)

        do {
            let stats = try JSONDecoder().decode(CharBattleIsk.self, from: data)
            Logger.info("成功获取角色战斗统计信息")
            return stats
        } catch {
            Logger.error("解析角色战斗统计信息失败: \(error)")
            throw error
        }
    }
}
