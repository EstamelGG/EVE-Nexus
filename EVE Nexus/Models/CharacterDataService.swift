import Foundation
import UIKit

/// 角色数据服务类
class CharacterDataService {
    static let shared = CharacterDataService()
    let databaseManager = DatabaseManager()
    private init() {}

    // MARK: - 基础信息

    /// 获取服务器状态
    func getServerStatus(forceRefresh: Bool = false) async throws -> ServerStatus {
        return try await ServerStatusAPI.shared.fetchServerStatus(forceRefresh: forceRefresh)
    }

    /// 获取角色头像
    func getCharacterPortrait(id: Int, forceRefresh: Bool = false) async throws -> UIImage {
        return try await CharacterAPI.shared.fetchCharacterPortrait(
            characterId: id, forceRefresh: forceRefresh
        )
    }

    // MARK: - 状态信息

    /// 获取钱包余额
    func getWalletBalance(id: Int, forceRefresh: Bool = false) async throws -> Double {
        return try await CharacterWalletAPI.shared.getWalletBalance(
            characterId: id, forceRefresh: forceRefresh
        )
    }

    /// 获取技能信息
    func getSkillInfo(id: Int, forceRefresh: Bool = false) async throws -> (
        skills: CharacterSkillsResponse, queue: [SkillQueueItem]
    ) {
        async let skills = CharacterSkillsAPI.shared.fetchCharacterSkills(
            characterId: id, forceRefresh: forceRefresh
        )
        async let queue = CharacterSkillsAPI.shared.fetchSkillQueue(
            characterId: id, forceRefresh: forceRefresh
        )
        return try await (skills, queue)
    }

    /// 获取位置信息
    func getLocation(id: Int, forceRefresh: Bool = false) async throws -> CharacterLocation {
        return try await CharacterLocationAPI.shared.fetchCharacterLocation(
            characterId: id, forceRefresh: forceRefresh
        )
    }

    /// 获取克隆状态
    func getCloneStatus(id: Int, forceRefresh: Bool = false) async throws -> CharacterCloneInfo {
        return try await CharacterClonesAPI.shared.fetchCharacterClones(
            characterId: id, forceRefresh: forceRefresh
        )
    }

    // MARK: - 市场信息

    /// 获取市场价格数据
    func getMarketPrices(forceRefresh: Bool = false) async throws -> [MarketPrice] {
        return try await MarketPricesAPI.shared.fetchMarketPrices(forceRefresh: forceRefresh)
    }
}
