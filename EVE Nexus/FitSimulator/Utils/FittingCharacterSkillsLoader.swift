import Foundation

/// 装配模拟中「人物技能」的单一入口：同步读偏好、异步拉取与队列合并。
enum FittingCharacterSkillsLoader {
    private static let skillsModeKey = "skillsModePreference"
    private static let selectedSkillCharacterKey = "selectedSkillCharacterId"
    private static let currentCharacterKey = "currentCharacterId"

    /// 与全局 `UserDefaults` 技能模式一致，供装配 `init` 使用（同步、不阻塞；缓存未命中时行为与 `CharacterSkillsUtils` 一致）。
    static func skillsFromUserPreferences() -> [Int: Int] {
        let type = resolveCharacterSkillsTypeFromPreferences()
        let skills = CharacterSkillsUtils.getCharacterSkills(type: type)
        Logger.info("装配技能(偏好): \(skills.count) 条")
        return skills
    }

    /// 偏好为「当前人物」或「指定人物」且账号有效时返回角色 ID；虚拟档位返回 `nil`（无需异步补全）。
    static func liveCharacterIdForAsyncRefresh() -> Int? {
        let mode = UserDefaults.standard.string(forKey: skillsModeKey) ?? "current_char"
        switch mode {
        case "current_char":
            let id = UserDefaults.standard.integer(forKey: currentCharacterKey)
            return id != 0 ? id : nil
        case "character":
            let id = UserDefaults.standard.integer(forKey: selectedSkillCharacterKey)
            guard id != 0,
                  let auth = EVELogin.shared.getCharacterByID(id),
                  !auth.character.refreshTokenExpired
            else { return nil }
            return id
        default:
            return nil
        }
    }

    /// 进入装配模拟前调用：**真实人物**先异步拉取合并技能再参与 `localFittingToSimulationInput`；**虚拟档位**仍走同步 `skillsFromUserPreferences()`。网络失败时回退同步偏好。
    static func loadSkillsBeforeFittingCalculation() async -> [Int: Int] {
        if let cid = liveCharacterIdForAsyncRefresh() {
            do {
                let skills = try await fetchMergedSkills(characterId: cid)
                Logger.info("装配：已异步加载人物技能 \(skills.count) 条 (角色 \(cid))")
                return skills
            } catch {
                Logger.error("装配：异步加载人物技能失败，回退同步偏好: \(error)")
                return skillsFromUserPreferences()
            }
        }
        return skillsFromUserPreferences()
    }

    /// 技能选择器与装配页「打开后补全」共用：`fetchCharacterSkillsAndQueue` + 队列合并。
    static func fetchMergedSkills(characterId: Int) async throws -> [Int: Int] {
        let (skillsResponse, queue) = try await CharacterSkillsAPI.shared.fetchCharacterSkillsAndQueue(
            characterId: characterId,
            forceRefresh: false
        )
        let baseSkills = Dictionary(
            uniqueKeysWithValues: skillsResponse.skillsMap.map { ($0.key, $0.value.trained_skill_level) }
        )
        return CharacterSkillsUtils.mergeCompletedQueueIntoSkills(baseSkills: baseSkills, queue: queue)
    }

    private static func resolveCharacterSkillsTypeFromPreferences() -> CharacterSkillsType {
        let skillsMode = UserDefaults.standard.string(forKey: skillsModeKey) ?? "current_char"
        switch skillsMode {
        case "all5": return .all5
        case "all4": return .all4
        case "all3": return .all3
        case "all2": return .all2
        case "all1": return .all1
        case "all0": return .all0
        case "character":
            let charId = UserDefaults.standard.integer(forKey: selectedSkillCharacterKey)
            if charId != 0,
               let characterAuth = EVELogin.shared.getCharacterByID(charId),
               !characterAuth.character.refreshTokenExpired
            {
                Logger.info("装配技能(偏好): 指定角色 \(charId)")
                return .character(charId)
            }
            if charId != 0 {
                if EVELogin.shared.getCharacterByID(charId) == nil {
                    Logger.warning("装配技能(偏好): 指定角色不存在 (\(charId))，改为 all5")
                } else {
                    Logger.warning("装配技能(偏好): 指定角色 token 过期 (\(charId))，改为 all5")
                }
            }
            UserDefaults.standard.removeObject(forKey: selectedSkillCharacterKey)
            UserDefaults.standard.set("all5", forKey: skillsModeKey)
            UserDefaults.standard.synchronize()
            return .all5
        default:
            return .current_char
        }
    }
}
