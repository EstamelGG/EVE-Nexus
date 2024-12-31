import Foundation
import UIKit

/// 角色数据服务类
class CharacterDataService {
    static let shared = CharacterDataService()
    private init() {}
    
    // MARK: - 基础信息
    /// 获取服务器状态
    func getServerStatus() async throws -> ServerStatus {
        return try await ServerStatusAPI.shared.fetchServerStatus()
    }
    
    /// 获取角色基本信息
    func getCharacterInfo(id: Int) async throws -> CharacterPublicInfo {
        return try await CharacterAPI.shared.fetchCharacterPublicInfo(characterId: id)
    }
    
    /// 获取角色头像
    func getCharacterPortrait(id: Int) async throws -> UIImage {
        return try await CharacterAPI.shared.fetchCharacterPortrait(characterId: id)
    }
    
    // MARK: - 组织信息
    /// 获取军团信息
    func getCorporationInfo(id: Int) async throws -> (info: CorporationInfo, logo: UIImage) {
        async let info = CorporationAPI.shared.fetchCorporationInfo(corporationId: id)
        async let logo = CorporationAPI.shared.fetchCorporationLogo(corporationId: id)
        return try await (info, logo)
    }
    
    /// 获取联盟信息
    func getAllianceInfo(id: Int) async throws -> (info: AllianceInfo, logo: UIImage) {
        async let info = AllianceAPI.shared.fetchAllianceInfo(allianceId: id)
        async let logo = AllianceAPI.shared.fetchAllianceLogo(allianceID: id)
        return try await (info, logo)
    }
    
    // MARK: - 状态信息
    /// 获取钱包余额
    func getWalletBalance(id: Int) async throws -> Double {
        return try await CharacterWalletAPI.shared.getWalletBalance(characterId: id)
    }
    
    /// 获取技能信息
    func getSkillInfo(id: Int) async throws -> (skills: CharacterSkillsResponse, queue: [SkillQueueItem]) {
        async let skills = CharacterSkillsAPI.shared.fetchCharacterSkills(characterId: id)
        async let queue = CharacterSkillsAPI.shared.fetchSkillQueue(characterId: id)
        return try await (skills, queue)
    }
    
    /// 获取位置信息
    func getLocation(id: Int) async throws -> CharacterLocation {
        return try await CharacterLocationAPI.shared.fetchCharacterLocation(characterId: id)
    }
    
    /// 获取克隆状态
    func getCloneStatus(id: Int) async throws -> CharacterCloneInfo {
        return try await CharacterClonesAPI.shared.fetchCharacterClones(characterId: id)
    }
} 