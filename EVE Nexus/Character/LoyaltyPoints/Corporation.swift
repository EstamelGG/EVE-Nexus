import Foundation

struct Corporation: Identifiable {
    let id: Int
    let name: String
    let factionId: Int
    let iconFileName: String

    init?(from row: [String: Any]) {
        guard let corporationId = row["corporation_id"] as? Int,
            let name = row["name"] as? String,
            let factionId = row["faction_id"] as? Int,
            let iconFileName = row["icon_filename"] as? String
        else {
            return nil
        }

        id = corporationId
        self.name = name
        self.factionId = factionId
        self.iconFileName = iconFileName.isEmpty ? "corporations_default" : iconFileName
    }
}
