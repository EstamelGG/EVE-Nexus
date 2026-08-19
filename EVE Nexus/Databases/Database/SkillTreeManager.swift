import Foundation

/// 技能要求结构
struct SkillRequirement: Hashable {
    let skillID: Int
    let name: String
    let level: Int
    let parentSkillID: Int?
    let timeMultiplier: Double?

    func hash(into hasher: inout Hasher) {
        hasher.combine(skillID)
        hasher.combine(parentSkillID)
    }

    static func == (lhs: SkillRequirement, rhs: SkillRequirement) -> Bool {
        lhs.skillID == rhs.skillID && lhs.parentSkillID == rhs.parentSkillID
    }
}

/// 技能树管理器
class SkillTreeManager {
    static let shared = SkillTreeManager()
    private init() {}

    /// 技能等级对应的基础点数
    static let levelBasePoints = [250, 1415, 8000, 45255, 256_000]

    /// 技能等级所需技能点（等级 1-5；倍率缺失或等级越界返回 nil）
    static func skillPoints(level: Int, multiplier: Double?) -> Int? {
        guard let multiplier,
              level > 0,
              level <= levelBasePoints.count
        else { return nil }
        return Int(Double(levelBasePoints[level - 1]) * multiplier)
    }

    /// [skillID: [(requiredSkillID, level)]]
    private var directRequirements: [Int: [(skillID: Int, level: Int)]] = [:]

    /// 训练主/副属性，对应 attribute 180/181
    private var skillTrainingAttributes: [Int: (primary: Int, secondary: Int)] = [:]

    /// 训练时间倍率，对应 attribute 275
    private var skillTimeMultipliers: [Int: Double] = [:]

    /// 技能要求的属性 ID 对应关系
    let skillRequirementAttributes: [(skillID: Int, levelID: Int)] = [
        (skillID: 182, levelID: 277),
        (skillID: 183, levelID: 278),
        (skillID: 184, levelID: 279),
        (skillID: 1285, levelID: 1286),
        (skillID: 1289, levelID: 1287),
        (skillID: 1290, levelID: 1288),
    ]

    /// 初始化并加载所有技能数据
    func initialize(databaseManager: DatabaseManager) {
        let requirementPairs = skillRequirementAttributes.map {
            "(ta1.attribute_id = \($0.skillID) AND ta2.attribute_id = \($0.levelID))"
        }.joined(separator: " OR ")

        let requirementQuery = """
            SELECT ta1.type_id,
                   ta1.attribute_id as skill_attr_id,
                   ta1.value as required_skill_id,
                   ta2.value as required_level
            FROM typeAttributes ta1
            JOIN typeAttributes ta2
            ON ta1.type_id = ta2.type_id
            WHERE ta1.type_id IN (SELECT type_id FROM types WHERE categoryID = 16)
            AND (\(requirementPairs))
        """

        if case let .success(rows) = databaseManager.executeQuery(requirementQuery) {
            for row in rows {
                guard let typeID = row["type_id"] as? Int,
                      let requiredSkillID = row["required_skill_id"] as? Double,
                      let requiredLevel = row["required_level"] as? Double
                else { continue }

                let skillID = Int(requiredSkillID)
                let level = Int(requiredLevel)

                if directRequirements[typeID] == nil {
                    directRequirements[typeID] = []
                }
                directRequirements[typeID]?.append((skillID: skillID, level: level))
            }
        }

        let trainingAttrQuery = """
            SELECT type_id, attribute_id, value
            FROM typeAttributes
            WHERE type_id IN (SELECT type_id FROM types WHERE categoryID = 16)
            AND attribute_id IN (180, 181, 275)
        """

        if case let .success(rows) = databaseManager.executeQuery(trainingAttrQuery) {
            var grouped: [Int: [Int: Int]] = [:]
            for row in rows {
                guard let typeID = row["type_id"] as? Int,
                      let attributeId = row["attribute_id"] as? Int,
                      let value = row["value"] as? Double
                else { continue }

                if attributeId == 275 {
                    skillTimeMultipliers[typeID] = value
                } else {
                    grouped[typeID, default: [:]][attributeId] = Int(value)
                }
            }

            for (typeID, attrs) in grouped {
                if let primary = attrs[180], let secondary = attrs[181] {
                    skillTrainingAttributes[typeID] = (primary, secondary)
                }
            }
        }

        Logger.debug(
            "技能树加载完成 - 有依赖: \(directRequirements.count), 训练属性: \(skillTrainingAttributes.count), 倍率: \(skillTimeMultipliers.count)"
        )
    }

    /// 获取技能的所有前置要求（包括递归依赖）
    func getAllRequirements(for skillID: Int, databaseManager: DatabaseManager? = nil)
        -> [SkillRequirement]
    {
        var result: [SkillRequirement] = []
        var visited = Set<Int>()
        var timeMultipliers: [Int: Double] = [:]

        func recursiveGetRequirements(for currentSkillID: Int, parentID: Int?) {
            guard !visited.contains(currentSkillID) else { return }
            visited.insert(currentSkillID)

            guard let requirements = directRequirements[currentSkillID] else { return }

            let skillIDs = requirements.map(\.skillID)
            for reqID in skillIDs where timeMultipliers[reqID] == nil {
                if let cached = skillTimeMultipliers[reqID] {
                    timeMultipliers[reqID] = cached
                }
            }

            if let db = databaseManager {
                let newSkillIDs = skillIDs.filter { timeMultipliers[$0] == nil }
                if !newSkillIDs.isEmpty {
                    timeMultipliers.merge(
                        getTrainingTimeMultipliers(for: newSkillIDs, databaseManager: db)
                    ) { current, _ in current }
                }
            }

            for (requiredSkillID, level) in requirements {
                guard let skillName = getSkillName(for: requiredSkillID) else { continue }
                result.append(
                    SkillRequirement(
                        skillID: requiredSkillID,
                        name: skillName,
                        level: level,
                        parentSkillID: parentID,
                        timeMultiplier: timeMultipliers[requiredSkillID]
                    )
                )
                recursiveGetRequirements(for: requiredSkillID, parentID: currentSkillID)
            }
        }

        recursiveGetRequirements(for: skillID, parentID: nil)
        return result
    }

    /// 获取技能的直接前置要求（内存缓存，无 SQL）
    func directSkillRequirements(for skillID: Int) -> [(skillID: Int, level: Int)] {
        directRequirements[skillID] ?? []
    }

    /// 获取技能的全部前置要求及所需最高等级（内存缓存，无 SQL）
    func prerequisiteMaxLevels(for skillID: Int) -> [Int: Int] {
        var skillMap: [Int: Int] = [:]
        for (reqID, level) in directSkillRequirements(for: skillID) {
            skillMap[reqID] = max(skillMap[reqID] ?? 0, level)
            for req in getAllRequirements(for: reqID, databaseManager: nil) {
                skillMap[req.skillID] = max(skillMap[req.skillID] ?? 0, req.level)
            }
        }
        return skillMap
    }

    /// 获取技能训练主/副属性（内存缓存，无 SQL）
    func trainingAttributes(for skillID: Int) -> (primary: Int, secondary: Int)? {
        skillTrainingAttributes[skillID]
    }

    /// 批量获取技能训练主/副属性（内存缓存，无 SQL）
    func trainingAttributes(forSkillIDs skillIDs: [Int]) -> [Int: (primary: Int, secondary: Int)] {
        var result: [Int: (primary: Int, secondary: Int)] = [:]
        for id in skillIDs {
            if let attrs = skillTrainingAttributes[id] {
                result[id] = attrs
            }
        }
        return result
    }

    /// 获取技能训练时间倍率（内存缓存，无 SQL）
    func trainingTimeMultiplier(for skillID: Int) -> Double? {
        skillTimeMultipliers[skillID]
    }

    /// 获取技能名称（按当前数据库语言从 SDEMemoryStore 解析）
    func getSkillName(for skillID: Int) -> String? {
        guard isSkill(skillID) else { return nil }
        let name = SDEMemoryStore.type(for: skillID)?.name
        return (name?.isEmpty == false) ? name : nil
    }

    /// 是否为技能（category 16）
    func isSkill(_ typeID: Int) -> Bool {
        SDEMemoryStore.type(for: typeID)?.categoryID == 16
    }

    /// 获取物品的所有技能要求（包括直接和间接技能）并去重
    func getDeduplicatedSkillRequirements(for typeID: Int, databaseManager: DatabaseManager) -> [(
        skillID: Int, level: Int, timeMultiplier: Double?
    )] {
        let directRequirements: [(skillID: Int, level: Int)]
        if isSkill(typeID) {
            directRequirements = self.directRequirements[typeID] ?? []
        } else {
            directRequirements = databaseManager.getDirectSkillRequirements(for: typeID)
        }

        let indirectRequirements = directRequirements.flatMap { requirement in
            getAllRequirements(for: requirement.skillID, databaseManager: databaseManager)
                .map { (skillID: $0.skillID, level: $0.level) }
        }

        var skillMap: [Int: Int] = [:]
        for requirement in directRequirements + indirectRequirements {
            if let existingLevel = skillMap[requirement.skillID] {
                skillMap[requirement.skillID] = max(existingLevel, requirement.level)
            } else {
                skillMap[requirement.skillID] = requirement.level
            }
        }

        let multipliers = getTrainingTimeMultipliers(
            for: Array(skillMap.keys),
            databaseManager: databaseManager
        )

        return skillMap.map {
            (skillID: $0.key, level: $0.value, timeMultiplier: multipliers[$0.key])
        }
        .sorted { first, second in
            if first.level == second.level {
                return first.skillID > second.skillID
            }
            return first.level > second.level
        }
    }

    /// 批量获取技能的训练时间倍增系数（技能优先读内存缓存）
    func getTrainingTimeMultipliers(for skillIDs: [Int], databaseManager: DatabaseManager)
        -> [Int: Double]
    {
        guard !skillIDs.isEmpty else { return [:] }

        var multipliers: [Int: Double] = [:]
        var missingIDs: [Int] = []
        for id in skillIDs {
            if let cached = skillTimeMultipliers[id] {
                multipliers[id] = cached
            } else {
                missingIDs.append(id)
            }
        }

        guard !missingIDs.isEmpty else { return multipliers }

        let placeholders = String(repeating: "?,", count: missingIDs.count).dropLast()
        let query = """
            SELECT type_id, value
            FROM typeAttributes
            WHERE type_id IN (\(placeholders))
            AND attribute_id = 275
        """

        if case let .success(rows) = databaseManager.executeQuery(query, parameters: missingIDs) {
            for row in rows {
                if let typeID = row["type_id"] as? Int,
                   let value = row["value"] as? Double
                {
                    multipliers[typeID] = value
                }
            }
        }

        return multipliers
    }
}

/// 技能需求统计：由需求列表 + 角色技能/属性一次性算出 SP 总量、缺口与预计训练时间
/// （技能要求页 SkillRequirementsView 与专精详情页 ShipMasteryDetailView 共用）
struct SkillRequirementStats {
    /// 全部要求等级的 SP 总和
    let totalPoints: Int
    /// 未达标部分还差的 SP（未登录角色时为 0）
    let missingPoints: Int
    /// 未达标技能按角色属性预计的总训练时间（秒）；无角色属性或无需训练时为 0
    let trainingTime: TimeInterval

    init(
        requirements: [(skillID: Int, level: Int, timeMultiplier: Double?)],
        characterSkills: [Int: Int],
        hasCharacter: Bool,
        attributes: CharacterAttributes?
    ) {
        var total = 0
        var missing = 0
        var unmetSkillIDs: [Int] = []

        for requirement in requirements {
            guard let requiredPoints = SkillTreeManager.skillPoints(
                level: requirement.level,
                multiplier: requirement.timeMultiplier
            ) else { continue }
            total += requiredPoints

            guard hasCharacter else { continue }
            let currentLevel = characterSkills[requirement.skillID] ?? 0
            guard currentLevel < requirement.level else { continue }

            unmetSkillIDs.append(requirement.skillID)
            let currentSP = currentLevel > 0
                ? (SkillTreeManager.skillPoints(
                    level: currentLevel,
                    multiplier: requirement.timeMultiplier
                ) ?? 0)
                : 0
            missing += max(0, requiredPoints - currentSP)
        }

        totalPoints = total
        missingPoints = missing

        guard let attributes, !unmetSkillIDs.isEmpty else {
            trainingTime = 0
            return
        }

        let skillAttributesMap = SkillTreeManager.shared.trainingAttributes(
            forSkillIDs: unmetSkillIDs
        )
        var totalTime: TimeInterval = 0
        for requirement in requirements {
            guard (characterSkills[requirement.skillID] ?? 0) < requirement.level,
                  let skillAttrs = skillAttributesMap[requirement.skillID],
                  let requiredPoints = SkillTreeManager.skillPoints(
                      level: requirement.level,
                      multiplier: requirement.timeMultiplier
                  )
            else { continue }

            let currentLevel = characterSkills[requirement.skillID] ?? 0
            let currentSP = currentLevel > 0
                ? (SkillTreeManager.skillPoints(
                    level: currentLevel,
                    multiplier: requirement.timeMultiplier
                ) ?? 0)
                : 0
            let missingSP = requiredPoints - currentSP

            guard missingSP > 0,
                  let pointsPerHour = SkillTrainingCalculator.calculateTrainingRate(
                      primaryAttrId: skillAttrs.primary,
                      secondaryAttrId: skillAttrs.secondary,
                      attributes: attributes
                  ),
                  pointsPerHour > 0
            else { continue }

            totalTime += Double(missingSP) / Double(pointsPerHour) * 3600
        }
        trainingTime = totalTime
    }

    /// footer 文案：共 X SP（有缺口时附 ", 需: Y SP"）
    var footerText: String {
        let total =
            "\(NSLocalizedString("Misc_InAll", comment: "")): \(FormatUtil.format(Double(totalPoints))) SP"
        guard missingPoints > 0 else { return total }
        return "\(total), \(NSLocalizedString("Misc_Need", comment: "")): \(FormatUtil.format(Double(missingPoints))) SP"
    }
}
