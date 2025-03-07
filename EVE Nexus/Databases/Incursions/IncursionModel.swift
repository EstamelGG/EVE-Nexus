import Foundation

struct Incursion: Codable {
    let constellationId: Int
    let factionId: Int
    let hasBoss: Bool
    let influence: Double
    let stagingSolarSystemId: Int
    let state: String
    let infestedSolarSystems: [Int]

    enum CodingKeys: String, CodingKey {
        case constellationId = "constellation_id"
        case factionId = "faction_id"
        case hasBoss = "has_boss"
        case influence
        case stagingSolarSystemId = "staging_solar_system_id"
        case state
        case infestedSolarSystems = "infested_solar_systems"
    }
}
