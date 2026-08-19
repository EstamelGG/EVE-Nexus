import Foundation

/// 突变系统（dynamic_item_mappings / dynamic_item_attributes）加载与查询
extension SDEMemoryStore {
    static func loadDynamicItemMappings(_ db: DatabaseManager) {
        var byApplicable: [Int: [DynamicItemMapping]] = [:]
        var byResulting: [Int: [DynamicItemMapping]] = [:]
        var byTypeID: [Int: [DynamicItemMapping]] = [:]
        var resultingIDs = Set<Int>()

        if case let .success(rows) = db.executeQuery(
            "SELECT applicable_type, type_id, resulting_type FROM dynamic_item_mappings",
            useCache: false
        ) {
            for row in rows {
                guard let applicableType = row["applicable_type"] as? Int,
                      let typeID = row["type_id"] as? Int,
                      let resultingType = row["resulting_type"] as? Int
                else { continue }
                let mapping = DynamicItemMapping(
                    applicableType: applicableType,
                    typeID: typeID,
                    resultingType: resultingType
                )
                byApplicable[applicableType, default: []].append(mapping)
                byResulting[resultingType, default: []].append(mapping)
                byTypeID[typeID, default: []].append(mapping)
                resultingIDs.insert(resultingType)
            }
        }
        dynamicMappingsByApplicable = byApplicable
        dynamicMappingsByResulting = byResulting
        dynamicMappingsByTypeID = byTypeID
        dynamicResultingTypeIDs = resultingIDs
    }

    /// 预加载 dynamic_item_attributes（突变质体属性范围）。
    /// high_is_good 为 NULL 时回退 dogma 默认值（延迟到 lookup 时物化）；
    /// 旧版 SDE 无该列时同样按 NULL 处理，避免查询失败导致突变属性整体为空
    static func loadDynamicItemAttributes(_ db: DatabaseManager) {
        var cache: [Int: [RawDynamicItemAttribute]] = [:]

        // 探测 high_is_good 列是否存在；不存在则用 NULL 占位（视为未覆盖）
        var highIsGoodColumn = "NULL AS high_is_good"
        if case let .success(columns) = db.executeQuery(
            "PRAGMA table_info(dynamic_item_attributes)", useCache: false
        ), columns.contains(where: { ($0["name"] as? String) == "high_is_good" }) {
            highIsGoodColumn = "high_is_good"
        } else {
            Logger.info("dynamic_item_attributes 无 high_is_good 列，highIsGood 回退 dogma 默认值")
        }

        if case let .success(rows) = db.executeQuery(
            """
            SELECT type_id, attribute_id, min_value, max_value, \(highIsGoodColumn)
            FROM dynamic_item_attributes
            ORDER BY type_id, attribute_id
            """,
            useCache: false
        ) {
            for row in rows {
                guard let typeID = row["type_id"] as? Int,
                      let attributeID = row["attribute_id"] as? Int,
                      let minValue = doubleOrInt(row, "min_value"),
                      let maxValue = doubleOrInt(row, "max_value")
                else { continue }
                cache[typeID, default: []].append(
                    RawDynamicItemAttribute(
                        attributeID: attributeID,
                        minValue: minValue,
                        maxValue: maxValue,
                        highIsGoodOverride: (row["high_is_good"] as? Int).map { $0 == 1 }
                    )
                )
            }
        }
        dynamicItemAttributesByType = cache
    }

    // MARK: - Lookups

    /// applicable_type → 所有映射（用于查询可突变产物、所需突变质体）
    static func dynamicMappings(applicableTo typeID: Int) -> [DynamicItemMapping] {
        dynamicMappingsByApplicable[typeID] ?? []
    }

    /// resulting_type → 所有映射（用于查询突变来源）
    static func dynamicMappings(resultingIn typeID: Int) -> [DynamicItemMapping] {
        dynamicMappingsByResulting[typeID] ?? []
    }

    /// type_id（突变质体）→ 所有映射（用于查询该质体可应用的物品及产物）
    static func dynamicMappings(forTypeID typeID: Int) -> [DynamicItemMapping] {
        dynamicMappingsByTypeID[typeID] ?? []
    }

    /// applicable_type + 突变质体 type_id → 突变产物 resulting_type
    static func dynamicResultingType(applicableType: Int, typeID: Int) -> Int? {
        dynamicMappingsByApplicable[applicableType]?.first { $0.typeID == typeID }?.resultingType
    }

    /// 突变质体 → 可影响属性列表（含 dogma 展示信息与覆盖后的 highIsGood），
    /// 按当前语言 displayName 排序；dogma 缺失或无名称的属性跳过（与旧 SQL 行为一致）
    static func dynamicItemAttributes(forTypeID typeID: Int) -> [DynamicItemAttributeInfo] {
        (dynamicItemAttributesByType[typeID] ?? []).compactMap { raw in
            guard let dogma = dogmaAttributes[raw.attributeID],
                  let name = dogma.displayName
            else { return nil }
            let icon = dogma.iconFilename
            return DynamicItemAttributeInfo(
                attributeID: raw.attributeID,
                name: name,
                iconFileName: icon.isEmpty ? nil : icon,
                unitID: dogma.unitID,
                minValue: raw.minValue,
                maxValue: raw.maxValue,
                highIsGood: raw.highIsGoodOverride ?? dogma.highIsGood
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
