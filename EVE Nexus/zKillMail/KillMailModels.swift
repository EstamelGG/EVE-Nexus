import Foundation

// MARK: - 列表用实体（ESI + ZKB + 补充数据，无 evetools 格式）

/// 星系摘要（用于列表展示，名称从 SDEMemoryStore 动态解析以跟随语言切换）
struct KillMailSystemSummary: Codable {
    let systemId: Int
    let regionId: Int
    let security: Double

    var systemName: String {
        SDEMemoryStore.solarSystemName(for: systemId) ?? "System \(systemId)"
    }

    var regionName: String {
        SDEMemoryStore.regionName(for: regionId) ?? "Region \(regionId)"
    }
}

/// 战斗记录列表项（以 ESI 为核心，补充名称与星系）
struct KillMailListEntity: Codable, Identifiable {
    let killmailId: Int
    let timestamp: Int
    let zkb: ZKBInfo
    let victim: ESIVictim
    let names: [Int: String] // ID -> 名称（角色/军团/联盟）
    let system: KillMailSystemSummary?

    var id: Int {
        killmailId
    }

    var totalValue: Double {
        zkb.totalValueValue
    }

    /// 显示用主名称（角色 > 联盟 > 军团）
    var displayName: String {
        if let charId = victim.character_id, let name = names[charId] {
            return name
        }
        if let allyId = victim.alliance_id, allyId > 0, let name = names[allyId] {
            return name
        }
        if let name = names[victim.corporation_id] {
            return name
        }
        return NSLocalizedString("Unknown", comment: "")
    }

    var characterId: Int? {
        victim.character_id
    }

    var corporationId: Int {
        victim.corporation_id
    }

    var allianceId: Int? {
        victim.alliance_id
    }

    var shipTypeId: Int {
        victim.ship_type_id
    }
}

// MARK: - 详情用数据（ESI + ZKB + 补充数据）

/// 战斗记录详情（以 ESI 为核心，补充名称、星系等；列表单价由详情视图异步拉取）
struct KillMailDetailData {
    let killmailId: Int
    let esi: ESIKillMail
    let zkb: ZKBInfo?
    let names: [Int: String]
    let system: KillMailSystemSummary?

    var timestamp: Int? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: esi.killmail_time) else { return nil }
        return Int(date.timeIntervalSince1970)
    }

    var attackers: [ESIAttacker] {
        esi.attackers ?? []
    }

    func characterName(for id: Int) -> String {
        names[id] ?? "Character \(id)"
    }

    func corporationName(for id: Int) -> String {
        names[id] ?? "Corporation \(id)"
    }

    func allianceName(for id: Int) -> String {
        names[id] ?? "Alliance \(id)"
    }

    /// 用于装配视图的物品格式 [flag, type_id, qty_dropped, qty_destroyed, singleton, depth]
    var itemsForFitting: [[Int]] {
        guard let items = esi.victim.items else { return [] }
        return KillMailItemTreeBuilder.flattenAllTopLevel(items)
    }

    /// 转换植入体后的装配物品（供 BRKillMailFittingView 使用）
    var convertedItemsForFitting: [[Int]] {
        BRKillMailUtils.shared.convertImplantsToFitting(
            shipId: esi.victim.ship_type_id,
            items: itemsForFitting
        )
    }

    /// 指定舱位（flag）下的展示行（含容器嵌套，深度优先；同级排序由调用方传入单价表）
    func displayRows(forFlag flag: Int, unitPriceByType: [Int: Double]) -> [KillMailDisplayRow] {
        let roots = (esi.victim.items ?? []).filter { $0.flag == flag }
        return KillMailItemTreeBuilder.displayRows(
            roots: roots,
            groupingFlag: flag,
            unitPriceByType: unitPriceByType
        )
    }

    /// 收集 victim.items 树中全部 type_id（含嵌套）
    static func allVictimItemTypeIds(from items: [ESIItem]?) -> [Int] {
        guard let items else { return [] }
        var ids = Set<Int>()
        func walk(_ list: [ESIItem]) {
            for item in list {
                ids.insert(item.item_type_id)
                if let nested = item.items { walk(nested) }
            }
        }
        walk(items)
        return Array(ids)
    }
}

// MARK: - 嵌套物品展平与同级排序

/// 详情列表中的一行物品（含嵌套深度）
struct KillMailDisplayRow: Identifiable, Hashable {
    let id: String
    let flag: Int
    let typeId: Int
    let quantityDropped: Int
    let quantityDestroyed: Int
    let singleton: Int
    let depth: Int
}

enum KillMailItemTreeBuilder {
    private static let depthIndex = 5

    /// 展平 victim 顶层物品树（深度优先；同一 flag 下仅对同级兄弟排序）
    static func flattenAllTopLevel(_ roots: [ESIItem]) -> [[Int]] {
        var rows: [[Int]] = []
        func walk(_ items: [ESIItem], groupingFlag: Int, depth: Int) {
            let sorted = sortESISiblings(items, unitPriceByType: [:])
            for item in sorted {
                rows.append([
                    groupingFlag,
                    item.item_type_id,
                    item.quantity_dropped ?? 0,
                    item.quantity_destroyed ?? 0,
                    item.singleton,
                    depth,
                ])
                if let nested = item.items, !nested.isEmpty {
                    walk(nested, groupingFlag: groupingFlag, depth: depth + 1)
                }
            }
        }
        for flag in Set(roots.map(\.flag)).sorted() {
            let siblings = roots.filter { $0.flag == flag }
            walk(siblings, groupingFlag: flag, depth: 0)
        }
        return rows
    }

    /// 某一 flag 舱位内的展示行（容器下紧跟内容物，仅同级排序）
    static func displayRows(
        roots: [ESIItem],
        groupingFlag: Int,
        unitPriceByType: [Int: Double]
    ) -> [KillMailDisplayRow] {
        var result: [KillMailDisplayRow] = []
        var counter = 0

        func walk(_ items: [ESIItem], depth: Int) {
            let sorted = sortESISiblings(items, unitPriceByType: unitPriceByType)
            for item in sorted {
                let rowId = "\(groupingFlag)-\(item.item_type_id)-\(depth)-\(counter)"
                counter += 1
                result.append(
                    KillMailDisplayRow(
                        id: rowId,
                        flag: groupingFlag,
                        typeId: item.item_type_id,
                        quantityDropped: item.quantity_dropped ?? 0,
                        quantityDestroyed: item.quantity_destroyed ?? 0,
                        singleton: item.singleton,
                        depth: depth
                    )
                )
                if let nested = item.items, !nested.isEmpty {
                    walk(nested, depth: depth + 1)
                }
            }
        }

        walk(roots, depth: 0)
        return result
    }

    /// 仅对同一父级下的兄弟节点排序（装配槽：先 flag，再非弹药优先）
    static func sortFittingSiblingRows(
        _ rows: [[Int]],
        itemInfoCache: [Int: (iconFileName: String, bpcIconFileName: String, categoryID: Int)]
    ) -> [[Int]] {
        rows.sorted { a, b in
            if a[0] != b[0] { return a[0] < b[0] }
            let aDepth = a.count > depthIndex ? a[depthIndex] : 0
            let bDepth = b.count > depthIndex ? b[depthIndex] : 0
            if aDepth != bDepth { return aDepth < bDepth }
            let aAmmo = itemInfoCache[a[1]]?.categoryID == 8
            let bAmmo = itemInfoCache[b[1]]?.categoryID == 8
            if aAmmo != bAmmo { return !aAmmo }
            return a[1] < b[1]
        }
    }

    private static func sortESISiblings(
        _ items: [ESIItem],
        unitPriceByType: [Int: Double]
    ) -> [ESIItem] {
        guard !items.isEmpty else { return items }
        let valueByType: [Int: Double] = Dictionary(grouping: items, by: \.item_type_id)
            .mapValues { group in
                group.reduce(0.0) { partial, item in
                    let qty = (item.quantity_dropped ?? 0) + (item.quantity_destroyed ?? 0)
                    let unit = unitPriceByType[item.item_type_id] ?? 0
                    return partial + Double(qty) * unit
                }
            }
        return items.sorted { lhs, rhs in
            let lhsStack = valueByType[lhs.item_type_id, default: 0]
            let rhsStack = valueByType[rhs.item_type_id, default: 0]
            if lhsStack != rhsStack { return lhsStack > rhsStack }
            if lhs.item_type_id != rhs.item_type_id {
                return lhs.item_type_id < rhs.item_type_id
            }
            let ld = lhs.quantity_dropped ?? 0
            let rd = rhs.quantity_dropped ?? 0
            if ld != rd { return ld > rd }
            return (lhs.quantity_destroyed ?? 0) > (rhs.quantity_destroyed ?? 0)
        }
    }
}
