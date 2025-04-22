import Foundation

struct Faction: Identifiable {
    let id: Int
    let name: String
    let iconName: String

    init?(from row: [String: Any]) {
        guard let id = row["id"] as? Int,
            let name = row["name"] as? String,
            let iconName = row["iconName"] as? String
        else {
            return nil
        }
        self.id = id
        self.name = name
        self.iconName = iconName
    }
}
