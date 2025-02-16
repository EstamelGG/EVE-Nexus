import Foundation

// MARK: - 主权战役数据模型
public struct SovereigntyCampaign: Codable {
    public let attackers_score: Float?
    public let campaign_id: Int
    public let constellation_id: Int
    public let defender_id: Int
    public let defender_score: Float?
    public let event_type: String
    public let solar_system_id: Int
    public let start_time: String
    public let structure_id: Int64
    
    public init(
        attackers_score: Float?,
        campaign_id: Int,
        constellation_id: Int,
        defender_id: Int,
        defender_score: Float?,
        event_type: String,
        solar_system_id: Int,
        start_time: String,
        structure_id: Int64
    ) {
        self.attackers_score = attackers_score
        self.campaign_id = campaign_id
        self.constellation_id = constellation_id
        self.defender_id = defender_id
        self.defender_score = defender_score
        self.event_type = event_type
        self.solar_system_id = solar_system_id
        self.start_time = start_time
        self.structure_id = structure_id
    }
}

// MARK: - 主权数据模型
public struct SovereigntyData: Codable {
    public let systemId: Int
    public let allianceId: Int?
    public let corporationId: Int?
    public let factionId: Int?
    
    public enum CodingKeys: String, CodingKey {
        case systemId = "system_id"
        case allianceId = "alliance_id"
        case corporationId = "corporation_id"
        case factionId = "faction_id"
    }
    
    public init(
        systemId: Int,
        allianceId: Int?,
        corporationId: Int?,
        factionId: Int?
    ) {
        self.systemId = systemId
        self.allianceId = allianceId
        self.corporationId = corporationId
        self.factionId = factionId
    }
} 