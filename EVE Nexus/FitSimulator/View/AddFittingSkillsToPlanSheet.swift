import SwiftUI

/// 将装配技能保存到新技能计划
enum AddFittingSkillsToPlanSheet {
    /// 保存装配所需全部技能到新计划（含已满足和未满足的技能，生成完整队列）
    /// - Parameters:
    ///   - requiredSkills: 装配所需的全部技能（含飞船、装备、弹药、无人机、货舱、舰载机）
    ///   - characterId: 角色ID
    ///   - planName: 计划名称
    ///   - databaseManager: 数据库管理器
    /// - Returns: 保存的计划名称，失败返回 nil
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

        // 待训练技能
        var plannedSkills = correctedSkills.map { skill -> PlannedSkill in
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

        // 已满足的技能也加入队列（作为完整清单）
        let completedSkills = missingSkills
            .filter { $0.currentLevel >= $0.requiredLevel }
            .sorted { $0.skillID < $1.skillID }
        for item in completedSkills {
            plannedSkills.insert(
                PlannedSkill(
                    id: UUID(),
                    skillID: item.skillID,
                    skillName: item.skillName,
                    currentLevel: item.requiredLevel,
                    targetLevel: item.requiredLevel,
                    trainingTime: 0,
                    requiredSP: 0,
                    prerequisites: [],
                    currentSkillPoints: nil,
                    isCompleted: true
                ),
                at: 0
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
            let (response, queue) = try await CharacterSkillsAPI.shared.fetchCharacterSkillsAndQueue(
                characterId: characterId,
                forceRefresh: false
            )
            let baseSkills = Dictionary(uniqueKeysWithValues: response.skillsMap.map { ($0.key, $0.value.trained_skill_level) })
            return CharacterSkillsUtils.mergeCompletedQueueIntoSkills(baseSkills: baseSkills, queue: queue)
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
