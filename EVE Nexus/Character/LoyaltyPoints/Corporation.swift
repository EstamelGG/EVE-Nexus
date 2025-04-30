import Foundation

struct Corporation: Identifiable {
    let id: Int
    let name: String
    let factionId: Int
    let iconFileName: String

    init?(from row: [String: Any]) {
        guard let corporationId = row["corporation_id"] as? Int,
            let name = row["name"] as? String,
            let factionId = row["faction_id"] as? Int
        else {
            return nil
        }

        id = corporationId
        self.name = name
        self.factionId = factionId
        self.iconFileName =
            (row["icon_filename"] as? String)?.isEmpty == true
            ? "corporations_default" : (row["icon_filename"] as? String ?? "corporations_default")
    }
}
