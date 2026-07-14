import Foundation

/// 技能训练速度计算器
enum SkillTrainingCalculator {
    /// 属性ID常量
    enum AttributeID {
        static let charisma = 164
        static let intelligence = 165
        static let memory = 166
        static let perception = 167
        static let willpower = 168
    }

    /// 植入体属性ID常量
    private enum ImplantAttributeID {
        static let charisma = 175 // 魅力加成
        static let intelligence = 176 // 智力加成
        static let memory = 177 // 记忆加成
        static let perception = 178 // 感知加成
        static let willpower = 179 // 意志加成
    }

    /// 最优属性分配结果
    struct OptimalAttributes {
        let charisma: Int
        let intelligence: Int
        let memory: Int
        let perception: Int
        let willpower: Int
        let totalTrainingTime: TimeInterval
        let currentTrainingTime: TimeInterval
    }

    /// 技能训练信息
    private struct SkillTrainingInfo {
        let skillId: Int
        let remainingSP: Int
        let primaryAttr: Int
        let secondaryAttr: Int
    }

    /// 批量获取技能主/副属性（优先技能树内存缓存）
    static func loadSkillAttributes(
        skillIds: [Int],
        databaseManager _: DatabaseManager
    ) -> [Int: (primary: Int, secondary: Int)] {
        SkillTreeManager.shared.trainingAttributes(forSkillIDs: skillIds)
    }

    /// 获取技能的训练属性（优先技能树内存缓存）
    static func getSkillAttributes(skillId: Int, databaseManager _: DatabaseManager) -> (
        primary: Int, secondary: Int
    )? {
        SkillTreeManager.shared.trainingAttributes(for: skillId)
    }

    /// 获取植入体属性加成
    static func getImplantBonuses(characterId: Int, forceRefresh: Bool = false) async
        -> ImplantAttributes
    {
        var bonuses = ImplantAttributes()

        do {
            let implants = try await CharacterImplantsAPI.shared.fetchCharacterImplants(
                characterId: characterId,
                forceRefresh: forceRefresh
            )

            if !implants.isEmpty {
                let query = """
                    SELECT type_id, attribute_id, value
                    FROM typeAttributes
                    WHERE type_id IN (\(implants.map { String($0) }.joined(separator: ",")))
                    AND attribute_id IN (\(ImplantAttributeID.charisma), \(ImplantAttributeID.intelligence),
                                      \(ImplantAttributeID.memory), \(ImplantAttributeID.perception),
                                      \(ImplantAttributeID.willpower))
                """

                if case let .success(rows) = DatabaseManager.shared.executeQuery(query) {
                    var maxBonuses: [Int: Int] = [:]
                    for row in rows {
                        guard let attributeId = row["attribute_id"] as? Int,
                              let value = row["value"] as? Double
                        else { continue }
                        maxBonuses[attributeId] = max(maxBonuses[attributeId] ?? 0, Int(value))
                    }
                    bonuses.charismaBonus = maxBonuses[ImplantAttributeID.charisma] ?? 0
                    bonuses.intelligenceBonus = maxBonuses[ImplantAttributeID.intelligence] ?? 0
                    bonuses.memoryBonus = maxBonuses[ImplantAttributeID.memory] ?? 0
                    bonuses.perceptionBonus = maxBonuses[ImplantAttributeID.perception] ?? 0
                    bonuses.willpowerBonus = maxBonuses[ImplantAttributeID.willpower] ?? 0
                }
            }
        } catch {
            Logger.error("获取植入体信息失败: \(error)")
        }

        return bonuses
    }

    /// 检测加速器提供的属性加成值
    static func detectBoosterBonus(
        currentAttributes: CharacterAttributes,
        implantBonuses: ImplantAttributes
    ) -> Int {
        let totalAttributes =
            currentAttributes.charisma + currentAttributes.intelligence + currentAttributes.memory
                + currentAttributes.perception + currentAttributes.willpower
        let totalImplantBonuses =
            implantBonuses.charismaBonus + implantBonuses.intelligenceBonus
                + implantBonuses.memoryBonus + implantBonuses.perceptionBonus
                + implantBonuses.willpowerBonus
        // (总属性 − 基础 85 − 可分配 14 − 植入体) ÷ 5
        let boosterBonus = (totalAttributes - 85 - 14 - totalImplantBonuses) / 5
        return max(0, boosterBonus)
    }

    /// 计算最优属性分配
    /// - Parameters:
    ///   - skillQueue: 技能队列信息数组，每个元素包含：技能ID、剩余SP、开始训练时间、结束训练时间
    ///   - databaseManager: 数据库管理器
    ///   - currentAttributes: 当前角色属性
    ///   - characterId: 角色ID
    ///   - implantBonuses: 已缓存的植入体加成；传入时不再请求 ESI
    ///   - skillAttributes: 已缓存的技能主/副属性；传入时不再查询 DB
    ///   - boosterBonus: 已算好的加速器加成；传入时不再重复 detect
    /// - Returns: 最优属性分配结果
    static func calculateOptimalAttributes(
        skillQueue: [(skillId: Int, remainingSP: Int, startDate: Date?, finishDate: Date?)],
        databaseManager: DatabaseManager,
        currentAttributes: CharacterAttributes,
        characterId: Int,
        implantBonuses providedBonuses: ImplantAttributes? = nil,
        skillAttributes providedAttributes: [Int: (primary: Int, secondary: Int)]? = nil,
        boosterBonus providedBooster: Int? = nil
    ) async -> OptimalAttributes? {
        let implantBonuses: ImplantAttributes
        if let providedBonuses {
            implantBonuses = providedBonuses
        } else {
            implantBonuses = await getImplantBonuses(characterId: characterId)
        }

        let boosterBonus =
            providedBooster
                ?? detectBoosterBonus(
                    currentAttributes: currentAttributes,
                    implantBonuses: implantBonuses
                )

        var skillTrainingInfo: [SkillTrainingInfo] = []

        var skillAttributes = providedAttributes ?? [:]
        let missingIds = Set(skillQueue.map(\.skillId)).subtracting(skillAttributes.keys)
        if !missingIds.isEmpty {
            skillAttributes.merge(
                loadSkillAttributes(skillIds: Array(missingIds), databaseManager: databaseManager)
            ) { _, new in new }
        }

        // 处理每个技能的训练信息
        for skill in skillQueue {
            guard let attrs = skillAttributes[skill.skillId] else {
                continue
            }

            var remainingSP = skill.remainingSP

            // 如果技能正在训练，计算实际剩余SP
            if let startDate = skill.startDate,
               let finishDate = skill.finishDate
            {
                let now = Date()
                if now > startDate, now < finishDate {
                    let totalTrainingTime = finishDate.timeIntervalSince(startDate)
                    let trainedTime = now.timeIntervalSince(startDate)
                    let progress = trainedTime / totalTrainingTime
                    remainingSP = Int(Double(remainingSP) * (1 - progress))
                }
            }

            skillTrainingInfo.append(
                SkillTrainingInfo(
                    skillId: skill.skillId,
                    remainingSP: remainingSP,
                    primaryAttr: attrs.primary,
                    secondaryAttr: attrs.secondary
                )
            )
        }

        // 如果没有需要训练的技能，返回nil
        if skillTrainingInfo.isEmpty {
            return nil
        }

        // 计算当前属性下的训练时间(去掉加速器影响，保留植入体)
        var currentTime: TimeInterval = 0
        let currentAttributesWithoutBooster = CharacterAttributes(
            charisma: currentAttributes.charisma - boosterBonus,
            intelligence: currentAttributes.intelligence - boosterBonus,
            memory: currentAttributes.memory - boosterBonus,
            perception: currentAttributes.perception - boosterBonus,
            willpower: currentAttributes.willpower - boosterBonus,
            bonus_remaps: currentAttributes.bonus_remaps,
            accrued_remap_cooldown_date: currentAttributes.accrued_remap_cooldown_date,
            last_remap_date: currentAttributes.last_remap_date
        )

        for info in skillTrainingInfo {
            if let pointsPerHour = calculateTrainingRate(
                primaryAttrId: info.primaryAttr,
                secondaryAttrId: info.secondaryAttr,
                attributes: currentAttributesWithoutBooster // 使用去掉加速器影响的属性
            ) {
                let trainingTimeHours = Double(info.remainingSP) / Double(pointsPerHour)
                currentTime += trainingTimeHours * 3600
            }
        }

        // 定义属性范围和可用点数
        let minAttr = 17
        let maxAttr = 27
        let availablePoints = 14
        let maxBonus = maxAttr - minAttr // 每个属性最多加 10 点

        // 属性索引：0=感知 1=记忆 2=意志 3=智力 4=魅力
        // (与 CharacterAttributes 字段的映射在 totalTrainingTime 和返回值中使用)

        /// 计算给定属性加成分配下的总训练时间
        /// - Parameter bonuses: 5 个属性的加成点数数组
        func totalTrainingTime(bonuses: [Int]) -> TimeInterval {
            let attrs = CharacterAttributes(
                charisma: minAttr + bonuses[4] + implantBonuses.charismaBonus,
                intelligence: minAttr + bonuses[3] + implantBonuses.intelligenceBonus,
                memory: minAttr + bonuses[1] + implantBonuses.memoryBonus,
                perception: minAttr + bonuses[0] + implantBonuses.perceptionBonus,
                willpower: minAttr + bonuses[2] + implantBonuses.willpowerBonus,
                bonus_remaps: 0,
                accrued_remap_cooldown_date: nil,
                last_remap_date: nil
            )

            var total: TimeInterval = 0
            for info in skillTrainingInfo {
                if let rate = calculateTrainingRate(
                    primaryAttrId: info.primaryAttr,
                    secondaryAttrId: info.secondaryAttr,
                    attributes: attrs
                ) {
                    total += Double(info.remainingSP) / Double(rate) * 3600
                }
            }
            return total
        }

        // 枚举所有合法的 14 点分配方案（每个属性 0~10），找出总训练时间最短的
        // 组合数约 2885 种，每种评估 O(队列长度)，总计算量在微秒级
        var bestBonuses = [0, 0, 0, 0, 0]
        var bestTime = totalTrainingTime(bonuses: bestBonuses)
        var current = [0, 0, 0, 0, 0]

        func enumerate(_ index: Int, _ remaining: Int) {
            // 剪枝：剩余点数超出剩余属性可吸收的容量
            guard remaining <= (5 - index) * maxBonus else { return }

            if index == 4 {
                current[4] = remaining
                let time = totalTrainingTime(bonuses: current)
                if time < bestTime {
                    bestTime = time
                    bestBonuses = current
                }
                current[4] = 0
                return
            }

            for p in 0 ... min(remaining, maxBonus) {
                current[index] = p
                enumerate(index + 1, remaining - p)
            }
            current[index] = 0
        }

        enumerate(0, availablePoints)

        // 返回最优属性分配结果，不包含植入体加成
        return OptimalAttributes(
            charisma: minAttr + bestBonuses[4],
            intelligence: minAttr + bestBonuses[3],
            memory: minAttr + bestBonuses[1],
            perception: minAttr + bestBonuses[0],
            willpower: minAttr + bestBonuses[2],
            totalTrainingTime: bestTime,
            currentTrainingTime: currentTime
        )
    }

    /// 计算技能训练速度（每小时技能点数）
    /// - Parameters:
    ///   - primaryAttrId: 主属性ID
    ///   - secondaryAttrId: 副属性ID
    ///   - attributes: 角色属性
    /// - Returns: 每小时训练点数，如果属性无效则返回nil
    static func calculateTrainingRate(
        primaryAttrId: Int,
        secondaryAttrId: Int,
        attributes: CharacterAttributes
    ) -> Int? {
        func getAttributeValue(_ attrId: Int) -> Int {
            switch attrId {
            case AttributeID.charisma: return attributes.charisma
            case AttributeID.intelligence: return attributes.intelligence
            case AttributeID.memory: return attributes.memory
            case AttributeID.perception: return attributes.perception
            case AttributeID.willpower: return attributes.willpower
            default: return 0
            }
        }

        let primaryValue = getAttributeValue(primaryAttrId)
        let secondaryValue = getAttributeValue(secondaryAttrId)

        // 每分钟训练点数 = 主属性 + 副属性/2
        let pointsPerMinute = Double(primaryValue) + Double(secondaryValue) / 2.0
        // 转换为每小时
        return Int(pointsPerMinute * 60)
    }
}
