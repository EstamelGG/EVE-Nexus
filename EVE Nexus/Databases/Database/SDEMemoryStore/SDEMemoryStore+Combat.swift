import Foundation

/// 舰载机能力 / 指挥脉冲波 buff / 专精认证 加载与查询
extension SDEMemoryStore {
    static func loadFighterAbilities(_ db: DatabaseManager) {
        var cache: [Int: [FighterAbilityInfo]] = [:]
        if case let .success(rows) = db.executeQuery(
            """
            SELECT type_id, slot, ability_id, name, description,
                   cooldown_seconds, charge_count, rearm_time_seconds, icon_filename
            FROM fighterAbilities
            ORDER BY type_id, slot
            """,
            useCache: false
        ) {
            for row in rows {
                guard let typeID = row["type_id"] as? Int,
                      let slot = row["slot"] as? Int,
                      let abilityID = row["ability_id"] as? Int
                else { continue }
                cache[typeID, default: []].append(
                    FighterAbilityInfo(
                        slot: slot,
                        abilityID: abilityID,
                        name: (row["name"] as? String) ?? "",
                        description: (row["description"] as? String) ?? "",
                        cooldownSeconds: row["cooldown_seconds"] as? Int,
                        chargeCount: row["charge_count"] as? Int,
                        rearmTimeSeconds: row["rearm_time_seconds"] as? Int,
                        iconFilename: (row["icon_filename"] as? String) ?? ""
                    )
                )
            }
        }
        fighterAbilities = cache
    }

    // MARK: - 指挥脉冲波 / 作战链 buff

    static func loadWarfareBuffs(_ db: DatabaseManager) {
        var cache: [Int: [Int: WarfareBuffInfo]] = [:]

        // 复合键 (dbuff_id, type_id)：type_id 指向使用该 buff 定义的物品（弹药/泰坦/天气等场景隔离）
        if case let .success(rows) = db.executeQuery(
            """
            SELECT dbuff_id, type_id, de_name, en_name, es_name, fr_name, ja_name, ko_name, ru_name, zh_name
            FROM dbuffCollection
            """,
            useCache: false
        ) {
            for row in rows {
                guard let buffID = row["dbuff_id"] as? Int,
                      let typeID = row["type_id"] as? Int
                else { continue }
                cache[buffID, default: [:]][typeID] = WarfareBuffInfo(
                    buffID: buffID,
                    displayNames: LocalizedText.from(row: row)
                )
            }
        }
        warfareBuffs = cache
    }

    /// 加载专精静态数据（masteries / certificateSkills 表，旧 SDE 缺表时保持为空自然降级）
    static func loadMasteryData(_ db: DatabaseManager) {
        var certSkills: [Int: [CertificateSkillRequirement]] = [:]

        if case let .success(rows) = db.executeQuery(
            """
            SELECT certificateID, skillID, basic, standard, improved, advanced, elite
            FROM certificateSkills
            """,
            useCache: false
        ) {
            for row in rows {
                guard let certificateID = row["certificateID"] as? Int,
                      let skillID = row["skillID"] as? Int
                else { continue }

                let tiers = ["basic", "standard", "improved", "advanced", "elite"].compactMap {
                    row[$0] as? Int
                }
                guard tiers.count == 5 else { continue }

                certSkills[certificateID, default: []].append(
                    CertificateSkillRequirement(skillID: skillID, tierLevels: tiers)
                )
            }
        }
        certificateSkills = certSkills

        var masteryCerts: [Int: [Int: Set<Int>]] = [:]
        if case let .success(rows) = db.executeQuery(
            """
            SELECT typeid, masteryLevel, certificateID
            FROM masteries
            """,
            useCache: false
        ) {
            for row in rows {
                guard let typeID = row["typeid"] as? Int,
                      let masteryLevel = row["masteryLevel"] as? Int,
                      let certificateID = row["certificateID"] as? Int,
                      (1 ... 5).contains(masteryLevel)
                else { continue }

                masteryCerts[typeID, default: [:]][masteryLevel, default: []].insert(certificateID)
            }
        }
        shipMasteryCerts = masteryCerts

        var certNames: [Int: LocalizedText] = [:]
        if case let .success(rows) = db.executeQuery(
            """
            SELECT certificateID, de_name, en_name, es_name, fr_name, ja_name, ko_name, ru_name, zh_name
            FROM certificates
            """,
            useCache: false
        ) {
            for row in rows {
                guard let certificateID = row["certificateID"] as? Int else { continue }
                certNames[certificateID] = LocalizedText.from(row: row)
            }
        }
        certificateNames = certNames
    }

    // MARK: - Lookups

    static func fighterAbilities(for typeID: Int) -> [FighterAbilityInfo] {
        fighterAbilities[typeID] ?? []
    }

    /// 按 buffID + typeID 精确查询（type_id 为使用该 buff 定义的物品，用于场景隔离）；
    /// 无精确匹配时回退到该 buffID 的任意定义（兼容数据不全）
    static func warfareBuff(for buffID: Int, typeID: Int) -> WarfareBuffInfo? {
        let byType = warfareBuffs[buffID] ?? [:]
        return byType[typeID] ?? byType.values.first
    }

    /// 按当前语言解析认证名称
    static func certificateName(for certificateID: Int) -> String? {
        certificateNames[certificateID]?.resolvedNonEmpty()
    }

    /// 从 warfareBuff* 属性键值对解析 dbuff 配对（ID + Multiplier，Value 回退）
    /// key 格式: warfareBuff<槽位><ID|Value|Multiplier>，覆盖弹药、泰坦现象发生器等一切 dbuff 物品
    /// 结果按槽位号升序排列，保证输出顺序稳定
    static func parseWarfareBuffPairs(_ keyValue: [String: Double]) -> [(buffID: Int, value: Double)] {
        var slotIDs: [Int: Double] = [:]
        var slotMultipliers: [Int: Double] = [:]
        var slotValues: [Int: Double] = [:]

        for (key, value) in keyValue {
            guard key.hasPrefix("warfareBuff") else { continue }
            let rest = String(key.dropFirst("warfareBuff".count))
            guard let slot = Int(rest.prefix(1)) else { continue }
            switch String(rest.dropFirst()) {
            case "ID": slotIDs[slot] = value
            case "Multiplier": slotMultipliers[slot] = value
            case "Value": slotValues[slot] = value
            default: break
            }
        }

        return slotIDs.keys.sorted().compactMap { slot in
            guard let id = slotIDs[slot], id > 0 else { return nil }
            let value = slotMultipliers[slot] ?? slotValues[slot] ?? 0
            guard abs(value) > 0.01 else { return nil }
            return (Int(id), value)
        }
    }
}
