import Foundation
import Combine
import SwiftUI

actor HomePageDataManager {
    static let shared = HomePageDataManager()
    private var characterDataCache: [Int: EVECharacterInfo] = [:]
    private var characterPortraits: [Int: UIImage] = [:]
    private var corporationLogos: [Int: UIImage] = [:]
    private var allianceLogos: [Int: UIImage] = [:]
    
    // 发布订阅机制
    private let characterUpdateSubject = PassthroughSubject<(EVECharacterInfo, UIImage?, UIImage?, UIImage?), Never>()
    var characterUpdates: AnyPublisher<(EVECharacterInfo, UIImage?, UIImage?, UIImage?), Never> {
        characterUpdateSubject.eraseToAnyPublisher()
    }
    
    // 刷新角色数据
    func refreshCharacterData(characterId: Int, forceRefresh: Bool = false) async throws {
        Logger.info("开始刷新角色数据 - 角色ID: \(characterId)")
        
        // 获取基础信息
        let publicInfo = try await CharacterAPI.shared.fetchCharacterPublicInfo(
            characterId: characterId,
            forceRefresh: forceRefresh
        )
        
        // 并行获取所有需要的数据
        async let skillsTask = CharacterSkillsAPI.shared.fetchCharacterSkills(
            characterId: characterId,
            forceRefresh: forceRefresh
        )
        async let walletTask = CharacterWalletAPI.shared.getWalletBalance(
            characterId: characterId,
            forceRefresh: forceRefresh
        )
        async let locationTask = CharacterLocationAPI.shared.fetchCharacterLocation(
            characterId: characterId,
            forceRefresh: forceRefresh
        )
        async let skillQueueTask = CharacterSkillsAPI.shared.fetchSkillQueue(
            characterId: characterId,
            forceRefresh: forceRefresh
        )
        async let portraitTask = CharacterAPI.shared.fetchCharacterPortrait(
            characterId: characterId,
            forceRefresh: forceRefresh
        )
        
        // 获取军团和联盟信息
        async let corporationTask = CorporationAPI.shared.fetchCorporationInfo(
            corporationId: publicInfo.corporation_id,
            forceRefresh: forceRefresh
        )
        async let corporationLogoTask = CorporationAPI.shared.fetchCorporationLogo(
            corporationId: publicInfo.corporation_id,
            forceRefresh: forceRefresh
        )
        
        var allianceInfoTask: Task<AllianceInfo, Error>?
        var allianceLogoTask: Task<UIImage, Error>?
        
        if let allianceId = publicInfo.alliance_id {
            allianceInfoTask = Task {
                try await AllianceAPI.shared.fetchAllianceInfo(
                    allianceId: allianceId,
                    forceRefresh: forceRefresh
                )
            }
            allianceLogoTask = Task {
                try await AllianceAPI.shared.fetchAllianceLogo(
                    allianceID: allianceId,
                    forceRefresh: forceRefresh
                )
            }
        }
        
        do {
            // 等待所有并行任务完成
            let skills = try await skillsTask
            let balance = try await walletTask
            let location = try await locationTask
            let queue = try await skillQueueTask
            let portrait = try await portraitTask
            let corpInfo = try await corporationTask
            let corpLogo = try await corporationLogoTask
            
            // 获取位置详细信息
            let locationInfo = await getSolarSystemInfo(
                solarSystemId: location.solar_system_id,
                databaseManager: DatabaseManager()
            )
            
            // 构建更新后的角色信息
            let defaultCharacterData: [String: Any] = [
                "CharacterID": characterId,
                "CharacterName": publicInfo.name,
                "ExpiresOn": Date().ISO8601Format(),
                "Scopes": "",
                "TokenType": "Bearer",
                "CharacterOwnerHash": ""
            ]
            
            let defaultCharacter: EVECharacterInfo
            if let jsonData = try? JSONSerialization.data(withJSONObject: defaultCharacterData),
               let decodedCharacter = try? JSONDecoder().decode(EVECharacterInfo.self, from: jsonData) {
                defaultCharacter = decodedCharacter
            } else {
                throw NetworkError.invalidData
            }
            
            var updatedCharacter = characterDataCache[characterId] ?? 
                EVELogin.shared.getCharacterByID(characterId)?.character ?? 
                defaultCharacter
            
            // 更新基本信息
            updatedCharacter.corporationId = publicInfo.corporation_id
            updatedCharacter.allianceId = publicInfo.alliance_id
            updatedCharacter.totalSkillPoints = skills.total_sp
            updatedCharacter.unallocatedSkillPoints = skills.unallocated_sp
            updatedCharacter.walletBalance = balance
            updatedCharacter.locationStatus = location.locationStatus
            updatedCharacter.location = locationInfo
            updatedCharacter.skillQueueLength = queue.count
            
            // 更新技能队列信息
            if let currentSkill = queue.first(where: { $0.isCurrentlyTraining }) {
                updatedCharacter.currentSkill = EVECharacterInfo.CurrentSkillInfo(
                    skillId: currentSkill.skill_id,
                    name: SkillTreeManager.shared.getSkillName(for: currentSkill.skill_id) ?? "",
                    level: currentSkill.skillLevel,
                    progress: currentSkill.progress,
                    remainingTime: currentSkill.remainingTime
                )
                
                // 更新队列完成时间
                if let lastSkill = queue.last,
                   let finishTime = lastSkill.remainingTime {
                    updatedCharacter.queueFinishTime = finishTime
                }
            }
            
            // 更新缓存
            characterDataCache[characterId] = updatedCharacter
            characterPortraits[characterId] = portrait
            corporationLogos[publicInfo.corporation_id] = corpLogo
            
            var allianceLogo: UIImage? = nil
            if let allianceId = publicInfo.alliance_id {
                allianceLogo = try await allianceLogoTask?.value
                if let logo = allianceLogo {
                    allianceLogos[allianceId] = logo
                }
            }
            
            // 发布更新通知
            await MainActor.run {
                characterUpdateSubject.send((updatedCharacter, portrait, corpLogo, allianceLogo))
            }
            
            Logger.info("成功刷新角色数据 - 角色: \(updatedCharacter.CharacterName)")
            
        } catch {
            Logger.error("刷新角色数据失败 - 错误: \(error)")
            throw error
        }
    }
    
    // 获取缓存的数据
    func getCachedData(characterId: Int) -> (EVECharacterInfo?, UIImage?, UIImage?, UIImage?) {
        let character = characterDataCache[characterId]
        let portrait = characterPortraits[characterId]
        let corpLogo = character.flatMap { corporationLogos[$0.corporationId ?? 0] }
        let allianceLogo = character.flatMap { allianceLogos[$0.allianceId ?? 0] }
        return (character, portrait, corpLogo, allianceLogo)
    }
    
    // 清除缓存
    func clearCache(for characterId: Int) {
        characterDataCache.removeValue(forKey: characterId)
        characterPortraits.removeValue(forKey: characterId)
        // 注意：不清除军团和联盟图标缓存，因为可能被其他角色共用
    }
} 