import SwiftUI

/// 将装配缺失技能保存到新技能计划
enum AddFittingSkillsToPlanSheet {
    /// 保存缺失技能到新计划，返回保存的计划名称，失败返回 nil
    static func saveMissingSkillsToPlan(
        missingSkills: [(skillID: Int, requiredLevel: Int, currentLevel: Int, skillName: String)],
        characterId: Int,
        planName: String,
        databaseManager: DatabaseManager
    ) async -> String? {
        let name = planName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }

        var skillsToAdd: [(skillId: Int, skillName: String, level: Int)] = []
        var addedSkills: Set<Int> = []
        var skillLevels: [Int: Int] = [:]
        let currentSkillLevels = await getCurrentSkillLevels(characterId: characterId)

        for item in missingSkills {
            let collected = SkillPlanHelper.collectSkillsToAdd(
                skillId: item.skillID,
                skillName: item.skillName,
                targetLevel: item.requiredLevel,
                databaseManager: databaseManager,
                currentSkillLevels: currentSkillLevels,
                addedSkills: &addedSkills,
                skillLevels: &skillLevels
            )
            skillsToAdd.append(contentsOf: collected)
        }

        let correctedSkills = SkillQueueCorrector(databaseManager: databaseManager)
            .correctSkillQueue(inputSkills: skillsToAdd.map { ($0.skillId, $0.level) })

        let plannedSkills = correctedSkills.map { skill -> PlannedSkill in
            let skillName = SkillTreeManager.shared.getSkillName(for: skill.skillId)
                ?? "Unknown (\(skill.skillId))"
            return PlannedSkill(
                id: UUID(),
                skillID: skill.skillId,
                skillName: skillName,
                currentLevel: 0,
                targetLevel: skill.level,
                trainingTime: 0,
                requiredSP: 0,
                prerequisites: [],
                currentSkillPoints: nil,
                isCompleted: false
            )
        }

        let newPlan = SkillPlan(
            id: UUID(),
            name: name,
            skills: plannedSkills,
            totalTrainingTime: 0,
            totalSkillPoints: 0,
            lastUpdated: Date()
        )

        SkillPlanFileManager.shared.saveSkillPlan(characterId: characterId, plan: newPlan)
        return name
    }

    private static func getCurrentSkillLevels(characterId: Int) async -> [Int: Int] {
        guard characterId != 0 else { return [:] }
        do {
            let response = try await CharacterSkillsAPI.shared.fetchCharacterSkills(
                characterId: characterId,
                forceRefresh: false
            )
            return Dictionary(uniqueKeysWithValues: response.skillsMap.map { ($0.key, $0.value.trained_skill_level) })
        } catch {
            Logger.error("加载角色技能失败: \(error)")
            return [:]
        }
    }
}

/// 待添加技能管理器 - 用于装配页与技能计划页之间的数据传递（添加技能到已有计划时使用）
final class PendingFittingSkillsManager {
    static let shared = PendingFittingSkillsManager()

    private struct PendingData {
        let skills: [(skillId: Int, skillName: String, level: Int)]
        let characterId: Int
    }

    private var pending: [UUID: PendingData] = [:]

    private init() {}

    func setPending(skills: [(skillId: Int, skillName: String, level: Int)], forPlanId planId: UUID, characterId: Int) {
        pending[planId] = PendingData(skills: skills, characterId: characterId)
    }

    func consumePending(forPlanId planId: UUID) -> (skills: [(skillId: Int, skillName: String, level: Int)], characterId: Int)? {
        guard let data = pending[planId] else { return nil }
        pending.removeValue(forKey: planId)
        return (data.skills, data.characterId)
    }
}
