import SwiftUI

// MARK: - Models
struct SovereigntyCampaign: Codable {
    let attackersScore: Double
    let campaignId: Int
    let constellationId: Int
    let defenderId: Int
    let defenderScore: Double
    let eventType: String
    let solarSystemId: Int
    let startTime: String
    let structureId: Int64
    
    enum CodingKeys: String, CodingKey {
        case attackersScore = "attackers_score"
        case campaignId = "campaign_id"
        case constellationId = "constellation_id"
        case defenderId = "defender_id"
        case defenderScore = "defender_score"
        case eventType = "event_type"
        case solarSystemId = "solar_system_id"
        case startTime = "start_time"
        case structureId = "structure_id"
    }
}

class PreparedSovereignty: NSObject, Identifiable, @unchecked Sendable, ObservableObject {
    let id: Int
    let campaign: SovereigntyCampaign
    let location: LocationInfo
    @Published var icon: Image?
    @Published var isLoadingIcon = false
    
    init(campaign: SovereigntyCampaign, location: LocationInfo) {
        self.id = campaign.campaignId
        self.campaign = campaign
        self.location = location
        super.init()
    }
    
    struct LocationInfo: Codable {
        let systemName: String
        let security: Double
        let constellationName: String
        let regionName: String
        let regionId: Int
    }
} 
