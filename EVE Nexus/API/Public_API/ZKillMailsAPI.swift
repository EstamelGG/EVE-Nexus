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
