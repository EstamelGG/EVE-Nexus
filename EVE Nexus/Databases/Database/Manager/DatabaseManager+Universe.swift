import Foundation
import SwiftUI

public struct WormholeInfo: Identifiable {
    public let id: Int
    public let name: String
    public let description: String
    public let icon: String
    public let target: String
    public let stableTime: String
    public let maxStableMass: String
    public let maxJumpMass: String
    public let sizeType: String
}

extension DatabaseManager {
    /// 加载虫洞数据
    func loadWormholes() -> [WormholeInfo] {
        let query = """
            SELECT type_id, name, description, icon, target_value, target, stable_time, max_stable_mass, max_jump_mass, size_type
            FROM wormholes
            ORDER BY target_value
        """

        let result = executeQuery(query)
        var wormholes: [WormholeInfo] = []

        switch result {
        case let .success(rows):
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
                    let wormhole = WormholeInfo(
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
                    wormholes.append(wormhole)
                }
            }
        case let .error(error):
            Logger.error("加载虫洞数据失败: \(error)")
        }

        return wormholes
    }

    /// 批量解析天体显示名：`Jita IV` / `Jita IV - Moon 1`
    func getCelestialNames(itemIDs: some Collection<Int>) -> [Int: String] {
        let unique = Array(Set(itemIDs))
        guard !unique.isEmpty else { return [:] }

        let ids = unique.sorted().map(String.init).joined(separator: ",")
        let query = """
        SELECT itemID, solarSystemID, celestialIndex, orbitIndex
        FROM celestials
        WHERE itemID IN (\(ids))
        """

        guard case let .success(rows) = executeQuery(query) else { return [:] }

        var names: [Int: String] = [:]
        for row in rows {
            guard let itemID = row["itemID"] as? Int,
                  let systemID = row["solarSystemID"] as? Int,
                  let index = row["celestialIndex"] as? Int,
                  let text = SDEMemoryStore.solarSystemNames[systemID]
            else { continue }

            // 天体英文惯用名（如 Jita IV）
            let systemName = text.en.isEmpty ? text.resolved() : text.en
            guard !systemName.isEmpty else { continue }

            let base = "\(systemName) \(Self.romanNumeral(index))"
            if let orbit = row["orbitIndex"] as? Int {
                names[itemID] = "\(base) - Moon \(orbit)"
            } else {
                names[itemID] = base
            }
        }
        return names
    }

    private static func romanNumeral(_ n: Int) -> String {
        guard n > 0 else { return String(n) }
        let pairs: [(Int, String)] = [
            (1000, "M"), (900, "CM"), (500, "D"), (400, "CD"),
            (100, "C"), (90, "XC"), (50, "L"), (40, "XL"),
            (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I"),
        ]
        var rest = n
        var out = ""
        for (value, glyph) in pairs {
            while rest >= value {
                out += glyph
                rest -= value
            }
        }
        return out
    }
}
