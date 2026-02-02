import Foundation

// MARK: - 列表用实体（ESI + ZKB + 补充数据，无 evetools 格式）

/// 星系摘要（用于列表展示）
struct KillMailSystemSummary: Codable {
    let systemId: Int
    let systemName: String
    let regionName: String
    let security: Double
}

/// 战斗记录列表项（以 ESI 为核心，补充名称与星系）
struct KillMailListEntity: Codable, Identifiable {
    let killmailId: Int
    let timestamp: Int
    let zkb: ZKBInfo
    let victim: ESIVictim
    let names: [Int: String] // ID -> 名称（角色/军团/联盟）
    let system: KillMailSystemSummary?

    var id: Int { killmailId }

    var totalValue: Double { zkb.totalValueValue }

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

    var characterId: Int? { victim.character_id }
    var corporationId: Int { victim.corporation_id }
    var allianceId: Int? { victim.alliance_id }
    var shipTypeId: Int { victim.ship_type_id }
}

// MARK: - 详情用数据（ESI + ZKB + 补充数据）

/// 战斗记录详情（以 ESI 为核心，补充名称、星系、价格等）
struct KillMailDetailData {
    let killmailId: Int
    let esi: ESIKillMail
    let zkb: ZKBInfo?
    let names: [Int: String]
    let system: KillMailSystemSummary?
    var prices: [Int: Double] = [:] // type_id -> 价格，由详情页异步填充

    var pricesForDisplay: [String: Double] {
        Dictionary(uniqueKeysWithValues: prices.map { (String($0.key), $0.value) })
    }

    var timestamp: Int? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: esi.killmail_time) else { return nil }
        return Int(date.timeIntervalSince1970)
    }

    var attackers: [ESIAttacker] { esi.attackers ?? [] }

    func characterName(for id: Int) -> String {
        names[id] ?? "Character \(id)"
    }

    func corporationName(for id: Int) -> String {
        names[id] ?? "Corporation \(id)"
    }

    func allianceName(for id: Int) -> String {
        names[id] ?? "Alliance \(id)"
    }

    /// 用于装配视图的物品格式 [flag, type_id, qty_dropped, qty_destroyed, singleton]
    var itemsForFitting: [[Int]] {
        guard let items = esi.victim.items else { return [] }
        return items.map { item in
            [
                item.flag,
                item.item_type_id,
                item.quantity_dropped ?? 0,
                item.quantity_destroyed ?? 0,
                item.singleton,
            ]
        }
    }

    /// 转换植入体后的装配物品（供 BRKillMailFittingView 使用）
    var convertedItemsForFitting: [[Int]] {
        BRKillMailUtils.shared.convertImplantsToFitting(
            shipId: esi.victim.ship_type_id,
            items: itemsForFitting
        )
    }
}
