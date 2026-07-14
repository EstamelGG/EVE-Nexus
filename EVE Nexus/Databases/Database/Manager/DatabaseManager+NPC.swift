import Foundation
import SwiftUI

extension DatabaseManager {
    // MARK: - NPC

    func getNPCScenes() -> [String] {
        let query = """
            SELECT DISTINCT npc_ship_scene FROM types
            WHERE npc_ship_scene IS NOT NULL ORDER BY npc_ship_scene
        """
        guard case let .success(rows) = executeQuery(query) else { return [] }
        return rows.compactMap { $0["npc_ship_scene"] as? String }
    }

    func getNPCFactions(for scene: String) -> [String] {
        let query = """
            SELECT DISTINCT npc_ship_faction FROM types
            WHERE npc_ship_scene = ? AND npc_ship_faction IS NOT NULL
            ORDER BY npc_ship_faction
        """
        guard case let .success(rows) = executeQuery(query, parameters: [scene]) else { return [] }
        return rows.compactMap { $0["npc_ship_faction"] as? String }
    }

    func getNPCTypes(for scene: String, faction: String) -> [String] {
        let query = """
            SELECT DISTINCT npc_ship_type FROM types
            WHERE npc_ship_scene = ? AND npc_ship_faction = ? AND npc_ship_type IS NOT NULL
            ORDER BY npc_ship_type
        """
        guard case let .success(rows) = executeQuery(query, parameters: [scene, faction]) else { return [] }
        return rows.compactMap { $0["npc_ship_type"] as? String }
    }

    func getNPCItems(for scene: String, faction: String, type: String) -> [NPCItem] {
        let query = """
            SELECT type_id, name, en_name, icon_filename FROM types
            WHERE npc_ship_scene = ? AND npc_ship_faction = ? AND npc_ship_type = ?
            ORDER BY name
        """
        guard case let .success(rows) = executeQuery(query, parameters: [scene, faction, type]) else { return [] }
        return rows.compactMap { row in
            guard let typeID = row["type_id"] as? Int,
                  let name = row["name"] as? String,
                  let enName = row["en_name"] as? String,
                  let iconFileName = row["icon_filename"] as? String else { return nil }
            return NPCItem(typeID: typeID, name: name, enName: enName, iconFileName: iconFileName)
        }
    }

    func getNPCFactionIcon(for faction: String) -> String? {
        let query = """
            SELECT DISTINCT npc_ship_faction_icon FROM types
            WHERE npc_ship_faction = ? AND npc_ship_faction_icon IS NOT NULL LIMIT 1
        """
        if case let .success(rows) = executeQuery(query, parameters: [faction]),
           let iconFileName = rows.first?["npc_ship_faction_icon"] as? String
        {
            return iconFileName.isEmpty ? IconManager.defaultItemIcon : iconFileName
        }
        return IconManager.defaultItemIcon
    }
}
