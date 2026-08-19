import Foundation
import SQLite3

/// 杂项小表加载与查询：oreColors / compressible_types / typeSkillRequirement / typeMaterials / wormholes
extension SDEMemoryStore {
    static func loadOreColors(_ db: DatabaseManager) {
        var cache: [Int: String] = [:]
        if case let .success(rows) = db.executeQuery(
            "SELECT type_id, hex_color FROM ore_colors", useCache: false
        ) {
            for row in rows {
                if let id = row["type_id"] as? Int, let color = row["hex_color"] as? String {
                    cache[id] = color
                }
            }
        }
        oreColors = cache
    }

    static func loadCompressibleTypes(_ db: DatabaseManager) {
        var forward: [Int: Int] = [:]
        var reverse: [Int: Int] = [:]
        if case let .success(rows) = db.executeQuery(
            "SELECT origin, compressed FROM compressible_types", useCache: false
        ) {
            for row in rows {
                guard let origin = row["origin"] as? Int,
                      let compressed = row["compressed"] as? Int
                else { continue }
                forward[origin] = compressed
                reverse[compressed] = origin
            }
        }
        originToCompressed = forward
        compressedToOrigin = reverse
    }

    /// 物品技能要求（typeSkillRequirement 表核心列，旧 SDE 缺表时保持为空自然降级）
    static func loadSkillRequirements(_ db: DatabaseManager) {
        var cache: [Int: [SkillRequirement]] = [:]
        if case let .success(rows) = db.executeQuery(
            "SELECT typeid, required_skill_id, required_skill_level FROM typeSkillRequirement",
            useCache: false
        ) {
            for row in rows {
                guard let typeID = row["typeid"] as? Int,
                      let skillID = row["required_skill_id"] as? Int
                else { continue }
                let level = row["required_skill_level"] as? Int ?? 0
                cache[typeID, default: []].append(SkillRequirement(skillID: skillID, level: level))
            }
        }
        skillRequirements = cache
    }

    /// 再利用材料（typeMaterials 表核心列；名称/icon 宽列运行时查 types 内存）
    static func loadTypeMaterials(_ db: DatabaseManager) {
        var cache: [Int: [TypeMaterialEntry]] = [:]
        cache.reserveCapacity(9541)
        db.executeQueryMapped(
            """
            SELECT typeid, process_size, output_material, output_quantity
            FROM typeMaterials
            ORDER BY typeid, output_material
            """,
            context: "typeMaterials"
        ) { resolve in
            let (iType, iProcess, iMaterial, iQuantity) = (
                resolve.index("typeid"), resolve.index("process_size"),
                resolve.index("output_material"), resolve.index("output_quantity")
            )
            return { stmt in
                guard let typeID = directIntOrNil(stmt, iType),
                      let outputMaterial = directIntOrNil(stmt, iMaterial)
                else { return }
                cache[typeID, default: []].append(
                    TypeMaterialEntry(
                        processSize: directIntOrNil(stmt, iProcess) ?? 0,
                        outputMaterial: outputMaterial,
                        outputQuantity: directIntOrNil(stmt, iQuantity) ?? 0
                    )
                )
            }
        }
        typeMaterialEntries = cache
    }

    /// 虫洞列表（130 行；name/description 走 TEMP VIEW 当前语言，语言切换时随 loadDatabase 重建）
    static func loadWormholes(_ db: DatabaseManager) {
        let query = """
            SELECT type_id, name, description, icon, target_value, target, stable_time, max_stable_mass, max_jump_mass, size_type
            FROM wormholes
            ORDER BY target_value
        """
        var cache: [WormholeInfo] = []
        if case let .success(rows) = db.executeQuery(query, useCache: false) {
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                   let name = row["name"] as? String,
                   let description = row["description"] as? String,
                   let icon = row["icon"] as? String,
                   let target = row["target"] as? String,
                   let stableTime = row["stable_time"] as? String,
                   let maxStableMass = row["max_stable_mass"] as? String,
                   let maxJumpMass = row["max_jump_mass"] as? String,
                   let sizeType = row["size_type"] as? String
                {
                    cache.append(
                        WormholeInfo(
                            id: typeId,
                            name: name,
                            description: description,
                            icon: icon.isEmpty ? "not_found" : icon,
                            target: target,
                            stableTime: stableTime,
                            maxStableMass: maxStableMass,
                            maxJumpMass: maxJumpMass,
                            sizeType: sizeType
                        )
                    )
                }
            }
        }
        wormholeList = cache
    }

    // MARK: - Lookups

    static func oreColor(for typeID: Int) -> String? {
        oreColors[typeID]
    }

    /// 物品技能要求
    static func requiredSkills(for typeID: Int) -> [SkillRequirement] {
        skillRequirements[typeID] ?? []
    }

    /// 再利用材料
    static func materials(for typeID: Int) -> [TypeMaterialEntry] {
        typeMaterialEntries[typeID] ?? []
    }
}
